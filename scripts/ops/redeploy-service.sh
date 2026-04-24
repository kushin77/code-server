#!/usr/bin/env bash
# @file        scripts/ops/redeploy-service.sh
# @module      ops/deployment
# @description Selective service redeploy across all cluster replicas
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
SERVICE_NAME="${1:-}"

if [[ -z "$SERVICE_NAME" ]]; then
    log_fatal "Usage: $0 <service_name>"
fi

################################################################################
# SERVICE REDEPLOY
################################################################################

redeploy_service_on_replica() {
    local replica="$1"
    local service="$2"
    
    log_info "🚀 Redeploying [$service] on $replica..."
    
    ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && \
        docker compose pull $service && \
        docker compose up -d $service" || log_fatal "Redeploy failed for $service on $replica"
        
    log_info "✅ Service [$service] redeployed on $replica"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Initiating Cluster Service Redeploy: $SERVICE_NAME"
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        redeploy_service_on_replica "$replica" "$SERVICE_NAME"
    done
    
    log_info "✅ Service cluster redeploy complete"
}

main "$@"
