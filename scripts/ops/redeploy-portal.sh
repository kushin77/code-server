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

REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"

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
