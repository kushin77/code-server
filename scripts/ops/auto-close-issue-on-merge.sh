#!/bin/bash
# @file auto-close-issue-on-merge.sh
# @module ops/automation
# @description Auto-close GitHub issues when linked PR merges
# @governance GOV-002

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Ensure shared initialization and GitHub API client are loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# ============================================================================
# Configuration
# ============================================================================
readonly GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
readonly LOG_FILE="artifacts/pr-merge-issue-close.log"
readonly REPORT_FILE="artifacts/pr-merge-issue-close-report.json"

# ============================================================================
# Logging
# ============================================================================

log_info() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [INFO] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [SUCCESS] $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# Find Linked Issues from PR
# ============================================================================

find_linked_issues() {
    local pr_number="$1"
    
    log_info "Searching for issues linked to PR #$pr_number..."
    
    # Get PR details including body
    local pr_body
    pr_body=$(github_gh pr view "$pr_number" --repo "$GITHUB_REPO" --json body -q '.body' 2>/dev/null || echo "")
    
    local pr_title
    pr_title=$(github_gh pr view "$pr_number" --repo "$GITHUB_REPO" --json title -q '.title' 2>/dev/null || echo "")
    
    local -a issues=()
    
    # Pattern 1: Fixes #123, Closes #456
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && issues+=("$ref")
    done < <(echo "$pr_title $pr_body" | grep -oE "(Fixes|Closes|Resolves) #[0-9]+" | grep -oE "#[0-9]+" | sed 's/#//' | sort -u)
    
    # Pattern 2: Linked via PR comments or automated linking
    # Note: GitHub API automatically creates issue links, but we extract from text
    
    printf '%s\n' "${issues[@]}" | grep -E "^[0-9]+" || true
}

# ============================================================================
# Close Linked Issue
# ============================================================================

close_linked_issue() {
    local issue_number="$1"
    local pr_number="$2"
    local merge_commit="$3"
    
    log_info "Closing issue #$issue_number (linked from merged PR #$pr_number)..."
    
    # Verify issue exists
    if ! github_gh issue view "$issue_number" --repo "$GITHUB_REPO" &>/dev/null; then
        log_error "Issue #$issue_number does not exist"
        return 1
    fi
    
    # Check if already closed
    local state
    state=$(github_gh issue view "$issue_number" --repo "$GITHUB_REPO" --json state -q '.state')
    
    if [[ "$state" == "CLOSED" ]]; then
        log_info "Issue #$issue_number is already closed"
        return 0
    fi
    
    # Add closing comment with PR reference
    local close_comment="Auto-closed via merged PR #$pr_number (commit: ${merge_commit:0:7})"
    
    if ! github_gh issue comment "$issue_number" --repo "$GITHUB_REPO" \
        --body "$close_comment" &>>"$LOG_FILE"; then
        log_error "Failed to add closing comment to issue #$issue_number"
        return 1
    fi
    
    # Close the issue
    if ! github_gh issue close "$issue_number" --repo "$GITHUB_REPO" &>>"$LOG_FILE"; then
        log_error "Failed to close issue #$issue_number"
        return 1
    fi
    
    log_success "Issue #$issue_number closed"
    return 0
}

# ============================================================================
# Handle Race Condition: Multiple PRs → Single Issue
# ============================================================================

check_other_open_prs() {
    local issue_number="$1"
    local exclude_pr="$2"
    
    log_info "Checking for other open PRs linked to issue #$issue_number..."
    
    # Search for other PRs mentioning this issue
    local open_prs
    open_prs=$(github_gh search prs \
        --repo "$GITHUB_REPO" \
        --state open \
        --in title,body \
        "Fixes #$issue_number OR Closes #$issue_number OR Resolves #$issue_number" \
        --json number \
        -q '.[].number' 2>/dev/null || echo "")
    
    local other_prs=0
    while read -r pr; do
        if [[ "$pr" != "$exclude_pr" ]]; then
            ((other_prs++))
            log_info "Found another open PR #$pr linked to issue #$issue_number"
        fi
    done <<< "$open_prs"
    
    log_info "Other open PRs: $other_prs"
    return $other_prs
}

# ============================================================================
# Main: Auto-Close on Merge
# ============================================================================

main() {
    local pr_number="$1"
    local merge_commit="${2:-}"
    
    if [[ -z "$pr_number" ]]; then
        log_error "Usage: $0 <pr_number> [merge_commit]"
        return 1
    fi
    
    log_info "=========================================="
    log_info "Auto-Close Linked Issues from Merged PR #$pr_number"
    log_info "=========================================="
    
    # Get PR merge status
    local merged
    merged=$(github_gh pr view "$pr_number" --repo "$GITHUB_REPO" --json merged -q '.merged' 2>/dev/null)
    
    if [[ "$merged" != "true" ]]; then
        log_error "PR #$pr_number is not merged"
        return 1
    fi
    
    # If no merge commit provided, get it
    if [[ -z "$merge_commit" ]]; then
        merge_commit=$(github_gh pr view "$pr_number" --repo "$GITHUB_REPO" --json mergeCommit -q '.mergeCommit.oid' 2>/dev/null || echo "")
    fi
    
    log_info "PR #$pr_number is merged (commit: ${merge_commit:0:7})"
    
    # Find linked issues
    local -a issues
    mapfile -t issues < <(find_linked_issues "$pr_number")
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_info "No linked issues found for PR #$pr_number"
        return 0
    fi
    
    log_info "Found ${#issues[@]} linked issue(s): ${issues[*]}"
    
    # Close each issue (with race condition check)
    local closed_count=0
    for issue in "${issues[@]}"; do
        # Check for other open PRs first
        if ! check_other_open_prs "$issue" "$pr_number"; then
            # No other open PRs - safe to close
            if close_linked_issue "$issue" "$pr_number" "$merge_commit"; then
                ((closed_count++))
            fi
        else
            log_info "Skipping close of issue #$issue - other open PRs still linked"
        fi
    done
    
    # Generate report
    cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "pr_number": $pr_number,
  "merge_commit": "$merge_commit",
  "issues_linked": ${#issues[@]},
  "issues_closed": $closed_count,
  "status": "$([ $closed_count -gt 0 ] && echo "SUCCESS" || echo "NO_ISSUES_CLOSED")"
}
EOF
    
    log_success "=========================================="
    log_success "Closed $closed_count issue(s) from merged PR #$pr_number"
    log_success "=========================================="
    
    return 0
}

# Execute
main "$@"
