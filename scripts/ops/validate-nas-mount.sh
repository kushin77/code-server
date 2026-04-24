#!/usr/bin/env bash
# @file        scripts/ops/validate-nas-mount.sh
# @module      ops/storage
# @description Verify NAS mount connectivity and permissions across cluster
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

################################################################################
# CONFIGURATION
################################################################################

REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
MOUNT_POINT="${NAS_MOUNT_POINT:-/mnt/nas/persistent}"

################################################################################
# VALIDATION
################################################################################

validate_nas_replica() {
    local replica="$1"
    
    log_info "Verifying NAS mount on $replica at $MOUNT_POINT..."
    
    if ssh "$DEPLOY_USER@$replica" "mountpoint -q $MOUNT_POINT && [ -w $MOUNT_POINT ]"; then
        log_info "✅ NAS mount OK and Writable on $replica"
    else
        log_error "✗ NAS mount verification failed on $replica"
        return 1
    fi
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Starting NAS Proximity Scan..."
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    local fails=0
    for replica in "${replica_array[@]}"; do
        validate_nas_replica "$replica" || ((fails++))
    done
    
    if [[ $fails -gt 0 ]]; then
        log_fatal "NAS verification failed on $fails cluster nodes"
    fi
    
    log_info "✅ NAS validated across entire active cluster"
}

main "$@"
