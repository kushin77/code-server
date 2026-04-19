#!/usr/bin/env bash
# @file        scripts/governance/dispatch-new-repo-onboarding.sh
# @module      governance/github
# @description Dispatch onboarding reconcile events for newly created org repositories
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh" || {
  echo "FATAL: Cannot load _common/init.sh from $SCRIPT_DIR" >&2
  exit 1
}

ORG=""
CONTROL_REPO=""
WINDOW_MINUTES="15"
DRY_RUN="false"
GH_CLI=""

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/dispatch-new-repo-onboarding.sh --org <org> --control-repo <owner/repo> [--window-minutes <int>] [--dry-run]

Examples:
  scripts/governance/dispatch-new-repo-onboarding.sh --org kushin77 --control-repo kushin77/code-server
  scripts/governance/dispatch-new-repo-onboarding.sh --org kushin77 --control-repo kushin77/code-server --window-minutes 20
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      ORG="$2"
      shift 2
      ;;
    --control-repo)
      CONTROL_REPO="$2"
      shift 2
      ;;
    --window-minutes)
      WINDOW_MINUTES="$2"
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
      log_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$ORG" || -z "$CONTROL_REPO" ]]; then
  log_error "--org and --control-repo are required"
  usage
  exit 1
fi

if [[ ! "$WINDOW_MINUTES" =~ ^[0-9]+$ ]] || [[ "$WINDOW_MINUTES" -lt 1 ]]; then
  log_error "--window-minutes must be a positive integer"
  exit 1
fi

if command -v gh >/dev/null 2>&1; then
  GH_CLI="gh"
elif command -v gh.exe >/dev/null 2>&1; then
  GH_CLI="gh.exe"
else
  log_fatal "Required command not found: gh (or gh.exe)"
fi

# Do not auto-bootstrap tokens here; callers/workflows should provide GH auth.
# This keeps local dry-runs deterministic and avoids hidden auth side effects.

cutoff_iso="$(date -u -d "-${WINDOW_MINUTES} minutes" +%Y-%m-%dT%H:%M:%SZ)"
control_repo_name="${CONTROL_REPO#*/}"

if ! repo_rows="$("$GH_CLI" api "orgs/${ORG}/repos" --paginate --jq '.[] | [(.name // ""), (.created_at // ""), (.archived|tostring), (.disabled|tostring)] | @tsv' 2>/tmp/dispatch-repos.err)"; then
  err_msg="$(cat /tmp/dispatch-repos.err 2>/dev/null || true)"
  rm -f /tmp/dispatch-repos.err
  log_fatal "Unable to list repos for org '${ORG}'. Ensure gh auth is configured (GH_TOKEN/GITHUB_TOKEN or gh auth login). Details: ${err_msg:-unknown error}"
fi
rm -f /tmp/dispatch-repos.err

scanned_count=0
candidate_count=0
dispatched_count=0

while IFS=$'\t' read -r repo_name created_at archived disabled; do
  [[ -z "$repo_name" ]] && continue
  scanned_count=$((scanned_count + 1))

  [[ "$archived" == "true" ]] && continue
  [[ "$disabled" == "true" ]] && continue
  [[ "$repo_name" == "$control_repo_name" ]] && continue
  [[ -z "$created_at" ]] && continue
  [[ "$created_at" < "$cutoff_iso" ]] && continue

  candidate_count=$((candidate_count + 1))

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would dispatch repo-onboarded for ${ORG}/${repo_name} to ${CONTROL_REPO}"
    continue
  fi

  payload="$(printf '{"event_type":"repo-onboarded","client_payload":{"repo":"%s","org":"%s","source":"auto-onboarding-dispatch"}}' "$repo_name" "$ORG")"
  if "$GH_CLI" api "repos/${CONTROL_REPO}/dispatches" -X POST --input <(printf '%s' "$payload") >/dev/null; then
    log_info "Dispatched repo-onboarded for ${ORG}/${repo_name}"
    dispatched_count=$((dispatched_count + 1))
  else
    log_warn "Failed to dispatch onboarding event for ${ORG}/${repo_name}"
  fi
done <<< "$repo_rows"

log_info "Onboarding dispatch summary: scanned=$scanned_count candidates=$candidate_count dispatched=$dispatched_count window_minutes=$WINDOW_MINUTES cutoff=$cutoff_iso"
