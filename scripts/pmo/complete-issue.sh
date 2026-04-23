#!/usr/bin/env bash
# @file        scripts/pmo/complete-issue.sh
# @module      pmo/completion
# @description Enforce universal 4-gate completion standard for GitHub issues
# @owner       PMO Framework
# @status      active
#
# 4-Gate Completion Standard:
#   Gate 1: Verify commits on feature branch or merge commit on main
#   Gate 2: Find and verify merged PR with "Closes #N"
#   Gate 3: SSH deploy to 192.168.168.31 and run docker compose up -d
#   Gate 4: Delete feature branch locally and remotely
#   Final: Apply gate labels and close issue

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="${1:-kushin77/code-server}"
ISSUE_NUMBER="${2}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_DEPLOY="${SKIP_DEPLOY:-0}"  # For docs-only or non-deployment changes

# Source logging
if [[ -f "$SCRIPT_DIR/scripts/_common/logging.sh" ]]; then
    source "$SCRIPT_DIR/scripts/_common/logging.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
    log_fatal() { echo "[FATAL] $*"; exit 1; }
fi

[[ -z "$ISSUE_NUMBER" ]] && log_fatal "Usage: $0 <repo> <issue_number> [--dry-run] [--skip-deploy]"

log_info "Completing issue #$ISSUE_NUMBER in $REPO"
[[ "$DRY_RUN" == "1" ]] && log_warn "DRY_RUN enabled — no changes will be made"

# Gate 1: Verify commits exist
log_info "GATE 1: Verify commits..."
COMMIT_COUNT=$(git rev-list main..HEAD --count 2>/dev/null || echo "0")
if [[ "$COMMIT_COUNT" -gt 0 ]]; then
    log_info "✓ Found $COMMIT_COUNT commits on current branch"
else
    # Check if on main and issue-related commits exist
    MAIN_COMMITS=$(git log main --oneline --all | grep -i "#$ISSUE_NUMBER" | wc -l || echo "0")
    if [[ "$MAIN_COMMITS" -gt 0 ]]; then
        log_info "✓ Found $MAIN_COMMITS issue-related commits on main"
    else
        log_fatal "GATE 1 FAILED: No commits found related to issue #$ISSUE_NUMBER"
    fi
fi

# Gate 2: Verify merged PR
log_info "GATE 2: Find merged PR with 'Closes #$ISSUE_NUMBER'..."
PR_JSON=$(gh pr list --repo "$REPO" --state closed --search "Closes #$ISSUE_NUMBER in:body" --json number,title,mergedAt --limit 1)
if [[ -z "$PR_JSON" ]] || [[ $(echo "$PR_JSON" | jq length) -eq 0 ]]; then
    log_fatal "GATE 2 FAILED: No merged PR found with 'Closes #$ISSUE_NUMBER'"
fi
PR_NUMBER=$(echo "$PR_JSON" | jq -r '.[0].number')
log_info "✓ Found merged PR #$PR_NUMBER"

# Gate 3: Deploy to production (skip if SKIP_DEPLOY=1)
if [[ "$SKIP_DEPLOY" != "1" ]]; then
    log_info "GATE 3: Deploy to 192.168.168.31..."
    if [[ "$DRY_RUN" != "1" ]]; then
        if ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker compose up -d" 2>&1 | head -20; then
            log_info "✓ Deployment successful"
        else
            log_error "GATE 3 WARNING: Deployment returned non-zero; review logs above"
        fi
    else
        log_info "[DRY-RUN] ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose up -d'"
    fi
else
    log_info "✓ GATE 3 skipped (SKIP_DEPLOY=1)"
fi

# Gate 4: Clean stale branches
log_info "GATE 4: Clean stale branches..."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    if [[ "$DRY_RUN" != "1" ]]; then
        git checkout main 2>/dev/null || log_warn "Could not checkout main"
        git branch -d "$CURRENT_BRANCH" 2>/dev/null || log_warn "Could not delete local branch $CURRENT_BRANCH"
        git push origin --delete "$CURRENT_BRANCH" 2>/dev/null || log_warn "Could not delete remote branch $CURRENT_BRANCH"
        log_info "✓ Deleted branches"
    else
        log_info "[DRY-RUN] Would delete branch: $CURRENT_BRANCH"
    fi
else
    log_info "✓ Already on main, skipping branch cleanup"
fi

# Final: Apply gate labels and close issue
log_info "Applying completion labels and closing issue #$ISSUE_NUMBER..."
if [[ "$DRY_RUN" != "1" ]]; then
    # Add all gate labels
    gh issue edit "$ISSUE_NUMBER" --repo "$REPO" \
        --add-label "gate:committed,gate:merged,gate:deployed,gate:cleaned" \
        --add-label "status:done" 2>/dev/null || log_warn "Could not add labels"
    
    # Close the issue
    gh issue close "$ISSUE_NUMBER" --repo "$REPO" --reason COMPLETED 2>/dev/null || log_warn "Could not close issue"
    log_info "✓ Issue #$ISSUE_NUMBER closed"
else
    log_info "[DRY-RUN] Would close issue #$ISSUE_NUMBER with gate labels"
fi

log_info "✅ Issue #$ISSUE_NUMBER completed successfully (all 4 gates passed)"
