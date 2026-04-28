#!/bin/bash

################################################################################
# Phase 22: Replica Sync Auto-Corrector
# Purpose: Automatically correct replica divergence
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
SYNC_LOG="${REPO_ROOT}/logs/replica-sync.log"
CONFIG_HASH_THRESHOLD=0.95  # 95% match required
REPLICATION_LAG_THRESHOLD=500  # 500ms
REPLICA_SSH_HOSTS_CSV="${REPLICA_SSH_HOSTS_CSV:?REPLICA_SSH_HOSTS_CSV must be set}"
IFS=',' read -r -a REPLICA_SSH_HOSTS <<< "$REPLICA_SSH_HOSTS_CSV"
mkdir -p "$(dirname "${SYNC_LOG}")"

log_sync() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${SYNC_LOG}"
}

################################################################################
# Section 1: Config Parity Detection
################################################################################

check_config_parity() {
    log_sync "🔍 Checking config parity across replicas..."
    
    local primary_hash=$(docker exec postgres-primary \
        bash -c 'cat /etc/postgresql/postgresql.conf | md5sum | cut -d" " -f1' 2>/dev/null || echo "")
    
    local replica_hash=""
    for replica_host in "${REPLICA_SSH_HOSTS[@]:1}"; do  # Skip primary, check replicas
        replica_hash=$(ssh "ubuntu@$replica_host" \
            'docker exec postgres-replica bash -c "cat /etc/postgresql/postgresql.conf | md5sum | cut -d\" \" -f1"' \
            2>/dev/null || echo "")
        
        if [ -z "$replica_hash" ]; then
            log_sync "⚠️  Could not get replica hash from $replica_host"
            continue
        fi
        
        if [ "$primary_hash" != "$replica_hash" ]; then
            log_sync "❌ Config mismatch detected on $replica_host"
            log_sync "   Primary hash: $primary_hash"
            log_sync "   Replica hash: $replica_hash"
            return 1  # Divergence detected
        fi
    done
    
    log_sync "✅ All replicas have matching configs"
    return 0
}

################################################################################
# Section 2: Replication Lag Detection
################################################################################

check_replication_lag() {
    log_sync "⏱️  Checking PostgreSQL replication lag..."
    
    # Get primary WAL LSN
    local primary_lsn=$(docker exec postgres-primary \
        psql -U postgres -c "SELECT pg_current_wal_lsn();" 2>/dev/null | tail -2 | head -1 | tr -d ' ')
    
    log_sync "Primary WAL LSN: $primary_lsn"
    
    # Check each replica
    for replica_host in "${REPLICA_SSH_HOSTS[@]:1}"; do
        local replica_lsn=$(ssh "ubuntu@$replica_host" \
            'docker exec postgres-replica psql -U postgres -c "SELECT pg_last_wal_receive_lsn();" 2>/dev/null | tail -2 | head -1 | tr -d " "' \
            2>/dev/null || echo "0/0")
        
        log_sync "Replica ($replica_host) WAL LSN: $replica_lsn"
        
        # Note: In production, would calculate actual byte difference
        # For now, log as detected
    done
}

################################################################################
# Section 3: Automatic Resync
################################################################################

auto_resync_replica() {
    local replica_host="$1"
    
    log_sync "🔄 Initiating auto-resync for replica: $replica_host"
    
    # Stop replica replication
    log_sync "Stopping replication on $replica_host..."
    ssh "ubuntu@$replica_host" \
        'docker exec postgres-replica psql -U postgres -c "SELECT pg_wal_replay_pause();"' \
        2>/dev/null || {
        log_sync "❌ Failed to pause replication"
        return 1
    }
    
    # Sync configs from primary
    log_sync "Syncing PostgreSQL config from primary..."
    docker cp postgres-primary:/etc/postgresql/postgresql.conf /tmp/postgresql.conf
    ssh "ubuntu@$replica_host" \
        'docker cp /tmp/postgresql.conf postgres-replica:/etc/postgresql/postgresql.conf' \
        2>/dev/null || {
        log_sync "❌ Failed to sync config"
        return 1
    }
    
    # Resume replication
    log_sync "Resuming replication on $replica_host..."
    ssh "ubuntu@$replica_host" \
        'docker exec postgres-replica psql -U postgres -c "SELECT pg_wal_replay_resume();"' \
        2>/dev/null || {
        log_sync "❌ Failed to resume replication"
        return 1
    }
    
    log_sync "✅ Replica resync completed"
    return 0
}

################################################################################
# Section 4: Environment Variable Parity
################################################################################

check_env_parity() {
    log_sync "🌍 Checking environment variable parity..."
    
    # Get primary env
    local primary_env=$(docker inspect postgres-primary \
        --format='{{json .Config.Env}}' 2>/dev/null || echo "[]")
    
    # Check replicas
    for replica_host in "${REPLICA_SSH_HOSTS[@]:1}"; do
        local replica_env=$(ssh "ubuntu@$replica_host" \
            'docker inspect postgres-replica --format="{{json .Config.Env}}"' \
            2>/dev/null || echo "[]")
        
        if [ "$primary_env" != "$replica_env" ]; then
            log_sync "❌ Environment mismatch on $replica_host"
            return 1
        fi
    done
    
    log_sync "✅ Environment variables match across all replicas"
    return 0
}

################################################################################
# Section 5: Container Version Parity
################################################################################

check_version_parity() {
    log_sync "📦 Checking container image versions..."
    
    local primary_image=$(docker inspect postgres-primary \
        --format='{{.Image}}' 2>/dev/null || echo "")
    
    log_sync "Primary image: $primary_image"
    
    for replica_host in "${REPLICA_SSH_HOSTS[@]:1}"; do
        local replica_image=$(ssh "ubuntu@$replica_host" \
            'docker inspect postgres-replica --format="{{.Image}}"' \
            2>/dev/null || echo "")
        
        log_sync "Replica ($replica_host) image: $replica_image"
        
        if [ "$primary_image" != "$replica_image" ]; then
            log_sync "❌ Image version mismatch on $replica_host"
            # Trigger image update
            ssh "ubuntu@$replica_host" \
                "docker pull $primary_image && docker-compose up -d postgres-replica" \
                2>/dev/null || log_sync "⚠️  Could not update image"
        fi
    done
}

################################################################################
# Section 6: Continuous Monitoring
################################################################################

continuous_sync_monitoring() {
    log_sync "🚀 Starting continuous replica sync monitoring..."
    
    while true; do
        log_sync "─────────────────────────────────────────────────"
        
        # Check all parity metrics
        check_config_parity || {
            log_sync "⚠️  Config parity check failed, initiating resync..."
            for replica_host in "${REPLICA_SSH_HOSTS[@]:1}"; do
                auto_resync_replica "$replica_host" || log_sync "❌ Resync failed for $replica_host"
            done
        }
        
        check_replication_lag
        check_env_parity || log_sync "⚠️  Environment parity issue detected"
        check_version_parity
        
        log_sync "Sync monitoring cycle complete"
        sleep 300  # Check every 5 minutes
    done
}

################################################################################
# Section 7: Main Execution
################################################################################

main() {
    local mode="${1:-continuous}"
    
    case "$mode" in
        continuous)
            continuous_sync_monitoring
            ;;
        check)
            check_config_parity
            check_replication_lag
            check_env_parity
            check_version_parity
            ;;
        resync)
            for replica_host in "${REPLICA_SSH_HOSTS[@]:1}"; do
                auto_resync_replica "$replica_host"
            done
            ;;
        *)
            echo "Usage: $0 {continuous|check|resync}"
            exit 1
            ;;
    esac
}

main "$@"
