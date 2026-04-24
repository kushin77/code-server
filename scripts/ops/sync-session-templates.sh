#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/sync-session-templates.sh
# @module      ops/session-management
# @description Synchronize session templates across cluster replicas via NAS
# @owner       infrastructure
# @status      active
#
# USAGE
#   scripts/ops/sync-session-templates.sh [--replica-id <id>] [--dry-run]
#
# Ensures all replicas have consistent template registry on shared NAS.
# Idempotent: safe to run on all replicas simultaneously.
#
################################################################################

set -euo pipefail

# Get directory of this script and source the canonical initialization module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

SCRIPT_NAME="$(basename "$0")"

################################################################################
# CONFIGURATION & VALIDATION
################################################################################

require_command "jq" "JSON query tool is required"
require_command "rsync" "rsync is required for template synchronization"

# Configuration from environment
NAS_MOUNT_PATH="${NAS_MOUNT_PATH:-/mnt/nas/persistent/code-server-enterprise}"
TEMPLATES_DIR="${NAS_MOUNT_PATH}/templates/session-templates"
LOCAL_TEMPLATES_DIR="./apps/session-broker/src/templates"
REPLICA_ID="${REPLICA_ID:-}"
DRY_RUN="${DRY_RUN:-false}"

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    log_info "Starting session template synchronization"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --replica-id)
                REPLICA_ID="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 2
                ;;
        esac
    done

    # Verify NAS is mounted
    if ! mountpoint -q "$NAS_MOUNT_PATH"; then
        log_error "NAS not mounted at $NAS_MOUNT_PATH"
        return 1
    fi

    # Create templates directory structure on NAS
    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$TEMPLATES_DIR"
        log_info "Templates directory ensured" "path=$TEMPLATES_DIR"
    fi

    # Sync templates from local repo to NAS (one-way push)
    if [[ -d "$LOCAL_TEMPLATES_DIR" ]]; then
        local rsync_opts="-av --delete"
        if [[ "$DRY_RUN" == "true" ]]; then
            rsync_opts="$rsync_opts --dry-run"
        fi
        
        log_info "Syncing templates to NAS" "source=$LOCAL_TEMPLATES_DIR target=$TEMPLATES_DIR"
        rsync $rsync_opts "$LOCAL_TEMPLATES_DIR/" "$TEMPLATES_DIR/" || {
            log_error "Failed to sync templates"
            return 1
        }
    fi

    # Generate sync manifest (for audit trail)
    local manifest_file="$TEMPLATES_DIR/.sync-manifest.json"
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > "$manifest_file" <<EOF
{
  "syncTime": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "replicaId": "${REPLICA_ID:-unknown}",
  "templateCount": $(find "$TEMPLATES_DIR" -name "*.json" -type f | grep -v ".sync-manifest" | wc -l),
  "nasMountPath": "$NAS_MOUNT_PATH"
}
EOF
        log_info "Manifest created" "path=$manifest_file"
    fi

    log_info "Template synchronization complete" "status=success"
    return 0
}

# Execute main function
main "$@"
