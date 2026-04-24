#!/usr/bin/env bash
# @file        scripts/pmo/cleanup-stale-branches.sh
# @module      pmo/maintenance
# @description Delete merged and orphaned branches after PMO issue completion
# @owner       PMO Framework
# @status      active
#
# Idempotent cleanup: deletes local branches merged into main,
# deletes remote branches merged into main, and detects branches
# linked to closed GitHub issues.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="${1:-kushin77/code-server}"
DRY_RUN="${DRY_RUN:-0}"

# Source logging
if [[ -f "$SCRIPT_DIR/scripts/_common/logging.sh" ]]; then
    source "$SCRIPT_DIR/scripts/_common/logging.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*"; }
fi

log_info "Starting stale branch cleanup for $REPO"
[[ "$DRY_RUN" == "1" ]] && log_warn "DRY_RUN enabled — no branches will be deleted"

local_deleted=0
remote_deleted=0
orphaned_cleaned=0

# Ensure we're on main branch
if git rev-parse --verify main >/dev/null 2>&1; then
    git checkout main >/dev/null 2>&1 || true
fi

log_info "Fetching latest remote state..."
git fetch --prune 2>/dev/null || log_warn "Could not fetch remote"

# Delete local branches merged into main
log_info "Scanning local branches merged into main..."
for branch in $(git branch --merged main --format='%(refname:short)'); do
    if [[ "$branch" == "main" ]] || [[ "$branch" == "master" ]] || [[ "$branch" == "develop" ]]; then
        continue  # Skip protected branches
    fi
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Delete local: $branch"
    else
        git branch -d "$branch" 2>/dev/null && log_info "✓ Deleted local: $branch" || true
    fi
    ((local_deleted++))
done

# Delete remote branches merged into main
log_info "Scanning remote branches merged into main..."
for branch in $(git branch -r --merged origin/main --format='%(refname:short)' 2>/dev/null | grep -v "origin/main" | cut -d'/' -f2-); do
    if [[ "$branch" == "HEAD" ]]; then
        continue  # Skip origin/HEAD
    fi
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Delete remote: $branch"
    else
        git push origin --delete "$branch" 2>/dev/null && log_info "✓ Deleted remote: $branch" || true
    fi
    ((remote_deleted++))
done

# Detect and report branches linked to closed issues
log_info "Detecting orphaned branches linked to closed issues..."
for branch in $(git branch -r --format='%(refname:short)'); do
    # Extract issue number from branch name (pattern: feature/epic-pmo-001-a-1576-label-taxonomy)
    if [[ $branch =~ -([0-9]+)-[a-z-]+$ ]]; then
        issue_num="${BASH_REMATCH[1]}"
        # Check if issue is closed
        issue_state=$(gh issue view "$issue_num" --repo "$REPO" --json state --jq .state 2>/dev/null || echo "UNKNOWN")
        if [[ "$issue_state" == "CLOSED" ]]; then
            branch_name=$(echo "$branch" | cut -d'/' -f2-)
            log_warn "Orphaned: $branch_name (linked to closed issue #$issue_num)"
            ((orphaned_cleaned++))
        fi
    fi
done

echo ""
log_info "Stale branch cleanup complete:"
log_info "  Local branches deleted: $local_deleted"
log_info "  Remote branches deleted: $remote_deleted"
log_info "  Orphaned branches detected: $orphaned_cleaned"

log_info "✅ Cleanup finished"
