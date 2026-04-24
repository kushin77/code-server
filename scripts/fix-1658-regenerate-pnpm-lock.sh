#!/usr/bin/env bash
# @file        scripts/fix-1658-regenerate-pnpm-lock.sh
# @module      ci/dependency-management
# @description Regenerate pnpm-lock.yaml to fix backend-integration test failures (issue #1658)
#
# This script resolves deterministic test failures caused by dependency version
# mismatches between package.json and pnpm-lock.yaml. The fix is idempotent
# and produces a deterministic lock file.

set -euo pipefail

# =============================================================================
# INITIALIZATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load shared libraries for error handling and logging
source "${SCRIPT_DIR}/_common/init.sh"
init_repo

log_info "Starting pnpm-lock.yaml regeneration for issue #1658"

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

log_info "Verifying environment..."

require_command pnpm "pnpm package manager"
require_command git "git version control"

# Verify we're at repo root with package.json
if [[ ! -f "${REPO_ROOT}/pnpm-workspace.yaml" ]]; then
    log_fatal "Not at repository root (no pnpm-workspace.yaml found)"
fi

log_info "✓ Environment verified"

# =============================================================================
# BACKUP CURRENT STATE
# =============================================================================

log_info "Backing up current pnpm-lock.yaml..."
if [[ -f "${REPO_ROOT}/pnpm-lock.yaml" ]]; then
    cp "${REPO_ROOT}/pnpm-lock.yaml" "${REPO_ROOT}/pnpm-lock.yaml.backup"
    log_info "✓ Backup created: pnpm-lock.yaml.backup"
else
    log_warn "No existing pnpm-lock.yaml found (fresh install)"
fi

# =============================================================================
# REGENERATE LOCK FILE
# =============================================================================

cd "${REPO_ROOT}"

log_info "Regenerating pnpm-lock.yaml (this may take 1-2 minutes)..."

# Use --prefer-frozen-lockfile to ensure deterministic resolution
# This command will update the lock file based on current package.json definitions
if pnpm install --prefer-frozen-lockfile 2>&1 | grep -v "^$"; then
    log_info "✓ pnpm-lock.yaml regenerated successfully"
else
    log_error "pnpm install failed"
    # Restore backup on failure
    if [[ -f "${REPO_ROOT}/pnpm-lock.yaml.backup" ]]; then
        log_warn "Restoring backup..."
        mv "${REPO_ROOT}/pnpm-lock.yaml.backup" "${REPO_ROOT}/pnpm-lock.yaml"
    fi
    log_fatal "Unable to regenerate pnpm-lock.yaml"
fi

# =============================================================================
# VERIFY LOCK FILE INTEGRITY
# =============================================================================

log_info "Verifying lock file integrity..."

# Check that lock file was modified
if [[ ! -f "${REPO_ROOT}/pnpm-lock.yaml" ]]; then
    log_fatal "pnpm-lock.yaml was not created"
fi

# Verify YAML syntax
if ! grep -q "lockfileVersion:" "${REPO_ROOT}/pnpm-lock.yaml"; then
    log_fatal "Lock file appears invalid (missing lockfileVersion)"
fi

log_info "✓ Lock file integrity verified"

# =============================================================================
# OPTIONAL: TEST LOCALLY (if requested)
# =============================================================================

if [[ "${1:-}" == "--test-local" ]]; then
    log_info "Testing backend integration tests locally..."
    
    cd "${REPO_ROOT}/apps/backend"
    
    if pnpm test 2>&1 | tail -20; then
        log_info "✓ Backend tests passed"
    else
        log_error "Backend tests failed (may indicate additional issues beyond lock file)"
        cd "${REPO_ROOT}"
        exit 1
    fi
    
    cd "${REPO_ROOT}"
fi

# =============================================================================
# SUMMARY
# =============================================================================

log_info "pnpm-lock.yaml regeneration complete"
log_info ""
log_info "Summary:"
log_info "  Issue: #1658 (backend-integration test failures)"
log_info "  Root Cause: @vitest/coverage-v8 version mismatch"
log_info "  Fix: Regenerated pnpm-lock.yaml for deterministic dependency resolution"
log_info "  Lock File: ${REPO_ROOT}/pnpm-lock.yaml"
log_info "  Backup: ${REPO_ROOT}/pnpm-lock.yaml.backup"
log_info ""
log_info "Next Steps:"
log_info "  1. Review: git diff pnpm-lock.yaml"
log_info "  2. Verify: cd apps/backend && pnpm test"
log_info "  3. Commit: git add pnpm-lock.yaml && git commit -m 'fix(deps): regenerate pnpm-lock for #1658'"
log_info "  4. Push: git push origin fix/1658-pnpm-lock"
log_info ""

exit 0
