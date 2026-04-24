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

REPLICAS="${REPLICAS:-${REPLICA_1_IP:-},${REPLICA_2_IP:-}}"
DEPLOY_USER="${DEPLOY_USER:-${SSH_USER:-}}"

if [[ -z "$REPLICAS" || "$REPLICAS" == "," ]]; then
    log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP"
fi

if [[ -z "$DEPLOY_USER" ]]; then
    log_fatal "Set DEPLOY_USER or SSH_USER"
fi

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
