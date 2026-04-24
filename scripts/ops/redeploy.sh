#!/usr/bin/env bash
# @file        scripts/ops/redeploy.sh
# @module      ops/deployment
# @description Standard multi-replica cluster redeployment (Idempotent & Immutable)
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

################################################################################
# REDEPLOY LOGIC
################################################################################

redeploy_cluster_node() {
    local replica="$1"
    
    log_info "🚀 Executing standard redeploy on $replica..."
    
    ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && \
        docker compose pull && \
        docker compose up -d --remove-orphans" || log_fatal "Redeploy failed on $replica"
        
    log_info "✅ Node $replica is up-to-date"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Initiating Standard Cluster Redeployment Campaign"
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    # Deploy to all replicas in parallel
    for replica in "${replica_array[@]}"; do
        redeploy_cluster_node "$replica" &
    done
    
    wait
    
    log_info "✅ All cluster nodes redeployed successfully"
}

main "$@"
