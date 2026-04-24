#!/usr/bin/env bash
# @file        scripts/ops/redis-sentinel-health.sh
# @module      ops/health-monitoring
# @description Cluster-wide Redis Sentinel health and topology audit
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

REPLICAS="${REPLICAS:-}"
SSH_USER="${SSH_USER:-${DEPLOY_USER:-}}"

if [[ -z "$REPLICAS" ]]; then
    if [[ -n "${REPLICA_1_IP:-}" && -n "${REPLICA_2_IP:-}" ]]; then
        REPLICAS="${REPLICA_1_IP},${REPLICA_2_IP}"
    else
        log_fatal "Set REPLICAS or REPLICA_1_IP/REPLICA_2_IP before running Redis Sentinel health audit"
    fi
fi

if [[ -z "$SSH_USER" ]]; then
    log_fatal "Set SSH_USER or DEPLOY_USER before running Redis Sentinel health audit"
fi

################################################################################
# HEALTH AUDIT
################################################################################

audit_redis_health() {
    local replica="$1"
    
    log_info "🔍 Auditing Redis Sentinel health on $replica..."
    
    # 1. Check Sentinel process
    if ! ssh "$SSH_USER@$replica" "cd code-server-enterprise && docker compose ps redis-sentinel | grep 'running'" > /dev/null 2>&1; then
        log_error "✗ Redis Sentinel NOT running on $replica"
        return 1
    fi
    
    # 2. Get master info from sentinel
    local master_info
    master_info=$(ssh "$SSH_USER@$replica" "cd code-server-enterprise && docker compose exec -T redis-sentinel redis-cli -p 26379 sentinel masters" 2>/dev/null)
    
    if [[ -n "$master_info" ]]; then
        log_info "✅ Sentinel topology healthy on $replica"
        echo "$master_info" | head -n 10 | log_debug
    else
        log_error "✗ Sentinel cannot see any masters on $replica"
        return 1
    fi
}

################################################################################
# MAIN
################################################################################

main() {
    log_info "Starting Global Redis Health Audit Across Cluster"
    
    local replica_array
    IFS=',' read -ra replica_array <<< "$REPLICAS"
    
    local total_fails=0
    for replica in "${replica_array[@]}"; do
        audit_redis_health "$replica" || ((total_fails++))
    done
    
    if [[ $total_fails -eq 0 ]]; then
        log_info "✅ ALL replicas report healthy Redis Sentinel topology"
    else
        log_fatal "Redis Sentinel health audit FAILED on $total_fails nodes"
    fi
}

main "$@"
