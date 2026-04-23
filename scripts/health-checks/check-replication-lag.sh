#!/usr/bin/env bash
# @file        scripts/health-checks/check-replication-lag.sh
# @module      operations/health-checks
# @description Health check for PostgreSQL streaming replication lag
# @owner       Infrastructure Team
# @status      Production ready - April 23, 2026
#
# Monitors replication lag between primary and replica databases and reports:
# - Current replication lag in bytes
# - Replication lag in milliseconds
# - Replica connection status
# - WAL archive status
#
# Exit Codes:
#   0 = Healthy (lag < 100ms)
#   1 = Warning (lag 100ms - 1s)
#   2 = Critical (lag > 1s or replica disconnected)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/logging.sh"

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
DB_USER="${DB_USER:-postgres}"
DB_PORT="${DB_PORT:-5432}"
LAG_WARNING_MS=${LAG_WARNING_MS:-100}
LAG_CRITICAL_MS=${LAG_CRITICAL_MS:-1000}

# Helper functions
check_primary_connectivity() {
    if ! timeout 5 bash -c "echo '' > /dev/tcp/$PRIMARY_HOST/$DB_PORT" 2>/dev/null; then
        log_error "Cannot connect to primary at $PRIMARY_HOST:$DB_PORT"
        return 1
    fi
    
    log_info "✓ Primary database connectivity verified"
    return 0
}

check_replica_connectivity() {
    if ! timeout 5 bash -c "echo '' > /dev/tcp/$REPLICA_HOST/$DB_PORT" 2>/dev/null; then
        log_error "Cannot connect to replica at $REPLICA_HOST:$DB_PORT"
        return 1
    fi
    
    log_info "✓ Replica database connectivity verified"
    return 0
}

get_replication_lag() {
    local lag_bytes lag_ms
    
    # Query primary for replication lag
    # This uses pg_last_xlog_receive_lsn() on replica or pg_last_wal_receive_lsn() on replica
    lag_bytes=$(psql -h "$PRIMARY_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -A -t \
        -c "SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp()))::bigint AS lag_seconds;" 2>/dev/null || echo "-1")
    
    if [[ "$lag_bytes" == "-1" ]]; then
        log_error "Failed to retrieve replication lag from primary"
        return 1
    fi
    
    # Convert to milliseconds for easier threshold checking
    lag_ms=$((lag_bytes * 1000))
    
    echo "$lag_bytes|$lag_ms"
}

get_replica_status() {
    local status
    
    # Query primary for replica connection status
    status=$(psql -h "$PRIMARY_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -A -t \
        -c "SELECT COUNT(*) FROM pg_stat_replication;" 2>/dev/null || echo "0")
    
    echo "$status"
}

get_wal_archive_status() {
    local ready archived failed
    
    ready=$(find /var/lib/postgresql/wal_archive/ready -type f 2>/dev/null | wc -l || echo "0")
    archived=$(find /var/lib/postgresql/wal_archive/archived -type f 2>/dev/null | wc -l || echo "0")
    failed=$(find /var/lib/postgresql/wal_archive/failed -type f 2>/dev/null | wc -l || echo "0")
    
    echo "$ready|$archived|$failed"
}

# Main health check logic
main() {
    log_info "Starting PostgreSQL replication lag health check"
    log_info "  Primary: $PRIMARY_HOST:$DB_PORT"
    log_info "  Replica: $REPLICA_HOST:$DB_PORT"
    
    # Step 1: Check connectivity
    if ! check_primary_connectivity; then
        log_fatal "Primary connectivity check failed"
        return 2
    fi
    
    if ! check_replica_connectivity; then
        log_fatal "Replica connectivity check failed"
        return 2
    fi
    
    # Step 2: Get replica connection status
    local replica_count
    replica_count=$(get_replica_status)
    log_info "Connected replicas: $replica_count"
    
    if (( replica_count == 0 )); then
        log_error "CRITICAL: No replica connections from primary"
        return 2
    fi
    
    # Step 3: Get replication lag
    local lag_info
    if ! lag_info=$(get_replication_lag); then
        log_error "Failed to retrieve replication lag"
        return 2
    fi
    
    IFS='|' read -r lag_seconds lag_ms <<< "$lag_info"
    
    log_info "Replication Lag Status:"
    log_info "  Lag: ${lag_seconds}s (${lag_ms}ms)"
    log_info "  Threshold: ${LAG_WARNING_MS}ms warning, ${LAG_CRITICAL_MS}ms critical"
    
    # Step 4: Get WAL archive status
    local wal_info
    wal_info=$(get_wal_archive_status)
    IFS='|' read -r wal_ready wal_archived wal_failed <<< "$wal_info"
    
    log_info "WAL Archive Status:"
    log_info "  Ready: $wal_ready files"
    log_info "  Archived: $wal_archived files"
    log_info "  Failed: $wal_failed files"
    
    # Step 5: Determine health status
    if (( lag_ms >= LAG_CRITICAL_MS )); then
        log_error "CRITICAL: Replication lag ${lag_ms}ms exceeds threshold ${LAG_CRITICAL_MS}ms"
        return 2
    elif (( lag_ms >= LAG_WARNING_MS )); then
        log_warn "WARNING: Replication lag ${lag_ms}ms exceeds threshold ${LAG_WARNING_MS}ms"
        return 1
    else
        log_info "✓ Replication lag health check PASSED (${lag_ms}ms lag)"
        return 0
    fi
}

main "$@"
