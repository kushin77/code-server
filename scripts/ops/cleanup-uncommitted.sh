#!/bin/bash

###
# @file scripts/ops/cleanup-uncommitted.sh
# @module operations/cleanup
# @description Clean up uncommitted changes and generated artifacts
# @governance GOV-002: Operational cleanup for deployment readiness
###

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

set -euo pipefail

# ============================================================================
# Logging Functions
# ============================================================================

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Cleanup failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Cleanup complete"; true' EXIT

# ============================================================================
# Configuration
# ============================================================================

DRY_RUN="${1:-false}"

log_info "=== Cleanup Uncommitted Changes ==="
log_info "Project Root: $REPO_ROOT"
log_info "Dry Run: $DRY_RUN"
log_info ""

# ============================================================================
# Stage 1: List uncommitted changes
# ============================================================================

log_info "Uncommitted modifications:"
git -C "${REPO_ROOT}" status --short || true

# ============================================================================
# Stage 2: Categorize changes
# ============================================================================

log_info ""
log_info "Analyzing changes..."

MODIFIED_FILES=()
NEW_FILES=()

while IFS= read -r line; do
    if [[ "$line" =~ ^\ M ]]; then
        file="${line:3}"
        MODIFIED_FILES+=("$file")
        log_info "  Modified: $file"
    elif [[ "$line" =~ ^\?\? ]]; then
        file="${line:3}"
        NEW_FILES+=("$file")
        log_info "  Untracked: $file"
    fi
done < <(git -C "${REPO_ROOT}" status --short 2>/dev/null || true)

# ============================================================================
# Stage 3: Cleanup strategy
# ============================================================================

log_info ""
log_info "Cleanup Strategy:"
log_info ""
log_info "1. Restore modified tracked files"
for file in "${MODIFIED_FILES[@]}"; do
    if [[ "$file" == "artifacts/"* ]] || [[ "$file" == "logs/"* ]]; then
        log_info "  - Remove: $file (artifact)"
    else
        log_info "  - Restore: $file (tracked)"
    fi
done

log_info ""
log_info "2. Remove untracked files"
for file in "${NEW_FILES[@]}"; do
    if [[ "$file" == "scripts/"* ]] || [[ "$file" == "artifacts/"* ]] || [[ "$file" == "logs/"* ]]; then
        log_info "  - Delete: $file (generated/temporary)"
    fi
done

# ============================================================================
# Stage 4: Execute cleanup
# ============================================================================

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN MODE - no changes made"
    exit 0
fi

log_info ""
log_info "Executing cleanup..."

# Restore modified tracked files (except generated ones)
for file in "${MODIFIED_FILES[@]}"; do
    if [[ ! "$file" =~ ^artifacts/ ]] && [[ ! "$file" =~ ^logs/ ]]; then
        git -C "${REPO_ROOT}" checkout "${file}" 2>/dev/null && log_success "Restored: $file" || log_error "Failed to restore: $file"
    fi
done

# Remove generated artifacts and logs
for file in "${NEW_FILES[@]}"; do
    if [[ "$file" =~ ^artifacts/ ]] || [[ "$file" =~ ^logs/ ]] || [[ "$file" =~ ^scripts/.*\.sh$ ]]; then
        rm -f "${REPO_ROOT}/${file}" && log_success "Deleted: $file" || log_error "Failed to delete: $file"
    fi
done

# ============================================================================
# Verification
# ============================================================================

log_info ""
REMAINING=$(git -C "${REPO_ROOT}" status --short 2>/dev/null | grep -v "^??" | wc -l || echo 0)

if (( REMAINING == 0 )); then
    log_success "✅ Repository cleaned successfully"
else
    log_warn "⚠️  $REMAINING files still uncommitted"
fi

git -C "${REPO_ROOT}" status --short 2>/dev/null || true
