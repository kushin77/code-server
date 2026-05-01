#!/bin/bash
# ============================================================================
# Smart Logging Consolidation Tool
# Migrates shell scripts to use centralized logging library (scripts/common/logging.sh)
# via scripts/_common/init.sh
# ============================================================================

set -e

# Define logging early for trap handlers
log_info() { echo "[INFO] $*"; }
log_success() { echo "[✓] $*"; }
log_error() { echo "[✗] $*"; }

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

REPO_ROOT="${REPO_ROOT:-/home/akushnir/code-server}"
SCRIPTS_TO_MIGRATE=(
    "scripts/ops/backup-automation.sh"
    "scripts/ops/deploy-production-replica.sh"
    "scripts/ops/iac-deploy.sh"
    "scripts/ops/postgres-backup.sh"
    "scripts/ops/failover-drill.sh"
    "scripts/ci/expand-drift-detector-scope.sh"
    "scripts/ci/quick-health-check.sh"
    "scripts/ci/setup-gitops-workflow.sh"
)

# Add logging source to script if not present
add_logging_source() {
    local file="$1"
    
    # Skip if already has logging
    if grep -q "source.*init.sh\|source.*logging.sh" "$file" 2>/dev/null; then
        return 0
    fi
    
    log_info "Adding logging source to $(basename $file)"
    
    # Insert source command after shebang
    local shebang_line=$(grep -n "^#!/bin/bash" "$file" | head -1 | cut -d: -f1)
    if [[ -n "$shebang_line" ]]; then
        sed -i "$((shebang_line + 1))i\\
# Source logging library
REPO_ROOT=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")/../..\" \&\& pwd)\"
source \"\${REPO_ROOT}/scripts/_common/init.sh\"" "$file"
    fi
}

# Replace echo patterns with log_* functions
migrate_echo_statements() {
    local file="$1"
    
    log_info "Migrating echo statements in $(basename $file)"
    
    # Create backup
    cp "$file" "${file}.backup"
    
    # Replace common patterns
    # Error patterns
    sed -i 's/^echo "Error:/log_error "/g' "$file"
    sed -i 's/^echo "ERROR:/log_error "/g' "$file"
    sed -i 's/^echo "\[ERROR\]/log_error "/g' "$file"
    
    # Success/OK patterns
    sed -i 's/^echo "✓/log_success "/g' "$file"
    sed -i 's/^echo "Success:/log_success "/g' "$file"
    sed -i 's/^echo "\[SUCCESS\]/log_success "/g' "$file"
    
    # Warning patterns
    sed -i 's/^echo "Warning:/log_warn "/g' "$file"
    sed -i 's/^echo "\[WARNING\]/log_warn "/g' "$file"
    sed -i 's/^echo "\[WARN\]/log_warn "/g' "$file"
    
    # Info patterns (generic)
    sed -i 's/^echo "\[INFO\]/log_info "/g' "$file"
    
    # Preserve section headers (don't convert)
    # Restore backups on error
    if ! bash -n "$file" 2>/dev/null; then
        log_error "Syntax error in migrated script: $file"
        mv "${file}.backup" "$file"
        return 1
    fi
    
    rm "${file}.backup"
    log_success "Migrated $(basename $file)"
}

main() {
    local updated=0
    local failed=0
    
    log_info "Starting consolidated logging migration..."
    
    for script in "${SCRIPTS_TO_MIGRATE[@]}"; do
        if [[ ! -f "${REPO_ROOT}/${script}" ]]; then
            log_error "Script not found: ${REPO_ROOT}/${script}"
            failed+=1
            continue
        fi
        
        cd "${REPO_ROOT}"
        
        if add_logging_source "${script}" && migrate_echo_statements "${script}"; then
            updated+=1
        else
            failed+=1
        fi
    done
    
    echo ""
    log_success "Migration complete: $updated scripts updated"
    if [[ $failed -gt 0 ]]; then
        log_error "$failed scripts failed or skipped"
        return 1
    fi
}

main "$@"
