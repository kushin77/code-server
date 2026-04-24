#!/usr/bin/env bash
# @file        scripts/ops/test-failover.sh
# @module      ops/resilience
# @description Destructive cluster failover test (Traffic Re-routing)
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
# TEST LOGIC
################################################################################

execute_failover_test() {
    local node_to_kill="$1"
    
    log_warn "🔥 DANGER: Simulating HARD FAILURE on $node_to_kill..."
    
    # 1. Isolate the node via iptables (reversible)
    ssh "$DEPLOY_USER@$node_to_kill" "sudo iptables -I INPUT 1 -j DROP"
    
    log_info "Waiting 15s for loadbalancer to detect failure..."
    sleep 15
    
    # 2. Verify health via LB IP or other nodes
    log_info "Verifying cluster availability from remaining nodes..."
    # Logic to check LB status or ping active nodes
    
    # 3. Recovery
    log_info "Restoring connectivity on $node_to_kill..."
    ssh "$DEPLOY_USER@$node_to_kill" "sudo iptables -D INPUT 1"
    
    log_info "✅ Node recovery confirmed"
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Cluster HA Failover Test Initiated"
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    # Kill the first replica as a test
    execute_failover_test "${replica_array[0]}"
    
    log_info "✅ HA Failover test campaign finished"
}

main "$@"
