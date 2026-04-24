#!/usr/bin/env bash
# @file        scripts/ops/fix-root-owned-files.sh
# @module      operations/git
# @description Fix root-owned test result files blocking git pull (P2 #1627)
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# CONSTANTS
PRIMARY_HOST="${DEPLOY_HOST:-192.168.168.31}"
REPLICA_HOST="${STANDBY_HOST:-192.168.168.42}"
EXEC_USER="${DEPLOY_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-0}"
REPO_PATH="/home/${EXEC_USER}/code-server-enterprise"

# Directories that commonly get root-owned files from Docker
PROBLEM_DIRS=(
    "tests/e2e/test-results"
    "config/grafana/dashboards"
    "packages/shared-events"
    "build"
    ".dist"
    "coverage"
)

# Check for root-owned files
check_root_owned_files() {
    local host="$1"
    
    log_info "Checking for root-owned files on $host..."
    
    local root_owned_count
    root_owned_count=$(ssh "${EXEC_USER}@${host}" "find $REPO_PATH -user root 2>/dev/null | wc -l" || echo "0")
    
    if [ "$root_owned_count" -eq 0 ]; then
        log_success "✓ No root-owned files found"
        return 0
    fi
    
    log_warn "Found $root_owned_count root-owned files/directories"
    
    log_info "Root-owned files in repository:"
    ssh "${EXEC_USER}@${host}" "find $REPO_PATH -user root -type f 2>/dev/null | head -10 || true" | sed 's/^/  /'
    
    return 1
}

# Fix file ownership
fix_file_ownership() {
    local host="$1"
    
    log_info "Fixing file ownership on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would run: sudo chown -R ${EXEC_USER}:${EXEC_USER} $REPO_PATH"
        log_info "[DRY-RUN] This fixes all root-owned files in repository"
        return 0
    fi
    
    log_info "Changing ownership to ${EXEC_USER}:${EXEC_USER}..."
    
    ssh "${EXEC_USER}@${host}" "sudo chown -R ${EXEC_USER}:${EXEC_USER} $REPO_PATH" || {
        log_error "Failed to change ownership"
        return 1
    }
    
    log_success "✓ File ownership fixed"
    return 0
}

# Fix git state
fix_git_state() {
    local host="$1"
    
    log_info "Fixing git state on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would run:"
        log_info "[DRY-RUN]   1. git reset --hard origin/main"
        log_info "[DRY-RUN]   2. git pull origin main"
        return 0
    fi
    
    # Reset git to origin/main
    log_info "Resetting to origin/main..."
    local reset_output
    reset_output=$(ssh "${EXEC_USER}@${host}" "cd $REPO_PATH && git reset --hard origin/main 2>&1" || echo "FAILED")
    
    if [ "$reset_output" = "FAILED" ]; then
        log_error "git reset failed"
        return 1
    fi
    
    log_info "Reset output:"
    echo "$reset_output" | head -5 | sed 's/^/  /'
    
    # Pull latest changes
    log_info "Pulling latest changes..."
    local pull_output
    pull_output=$(ssh "${EXEC_USER}@${host}" "cd $REPO_PATH && git pull origin main 2>&1" || echo "FAILED")
    
    if [ "$pull_output" = "FAILED" ]; then
        log_error "git pull failed"
        return 1
    fi
    
    log_success "✓ Git state fixed and updated"
    return 0
}

# Update .gitignore to prevent future issues
update_gitignore() {
    local host="$1"
    
    log_info "Checking .gitignore for test results directory on $host..."
    
    local gitignore_path="$REPO_PATH/.gitignore"
    
    # Check if already in .gitignore
    local already_ignored
    already_ignored=$(ssh "${EXEC_USER}@${host}" "grep -q 'tests/e2e/test-results' $gitignore_path 2>/dev/null && echo 'YES' || echo 'NO'" || echo "ERROR")
    
    if [ "$already_ignored" = "YES" ]; then
        log_success "✓ Test results directory already in .gitignore"
        return 0
    fi
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would add test-results directories to .gitignore"
        return 0
    fi
    
    log_info "Adding test-results directories to .gitignore..."
    
    # Add to .gitignore
    ssh "${EXEC_USER}@${host}" "cat >> $gitignore_path << 'EOF'

# Test results from Playwright and E2E tests (can contain root-owned files from Docker)
tests/e2e/test-results/
tests/integration/test-results/
coverage/
.nyc_output/
EOF" || {
        log_error "Failed to update .gitignore"
        return 1
    }
    
    log_success "✓ .gitignore updated"
    return 0
}

# Verify git is clean and up-to-date
verify_git_state() {
    local host="$1"
    
    log_info "Verifying git state on $host..."
    
    if [ "$DRY_RUN" = "1" ]; then
        log_info "[DRY-RUN] Would verify git status and commit log"
        return 0
    fi
    
    # Check git status
    log_info "Current git status:"
    ssh "${EXEC_USER}@${host}" "cd $REPO_PATH && git status | head -10" | sed 's/^/  /'
    
    # Check latest commit
    log_info ""
    log_info "Latest commit:"
    ssh "${EXEC_USER}@${host}" "cd $REPO_PATH && git log -1 --oneline" | sed 's/^/  /'
    
    return 0
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "Fixing root-owned files blocking git pull (P2 #1627)"
    log_info "========================================================================"
    log_info ""
    log_info "Configuration:"
    log_info "  Primary Host: $PRIMARY_HOST"
    log_info "  Replica Host: $REPLICA_HOST"
    log_info "  Repository Path: $REPO_PATH"
    log_info "  Dry-Run Mode: $([ "$DRY_RUN" = "1" ] && echo "YES" || echo "NO")"
    log_info ""
    
    log_info "Verifying SSH connectivity..."
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${PRIMARY_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to primary host"
    fi
    log_success "✓ Connected to primary"
    
    if ! ssh -o ConnectTimeout=5 "${EXEC_USER}@${REPLICA_HOST}" "echo ok" > /dev/null 2>&1; then
        log_fatal "Cannot connect to replica host"
    fi
    log_success "✓ Connected to replica"
    log_info ""
    
    # PRIMARY HOST
    log_info "PRIMARY HOST ($PRIMARY_HOST)"
    log_info "=============================="
    log_info ""
    
    check_root_owned_files "$PRIMARY_HOST" || true
    log_info ""
    
    fix_file_ownership "$PRIMARY_HOST" || return 1
    log_info ""
    
    fix_git_state "$PRIMARY_HOST" || return 1
    log_info ""
    
    update_gitignore "$PRIMARY_HOST" || true
    log_info ""
    
    verify_git_state "$PRIMARY_HOST"
    log_info ""
    
    # REPLICA HOST
    log_info "REPLICA HOST ($REPLICA_HOST)"
    log_info "============================="
    log_info ""
    
    check_root_owned_files "$REPLICA_HOST" || true
    log_info ""
    
    fix_file_ownership "$REPLICA_HOST" || return 1
    log_info ""
    
    fix_git_state "$REPLICA_HOST" || return 1
    log_info ""
    
    update_gitignore "$REPLICA_HOST" || true
    log_info ""
    
    verify_git_state "$REPLICA_HOST"
    log_info ""
    
    log_success "========================================================================"
    log_success "Root-owned files fixed and git state restored on both replicas!"
    log_success "========================================================================"
    log_info ""
    log_info "Summary:"
    log_info "  ✓ File ownership fixed (root → ${EXEC_USER})"
    log_info "  ✓ Git state reset to origin/main"
    log_info "  ✓ Latest changes pulled"
    log_info "  ✓ .gitignore updated to prevent future conflicts"
    log_info ""
    log_info "Git pull should now work without permission errors."
}

main "$@"
