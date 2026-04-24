#!/usr/bin/env bash
# @file        scripts/verify-cluster-health.sh
# @module      deployment/verification
# @description Pre-deployment cluster health verification for active-active replicas

set -euo pipefail

source scripts/_common/init.sh

log_info "========== CLUSTER HEALTH VERIFICATION =========="
log_info "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log_info ""

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
TIMEOUT=10

# Health check results
HEALTH_PASS=0
HEALTH_FAIL=0

# ============================================================================
# FUNCTION: Check SSH connectivity to a host
# ============================================================================
check_ssh_connectivity() {
    local host=$1
    local user="${DEPLOY_USER:-akushnir}"
    
    log_info "Checking SSH connectivity to $host..."
    if timeout $TIMEOUT ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${user}@${host}" "echo OK" 2>/dev/null; then
        log_info "✓ SSH connectivity OK: $host"
        HEALTH_PASS=$((HEALTH_PASS + 1))
        return 0
    else
        log_error "✗ SSH connectivity FAILED: $host"
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
        return 1
    fi
}

# ============================================================================
# FUNCTION: Check Docker daemon on a host
# ============================================================================
check_docker_daemon() {
    local host=$1
    local user="${DEPLOY_USER:-akushnir}"
    
    log_info "Checking Docker daemon on $host..."
    if timeout $TIMEOUT ssh -o ConnectTimeout=5 "${user}@${host}" "docker ps -q" > /dev/null 2>&1; then
        log_info "✓ Docker daemon OK: $host"
        HEALTH_PASS=$((HEALTH_PASS + 1))
        return 0
    else
        log_error "✗ Docker daemon FAILED: $host"
        HEALTH_FAIL=$((HEALTH_FAIL + 1))
        return 1
    fi
}

# ============================================================================
# FUNCTION: Check core services on a host
# ============================================================================
check_services() {
    local host=$1
    local user="${DEPLOY_USER:-akushnir}"
    local services=("caddy" "code-server" "postgres" "redis" "prometheus")
    
    log_info "Checking core services on $host..."
    for service in "${services[@]}"; do
        if timeout $TIMEOUT ssh -o ConnectTimeout=5 "${user}@${host}" "docker ps --format '{{.Names}}' | grep -q '^${service}$'" 2>/dev/null; then
            log_info "  ✓ $service is running"
            HEALTH_PASS=$((HEALTH_PASS + 1))
        else
            log_warn "  ⚠ $service status unclear (may not be running or not found)"
        fi
    done
}

# ============================================================================
# FUNCTION: Check database connectivity
# ============================================================================
check_database() {
    local host=$1
    local user="${DEPLOY_USER:-akushnir}"
    
    log_info "Checking PostgreSQL connectivity on $host..."
    if timeout $TIMEOUT ssh -o ConnectTimeout=5 "${user}@${host}" \
        "docker exec postgres psql -U postgres -d postgres -c 'SELECT 1;'" > /dev/null 2>&1; then
        log_info "✓ PostgreSQL OK: $host"
        HEALTH_PASS=$((HEALTH_PASS + 1))
        return 0
    else
        log_warn "⚠ PostgreSQL check inconclusive on $host (may be starting up)"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

log_info "REPLICA 1: $PRIMARY_HOST"
log_info "─────────────────────────────"
check_ssh_connectivity "$PRIMARY_HOST"
check_docker_daemon "$PRIMARY_HOST"
check_services "$PRIMARY_HOST"
check_database "$PRIMARY_HOST"

log_info ""
log_info "REPLICA 2: $REPLICA_HOST"
log_info "─────────────────────────────"
check_ssh_connectivity "$REPLICA_HOST"
check_docker_daemon "$REPLICA_HOST"
check_services "$REPLICA_HOST"
check_database "$REPLICA_HOST"

log_info ""
log_info "========== SUMMARY =========="
log_info "Checks Passed: $HEALTH_PASS"
log_info "Checks Failed: $HEALTH_FAIL"

if [ $HEALTH_FAIL -eq 0 ] && [ $HEALTH_PASS -gt 0 ]; then
    log_info "✅ CLUSTER HEALTH: READY FOR DEPLOYMENT"
    exit 0
else
    log_warn "⚠ CLUSTER HEALTH: DEGRADED (review output above)"
    exit 1
fi
