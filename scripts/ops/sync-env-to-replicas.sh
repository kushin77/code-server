#!/usr/bin/env bash
# @file        scripts/ops/sync-env-to-replicas.sh
# @module      ops/deployment
# @description Synchronize .env configuration across all cluster replicas
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
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
ENV_FILE=".env"

################################################################################
# SYNC LOGIC
################################################################################

sync_env_to_replica() {
    local replica="$1"
    
    log_info "🔄 Syncing $ENV_FILE to $replica..."
    
    scp "$ENV_FILE" "$DEPLOY_USER@$replica:code-server-enterprise/" || \
        log_fatal "Failed to sync $ENV_FILE to $replica"
        
    log_info "✅ $ENV_FILE synced on $replica"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Global Configuration Sync"
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log_fatal "Local $ENV_FILE not found. Run GSM secret fetch first."
    fi
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        sync_env_to_replica "$replica"
    done
    
    log_info "✅ Global configuration synchronization complete"
}

main "$@"
