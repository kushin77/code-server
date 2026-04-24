#!/usr/bin/env bash
# @file        scripts/ops/rollback.sh
# @module      ops/deployment
# @description Rollback the cluster to a specific Git commit across all replicas
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
ROLLBACK_COMMIT="${1:-HEAD^}"

if [[ -z "$REPLICAS" || "$REPLICAS" == "," ]]; then
    log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP"
fi

if [[ -z "$DEPLOY_USER" ]]; then
    log_fatal "Set DEPLOY_USER or SSH_USER"
fi

################################################################################
# ROLLBACK LOGIC
################################################################################

rollback_replica() {
    local replica="$1"
    local commit="$2"
    
    log_warn "⚠️  Rolling back $replica to $commit..."
    
    ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && \
        git fetch origin && \
        git reset --hard $commit && \
        docker compose pull && \
        docker compose up -d" || log_fatal "Rollback failed on $replica"
        
    log_info "✅ Rollback complete on $replica"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Cluster Rollback Initiated"
    log_info "Target Commit: $ROLLBACK_COMMIT"
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        rollback_replica "$replica" "$ROLLBACK_COMMIT"
    done
    
    log_info "✅ Cluster rollback process finished"
}

main "$@"
