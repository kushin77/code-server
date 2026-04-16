#!/usr/bin/env bash
# @file        scripts/ops/error-fingerprint-triage.sh
# @module      ops/incident
# @description Phase 8 / #375 — Runtime error fingerprint collection + GitHub auto-triage
#              Scrapes Docker container logs for error patterns, deduplicates by fingerprint,
#              and creates/comments GitHub issues with structured context.
#
# Usage:
#   bash scripts/ops/error-fingerprint-triage.sh [--dry-run] [--since 1h] [--repo owner/repo]
#
# On-prem:
#   ssh akushnir@192.168.168.31 'cd code-server-enterprise && bash scripts/ops/error-fingerprint-triage.sh'
#
# Requires: docker, gh CLI (authenticated), jq
#
set -euo pipefail

# shellcheck source=scripts/_common/logging.sh
source "$(dirname "${BASH_SOURCE[0]}")/../_common/logging.sh"

# ─── Config ──────────────────────────────────────────────────────────────────
DRY_RUN="${DRY_RUN:-false}"
SINCE="${SINCE:-1h}"
REPO="${GH_REPO:-kushin77/code-server}"
STATE_DIR="/tmp/error-fingerprints"
MAX_ISSUE_BODY_LEN=5000

# ─── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN="true"; shift ;;
    --since)   SINCE="$2"; shift 2 ;;
    --repo)    REPO="$2"; shift 2 ;;
    *) log_warn "Unknown arg: $1"; shift ;;
  esac
done

# ─── Verify on correct host ───────────────────────────────────────────────────
EXPECTED_HOST="192.168.168.31"
ACTUAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
if [[ "${ACTUAL_IP}" != "${EXPECTED_HOST}" ]]; then
  log_warn "Not running on production host (${ACTUAL_IP} != ${EXPECTED_HOST})"
  log_warn "Docker container logs may be unavailable. Consider SSH: ssh akushnir@${EXPECTED_HOST}"
fi

# ─── Dependency checks ────────────────────────────────────────────────────────
for cmd in docker gh jq; do
  if ! command -v "${cmd}" &>/dev/null; then
    log_error "Missing required command: ${cmd}"
    exit 1
  fi
done

mkdir -p "${STATE_DIR}"

# ─── Error pattern definitions ────────────────────────────────────────────────
# Each entry: "PATTERN|SEVERITY|COMPONENT|LABEL"
declare -a ERROR_PATTERNS=(
  "FATAL|critical|any|bug"
  "panic:|critical|any|bug"
  "OOM killer|critical|system|P0"
  "Out of memory|critical|system|P0"
  "connection refused|warning|network|P1"
  "certificate has expired|critical|tls|security"
  "authentication failed|warning|auth|security"
  "CSRF token|warning|auth|security"
  "permission denied|warning|auth|security"
  "database.*error|warning|postgres|P1"
  "too many connections|warning|postgres|P1"
  "FATAL.*password|warning|postgres|security"
  "redis.*NOAUTH|warning|redis|P1"
  "oauth2.*error|warning|oauth2|P1"
  "caddy.*error|warning|caddy|P1"
  "ERROR.*code-server|warning|code-server|P2"
  "exit status [^0]|warning|any|P2"
)

# ─── Container list ───────────────────────────────────────────────────────────
CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')
if [[ -z "${CONTAINERS}" ]]; then
  log_warn "No running Docker containers found."
  exit 0
fi
log_info "Scanning containers: ${CONTAINERS}"
log_info "Looking back: ${SINCE} | Dry run: ${DRY_RUN}"

# ─── Fingerprint function ─────────────────────────────────────────────────────
# Produces a stable SHA fingerprint for a given error line
fingerprint() {
  local container="$1" pattern="$2" line="$3"
  # Normalize: strip timestamps, PIDs, hex addresses, line numbers
  local normalized
  normalized=$(echo "${line}" | \
    sed 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9:\.Z+-]*//g' | \
    sed 's/\b0x[0-9a-fA-F]\+\b/ADDR/g' | \
    sed 's/\bpid=[0-9]\+\b/pid=N/g' | \
    sed 's/:[0-9]\+\b/:N/g' | \
    tr -s ' ')
  printf '%s:%s:%s' "${container}" "${pattern}" "${normalized}" | sha256sum | awk '{print $1}' | cut -c1-12
}

# ─── Scan logs and collect errors ─────────────────────────────────────────────
declare -A fingerprint_seen
declare -a findings

for container in ${CONTAINERS}; do
  log_info "Scanning ${container}..."
  # Fetch logs since SINCE (Docker accepts: 1h, 30m, 2006-01-02T15:04:05)
  LOGS=$(docker logs --since "${SINCE}" "${container}" 2>&1 || true)
  if [[ -z "${LOGS}" ]]; then continue; fi

  for pattern_entry in "${ERROR_PATTERNS[@]}"; do
    IFS='|' read -r pattern severity component label <<< "${pattern_entry}"
    # Case-insensitive grep for pattern
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      fp=$(fingerprint "${container}" "${pattern}" "${line}")
      # Skip if already seen this fingerprint this run
      if [[ -n "${fingerprint_seen[${fp}]+_}" ]]; then continue; fi
      fingerprint_seen["${fp}"]=1
      # Persist fingerprint to avoid re-filing across runs
      if [[ -f "${STATE_DIR}/${fp}.filed" ]]; then
        log_debug "Already filed: ${fp} — skipping"
        continue
      fi
      # Truncate long log lines
      local_line="${line:0:300}"
      findings+=("${fp}|${container}|${pattern}|${severity}|${component}|${label}|${local_line}")
    done < <(echo "${LOGS}" | grep -i "${pattern}" 2>/dev/null || true)
  done
done

if [[ ${#findings[@]} -eq 0 ]]; then
  log_info "No new error fingerprints found in the past ${SINCE}."
  exit 0
fi

log_info "Found ${#findings[@]} unique new error fingerprints."

# ─── GitHub auto-triage ───────────────────────────────────────────────────────
# Search for existing open issue with same fingerprint in title
search_existing_issue() {
  local fp="$1"
  gh issue list --repo "${REPO}" --state open --json number,title \
    --jq ".[] | select(.title | contains(\"[${fp}]\")) | .number" 2>/dev/null | head -1
}

filed_count=0
commented_count=0

for finding in "${findings[@]}"; do
  IFS='|' read -r fp container pattern severity component label log_line <<< "${finding}"
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  short_fp="${fp:0:8}"

  # Issue title (fingerprint-keyed for dedup)
  title="[${short_fp}] ${severity^}: ${component} — ${pattern} in ${container}"

  # Issue body
  body="## Error Fingerprint Triage Report

**Fingerprint**: \`${short_fp}\`  
**Timestamp**: ${timestamp}  
**Container**: \`${container}\`  
**Pattern**: \`${pattern}\`  
**Severity**: ${severity}  
**Component**: ${component}  

### Log Evidence
\`\`\`
${log_line:0:${MAX_ISSUE_BODY_LEN}}
\`\`\`

### Triage Checklist
- [ ] Confirm root cause
- [ ] Check if recurring (last 7d): \`docker logs --since 7d ${container} 2>&1 | grep -i '${pattern}' | wc -l\`
- [ ] Apply fix or add suppression rule to \`scripts/ops/error-fingerprint-triage.sh\`
- [ ] Update runbook if this recurs

### Auto-Generated
This issue was created by \`scripts/ops/error-fingerprint-triage.sh\` (fingerprint: \`${fp}\`).  
Deduplicated: re-runs will comment instead of filing new issues for the same fingerprint.
"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY RUN] Would file: ${title}"
    log_info "[DRY RUN] Fingerprint: ${fp}"
    continue
  fi

  # Check for existing open issue with this fingerprint
  existing=$(search_existing_issue "${short_fp}")

  if [[ -n "${existing}" ]]; then
    log_info "Fingerprint ${short_fp} already has open issue #${existing} — adding comment"
    gh issue comment "${existing}" --repo "${REPO}" \
      --body "**Re-occurrence detected** (${timestamp})

\`\`\`
${log_line:0:500}
\`\`\`
Container: \`${container}\` | Pattern: \`${pattern}\`  
Fingerprint: \`${fp}\`" 2>/dev/null || log_warn "Failed to comment on #${existing}"
    commented_count=$((commented_count + 1))
  else
    log_info "Filing new issue: ${title}"
    issue_url=$(gh issue create --repo "${REPO}" \
      --title "${title}" \
      --body "${body}" \
      --label "${label}" \
      2>/dev/null || echo "")
    if [[ -n "${issue_url}" ]]; then
      log_info "Created: ${issue_url}"
      # Mark as filed to suppress future runs
      touch "${STATE_DIR}/${fp}.filed"
      filed_count=$((filed_count + 1))
    else
      log_warn "Failed to create issue for fingerprint ${fp}"
    fi
  fi
done

# ─── Summary ─────────────────────────────────────────────────────────────────
log_info "Error fingerprint triage complete."
log_info "  New issues filed:   ${filed_count}"
log_info "  Existing commented: ${commented_count}"
log_info "  Total fingerprints: ${#findings[@]}"
log_info "  State dir:          ${STATE_DIR}"
