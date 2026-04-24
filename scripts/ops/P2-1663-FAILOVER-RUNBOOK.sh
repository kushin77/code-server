#!/usr/bin/env bash
# @file        scripts/ops/P2-1663-FAILOVER-RUNBOOK.sh
# @module      operations/failover
# @description Failover runbook for operations team - manual failover procedures
#
# Usage: bash scripts/ops/P2-1663-FAILOVER-RUNBOOK.sh [--action status|isolate|promote|rollback] [--replica 192.168.168.31]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
SSH_USER="${SSH_USER:-akushnir}"
REPO_PATH="${REPO_PATH:-/home/${SSH_USER}/code-server-enterprise}"
ACTION="${ACTION:-status}"
TARGET_REPLICA="${TARGET_REPLICA:-}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-http://localhost:8080/healthz}"

ssh_exec() {
    local host="$1"
    local cmd="$2"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
        "$SSH_USER@$host" "cd $REPO_PATH && $cmd"
}

# ============================================================================
# Health Assessment
# ============================================================================

assess_replica_health() {
    local replica="$1"
    
    log_info "Assessing replica health: $replica"
    
    # Check SSH connectivity
    if ! ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$replica" "echo OK" >/dev/null 2>&1; then
        log_error "[$replica] ❌ SSH connectivity FAILED"
        return 1
    fi
    log_info "[$replica] ✅ SSH connectivity OK"
    
    # Check services running
    local service_count=$(ssh_exec "$replica" "docker ps --quiet | wc -l" 2>/dev/null || echo "0")
    log_info "[$replica] Services running: $service_count"
    
    # Check health endpoint
    if ssh_exec "$replica" "curl -sf $HEALTH_ENDPOINT >/dev/null" 2>/dev/null; then
        log_info "[$replica] ✅ Health endpoint responding"
        return 0
    else
        log_error "[$replica] ❌ Health endpoint NOT responding"
        return 1
    fi
}

assess_all_replicas() {
    log_info "=========================================="
    log_info "ASSESSING ALL REPLICAS"
    log_info "=========================================="
    
    local replicas=(192.168.168.31 192.168.168.42)
    
    for replica in "${replicas[@]}"; do
        if assess_replica_health "$replica"; then
            log_info "[$replica] STATUS: 🟢 HEALTHY"
        else
            log_info "[$replica] STATUS: 🔴 UNHEALTHY"
        fi
        log_info ""
    done
}

# ============================================================================
# Failover Actions
# ============================================================================

isolate_replica() {
    local replica="$1"
    
    if [[ -z "$replica" ]]; then
        log_fatal "Replica not specified for isolation"
    fi
    
    log_info "=========================================="
    log_info "ISOLATING REPLICA: $replica"
    log_info "=========================================="
    
    log_warn "⚠️  This will block network traffic to $replica"
    log_info "To isolate (using iptables on the replica itself):"
    log_info ""
    log_info "  ssh -i $SSH_KEY $SSH_USER@$replica"
    log_info "  sudo iptables -I INPUT 1 -j DROP"
    log_info ""
    log_info "  # Services will continue running but will be unreachable"
    log_info "  # Load balancer will detect failure and route traffic to other replica"
    log_info "  # Monitor: curl -s http://other-replica/health"
    log_info ""
    log_info "To restore:"
    log_info "  sudo iptables -D INPUT -j DROP"
    log_info ""
}

promote_replica() {
    local replica="$1"
    
    if [[ -z "$replica" ]]; then
        log_fatal "Replica not specified for promotion"
    fi
    
    log_info "=========================================="
    log_info "REPLICA PROMOTION PROCEDURE: $replica"
    log_info "=========================================="
    
    # Assess current replica
    if ! assess_replica_health "$replica"; then
        log_fatal "Target replica $replica is not healthy - cannot promote"
    fi
    
    log_info ""
    log_info "✅ Target replica is healthy"
    log_info ""
    log_info "Next steps:"
    log_info "1. Update load balancer to route all traffic to $replica"
    log_info "2. Monitor database replication lag: "
    log_info "   ssh -i $SSH_KEY $SSH_USER@$replica 'docker-compose logs postgresql'"
    log_info "3. Verify session state is consistent:"
    log_info "   ssh -i $SSH_KEY $SSH_USER@$replica 'redis-cli INFO replication'"
    log_info ""
    log_info "📝 NOTE: In active-active cluster, no promotion needed - both replicas accept traffic"
    log_info ""
}

rollback_failover() {
    local replica="$1"
    
    if [[ -z "$replica" ]]; then
        log_fatal "Replica not specified for rollback"
    fi
    
    log_info "=========================================="
    log_info "FAILOVER ROLLBACK PROCEDURE"
    log_info "=========================================="
    
    log_info "1. Verify isolated replica is recovered:"
    log_info "   ssh -i $SSH_KEY $SSH_USER@$replica 'sudo iptables -D INPUT -j DROP'"
    log_info ""
    log_info "2. Check if services auto-recovered:"
    log_info "   ssh -i $SSH_KEY $SSH_USER@$replica 'curl -sf $HEALTH_ENDPOINT && echo OK'"
    log_info ""
    log_info "3. If services didn't recover, redeploy:"
    log_info "   bash scripts/ops/P2-1664-PRODUCTION-DEPLOYMENT-RUNBOOK.sh --replicas $replica"
    log_info ""
    log_info "4. Load balancer will automatically restore distribution once health checks pass"
    log_info ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "=========================================="
    log_info "FAILOVER RUNBOOK FOR OPERATIONS"
    log_info "=========================================="
    log_info "Action: $ACTION"
    log_info "Target Replica: ${TARGET_REPLICA:-all}"
    log_info ""
    
    case "$ACTION" in
        status)
            assess_all_replicas
            ;;
        isolate)
            isolate_replica "$TARGET_REPLICA"
            ;;
        promote)
            promote_replica "$TARGET_REPLICA"
            ;;
        rollback)
            rollback_failover "$TARGET_REPLICA"
            ;;
        *)
            log_fatal "Unknown action: $ACTION (valid: status, isolate, promote, rollback)"
            ;;
    esac
    
    log_info "✅ Failover runbook complete"
}

main "$@"
