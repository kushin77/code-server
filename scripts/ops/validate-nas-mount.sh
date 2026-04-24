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

if [[ -z "${REPLICAS:-}" ]]; then
    if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
        REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
    else
        log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before running NAS validation"
    fi
fi

SSH_USER="${SSH_USER:-${DEPLOY_USER:-}}"
if [[ -z "$SSH_USER" ]]; then
    log_fatal "Set SSH_USER or DEPLOY_USER before running NAS validation"
fi

MOUNT_POINT="${NAS_MOUNT_POINT:-/mnt/nas/persistent}"
NAS_SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout="${NAS_SSH_TIMEOUT:-10}" -o StrictHostKeyChecking=no)

################################################################################
# VALIDATION
################################################################################

validate_nas_replica() {
    local replica="$1"
    
    log_info "Verifying NAS mount on $replica at $MOUNT_POINT..."
    
    if ssh "${NAS_SSH_OPTS[@]}" "${SSH_USER}@${replica}" "mountpoint -q \"$MOUNT_POINT\" && [ -w \"$MOUNT_POINT\" ]"; then
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
