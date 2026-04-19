#!/usr/bin/env bash
# @file        scripts/ci/validate-triage-open-backlog.sh
# @module      ci/governance
# @description Validate that triage Open Backlog issues are unique and still open
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

DOC_PATH="${DOC_PATH:-docs/governance/elite-best-practices/instructions/TRIAGE-NEXT-STEPS-EXECUTION-2026-04-18.md}"

require_file "$DOC_PATH" "Triage next-steps document is required"

GH_BIN=""
if command -v gh >/dev/null 2>&1; then
  GH_BIN="gh"
elif command -v gh.exe >/dev/null 2>&1; then
  GH_BIN="gh.exe"
else
  log_fatal "GitHub CLI is required (gh or gh.exe not found)"
fi

if ! "$GH_BIN" auth status >/dev/null 2>&1; then
  log_fatal "GitHub CLI is not authenticated. Run 'gh auth login' first."
fi

log_info "Validating Open Backlog section in $DOC_PATH"

# Extract issue IDs only from Open Backlog section.
mapfile -t backlog_ids < <(
  awk '
    /^## Issue-Mapped Next Steps \(Open Backlog\)/ { in_section=1; next }
    /^## Execution Order/ { in_section=0 }
    in_section { print }
  ' "$DOC_PATH" | grep -oE '#[0-9]+' | tr -d '#' || true
)

if [[ ${#backlog_ids[@]} -eq 0 ]]; then
  log_fatal "No issue references found in Open Backlog section."
fi

declare -A seen=()
declare -A duplicate=()

for issue_id in "${backlog_ids[@]}"; do
  if [[ -n "${seen[$issue_id]:-}" ]]; then
    duplicate[$issue_id]=1
  fi
  seen[$issue_id]=1
done

if [[ ${#duplicate[@]} -gt 0 ]]; then
  for issue_id in "${!duplicate[@]}"; do
    log_error "Duplicate issue #$issue_id found in Open Backlog section"
  done
  log_fatal "Open Backlog section contains duplicate issues"
fi

has_failure=0

for issue_id in "${!seen[@]}"; do
  issue_state="$("$GH_BIN" issue view "$issue_id" --json state --template '{{.state}}' 2>/dev/null || echo "UNKNOWN")"
  issue_title="$("$GH_BIN" issue view "$issue_id" --json title --template '{{.title}}' 2>/dev/null || echo "<unavailable>")"

  if [[ "$issue_state" != "OPEN" ]]; then
    log_error "FAIL: #$issue_id is $issue_state but listed in Open Backlog -> $issue_title"
    has_failure=1
  else
    log_info "PASS: #$issue_id is OPEN -> $issue_title"
  fi
done

if [[ "$has_failure" -ne 0 ]]; then
  log_fatal "Triage Open Backlog validation failed"
fi

log_info "Triage Open Backlog validation passed (${#seen[@]} issues checked)"
