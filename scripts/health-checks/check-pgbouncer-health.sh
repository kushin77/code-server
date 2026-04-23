#!/usr/bin/env bash
# @file        scripts/health-checks/check-pgbouncer-health.sh
# @module      operations/health-checks
# @description Health check for PgBouncer connection pooler
# @owner       Infrastructure Team
# @status      Production ready - April 23, 2026
#
# Monitors PgBouncer connection pool status and reports:
# - Active connections
# - Idle connections
# - Pool utilization percentage
# - Connection errors
#
# Exit Codes:
#   0 = Healthy (< 90% pool utilization)
#   1 = Warning (90-99% utilization)
#   2 = Critical (100% utilized or not responding)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/logging.sh"

# Configuration
PGBOUNCER_HOST="${PGBOUNCER_HOST:-localhost}"
PGBOUNCER_PORT="${PGBOUNCER_PORT:-6432}"
PGBOUNCER_ADMIN_USER="${PGBOUNCER_ADMIN_USER:-pgbouncer}"
PGBOUNCER_TIMEOUT="${PGBOUNCER_TIMEOUT:-5}"
POOL_WARNING_THRESHOLD=${POOL_WARNING_THRESHOLD:-90}
POOL_CRITICAL_THRESHOLD=${POOL_CRITICAL_THRESHOLD:-100}

# Helper functions
check_pgbouncer_connectivity() {
    if ! timeout "$PGBOUNCER_TIMEOUT" bash -c "echo '' > /dev/tcp/$PGBOUNCER_HOST/$PGBOUNCER_PORT" 2>/dev/null; then
        log_error "Cannot connect to PgBouncer at $PGBOUNCER_HOST:$PGBOUNCER_PORT"
        return 1
    fi
    return 0
}

get_pool_stats() {
    local stats_output
    
    # Try to get stats via psql admin interface
    stats_output=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$PGBOUNCER_ADMIN_USER" \
        -d pgbouncer -A -t -c "SHOW POOLS;" 2>/dev/null) || {
        log_error "Failed to retrieve PgBouncer pool statistics"
        return 1
    }
    
    echo "$stats_output"
}

parse_pool_stats() {
    local stats="$1"
    local total_active=0
    local total_idle=0
    local total_waiting=0
    local max_connections=0
    
    # Parse each pool line and sum up connections
    while IFS='|' read -r database user_name cl_active cl_waiting sv_active sv_idle sv_tested sv_login maxwait maxage pool_mode; do
        # Skip header or empty lines
        [[ -z "$database" ]] && continue
        [[ "$database" == "database" ]] && continue
        
        # Convert to numbers (handle empty/whitespace values)
        cl_active=$((${cl_active:-0}))
        sv_active=$((${sv_active:-0}))
        sv_idle=$((${sv_idle:-0}))
        
        total_active=$((total_active + sv_active))
        total_idle=$((total_idle + sv_idle))
        total_waiting=$((total_waiting + cl_active))
        max_connections=$((max_connections + 100))  # Default pool size per database
    done <<< "$stats"
    
    echo "$total_active|$total_idle|$total_waiting|$max_connections"
}

# Main health check logic
main() {
    log_info "Starting PgBouncer health check (host=$PGBOUNCER_HOST:$PGBOUNCER_PORT)"
    
    # Step 1: Check connectivity
    if ! check_pgbouncer_connectivity; then
        log_fatal "PgBouncer connectivity check failed"
        return 2
    fi
    
    log_info "✓ PgBouncer connectivity verified"
    
    # Step 2: Get pool statistics
    local stats
    if ! stats=$(get_pool_stats); then
        log_fatal "Failed to retrieve pool statistics"
        return 2
    fi
    
    # Step 3: Parse and analyze
    local parsed
    parsed=$(parse_pool_stats "$stats")
    IFS='|' read -r active idle waiting max_conns <<< "$parsed"
    
    local total_used=$((active + waiting))
    local utilization=$((total_used * 100 / max_conns))
    
    log_info "PgBouncer Status:"
    log_info "  Active Connections: $active"
    log_info "  Idle Connections: $idle"
    log_info "  Waiting Clients: $waiting"
    log_info "  Total Used: $total_used / $max_conns"
    log_info "  Pool Utilization: $utilization%"
    
    # Step 4: Determine health status
    if (( utilization >= POOL_CRITICAL_THRESHOLD )); then
        log_error "CRITICAL: Connection pool at $utilization% utilization (limit: $POOL_CRITICAL_THRESHOLD%)"
        return 2
    elif (( utilization >= POOL_WARNING_THRESHOLD )); then
        log_warn "WARNING: Connection pool at $utilization% utilization (threshold: $POOL_WARNING_THRESHOLD%)"
        return 1
    else
        log_info "✓ PgBouncer health check PASSED"
        return 0
    fi
}

main "$@"
