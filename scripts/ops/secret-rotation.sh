#!/usr/bin/env bash
# @file        scripts/ops/secret-rotation.sh
# @module      ops/security
# @description Automated cluster-wide secret rotation and service restarts
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

################################################################################
# ROTATION LOGIC
################################################################################

rotate_cluster_secrets() {
    log_info "🔄 Starting secret rotation campaign..."
    
    # 1. Trigger GSM fetch locally to get fresh secrets
    log_info "Fetching latest secrets from GSM..."
    source "$SCRIPT_DIR/scripts/fetch-gsm-secrets.sh"
    
    # 2. Sync fresh .env to all replicas
    log_info "Syncing fresh .env to replicas..."
    "$SCRIPT_DIR/scripts/ops/sync-env-to-replicas.sh"
    
    # 3. Perform rolling restart of services
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        log_info "♻️ Rolling restart on $replica..."
        ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && docker compose up -d"
        log_info "✅ $replica secret rotation applied"
    done
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Kushnir.cloud Secret Rotation Pipeline Initiated"
    rotate_cluster_secrets
    log_info "✅ Secret rotation and service adoption complete"
}

main "$@"
