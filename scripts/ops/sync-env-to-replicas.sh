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

REPLICAS="${REPLICAS:-}"
DEPLOY_USER="${DEPLOY_USER:-${SSH_USER:-}}"
ENV_FILE=".env"

if [[ -z "$REPLICAS" ]]; then
    if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
        REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
    else
        log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before syncing the environment"
    fi
fi

if [[ -z "$DEPLOY_USER" ]]; then
    log_fatal "Set DEPLOY_USER or SSH_USER before syncing the environment"
fi

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
