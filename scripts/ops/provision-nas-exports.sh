#!/usr/bin/env bash
# @file        scripts/ops/provision-nas-exports.sh
# @module      operations/nas-provisioning
# @description Provision required NAS export directories for cluster services
# @owner       platform-engineering
# @status      active
#
# Purpose:
#   Creates NAS export directories (/export/*) required by Replica 1, Replica 2,
#   and supporting services (Appsmith, Loki, Error Triage DB).
#
#   This script MUST be run on the NAS host with root or
#   passwordless sudo access.
#
# Usage (on NAS host):
#   ssh akushnir@<nas-host>
#   cd /path/to/code-server-enterprise  # or copy script there
#   sudo bash scripts/ops/provision-nas-exports.sh
#
# Prerequisites:
#   - SSH access to the NAS host
#   - Passwordless sudo (or root shell access)
#   - NFS/NAS filesystem available at /export
#
# Exit Codes:
#   0 = All directories created successfully
#   1 = Some directories failed to create
#   2 = Invalid preconditions (not NAS host, no /export, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
NAS_EXPORT_BASE="${NAS_EXPORT_BASE:-/export}"
REPLICA_1_HOST="${REPLICA_1_HOST:-}"
REPLICA_2_HOST="${REPLICA_2_HOST:-}"
DRY_RUN="${DRY_RUN:-0}"

# Required export directories
declare -A EXPORTS=(
    [appsmith]="Portal administration interface"
    [appsmith-replica-2]="Replica 2 isolated Appsmith store"
    [loki]="Log aggregation and persistence"
    [error-triage-db]="Error diagnostics database"
    [code-server-enterprise]="IDE workspace persistence"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

##############################################################################
# VALIDATION
##############################################################################

validate_environment() {
    log_info "Validating NAS provisioning environment..."

    # Check if running as root or with sudo
    if [[ "$EUID" -ne 0 ]]; then
        log_fatal "This script must be run with root privileges (use: sudo bash $0)"
        exit 2
    fi

    # Check if /export exists
    if [[ ! -d "$NAS_EXPORT_BASE" ]]; then
        log_fatal "NAS export base directory does not exist: $NAS_EXPORT_BASE"
        log_fatal "This script must be run on the NAS host"
        exit 2
    fi

    # Check if /export is writable
    if [[ ! -w "$NAS_EXPORT_BASE" ]]; then
        log_fatal "NAS export base directory is not writable: $NAS_EXPORT_BASE"
        exit 2
    fi

    log_success "Environment validation passed"
}

##############################################################################
# PROVISIONING
##############################################################################

create_export_directory() {
    local name="$1"
    local description="$2"
    local path="${NAS_EXPORT_BASE}/${name}"

    log_info "Processing: $name ($description)"
    log_info "  Path: $path"

    # Check if directory already exists
    if [[ -d "$path" ]]; then
        log_success "✓ Directory already exists: $path"
        return 0
    fi

    # Create directory
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would create directory: $path"
        log_info "[DRY-RUN]   chmod 755"
        log_info "[DRY-RUN]   chown nobody:nogroup"
        return 0
    fi

    # Actual creation
    if mkdir -p "$path"; then
        if chmod 755 "$path"; then
            if chown nobody:nogroup "$path"; then
                log_success "✓ Created and configured: $path"
                return 0
            else
                log_error "Failed to set ownership: $path"
                return 1
            fi
        else
            log_error "Failed to set permissions: $path"
            return 1
        fi
    else
        log_error "Failed to create directory: $path"
        return 1
    fi
}

provision_all_exports() {
    local created=0
    local failed=0

    log_info "Creating NAS export directories..."
    [[ "$DRY_RUN" == "1" ]] && log_info "Mode: DRY-RUN (no changes)"
    log_info ""

    for name in "${!EXPORTS[@]}"; do
        if create_export_directory "$name" "${EXPORTS[$name]}"; then
            ((created++))
        else
            ((failed++))
        fi
    done

    log_info ""
    log_info "Provisioning Summary:"
    log_info "  Created: $created/${#EXPORTS[@]}"
    if [[ $failed -gt 0 ]]; then
        log_error "  Failed: $failed/${#EXPORTS[@]}"
        return 1
    fi

    return 0
}

##############################################################################
# VERIFICATION
##############################################################################

verify_exports() {
    log_info "Verifying provisioned exports..."
    local verified=0
    local missing=0

    for name in "${!EXPORTS[@]}"; do
        local path="${NAS_EXPORT_BASE}/${name}"
        if [[ -d "$path" ]]; then
            local perms=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%OLp' "$path" 2>/dev/null || echo "unknown")
            local owner=$(stat -c '%U:%G' "$path" 2>/dev/null || stat -f '%Su:%Sg' "$path" 2>/dev/null || echo "unknown")
            log_success "✓ $name: $path (perms: $perms, owner: $owner)"
            ((verified++))
        else
            log_error "✗ $name: Missing directory $path"
            ((missing++))
        fi
    done

    log_info ""
    log_info "Verification Summary:"
    log_info "  Verified: $verified/${#EXPORTS[@]}"
    if [[ $missing -gt 0 ]]; then
        log_error "  Missing: $missing/${#EXPORTS[@]}"
        return 1
    fi

    return 0
}

##############################################################################
# NFS EXPORT CONFIGURATION
##############################################################################

configure_nfs_exports() {
    log_info "Checking NFS export configuration..."

    local exports_file="/etc/exports"
    if [[ ! -f "$exports_file" ]]; then
        log_warn "NFS exports file not found: $exports_file"
        log_warn "Manual NFS configuration may be required"
        return 0
    fi

    log_info "Current NFS exports:"
    grep "^/export" "$exports_file" | sed 's/^/  /'

    if [[ -n "$REPLICA_1_HOST" ]]; then
        if grep -q "^/export.*${REPLICA_1_HOST}" "$exports_file"; then
            log_success "✓ NFS export includes Replica 1 (${REPLICA_1_HOST})"
        else
            log_warn "Replica 1 (${REPLICA_1_HOST}) may not be in NFS exports"
        fi
    fi

    if [[ -n "$REPLICA_2_HOST" ]]; then
        if grep -q "^/export.*${REPLICA_2_HOST}" "$exports_file"; then
            log_success "✓ NFS export includes Replica 2 (${REPLICA_2_HOST})"
        else
            log_warn "Replica 2 (${REPLICA_2_HOST}) may not be in NFS exports"
        fi
    fi

    return 0
}

##############################################################################
# MAIN
##############################################################################

main() {
    log_info "========================================="
    log_info "NAS Export Provisioning Script"
    log_info "========================================="
    log_info "NAS Host: $(hostname)"
    log_info "Export Base: $NAS_EXPORT_BASE"
    log_info "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log_info ""

    # Step 1: Validate
    validate_environment

    # Step 2: Provision directories
    if provision_all_exports; then
        log_success "✓ Export directory provisioning successful"
    else
        log_error "✗ Export directory provisioning failed"
        return 1
    fi

    # Step 3: Verify
    if verify_exports; then
        log_success "✓ Export directory verification successful"
    else
        log_error "✗ Export directory verification failed"
        return 1
    fi

    # Step 4: Check NFS configuration
    configure_nfs_exports

    # Step 5: Next steps
    log_info ""
    log_info "Next Steps:"
    log_info "  1. On Replica 1 (${REPLICA_1_HOST}): Re-run docker-compose deployment"
    log_info "  2. On Replica 2 (${REPLICA_2_HOST}): Re-run fix-replica-2-nfs.sh"
    log_info "  3. Verify both replicas have same running services"
    log_info "  4. Confirm cluster parity (Epic #1616)"
    log_info ""

    log_success "NAS export provisioning complete"
    return 0
}

# Run main function
main "$@"
