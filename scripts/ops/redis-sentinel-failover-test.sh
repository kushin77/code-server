#!/usr/bin/env bash
# @file        scripts/ops/redis-sentinel-failover-test.sh
# @module      ops/resilience
# @description Comprehensive Redis Sentinel failover test across cluster
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

################################################################################
# TEST LOGIC
################################################################################

test_redis_failover() {
    log_info "🔥 Initiating Redis Sentinel Failover Test..."
    
    # 1. Identify current master
    local master_host
    master_host=$(docker compose exec -T redis-sentinel redis-cli -p 26379 sentinel get-master-addr-by-name mymaster | head -n 1)
    log_info "Found current Redis master: $master_host"
    
    # 2. Trigger failover
    log_warn "FORCE: Triggering Sentinel failover..."
    docker compose exec -T redis-sentinel redis-cli -p 26379 sentinel failover mymaster
    
    # 3. Wait and verify
    log_info "Waiting 10s for election..."
    sleep 10
    
    local new_master
    new_master=$(docker compose exec -T redis-sentinel redis-cli -p 26379 sentinel get-master-addr-by-name mymaster | head -n 1)
    
    if [[ "$new_master" != "$master_host" ]]; then
        log_info "✅ Failover successful. New master: $new_master"
    else
        log_error "✗ Failover failed. Master remains: $master_host"
        return 1
    fi
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Starting Redis Resilience Verification"
    test_redis_failover
    log_info "✅ Redis failover verification finished"
}

main "$@"
