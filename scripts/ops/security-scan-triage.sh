#!/usr/bin/env bash
# @file        scripts/ops/security-scan-triage.sh
# @module      ops/security
# @description Route security scan findings from SARIF and npm audit outputs into GitHub Issues.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

GH_REPO="${GH_REPO:-kushin77/code-server}"
DRY_RUN="false"
TOOL_NAME="security-scan"
SARIF_FILE=""
NPM_AUDIT_FILE=""
AUDIT_JSONL_FILE=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ops/security-scan-triage.sh --tool <name> --sarif <file> [--repo owner/repo]
  bash scripts/ops/security-scan-triage.sh --tool npm-audit --npm-audit <file> [--repo owner/repo]
  bash scripts/ops/security-scan-triage.sh --tool audit-log --audit-jsonl <file> [--repo owner/repo]

Options:
  --tool        Logical scan name used in issue titles and labels.
  --sarif       SARIF file to triage (Semgrep, Trivy, etc.).
  --npm-audit   npm audit JSON file to triage.
  --audit-jsonl  Structured audit JSONL file to triage.
  --repo        GitHub repository in owner/repo form.
  --dry-run     Print intended actions without creating issues.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      TOOL_NAME="${2:-}"
      shift 2
      ;;
    --sarif)
      SARIF_FILE="${2:-}"
      shift 2
      ;;
    --npm-audit)
      NPM_AUDIT_FILE="${2:-}"
      shift 2
      ;;
    --audit-jsonl)
      AUDIT_JSONL_FILE="${2:-}"
      shift 2
      ;;
    --repo)
      GH_REPO="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_fatal "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "${SARIF_FILE}" && -z "${NPM_AUDIT_FILE}" && -z "${AUDIT_JSONL_FILE}" ]]; then
  log_fatal "Provide --sarif, --npm-audit, or --audit-jsonl"
fi

if [[ -n "${SARIF_FILE}" && ! -f "${SARIF_FILE}" ]]; then
  log_fatal "SARIF file not found: ${SARIF_FILE}"
fi

if [[ -n "${NPM_AUDIT_FILE}" && ! -f "${NPM_AUDIT_FILE}" ]]; then
  log_fatal "npm audit file not found: ${NPM_AUDIT_FILE}"
fi

if [[ -n "${AUDIT_JSONL_FILE}" && ! -f "${AUDIT_JSONL_FILE}" ]]; then
  log_fatal "audit JSONL file not found: ${AUDIT_JSONL_FILE}"
fi

if [[ "${DRY_RUN}" != "true" ]] && ! command -v gh >/dev/null 2>&1; then
  log_fatal "gh CLI is required for issue routing"
fi

if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  log_fatal "Either jq or python3 is required for scan parsing"
fi

if [[ "${DRY_RUN}" != "true" && -z "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]]; then
  log_fatal "GitHub token is required for issue routing"
fi

normalize_text() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[0-9a-f]{8,}/<hex>/g; s/[0-9]{2,}/<num>/g; s/[[:space:]]+/ /g; s/^ //; s/ $//'
}

issue_fingerprint() {
  printf '%s' "$1" | sha256sum | awk '{print substr($1, 1, 12)}'
}

extract_sarif_findings() {
  local sarif_file="$1"
  local scan_name="$2"

  if command -v jq >/dev/null 2>&1; then
    jq -r --arg scan "$scan_name" '
      .runs[]?.results[]? |
      select((.level // "warning") != "note" and (.level // "warning") != "none") |
      [
        $scan,
        (.ruleId // "unknown-rule"),
        (.level // "warning"),
        ((.message.text // .message // "Security finding") | gsub("\n"; " ")),
        (.locations[0].physicalLocation.artifactLocation.uri // "unknown"),
        ((.locations[0].physicalLocation.region.startLine // 0) | tostring)
      ] | @tsv
    ' "${sarif_file}"
    return 0
  fi

  python3 - "$sarif_file" "$scan_name" <<'PY'
import json
import sys

sarif_path = sys.argv[1]
scan_name = sys.argv[2]
with open(sarif_path, encoding='utf-8') as handle:
    data = json.load(handle)

for run in data.get('runs', []):
    for result in run.get('results', []) or []:
        level = (result.get('level') or 'warning')
        if level in {'note', 'none'}:
            continue
        rule_id = result.get('ruleId') or 'unknown-rule'
        message = result.get('message')
        if isinstance(message, dict):
            message = message.get('text') or str(message)
        else:
            message = str(message)
        locations = result.get('locations') or [{}]
        physical = (locations[0].get('physicalLocation') or {}) if locations else {}
        artifact = physical.get('artifactLocation') or {}
        region = physical.get('region') or {}
        uri = artifact.get('uri') or 'unknown'
        line = str(region.get('startLine') or 0)
        print("\t".join([scan_name, rule_id, level, message.replace('\n', ' '), uri, line]))
PY
}

extract_npm_audit_findings() {
  local audit_file="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -r '
      .vulnerabilities // {} |
      to_entries[] |
      select(.value.severity == "high" or .value.severity == "critical") |
      .value as $v |
      [
        (.key // $v.name // "unknown-package"),
        ($v.severity // "high"),
        ($v.range // "unknown range"),
        (($v.via | map(if type == "object" then (.title // (.source | tostring) // "advisory") else . end) | join("; ")) // "advisory"),
        (($v.fixAvailable | tostring) // "false")
      ] | @tsv
    ' "${audit_file}"
    return 0
  fi

  python3 - "$audit_file" <<'PY'
import json
import sys

audit_path = sys.argv[1]
with open(audit_path, encoding='utf-8') as handle:
    data = json.load(handle)

for package_name, payload in (data.get('vulnerabilities') or {}).items():
    severity = payload.get('severity') or 'high'
    if severity not in {'high', 'critical'}:
        continue
    range_value = payload.get('range') or 'unknown range'
    via_items = payload.get('via') or []
    advisories = []
    for item in via_items:
        if isinstance(item, dict):
            advisories.append(str(item.get('title') or item.get('source') or 'advisory'))
        else:
            advisories.append(str(item))
    if not advisories:
        advisories = ['advisory']
    fix_available = str(payload.get('fixAvailable') or 'false')
    print("\t".join([package_name, severity, range_value, '; '.join(advisories), fix_available]))
PY
}

extract_audit_findings() {
  local audit_file="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -r '
      select(
        .event_type == "SHELL_VIOLATION" or
        .event_type == "FILE_WRITE_ATTEMPT" or
        .event_type == "FILE_DELETE_ATTEMPT" or
        .event_type == "FILE_DOWNLOAD_ATTEMPT" or
        .event_type == "policy.denied" or
        .event_type == "SECURITY_POLICY_VIOLATION" or
        .status == "blocked" or
        .status == "denied"
      ) |
      [
        (.event_type // "audit-event"),
        (.component // "audit"),
        (.status // "unknown"),
        ((.timestamp // "unknown") + " | " + (.details | tostring)),
        (.developer_id // "unknown"),
        (.ip_address // "unknown")
      ] | @tsv
    ' "${audit_file}"
    return 0
  fi

  python3 - "$audit_file" <<'PY'
import json
import sys

audit_path = sys.argv[1]
target_events = {
    'SHELL_VIOLATION',
    'FILE_WRITE_ATTEMPT',
    'FILE_DELETE_ATTEMPT',
    'FILE_DOWNLOAD_ATTEMPT',
    'policy.denied',
    'SECURITY_POLICY_VIOLATION',
}

with open(audit_path, encoding='utf-8') as handle:
    for raw_line in handle:
        line = raw_line.strip()
        if not line:
            continue
        event = json.loads(line)
        event_type = event.get('event_type') or ''
        status = event.get('status') or ''
        if event_type not in target_events and status not in {'blocked', 'denied'}:
            continue
        timestamp = event.get('timestamp') or 'unknown'
        component = event.get('component') or 'audit'
        developer_id = event.get('developer_id') or 'unknown'
        ip_address = event.get('ip_address') or 'unknown'
        details = event.get('details')
        print("\t".join([
            event_type or 'audit-event',
            component,
            status or 'unknown',
            f"{timestamp} | {details}",
            developer_id,
            ip_address,
        ]))
PY
}

find_existing_issue() {
  local marker="$1"
  if [[ "${DRY_RUN}" == "true" && -z "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]]; then
    echo ""
    return 0
  fi

  gh issue list --repo "${GH_REPO}" --state open --limit 200 --json number,body \
    | jq -r --arg marker "$marker" '.[] | select(.body | contains($marker)) | .number' \
    | head -1
}

route_issue() {
  local scan_name="$1"
  local severity="$2"
  local title_detail="$3"
  local body_detail="$4"
  local labels="$5"
  local evidence_file="$6"
  local fingerprint_source="$7"

  local fingerprint marker title body existing_issue
  fingerprint="$(issue_fingerprint "$(normalize_text "${fingerprint_source}")")"
  marker="<!-- security-scan-fingerprint:${fingerprint} -->"
  title="[SECURITY][${scan_name}] ${title_detail}"
  body=$(cat <<EOF
${marker}
## Security Scan Finding

**Scan**: ${scan_name}
**Severity**: ${severity}
**Fingerprint**: ${fingerprint}
**Evidence**: ${evidence_file}

### Finding
${body_detail}

### Triage
- [ ] Confirm whether this is a true positive
- [ ] Fix the issue or document a time-bounded suppression
- [ ] Link the remediation PR or suppression PR back here

### Evidence
\`\`\`
${fingerprint_source}
\`\`\`
EOF
)

  existing_issue="$(find_existing_issue "${marker}")"

  if [[ "${DRY_RUN}" == "true" ]]; then
    local preview_body
    preview_body=$(cat <<EOF
${marker}

Additional scan evidence:

${body_detail}
EOF
)
    if [[ -n "${existing_issue}" ]]; then
      log_info "[DRY-RUN] Would comment on issue #${existing_issue} for ${scan_name}: ${title_detail}"
    else
      log_info "[DRY-RUN] Would create issue for ${scan_name}: ${title_detail}"
    fi
    printf '%s\n' "${preview_body}" >/dev/null
    return 0
  fi

  if [[ -n "${existing_issue}" ]]; then
    gh issue comment "${existing_issue}" --repo "${GH_REPO}" --body "$(cat <<EOF
${marker}

Additional scan evidence:

${body_detail}
EOF
)" >/dev/null
    log_info "Updated existing security issue #${existing_issue} for ${scan_name}: ${title_detail}"
  else
    gh issue create --repo "${GH_REPO}" --title "${title}" --body "${body}" --label "${labels}" >/dev/null
    log_info "Created security issue for ${scan_name}: ${title_detail}"
  fi
}

triage_sarif() {
  local sarif_file="$1"
  local scan_name="$2"

  mapfile -t findings < <(extract_sarif_findings "${sarif_file}" "${scan_name}")

  if [[ ${#findings[@]} -eq 0 ]]; then
    log_info "No actionable SARIF findings in ${sarif_file}"
    return 0
  fi

  for finding in "${findings[@]}"; do
    IFS=$'\t' read -r scan_name rule_id level message uri line <<< "${finding}"
    severity="P2"
    if [[ "${level}" == "error" || "${level}" == "high" || "${level}" == "critical" ]]; then
      severity="P1"
    fi

    local detail_body
    detail_body=$(cat <<EOF
  Rule: ${rule_id}
  Location: ${uri}:${line}
  Level: ${level}
Message: ${message}
EOF
)

    route_issue \
      "${scan_name}" \
      "${severity}" \
      "${rule_id} in ${uri}:${line}" \
      "${detail_body}" \
      "security-scan,${scan_name},${severity}" \
      "${sarif_file}" \
      "${scan_name}|${rule_id}|${uri}|${line}|${message}"
  done
}

triage_npm_audit() {
  local audit_file="$1"

  mapfile -t findings < <(extract_npm_audit_findings "${audit_file}")

  if [[ ${#findings[@]} -eq 0 ]]; then
    log_info "No high/critical npm audit findings in ${audit_file}"
    return 0
  fi

  for finding in "${findings[@]}"; do
    IFS=$'\t' read -r package_name severity range advisories fix_available <<< "${finding}"

    local detail_body
    detail_body=$(cat <<EOF
  Package: ${package_name}
  Range: ${range}
Advisories: ${advisories}
  Fix available: ${fix_available}
EOF
)

    route_issue \
      "npm-audit" \
      "${severity^^}" \
      "${package_name} vulnerability" \
      "${detail_body}" \
      "security-scan,npm-audit,${severity}" \
      "${audit_file}" \
      "npm-audit|${package_name}|${range}|${advisories}"
  done
}

if [[ -n "${SARIF_FILE}" ]]; then
  triage_sarif "${SARIF_FILE}" "${TOOL_NAME}"
fi

if [[ -n "${NPM_AUDIT_FILE}" ]]; then
  triage_npm_audit "${NPM_AUDIT_FILE}"
fi

if [[ -n "${AUDIT_JSONL_FILE}" ]]; then
  mapfile -t findings < <(extract_audit_findings "${AUDIT_JSONL_FILE}")

  if [[ ${#findings[@]} -eq 0 ]]; then
    log_info "No actionable audit findings in ${AUDIT_JSONL_FILE}"
    exit 0
  fi

  for finding in "${findings[@]}"; do
    IFS=$'\t' read -r event_type component status details developer_id ip_address <<< "${finding}"
    severity="P2"
    if [[ "${event_type}" == "SHELL_VIOLATION" || "${event_type}" == "FILE_WRITE_ATTEMPT" || "${event_type}" == "FILE_DELETE_ATTEMPT" || "${event_type}" == "FILE_DOWNLOAD_ATTEMPT" || "${status}" == "blocked" || "${status}" == "denied" ]]; then
      severity="P1"
    fi

    route_issue \
      "audit-log" \
      "${severity}" \
      "${event_type} in ${component} (${status})" \
      "Event: ${event_type}
Component: ${component}
Status: ${status}
Developer: ${developer_id}
IP: ${ip_address}
Details: ${details}" \
      "security-scan,audit-log,${severity}" \
      "${AUDIT_JSONL_FILE}" \
      "audit-log|${event_type}|${component}|${status}|${developer_id}|${ip_address}|${details}"
  done
fi
