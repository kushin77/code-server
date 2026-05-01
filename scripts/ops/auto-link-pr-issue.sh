#!/bin/bash
# @file auto-link-pr-issue.sh
# @module ops/automation
# @description Auto-link GitHub PRs to issues based on title/branch name references
# @governance GOV-002

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# ============================================================================
# Configuration
# ============================================================================
readonly GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
readonly LOG_FILE="artifacts/pr-issue-linking.log"
readonly REPORT_FILE="artifacts/pr-issue-linking-report.json"

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
# Extract Issue References from PR
# ============================================================================

extract_issue_references() {
    local pr_title="$1"
    local pr_body="$2"
    local branch_name="$3"
    
    local -a references=()
    
    # Pattern 1: Fixes #123, Closes #456, Resolves #789
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && references+=("$ref")
    done < <(echo "$pr_title $pr_body" | grep -oE "(Fixes|Closes|Resolves|fix|close|resolve) #[0-9]+" | grep -oE "#[0-9]+" | sort -u)
    
    # Pattern 2: Branch name like "fix/issue-123" or "feature-#456"
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && references+=("#$ref")
    done < <(echo "$branch_name" | grep -oE "(issue|fix|feature)-#?([0-9]+)" | grep -oE "[0-9]+" | sort -u)
    
    # Deduplicate
    printf '%s\n' "${references[@]}" | sort -u | grep -E "^#[0-9]+" || true
}

# ============================================================================
# Link PR to Issue
# ============================================================================

link_pr_to_issue() {
    local pr_number="$1"
    local issue_ref="$2"
    
    log_info "Linking PR #$pr_number to issue $issue_ref"
    
    # Extract issue number
    local issue_num
    issue_num=$(echo "$issue_ref" | grep -oE "[0-9]+")
    
    # Verify issue exists
    if ! github_gh issue view "$issue_num" --repo "$GITHUB_REPO" &>/dev/null; then
        log_error "Issue #$issue_num does not exist"
        return 1
    fi
    
    # Add comment linking PR to issue
    local comment="🔗 Linked from PR #$pr_number"
    if github_gh issue comment "$issue_num" --repo "$GITHUB_REPO" \
        --body "$comment" &>>"$LOG_FILE"; then
        log_success "Linked PR #$pr_number → Issue #$issue_num"
        return 0
    else
        log_error "Failed to link PR #$pr_number to issue #$issue_num"
        return 1
    fi
}

# ============================================================================
# Main: Auto-Link PR
# ============================================================================

main() {
    local pr_number="$1"
    local pr_title="${2:-}"
    local pr_body="${3:-}"
    local branch_name="${4:-}"
    
    if [[ -z "$pr_number" ]]; then
        log_error "Usage: $0 <pr_number> <pr_title> <pr_body> <branch_name>"
        return 1
    fi

    if [[ -z "$pr_title" || -z "$pr_body" || -z "$branch_name" ]]; then
        log_info "Resolving PR metadata from GitHub for #$pr_number"
        pr_title=$(github_gh pr view "$pr_number" --repo "$GITHUB_REPO" --json title -q '.title' 2>/dev/null || echo "")
        pr_body=$(github_gh pr view "$pr_number" --repo "$GITHUB_REPO" --json body -q '.body' 2>/dev/null || echo "")
        branch_name=$(github_gh pr view "$pr_number" --repo "$GITHUB_REPO" --json headRefName -q '.headRefName' 2>/dev/null || echo "")
    fi

    if [[ -z "$pr_title" || -z "$branch_name" ]]; then
        log_error "Unable to resolve PR metadata for #$pr_number"
        return 1
    fi
    
    log_info "=========================================="
    log_info "Auto-Linking PR #$pr_number"
    log_info "=========================================="
    log_info "Title: $pr_title"
    log_info "Branch: $branch_name"
    
    # Extract issue references
    local -a issues
    mapfile -t issues < <(extract_issue_references "$pr_title" "$pr_body" "$branch_name")
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_error "No issue references found in PR #$pr_number"
        log_error "Required format: 'Fixes #123' or branch 'fix/issue-123'"
        return 1
    fi
    
    log_info "Found ${#issues[@]} issue reference(s): ${issues[*]}"
    
    # Link to each issue
    local linked_count=0
    for issue in "${issues[@]}"; do
        if link_pr_to_issue "$pr_number" "$issue"; then
            ((linked_count++))
        fi
    done
    
    # Generate report
    cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "pr_number": $pr_number,
  "issues_found": ${#issues[@]},
  "issues_linked": $linked_count,
  "status": "$([ $linked_count -gt 0 ] && echo "SUCCESS" || echo "FAILED")"
}
EOF
    
    log_success "=========================================="
    log_success "PR #$pr_number linked to $linked_count issue(s)"
    log_success "=========================================="
    
    [[ $linked_count -gt 0 ]] && return 0 || return 1
}

# Execute
main "$@"
