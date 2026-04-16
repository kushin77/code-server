#!/usr/bin/env bash
################################################################################
# ci-merge-automation.sh
# CI Completion Monitor & Automatic Merge Executor for Phase PRs
# LINUX MANDATORY: GitHub API automation
#
# Usage:
#   ./ci-merge-automation.sh --monitor [--check-interval 30]
#   ./ci-merge-automation.sh --monitor --merge
#   ./ci-merge-automation.sh --merge
#
# Monitors GitHub Actions CI for PRs and executes merge sequence when all checks pass.
# Default sequence: #167 (Phase 9) → #136 (Phase 10) → #137 (Phase 11) → main
#
# Author: GitHub Copilot | April 14, 2026
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "$SCRIPT_DIR/../common-functions.sh"

# Configuration
REPO="${REPO:-kushin77/code-server}"
MONITOR=false
MERGE=false
CHECK_INTERVAL=30

# Target PRs (can be overridden)
PR_PHASE9="${PR_PHASE9:-167}"
PR_PHASE10="${PR_PHASE10:-136}"
PR_PHASE11="${PR_PHASE11:-137}"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
  -m, --monitor              Monitor CI status until all checks pass
  -M, --merge                Execute merge when CI passes
  -i, --check-interval SECS  Check interval in seconds (default: 30)
  -r, --repo REPO            Repository (default: kushin77/code-server)
  -h, --help                 Show this help message

EXAMPLES:
  Monitor CI status:
    $0 --monitor

  Monitor and auto-merge when ready:
    $0 --monitor --merge

  Execute merge if all CI passed:
    $0 --merge

  Monitor with custom check interval:
    $0 --monitor --check-interval 60
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--monitor) MONITOR=true; shift ;;
        -M|--merge) MERGE=true; shift ;;
        -i|--check-interval) CHECK_INTERVAL="$2"; shift 2 ;;
        -r|--repo) REPO="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) die "Unknown option: $1" ;;
    esac
done

require_github_cli

# ─────────────────────────────────────────────────────────────────────────────
# FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

get_pr_check_status() {
    local pr_number="$1"
    local output
    
    output=$(gh pr checks "$pr_number" --repo "$REPO" 2>&1 || echo "ERROR")
    
    if echo "$output" | grep -q "All checks passed"; then
        echo "PASSED"
    elif echo "$output" | grep -q "Some checks failed"; then
        echo "FAILED"
    elif echo "$output" | grep -q "ERROR\|pr not found"; then
        echo "ERROR"
    else
        echo "RUNNING"
    fi
}

get_pr_check_details() {
    local pr_number="$1"
    local output
    
    output=$(gh pr checks "$pr_number" --repo "$REPO" 2>&1 || echo "")
    
    local pending
    local failed
    pending=$(echo "$output" | grep -c "pending" || echo 0)
    failed=$(echo "$output" | grep -c "failed" || echo 0)
    
    if [[ $pending -gt 0 || $failed -gt 0 ]]; then
        echo "$pending pending, $failed failed"
    else
        echo "$output" | head -1 || echo "No details available"
    fi
}

merge_pr() {
    local pr_number="$1"
    
    write_info "→ Merging PR #$pr_number..."
    
    if gh pr merge "$pr_number" --repo "$REPO" --merge 2>&1 | grep -q "Pull Request successfully merged"; then
        write_success "✅ PR #$pr_number merged to main"
        return 0
    else
        write_error "❌ Failed to merge PR #$pr_number"
        return 1
    fi
}

monitor_ci() {
    write_section "CI Status Monitor"
    write_info "Checking PR #$PR_PHASE9 (Phase 9), #$PR_PHASE10 (Phase 10), #$PR_PHASE11 (Phase 11)"
    write_info "Check interval: $CHECK_INTERVAL seconds"
    write_info "Repository: $REPO"
    write_info ""
    
    local iteration=0
    
    while true; do
        ((iteration++))
        local timestamp
        timestamp=$(date '+%H:%M:%S')
        
        write_warning "[$timestamp] Check #$iteration"
        
        local status9 status10 status11
        status9=$(get_pr_check_status "$PR_PHASE9")
        status10=$(get_pr_check_status "$PR_PHASE10")
        status11=$(get_pr_check_status "$PR_PHASE11")
        
        local detail9 detail10 detail11
        detail9=$(get_pr_check_details "$PR_PHASE9")
        detail10=$(get_pr_check_details "$PR_PHASE10")
        detail11=$(get_pr_check_details "$PR_PHASE11")
        
        write_info "  PR #$PR_PHASE9 (Phase 9):   $status9 - $detail9"
        write_info "  PR #$PR_PHASE10 (Phase 10):  $status10 - $detail10"
        write_info "  PR #$PR_PHASE11 (Phase 11):  $status11 - $detail11"
        
        # Check if all passed
        if [[ "$status9" == "PASSED" && "$status10" == "PASSED" && "$status11" == "PASSED" ]]; then
            write_success ""
            write_success "🎉 ALL CI CHECKS PASSED! Ready for merge sequence."
            return 0
        fi
        
        # Check for any failures
        if [[ "$status9" == "FAILED" || "$status10" == "FAILED" || "$status11" == "FAILED" ]]; then
            write_error ""
            write_error "❌ CI FAILURE DETECTED"
            [[ "$status9" == "FAILED" ]] && write_error "  → PR #$PR_PHASE9 failed - check GitHub Actions logs"
            [[ "$status10" == "FAILED" ]] && write_error "  → PR #$PR_PHASE10 failed - check GitHub Actions logs"
            [[ "$status11" == "FAILED" ]] && write_error "  → PR #$PR_PHASE11 failed - check GitHub Actions logs"
            return 1
        fi
        
        write_info "  → Waiting $CHECK_INTERVAL seconds for next check..."
        write_info ""
        sleep "$CHECK_INTERVAL"
    done
}

execute_merge_sequence() {
    write_section "MERGE SEQUENCE EXECUTION"
    
    write_info ""
    write_info "Step 1: Merge PR #$PR_PHASE9 (Phase 9) to main"
    if ! merge_pr "$PR_PHASE9"; then
        write_error "❌ Phase 9 merge failed - aborting sequence"
        return 1
    fi
    sleep 5
    
    write_info ""
    write_info "Step 2: Merge PR #$PR_PHASE10 (Phase 10) to main"
    if ! merge_pr "$PR_PHASE10"; then
        write_error "❌ Phase 10 merge failed - aborting sequence"
        return 1
    fi
    sleep 5
    
    write_info ""
    write_info "Step 3: Merge PR #$PR_PHASE11 (Phase 11) to main"
    if ! merge_pr "$PR_PHASE11"; then
        write_error "❌ Phase 11 merge failed - aborting sequence"
        return 1
    fi
    
    write_success ""
    write_success "✅ ALL THREE PHASES MERGED TO MAIN!"
    write_success "   Code-server is now production-ready with:"
    write_success "   • Phase 9: Operational readiness"
    write_success "   • Phase 10: On-premises optimization"
    write_success "   • Phase 11: Advanced resilience & HA/DR"
    write_success "   📋 Next: Deploy Phase 12 multi-region federation"
    write_info ""
    
    return 0
}

show_current_status() {
    write_section "Current CI Status"
    
    local status9 status10 status11
    status9=$(get_pr_check_status "$PR_PHASE9")
    status10=$(get_pr_check_status "$PR_PHASE10")
    status11=$(get_pr_check_status "$PR_PHASE11")
    
    write_info "PR #$PR_PHASE9 (Phase 9):  $status9"
    write_info "PR #$PR_PHASE10 (Phase 10): $status10"
    write_info "PR #$PR_PHASE11 (Phase 11): $status11"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

if $MONITOR; then
    if monitor_ci && $MERGE; then
        write_info ""
        write_info "🤖 Auto-executing merge sequence..."
        write_info ""
        execute_merge_sequence
    elif monitor_ci; then
        write_info ""
        write_info "→ Run with --merge flag to execute merge sequence automatically"
    fi
elif $MERGE; then
    status9=$(get_pr_check_status "$PR_PHASE9")
    
    if [[ "$status9" == "PASSED" ]]; then
        execute_merge_sequence
    else
        write_error "Cannot merge - PR #$PR_PHASE9 CI status is: $status9"
        exit 1
    fi
else
    write_section "CI Merge Automation"
    write_info "Usage:"
    write_info "  ./ci-merge-automation.sh --monitor               # Monitor CI until complete"
    write_info "  ./ci-merge-automation.sh --monitor --merge      # Monitor and auto-merge when done"
    write_info "  ./ci-merge-automation.sh --merge                # Execute merge if all CI passed"
    write_info ""
    show_current_status
fi
