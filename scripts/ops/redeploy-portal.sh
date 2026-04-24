#!/usr/bin/env bash
# @file        scripts/ops/redeploy-portal.sh
# @module      ops/deployment
# @description Redeploy the Kushnir.cloud Portal across all cluster replicas
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
# DEPLOYMENT LOGIC
################################################################################

redeploy_replica() {
    local replica="$1"
    
    log_info "🚀 Redeploying portal on $replica..."
    
    ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && \
        docker compose pull portal && \
        docker compose up -d portal" || log_fatal "Redeploy failed on $replica"
        
    log_info "✅ Portal redeployed on $replica"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Initiating Portal Cluster Redeploy..."
    
    # Convert replicas string to array
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        redeploy_replica "$replica"
    done
    
    log_info "✅ Portal cluster redeploy complete"
}

main "$@"
