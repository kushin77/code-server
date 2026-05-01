#!/bin/bash
###############################################################################
# @file        scripts/ops/monitor-replication.sh
# @module      ops/monitor-replication
# @description Infrastructure automation script
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        2026-04-25
###############################################################################

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"
# @description Monitors database replication lag and status for PostgreSQL and Redis.
# @governance GOV-002

# Configuration
PG_USER=${DB_USER:?DB_USER must be set}

check_pg_replication() {
    log_info "Checking PostgreSQL replication status..."
    
    # Query replication lag using docker exec to avoid local dependencies
    QUERY="SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replication_lag_bytes FROM pg_stat_replication;"
    
    RESULT=$(docker exec postgres psql -U "$PG_USER" -c "$QUERY" 2>/dev/null || true)
    
    if [[ -z "$RESULT" ]] || [[ "$RESULT" == *"0 rows"* ]]; then
        log_warn "No PostgreSQL replication slots active or unable to query."
    else
        echo "$RESULT"
        log_success "PostgreSQL replication status retrieved."
    fi
}

check_redis_replication() {
    log_info "Checking Redis replication status..."
    
    REPL_INFO=$(docker exec redis redis-cli info replication 2>/dev/null || true)
    
    if [[ -n "$REPL_INFO" ]]; then
        ROLE=$(echo "$REPL_INFO" | grep "role:" | cut -d: -f2 | tr -d '\r')
        log_info "Redis Role: $ROLE"
        if [[ "$ROLE" == "master" ]]; then
            SLAVES=$(echo "$REPL_INFO" | grep "connected_slaves:" | cut -d: -f2 | tr -d '\r')
            log_info "Connected Slaves: $SLAVES"
        fi
        log_success "Redis replication info retrieved."
    else
        log_warn "Failed to retrieve Redis replication info (is Redis running?)."
    fi
}

main() {
    log_info "Starting Database Replication Monitoring (P1 Priority 5)..."
    check_pg_replication
    check_redis_replication
    log_success "Replication monitoring check complete."
}

main
