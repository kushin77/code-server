#!/bin/bash
###############################################################################
# @file        scripts/automation/auto-link-pr-to-issue.sh
# @module      automation/auto-link-pr-to-issue
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################
#
# @file scripts/automation/auto-link-pr-to-issue.sh
# @description Auto-link PRs to related GitHub issues (detects from branch/title/body)
# @governance GOV-002: Immutable, deterministic, audit-logged
# @author GitHub Copilot
# @created 2026-04-25
#
# Usage:
#   bash scripts/automation/auto-link-pr-to-issue.sh <pr-number> [--dry-run]
#
# Environment Variables:
#   GITHUB_TOKEN - GitHub personal access token (auto-detected from gh auth)
#   DRY_RUN - Set to true to preview changes without executing
#

set -euo pipefail

readonly SCRIPT_VERSION="1.0"
readonly PR_NUMBER="${1:-}"
readonly DRY_RUN="${2:-false}"
readonly LOG_DIR="artifacts/automation-logs"
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly LOG_FILE="${LOG_DIR}/auto-link-pr-${TIMESTAMP}.log"

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

# Validate input
if [ -z "$PR_NUMBER" ]; then
    log_error "Usage: $0 <pr-number> [--dry-run]"
    exit 1
fi

log_info "Auto-linking PR #$PR_NUMBER to related issues..."

# Fetch PR details
log_info "Fetching PR #$PR_NUMBER details..."
pr_data=$(gh pr view "$PR_NUMBER" --repo kushin77/code-server \
    --json number,title,body,headRefName,state)

pr_title=$(echo "$pr_data" | jq -r '.title')
pr_body=$(echo "$pr_data" | jq -r '.body')
pr_branch=$(echo "$pr_data" | jq -r '.headRefName')

log_info "PR Title: $pr_title"
log_info "PR Branch: $pr_branch"

# Extract issue numbers from various sources
declare -a issue_numbers

# Strategy 1: Extract from PR title (#1234)
if [[ "$pr_title" =~ \#([0-9]+) ]]; then
    issue_numbers+=("${BASH_REMATCH[1]}")
    log_info "Found issue #${BASH_REMATCH[1]} in PR title"
fi

# Strategy 2: Extract from branch name (fix/issue-1234, feat/1234)
if [[ "$pr_branch" =~ ([0-9]{4,}) ]]; then
    issue_numbers+=("${BASH_REMATCH[1]}")
    log_info "Found issue #${BASH_REMATCH[1]} in branch name"
fi

# Strategy 3: Extract from PR body (fixes #1234, related to #1234)
while IFS= read -r line; do
    if [[ "$line" =~ (fixes|related\ to|closes|fix|close|resolve):?\ #([0-9]+) ]]; then
        issue_numbers+=("${BASH_REMATCH[2]}")
        log_info "Found issue #${BASH_REMATCH[2]} in PR body"
    fi
done <<< "$pr_body"

# Remove duplicates
issue_numbers=($(printf '%s\n' "${issue_numbers[@]}" | sort -u))

if [ ${#issue_numbers[@]} -eq 0 ]; then
    log_error "No related issues found in PR #$PR_NUMBER"
    exit 1
fi

log_success "Found ${#issue_numbers[@]} related issue(s): ${issue_numbers[*]}"

# Link each issue to PR
for issue_number in "${issue_numbers[@]}"; do
    log_info "Linking PR #$PR_NUMBER to issue #$issue_number..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would add comment to issue #$issue_number"
    else
        # Add comment to issue linking to PR
        gh issue comment "$issue_number" \
            --repo kushin77/code-server \
            --body "🔗 Related PR: #$PR_NUMBER

This PR addresses this issue. Once merged, this issue will be automatically closed." \
            2>/dev/null || log_error "Failed to comment on issue #$issue_number"
    fi
done

log_success "PR #$PR_NUMBER linked to ${#issue_numbers[@]} issue(s)"
