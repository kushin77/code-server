#!/usr/bin/env bash
# @file        scripts/_common/copilot-session-init.sh
# @module      governance/copilot-automation
# @description Copilot session initialization - search for existing work before task execution
#
# MANDATE: Every Copilot task MUST source this script and run copilot_pre_execute_check()
# before starting work. This prevents duplicate issues, finds existing implementations,
# and ensures idempotent, immutable operations.
#
# Usage:
#   source scripts/_common/copilot-session-init.sh
#   copilot_pre_execute_check --task "description" --repo kushin77/code-server
#   # If check returns 0, proceed with task. If 1, review findings and update plan.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/config.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Cache settings (prevent GitHub API hammering)
COPILOT_SESSION_CACHE="/tmp/copilot-session-$(date +%Y%m%d-%H%M%S).json"
COPILOT_CACHE_TTL=300  # 5 minutes

# GitHub repo context
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"

# ============================================================================
# SEARCH & DEDUPLICATION
# ============================================================================

# Search GitHub issues for related work
search_for_existing_issues() {
    local task_description="$1"
    local repo="$2"
    
    log_info "Searching for existing issues related to: $task_description"
    
    # Extract keywords from task description
    local keywords
    keywords=$(echo "$task_description" | grep -oE '\b[a-z]{4,}\b' | sort -u | head -10 | tr '\n' ' ')
    
    if [[ -z "$keywords" ]]; then
        log_warn "Could not extract keywords from task description"
        return 1
    fi
    
    # Search GitHub issues
    local search_query="repo:$repo is:open $keywords"
    
    log_info "Search query: $search_query"
    
    gh issue list --repo "$repo" \
        --state open \
        --limit 50 \
        --json "number,title,labels,state,updatedAt" 2>/dev/null | \
    jq --arg keywords "$keywords" '
        .[] |
        select(
            (.title | test($keywords; "i")) or
            (.title | test("duplicate|existing|already|pending"; "i"))
        ) |
        {number, title, labels: [.labels[] | .name], updatedAt}
    ' | head -20
    
    return 0
}

# Search repository for existing implementations
search_for_existing_code() {
    local task_description="$1"
    local search_patterns=()
    
    log_info "Searching repository for existing implementations..."
    
    # Extract key terms and convert to patterns
    local patterns
    patterns=$(echo "$task_description" | sed -E 's/^(feat|fix|refactor|docs|ci|chore)\(.*\):\s*//; s/[^a-z0-9 ]//g' | tr ' ' '\n' | grep -v '^$' | head -5)
    
    if [[ -z "$patterns" ]]; then
        log_warn "Could not extract patterns from task"
        return 1
    fi
    
    # Search for implementations
    grep -r --include="*.ts" --include="*.js" --include="*.sh" --include="*.py" \
        --exclude-dir=node_modules --exclude-dir=.git \
        $(echo "$patterns" | head -1) . 2>/dev/null | head -10 || true
    
    return 0
}

# Check if work is already in progress
check_work_in_progress() {
    local task_description="$1"
    local repo="$2"
    
    log_info "Checking for in-progress work..."
    
    # Search for open PRs with similar description
    gh pr list --repo "$repo" \
        --state open \
        --json "number,title,headRefName" \
        --limit 50 2>/dev/null | \
    jq --arg search "$task_description" '
        .[] |
        select(.title | test($search; "i")) |
        {number, title, branch: .headRefName}
    ' | head -10
    
    return 0
}

# ============================================================================
# IDEMPOTENT WORK VALIDATION
# ============================================================================

# Check if work is already completed
check_work_completed() {
    local issue_number="$1"
    local repo="$2"
    
    if [[ -z "$issue_number" ]]; then
        return 1
    fi
    
    # Get issue state
    local state
    state=$(gh issue view "$issue_number" --repo "$repo" --json state --jq '.state' 2>/dev/null)
    
    if [[ "$state" == "CLOSED" ]]; then
        log_warn "Issue #$issue_number is already CLOSED"
        return 0  # Work is done
    fi
    
    return 1  # Work is not done
}

# Validate work is idempotent (safe to run multiple times)
validate_idempotent_operation() {
    local task_description="$1"
    
    # Check for idempotency anti-patterns
    local anti_patterns=(
        "delete database"
        "remove all"
        "clear everything"
        "truncate table"
        "DROP TABLE"
        "force push"
        "force delete"
    )
    
    for pattern in "${anti_patterns[@]}"; do
        if [[ "$task_description" =~ $pattern ]]; then
            log_error "⚠️  DANGER: Task contains non-idempotent operation: '$pattern'"
            log_error "Idempotent operations must be safe to run multiple times without side effects."
            return 1
        fi
    done
    
    log_info "✓ Task passes idempotency validation"
    return 0
}

# ============================================================================
# PRE-EXECUTION CHECK (Main Entry Point)
# ============================================================================

copilot_pre_execute_check() {
    local task_description=""
    local repo="$GITHUB_REPO"
    local issue_number=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task)
                task_description="$2"
                shift 2
                ;;
            --repo)
                repo="$2"
                shift 2
                ;;
            --issue)
                issue_number="$2"
                shift 2
                ;;
            *)
                log_fatal "Unknown option: $1"
                ;;
        esac
    done
    
    if [[ -z "$task_description" ]]; then
        log_fatal "Missing required parameter: --task"
    fi
    
    log_info ""
    log_info "╔══════════════════════════════════════════════════════════╗"
    log_info "║  COPILOT SESSION INITIALIZATION - PRE-EXECUTION CHECK    ║"
    log_info "╚══════════════════════════════════════════════════════════╝"
    log_info ""
    log_info "Task: $task_description"
    log_info "Repository: $repo"
    log_info ""
    
    # ========================================================================
    # STAGE 1: VALIDATE IDEMPOTENCY
    # ========================================================================
    
    log_info "STAGE 1: Validating idempotency..."
    if ! validate_idempotent_operation "$task_description"; then
        log_error ""
        log_error "✗ BLOCKED: Task contains non-idempotent operations."
        log_error "Refactor task to be safe to run multiple times without side effects."
        return 1
    fi
    log_info "✓ Task is idempotent"
    log_info ""
    
    # ========================================================================
    # STAGE 2: CHECK IF WORK IS COMPLETED
    # ========================================================================
    
    if [[ -n "$issue_number" ]]; then
        log_info "STAGE 2: Checking if work is already completed..."
        if check_work_completed "$issue_number" "$repo"; then
            log_warn ""
            log_warn "ℹ️  Issue #$issue_number is already CLOSED."
            log_warn "Review the issue to understand prior resolution before proceeding."
            log_info ""
            return 1
        fi
        log_info "✓ Issue #$issue_number is open and ready for work"
        log_info ""
    else
        log_info "STAGE 2: Skipping completed check (no issue number provided)"
        log_info ""
    fi
    
    # ========================================================================
    # STAGE 3: SEARCH FOR DUPLICATE ISSUES
    # ========================================================================
    
    log_info "STAGE 3: Searching for duplicate/related issues..."
    local existing_issues
    existing_issues=$(search_for_existing_issues "$task_description" "$repo" 2>/dev/null || echo "[]")
    
    local issue_count
    issue_count=$(echo "$existing_issues" | jq 'length' 2>/dev/null || echo 0)
    
    if [[ $issue_count -gt 0 ]]; then
        log_warn ""
        log_warn "Found $issue_count related open issues:"
        echo "$existing_issues" | jq -r '.[] | "  #\(.number): \(.title)"' || true
        log_warn ""
        log_warn "Review these issues before starting work:"
        log_warn "- Check if any duplicate your planned work"
        log_warn "- Link related issues in PR description"
        log_warn "- Update existing issues if your work relates to them"
    else
        log_info "✓ No duplicate issues found"
    fi
    log_info ""
    
    # ========================================================================
    # STAGE 4: SEARCH FOR WORK IN PROGRESS
    # ========================================================================
    
    log_info "STAGE 4: Checking for work in progress..."
    local wip_prs
    wip_prs=$(check_work_in_progress "$task_description" "$repo" 2>/dev/null || echo "[]")
    
    local wip_count
    wip_count=$(echo "$wip_prs" | jq 'length' 2>/dev/null || echo 0)
    
    if [[ $wip_count -gt 0 ]]; then
        log_warn ""
        log_warn "Found $wip_count in-progress PRs:"
        echo "$wip_prs" | jq -r '.[] | "  #\(.number): \(.title) (branch: \(.branch))"' || true
        log_warn ""
        log_warn "Possible actions:"
        log_warn "- Link to existing PR if work is related"
        log_warn "- Request review if PR needs attention"
        log_warn "- Merge if ready, or update if waiting"
    else
        log_info "✓ No conflicting work in progress"
    fi
    log_info ""
    
    # ========================================================================
    # STAGE 5: SEARCH FOR EXISTING IMPLEMENTATIONS
    # ========================================================================
    
    log_info "STAGE 5: Searching repository for existing code..."
    local existing_code
    existing_code=$(search_for_existing_code "$task_description" 2>/dev/null || echo "")
    
    if [[ -n "$existing_code" ]]; then
        log_warn ""
        log_warn "Found potentially relevant existing code:"
        echo "$existing_code" | head -5 || true
        log_warn ""
        log_warn "Review to avoid reimplementing existing functionality."
    else
        log_info "✓ No obvious implementations found"
    fi
    log_info ""
    
    # ========================================================================
    # STAGE 6: FINAL SUMMARY & RECOMMENDATION
    # ========================================================================
    
    log_info "╔══════════════════════════════════════════════════════════╗"
    log_info "║  PRE-EXECUTION SUMMARY                                  ║"
    log_info "╚══════════════════════════════════════════════════════════╝"
    log_info ""
    
    if [[ $issue_count -eq 0 ]] && [[ $wip_count -eq 0 ]]; then
        log_info "✓ Green light - no blocking issues found"
        log_info "✓ Task is idempotent and safe"
        log_info ""
        log_info "Next steps:"
        log_info "1. Create issue or link existing issue"
        log_info "2. Create branch from main"
        log_info "3. Implement changes"
        log_info "4. Create PR with issue reference (Fixes #N)"
        log_info "5. Merge after approval"
        log_info ""
        return 0
    else
        log_warn ""
        log_warn "⚠️  Review findings above before proceeding"
        log_warn ""
        return 1
    fi
}

# ============================================================================
# EXPORTS
# ============================================================================

export -f copilot_pre_execute_check
export -f search_for_existing_issues
export -f search_for_existing_code
export -f check_work_in_progress
export -f validate_idempotent_operation
