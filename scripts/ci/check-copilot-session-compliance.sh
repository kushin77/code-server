#!/usr/bin/env bash
# @file        scripts/ci/check-copilot-session-compliance.sh
# @module      ci/governance
# @description Enforce that major tasks document pre-execution check (Rule 9)
#
# Validates PR titles/bodies for Rule 9 compliance:
# - Copilot tasks must document pre-execution check
# - No PRs without "pre-execute-check: ✓" or "search complete" markers
# - Warns on suspicious patterns (duplicate prevention not attempted)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Markers that indicate pre-execution check was done
COMPLIANCE_MARKERS=(
    "pre-execution check"
    "pre-execute-check"
    "search-aware"
    "copilot_pre_execute_check"
    "✓ Green light"
    "searched for"
    "found.*duplicate"
    "no conflicts found"
    "idempotency validated"
)

# PR authors exempt from check (bots, automation)
EXEMPT_AUTHORS=(
    "dependabot"
    "renovate"
    "github-actions"
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

is_copilot_task() {
    local pr_body="$1"
    
    # Heuristic: Copilot tasks often have:
    # - Multiple files changed
    # - Structured descriptions
    # - References to implementations/phases
    
    if [[ "$pr_body" =~ (feat|fix|refactor)\(#[0-9]+\) ]]; then
        return 0  # Likely Copilot task
    fi
    
    return 1
}

check_compliance_marker() {
    local pr_body="$1"
    
    for marker in "${COMPLIANCE_MARKERS[@]}"; do
        if [[ "$pr_body" =~ $marker ]]; then
            return 0  # Found marker
        fi
    done
    
    return 1  # No marker found
}

is_exempt_author() {
    local author="$1"
    
    for exempt in "${EXEMPT_AUTHORS[@]}"; do
        if [[ "$author" =~ $exempt ]]; then
            return 0  # Exempt author
        fi
    done
    
    return 1  # Not exempt
}

count_files_changed() {
    local pr_number="$1"
    local repo="${2:-kushin77/code-server}"
    
    gh pr view "$pr_number" --repo "$repo" \
        --json files --jq '.files | length' 2>/dev/null || echo 0
}

# ============================================================================
# MAIN CHECK
# ============================================================================

main() {
    local pr_number="${1:-}"
    local repo="${2:-kushin77/code-server}"
    
    if [[ -z "$pr_number" ]]; then
        log_fatal "Usage: $0 <pr_number> [repo]"
    fi
    
    log_info "Checking Rule 9 Compliance (Copilot Session Initialization)..."
    log_info "PR #$pr_number in $repo"
    log_info ""
    
    # ========================================================================
    # Get PR details
    # ========================================================================
    
    local pr_data
    pr_data=$(gh pr view "$pr_number" --repo "$repo" \
        --json "title,body,author,files" 2>/dev/null)
    
    local pr_title
    pr_title=$(echo "$pr_data" | jq -r '.title')
    
    local pr_body
    pr_body=$(echo "$pr_data" | jq -r '.body // ""')
    
    local pr_author
    pr_author=$(echo "$pr_data" | jq -r '.author.login // "unknown"')
    
    local files_count
    files_count=$(echo "$pr_data" | jq '.files | length')
    
    log_info "Title: $pr_title"
    log_info "Author: $pr_author"
    log_info "Files changed: $files_count"
    log_info ""
    
    # ========================================================================
    # Skip exempt authors (bots, automation)
    # ========================================================================
    
    if is_exempt_author "$pr_author"; then
        log_info "✓ Author is exempt from Rule 9 check (automation/bot)"
        return 0
    fi
    
    # ========================================================================
    # Skip if not a Copilot task
    # ========================================================================
    
    if ! is_copilot_task "$pr_body"; then
        log_info "ℹ  Not a Copilot task (no governance markers in description)"
        log_info "✓ Skipping Rule 9 check (not applicable)"
        return 0
    fi
    
    log_info "⚠ Detected Copilot task (governance markers present)"
    log_info "→ Enforcing Rule 9: Pre-Execution Check Documentation"
    log_info ""
    
    # ========================================================================
    # Check for compliance marker
    # ========================================================================
    
    if check_compliance_marker "$pr_body"; then
        log_info "✓ PR body contains pre-execution check documentation"
        log_info "✓ Rule 9 PASSED"
        return 0
    fi
    
    # ========================================================================
    # Compliance failed - provide guidance
    # ========================================================================
    
    log_error ""
    log_error "✗ Rule 9 FAILED: Missing pre-execution check documentation"
    log_error ""
    log_error "What happened:"
    log_error "  This PR appears to be a Copilot task but doesn't document"
    log_error "  the pre-execution check (search for existing work)."
    log_error ""
    log_error "What to do:"
    log_error "  1. Run pre-execution check before merge:"
    log_error "     source scripts/_common/copilot-session-init.sh"
    log_error "     copilot_pre_execute_check --task 'your task' --repo $repo"
    log_error ""
    log_error "  2. Document findings in PR description:"
    log_error "     - Did you search for duplicates? What did you find?"
    log_error "     - Any existing code that could be reused?"
    log_error "     - Any work in progress?"
    log_error "     - Include: '✓ Pre-execution check: ...'"
    log_error ""
    log_error "  3. Push updated PR"
    log_error ""
    log_error "Reference: Rule 9 in .github/copilot-instructions.md"
    log_error "Documentation: docs/COPILOT-SESSION-INITIALIZATION.md"
    log_error ""
    
    return 1
}

# ============================================================================
# ENTRY POINT
# ============================================================================

main "$@"
