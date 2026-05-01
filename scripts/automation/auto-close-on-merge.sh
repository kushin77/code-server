#!/bin/bash
###############################################################################
# @file        scripts/automation/auto-close-on-merge.sh
# @module      automation/auto-close-on-merge
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"
###############################################################################
#
# @file scripts/automation/auto-close-on-merge.sh
# @description Auto-close issues when related PRs are merged
# @governance GOV-002: Idempotent, deterministic, audit-logged
# @author GitHub Copilot
# @created 2026-04-25
#
# Usage:
#   bash scripts/automation/auto-close-on-merge.sh <pr-number> [--dry-run]
#
# Process:
#   1. Get merged PR details
#   2. Find linked issues (from comments, PR body)
#   3. Check if PR is merged
#   4. Close issue with reference to PR
#   5. Log all actions
#

set -euo pipefail

readonly SCRIPT_VERSION="1.0"
readonly PR_NUMBER="${1:-}"
readonly DRY_RUN="${2:-false}"
readonly LOG_DIR="artifacts/automation-logs"
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly LOG_FILE="${LOG_DIR}/auto-close-on-merge-${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*" | tee -a "$LOG_FILE"
}

if [ -z "$PR_NUMBER" ]; then
    log_error "Usage: $0 <pr-number> [--dry-run]"
    exit 1
fi

log_info "Checking PR #$PR_NUMBER for auto-close eligibility..."

# Fetch PR details
pr_data=$(gh pr view "$PR_NUMBER" --repo kushin77/code-server \
    --json number,title,body,state,mergedAt,reviews)

pr_state=$(echo "$pr_data" | jq -r '.state')
merged_at=$(echo "$pr_data" | jq -r '.mergedAt')
pr_title=$(echo "$pr_data" | jq -r '.title')
pr_body=$(echo "$pr_data" | jq -r '.body')

# Check if merged
if [ "$pr_state" != "MERGED" ] || [ "$merged_at" == "null" ]; then
    log_error "PR #$PR_NUMBER is not merged (state: $pr_state)"
    exit 1
fi

log_success "PR #$PR_NUMBER is merged (at $merged_at)"

# Extract issue numbers from PR body
declare -a issue_numbers

# Look for "fixes #1234", "closes #1234", "resolves #1234"
while IFS= read -r line; do
    if [[ "$line" =~ (fixes|closes|resolves):?\ #([0-9]+) ]]; then
        issue_numbers+=("${BASH_REMATCH[2]}")
        log_info "Found linked issue #${BASH_REMATCH[2]}"
    fi
done <<< "$pr_body"

# Remove duplicates
issue_numbers=($(printf '%s\n' "${issue_numbers[@]}" | sort -u))

if [ ${#issue_numbers[@]} -eq 0 ]; then
    log_error "No linked issues found in PR #$PR_NUMBER"
    exit 1
fi

log_info "Found ${#issue_numbers[@]} linked issue(s): ${issue_numbers[*]}"

# Close each linked issue
closed_count=0
for issue_number in "${issue_numbers[@]}"; do
    log_info "Closing issue #$issue_number (merged from PR #$PR_NUMBER)..."
    
    issue_state=$(gh issue view "$issue_number" --repo kushin77/code-server \
        --json state | jq -r '.state')
    
    if [ "$issue_state" == "CLOSED" ]; then
        log_info "Issue #$issue_number already closed"
        continue
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would close issue #$issue_number"
    else
        # Close the issue
        gh issue close "$issue_number" \
            --repo kushin77/code-server \
            --comment "✅ Resolved by PR #$PR_NUMBER (merged on $merged_at)

This issue has been automatically closed as the related pull request has been merged." \
            2>/dev/null || log_error "Failed to close issue #$issue_number"
        
        closed_count+=1
    fi
done

log_success "Auto-close complete: $closed_count issue(s) closed"
