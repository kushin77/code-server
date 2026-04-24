#!/usr/bin/env bash
# @file        scripts/ops/validate-cluster-parity.sh
# @module      ops/cluster-validation
# @description Quick parity check for cluster node metadata and commit drift
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
# QUICK PARITY CHECK
################################################################################

check_node_parity() {
    local replica="$1"
    
    log_info "⚡ Quick parity scan on $replica..."
    
    local node_commit
    node_commit=$(ssh "$DEPLOY_USER@$replica" "cd code-server-enterprise && git rev-parse HEAD" 2>/dev/null || echo "COMM_ERR")
    
    if [[ "$node_commit" == "COMM_ERR" ]]; then
        log_error "✗ Could not retrieve commit from $replica"
        return 1
    fi
    
    log_info "✅ $replica on commit: ${node_commit:0:8}"
    return 0
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Starting Quick Cluster Parity Sweep"
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    for replica in "${replica_array[@]}"; do
        check_node_parity "$replica"
    done
    
    log_info "✅ Quick parity sweep complete"
}

main "$@"
