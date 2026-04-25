#!/bin/bash
###############################################################################
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# Purpose: Monitors database replication lag and status for PostgreSQL and Redis
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1534 (IaC Governance), #1531 (Replica Deployment)
###############################################################################

set -euo pipefail

# Configuration (all env-var driven)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly DB_USER="${DB_USER:-postgres}"
readonly DB_CONTAINER="${DB_CONTAINER:-postgres}"
readonly PG_LAG_WARNING_THRESHOLD="${PG_LAG_WARNING_THRESHOLD:-1048576}"  # 1MB in bytes
readonly REDIS_CONTAINER="${REDIS_CONTAINER:-redis}"

log_info() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"; }
log_success() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"; }
log_warn() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"; }
log_error() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*"; }

check_pg_replication() {
    log_info "Checking PostgreSQL replication status..."
    
    # Query replication lag using docker exec to avoid local dependencies
    QUERY="SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replication_lag_bytes FROM pg_stat_replication;"
    
    RESULT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -c "$QUERY" 2>/dev/null || true)
    
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
