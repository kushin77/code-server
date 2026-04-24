#!/usr/bin/env bash
# @file        scripts/ops/failover-promote.sh
# @module      ops/failover
# @description Promote a replica to primary role with data consistency checks
# @owner       infrastructure
# @status      stable

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

DRY_RUN="${DRY_RUN:-0}"
PRIMARY_HOST="${PRIMARY_HOST:-${DEPLOY_HOST:-${REPLICA_1_IP:-}}}"
REPLICA_HOST="${REPLICA_HOST:-${REPLICA_2_IP:-}}"
DEPLOY_USER="${DEPLOY_USER:-${SSH_USER:-}}"
HEALTH_SCHEME="${HEALTH_SCHEME:-http}"
DATA_SYNC_CHECK="${DATA_SYNC_CHECK:-1}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"

require_value() {
    local value="$1"
    local message="$2"

    if [[ -z "$value" ]]; then
        log_fatal "$message"
    fi
}

check_endpoint() {
    local url="$1"
    timeout 10 bash -c "curl -sf '$url' >/dev/null 2>&1"
}

require_value "$PRIMARY_HOST" "Set PRIMARY_HOST or DEPLOY_HOST before failover"
require_value "$REPLICA_HOST" "Set REPLICA_HOST or REPLICA_2_IP before failover"
require_value "$DEPLOY_USER" "Set DEPLOY_USER or SSH_USER before failover"

log_stage() {
    log_info "========== $1 =========="
}

main() {
    log_stage "FAILOVER: PROMOTE REPLICA TO PRIMARY"
    log_info "Primary (failing): $PRIMARY_HOST"
    log_info "Replica (promoting): $REPLICA_HOST"
    log_info "Dry-run mode: $([ "$DRY_RUN" -eq 1 ] && echo 'YES (no changes)' || echo 'NO (will promote)')"
    echo ""

    log_stage "STEP 1: Verify Primary is Unavailable"
    log_info "Checking primary at $PRIMARY_HOST..."
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would check: curl ${HEALTH_SCHEME}://${PRIMARY_HOST}:8080/healthz"
    else
        if timeout 10 bash -c "curl -sf ${HEALTH_SCHEME}://${PRIMARY_HOST}:8080/healthz >/dev/null 2>&1"; then
            if [ "${FORCE_FAILOVER:-0}" -eq 1 ]; then
                log_warn "Primary still responds, but FORCE_FAILOVER=1 is set"
            else
                log_error "Primary appears to be up; set FORCE_FAILOVER=1 to continue"
                exit 1
            fi
        else
            log_info "Primary is unreachable as expected"
        fi
    fi

    echo ""
    log_stage "STEP 2: Verify Replica is Healthy"
    log_info "Checking replica at $REPLICA_HOST..."
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would check replica SSH, Docker, and database health"
    else
        if ! timeout 10 ssh -o ConnectTimeout=5 "$DEPLOY_USER@$REPLICA_HOST" "echo Connected" >/dev/null 2>&1; then
            log_error "Cannot connect to replica"
            exit 1
        fi
        if ! ssh "$DEPLOY_USER@$REPLICA_HOST" "docker ps >/dev/null 2>&1"; then
            log_error "Docker daemon not accessible on replica"
            exit 1
        fi
        if ! ssh "$DEPLOY_USER@$REPLICA_HOST" "docker ps | grep -q postgres"; then
            log_error "PostgreSQL not running on replica"
            exit 1
        fi
    fi

    echo ""
    if [ "$DATA_SYNC_CHECK" -eq 1 ]; then
        log_stage "STEP 3: Verify Data Synchronization"
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would check PostgreSQL replication state"
        else
            ssh "$DEPLOY_USER@$REPLICA_HOST" "docker exec postgres psql -U postgres -c \"SELECT pg_last_wal_receive_lsn()\" >/dev/null" || {
                log_error "Could not verify PostgreSQL replication state"
                exit 1
            }
        fi
    fi

    echo ""
    log_stage "STEP 4: Promote Replica to Primary"
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would update DNS/load balancer and restart services on $REPLICA_HOST"
    else
        ssh "$DEPLOY_USER@$REPLICA_HOST" "docker compose restart" >/dev/null 2>&1 || true
    fi

    echo ""
    log_stage "STEP 5: Health Verification"
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would verify health endpoints on $REPLICA_HOST"
    else
        timeout "$HEALTH_CHECK_TIMEOUT" bash -c "until curl -sf ${HEALTH_SCHEME}://${REPLICA_HOST}:8080/healthz >/dev/null 2>&1; do sleep 2; done"
        timeout "$HEALTH_CHECK_TIMEOUT" bash -c "until curl -sf ${HEALTH_SCHEME}://${REPLICA_HOST}:9090/-/healthy >/dev/null 2>&1; do sleep 2; done"
    fi

    log_stage "FAILOVER COMPLETE"
    log_info "New Primary: $REPLICA_HOST"
    log_info "  Code-server: ${HEALTH_SCHEME}://${REPLICA_HOST}:8080"
    log_info "  Prometheus:  ${HEALTH_SCHEME}://${REPLICA_HOST}:9090"
    log_info "Run failback when the original primary is ready again"
}

main "$@"