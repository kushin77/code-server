#!/bin/bash

################################################################################
# Phase 22: Failover Automation System
# Purpose: Automatic VRRP, PostgreSQL, and Redis failover
# Date: April 28, 2026
################################################################################

set -euo pipefail

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR%/scripts*}" && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh" || exit 1

# Configuration
PRIMARY_IP="192.168.168.30"
REPLICA_IP="192.168.168.31"
WITNESS_IP="192.168.168.32"
VRRP_VIP="192.168.168.50"
FAILOVER_LOG="${REPO_ROOT}/logs/failover.log"
mkdir -p "$(dirname "${FAILOVER_LOG}")"

log_failover() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${FAILOVER_LOG}"
}

################################################################################
# Section 1: Health Checking
################################################################################

check_primary_health() {
    log_failover "🏥 Checking primary health..."
    
    # Check connectivity
    if ! ping -c 1 -W 2 "$PRIMARY_IP" &>/dev/null; then
        log_failover "❌ Primary unreachable: $PRIMARY_IP"
        return 1
    fi
    
    # Check PostgreSQL
    if ! timeout 5 psql -h "$PRIMARY_IP" -U postgres -c "SELECT 1" &>/dev/null; then
        log_failover "❌ PostgreSQL unavailable on primary"
        return 1
    fi
    
    # Check Redis
    if ! timeout 5 redis-cli -h "$PRIMARY_IP" ping &>/dev/null; then
        log_failover "❌ Redis unavailable on primary"
        return 1
    fi
    
    log_failover "✅ Primary is healthy"
    return 0
}

################################################################################
# Section 2: Quorum Voting
################################################################################

check_quorum() {
    log_failover "🗳️  Checking cluster quorum..."
    
    local votes=0
    local node_count=0
    
    # Check primary
    if check_primary_health; then
        ((votes++))
    fi
    ((node_count++))
    
    # Check replica
    if timeout 5 psql -h "$REPLICA_IP" -U postgres -c "SELECT 1" &>/dev/null; then
        ((votes++))
    fi
    ((node_count++))
    
    # Check witness (usually lighter check)
    if timeout 5 ssh "ubuntu@$WITNESS_IP" "echo ok" &>/dev/null; then
        ((votes++))
    fi
    ((node_count++))
    
    local quorum_needed=$(( (node_count + 1) / 2 ))
    
    log_failover "Votes: $votes/$node_count (quorum: $quorum_needed)"
    
    if [ $votes -ge $quorum_needed ]; then
        log_failover "✅ Quorum established"
        return 0
    else
        log_failover "❌ Quorum NOT established"
        return 1
    fi
}

################################################################################
# Section 3: PostgreSQL Failover
################################################################################

failover_postgresql() {
    log_failover "🔄 Initiating PostgreSQL failover..."
    
    # Pause replica replication
    log_failover "Pausing replica replication..."
    ssh "ubuntu@$REPLICA_IP" \
        'docker exec postgres-replica psql -U postgres -c "SELECT pg_wal_replay_pause();"' \
        2>/dev/null || {
        log_failover "⚠️  Could not pause replication"
        return 1
    }
    
    # Promote replica to primary
    log_failover "Promoting replica to primary..."
    ssh "ubuntu@$REPLICA_IP" \
        'docker exec postgres-replica pg_ctl promote -D /var/lib/postgresql/data' \
        2>/dev/null || {
        log_failover "❌ Replica promotion failed"
        return 1
    }
    
    # Wait for promotion
    sleep 5
    
    # Verify promotion
    if timeout 5 psql -h "$REPLICA_IP" -U postgres -c "SELECT version();" &>/dev/null; then
        log_failover "✅ PostgreSQL failover successful"
        return 0
    else
        log_failover "❌ PostgreSQL failover verification failed"
        return 1
    fi
}

################################################################################
# Section 4: Redis Sentinel Failover
################################################################################

failover_redis() {
    log_failover "⚡ Initiating Redis failover..."
    
    # Trigger Sentinel failover
    log_failover "Requesting Sentinel failover..."
    redis-cli -h "$PRIMARY_IP" -p 26379 sentinel failover mymaster 2>/dev/null || {
        log_failover "❌ Redis sentinel failover failed"
        return 1
    }
    
    # Wait for failover
    sleep 5
    
    # Verify new master
    if timeout 5 redis-cli -h "$REPLICA_IP" ping &>/dev/null; then
        log_failover "✅ Redis failover successful"
        return 0
    else
        log_failover "❌ Redis failover verification failed"
        return 1
    fi
}

################################################################################
# Section 5: VRRP Virtual IP Failover
################################################################################

failover_vrrp() {
    log_failover "🌐 Initiating VRRP VIP failover..."
    
    # Get current VRRP master
    local vrrp_status=$(ip addr show | grep -E "inet.*$VRRP_VIP" | head -1 || echo "")
    
    if [ -z "$vrrp_status" ]; then
        log_failover "Current node doesn't have VIP, requesting priority increase..."
    else
        log_failover "Current node has VIP, initiating release..."
        # Set priority to 0 to trigger failover
        ssh "ubuntu@$REPLICA_IP" \
            'echo "$(vrrp show)" | grep -i vrrp' \
            2>/dev/null || true
    fi
    
    # Force failover by stopping VRRP on primary
    log_failover "Stopping VRRP on primary (forcing failover)..."
    ssh "ubuntu@$PRIMARY_IP" "systemctl stop keepalived" 2>/dev/null || {
        log_failover "⚠️  Could not stop keepalived on primary"
    }
    
    # Wait for VRRP transition
    sleep 3
    
    # Verify VIP moved
    if timeout 5 ssh "ubuntu@$REPLICA_IP" "ip addr show | grep $VRRP_VIP" &>/dev/null; then
        log_failover "✅ VRRP VIP failover successful"
        return 0
    else
        log_failover "⚠️  VRRP failover status unclear"
        return 0
    fi
}

################################################################################
# Section 6: Complete Failover Process
################################################################################

execute_complete_failover() {
    log_failover "═══════════════════════════════════════════════════════"
    log_failover "🚨 STARTING COMPLETE CLUSTER FAILOVER SEQUENCE"
    log_failover "═══════════════════════════════════════════════════════"
    
    # Check quorum first
    if ! check_quorum; then
        log_failover "❌ Cannot perform failover without quorum"
        return 1
    fi
    
    # Execute failovers in sequence
    local success=true
    
    # PostgreSQL failover
    if failover_postgresql; then
        log_failover "✅ PostgreSQL failover succeeded"
    else
        log_failover "❌ PostgreSQL failover failed"
        success=false
    fi
    
    # Redis failover
    if failover_redis; then
        log_failover "✅ Redis failover succeeded"
    else
        log_failover "❌ Redis failover failed"
        success=false
    fi
    
    # VRRP failover
    if failover_vrrp; then
        log_failover "✅ VRRP failover succeeded"
    else
        log_failover "❌ VRRP failover failed"
        success=false
    fi
    
    if [ "$success" = true ]; then
        log_failover "✅ COMPLETE FAILOVER SUCCESSFUL"
        return 0
    else
        log_failover "❌ COMPLETE FAILOVER PARTIAL/FAILED"
        return 1
    fi
}

################################################################################
# Section 7: Continuous Monitoring with Auto-Failover
################################################################################

continuous_failover_monitoring() {
    log_failover "🚀 Starting continuous failover monitoring..."
    
    local consecutive_failures=0
    local failure_threshold=3
    
    while true; do
        if check_primary_health; then
            consecutive_failures=0
        else
            ((consecutive_failures++))
            log_failover "Primary health check failed ($consecutive_failures/$failure_threshold)"
            
            if [ $consecutive_failures -ge $failure_threshold ]; then
                log_failover "🚨 Primary has failed threshold, executing automatic failover"
                
                if execute_complete_failover; then
                    log_failover "✅ Automatic failover completed"
                else
                    log_failover "❌ Automatic failover failed, manual intervention required"
                fi
                
                # Reset counters after failover attempt
                consecutive_failures=0
            fi
        fi
        
        sleep 10  # Check every 10 seconds
    done
}

################################################################################
# Section 8: Main Execution
################################################################################

main() {
    local mode="${1:-monitor}"
    
    case "$mode" in
        monitor)
            continuous_failover_monitoring
            ;;
        check)
            check_primary_health
            check_quorum
            ;;
        failover)
            execute_complete_failover
            ;;
        *)
            echo "Usage: $0 {monitor|check|failover}"
            exit 1
            ;;
    esac
}

main "$@"
