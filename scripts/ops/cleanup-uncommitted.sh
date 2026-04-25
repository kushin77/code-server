#!/bin/bash

###
# @governance: Cleanup uncommitted state — remove transient artifacts before deployment
# Purpose: Clean up uncommitted changes and generated artifacts
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1534 (IaC Governance), #1531 (Infrastructure as Code)
###

set -euo pipefail

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
  printf '[%s] [INFO] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

log_success() {
  printf '[%s] [SUCCESS] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

log_warn() {
  printf '[%s] [WARN] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

# ============================================================================
# Configuration (all env-var driven)
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly DRY_RUN="${1:-${DRY_RUN:-false}}"
readonly CLEANUP_STATE_DIR="${CLEANUP_STATE_DIR:-${PROJECT_ROOT}/state}"
readonly CLEANUP_ARTIFACTS_DIR="${CLEANUP_ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts}"

log_info "=== Cleanup Uncommitted Changes ==="
log_info "Project Root: $PROJECT_ROOT"
log_info "Dry Run: $DRY_RUN"
log_info ""

# ============================================================================
# Stage 1: List uncommitted changes
# ============================================================================

log_info "Uncommitted modifications:"
git -C "${PROJECT_ROOT}" status --short || true

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
done < <(git -C "${PROJECT_ROOT}" status --short 2>/dev/null || true)

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
        git -C "${PROJECT_ROOT}" checkout "${file}" 2>/dev/null && log_success "Restored: $file" || log_error "Failed to restore: $file"
    fi
done

# Remove generated artifacts and logs
for file in "${NEW_FILES[@]}"; do
    if [[ "$file" =~ ^artifacts/ ]] || [[ "$file" =~ ^logs/ ]] || [[ "$file" =~ ^scripts/.*\.sh$ ]]; then
        rm -f "${PROJECT_ROOT}/${file}" && log_success "Deleted: $file" || log_error "Failed to delete: $file"
    fi
done

# ============================================================================
# Verification
# ============================================================================

log_info ""
REMAINING=$(git -C "${PROJECT_ROOT}" status --short 2>/dev/null | grep -v "^??" | wc -l || echo 0)

if (( REMAINING == 0 )); then
    log_success "✅ Repository cleaned successfully"
else
    log_warn "⚠️  $REMAINING files still uncommitted"
fi

git -C "${PROJECT_ROOT}" status --short 2>/dev/null || true
