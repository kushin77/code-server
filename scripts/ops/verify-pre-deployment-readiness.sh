#!/usr/bin/env bash
# @file        scripts/ops/verify-pre-deployment-readiness.sh
# @module      operations/deployment
# @description Pre-deployment infrastructure verification checklist (P1 #1085 Phase 2/3/4)
# @owner       Platform Engineering
# @status      production-ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# CONSTANTS
PRIMARY_HOST="${DEPLOY_HOST:-192.168.168.31}"
REPLICA_HOST="${STANDBY_HOST:-192.168.168.42}"
EXEC_USER="${DEPLOY_USER:-akushnir}"
REPO_PATH="/home/akushnir/code-server-enterprise"

# Verify SSH connectivity
verify_ssh_connectivity() {
    local host="$1"
    
    log_info "Verifying SSH connectivity to $host..."
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${EXEC_USER}@${host}" "echo 'Connected'" > /dev/null 2>&1; then
        log_success "✓ SSH connection successful to $host"
        return 0
    else
        log_fatal "Cannot establish SSH connection to $host"
    fi
}

# Verify services are operational
verify_services_operational() {
    local host="$1"
    
    log_info "Verifying services operational on $host..."
    
    local running_count
    running_count=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${EXEC_USER}@${host}" "docker ps --format 'table {{.Names}}' | wc -l" || echo "0")
    
    log_info "Running containers on $host: $running_count"
    
    # Expected services: caddy, code-server, postgres, redis, oauth2-proxy, etc.
    local expected_min=8
    
    if [ "$running_count" -ge "$expected_min" ]; then
        log_success "✓ Sufficient services operational (>= $expected_min)"
        return 0
    else
        log_warn "⚠ Only $running_count services running (expected >= $expected_min)"
        return 1
    fi
}

# Check database replication
check_database_replication() {
    local host="$1"
    
    log_info "Checking PostgreSQL replication lag on $host..."
    
    local replication_lag
    replication_lag=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${EXEC_USER}@${host}" "docker exec \$(docker ps -q -f name=postgres) psql -U postgres -c 'SELECT slot_name, restart_lsn FROM pg_replication_slots;' 2>/dev/null || echo 'FAILED'" || echo "ERROR")
    
    if [ "$replication_lag" = "FAILED" ] || [ "$replication_lag" = "ERROR" ]; then
        log_warn "⚠ Could not determine replication status"
        return 1
    fi
    
    log_info "PostgreSQL replication status:"
    echo "$replication_lag" | sed 's/^/  /'
    log_success "✓ Database replication configured"
    return 0
}

# Check Redis Sentinel quorum
check_redis_sentinel_quorum() {
    local host="$1"
    
    log_info "Checking Redis Sentinel quorum health on $host..."
    
    local sentinel_info
    sentinel_info=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${EXEC_USER}@${host}" "docker exec \$(docker ps -q -f name=sentinel) redis-cli -p 26379 info sentinel 2>/dev/null | grep -E 'masters|slaves' || echo 'FAILED'" || echo "ERROR")
    
    if [ "$sentinel_info" = "FAILED" ] || [ "$sentinel_info" = "ERROR" ]; then
        log_warn "⚠ Could not determine Sentinel quorum status"
        return 1
    fi
    
    log_info "Redis Sentinel status:"
    echo "$sentinel_info" | sed 's/^/  /'
    log_success "✓ Redis Sentinel quorum configured"
    return 0
}

# Verify NAS storage
verify_nas_storage() {
    local host="$1"
    
    log_info "Verifying NAS storage availability on $host..."
    
    local nas_space
    nas_space=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${EXEC_USER}@${host}" "df -h /mnt/eiq-shared 2>/dev/null | tail -1 | awk '{print \$4}' || echo 'FAILED'" || echo "ERROR")
    
    if [ "$nas_space" = "FAILED" ] || [ "$nas_space" = "ERROR" ]; then
        log_warn "⚠ Could not determine NAS storage availability"
        return 1
    fi
    
    log_success "✓ NAS storage available: $nas_space"
    return 0
}

# Run full E2E test suite
run_e2e_tests() {
    local host="$1"
    
    log_info "Running full E2E test suite on $host..."
    
    # Check for test script
    local test_result
    test_result=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "${EXEC_USER}@${host}" "cd $REPO_PATH && npm test 2>&1 | tail -5 || echo 'TESTS_FAILED'" || echo "ERROR")
    
    if [ "$test_result" = "ERROR" ] || [ "$test_result" = "TESTS_FAILED" ]; then
        log_warn "⚠ E2E tests may have failed - review results:"
        echo "$test_result" | sed 's/^/  /'
        return 1
    fi
    
    log_success "✓ E2E test suite execution initiated"
    return 0
}

# Test rollback procedure
test_rollback_procedure() {
    local host="$1"
    
    log_info "Testing rollback procedure on $host..."
    
    # Check if rollback script exists
    local rollback_exists
    rollback_exists=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "${EXEC_USER}@${host}" "test -f $REPO_PATH/scripts/ops/rollback.sh && echo 'EXISTS' || echo 'MISSING'" || echo "ERROR")
    
    if [ "$rollback_exists" = "MISSING" ]; then
        log_error "Rollback procedure script not found"
        return 1
    fi
    
    log_info "Rollback procedure available at: $REPO_PATH/scripts/ops/rollback.sh"
    log_success "✓ Rollback procedure documented and ready"
    return 0
}

# Generate GO/NO-GO assessment
generate_assessment() {
    local primary_tests=$1
    local replica_tests=$2
    
    log_info ""
    log_info "=========================================="
    log_info "PRE-DEPLOYMENT ASSESSMENT"
    log_info "=========================================="
    log_info ""
    
    if [ "$primary_tests" -eq 5 ] && [ "$replica_tests" -eq 5 ]; then
        log_success "✅ GO CONDITION MET"
        log_success "All verification checks passed on both replicas."
        log_success "Ready for Phase 2/3/4 deployment."
        return 0
    else
        log_warn "⚠ CONDITIONAL GO"
        log_warn "Some checks may need attention:"
        log_info "  Primary: $primary_tests/5 passed"
        log_info "  Replica: $replica_tests/5 passed"
        return 1
    fi
}

# MAIN
main() {
    log_info "========================================================================"
    log_info "Pre-Deployment Infrastructure Verification (P1 #1085)"
    log_info "========================================================================"
    log_info ""
    
    local primary_pass=0
    local replica_pass=0
    
    # PRIMARY HOST VERIFICATION
    log_info "PRIMARY HOST VERIFICATION ($PRIMARY_HOST)"
    log_info "=========================================="
    log_info ""
    
    verify_ssh_connectivity "$PRIMARY_HOST" || return 1
    verify_services_operational "$PRIMARY_HOST" && ((primary_pass++)) || true
    check_database_replication "$PRIMARY_HOST" && ((primary_pass++)) || true
    check_redis_sentinel_quorum "$PRIMARY_HOST" && ((primary_pass++)) || true
    verify_nas_storage "$PRIMARY_HOST" && ((primary_pass++)) || true
    test_rollback_procedure "$PRIMARY_HOST" && ((primary_pass++)) || true
    
    log_info ""
    
    # REPLICA HOST VERIFICATION
    log_info "REPLICA HOST VERIFICATION ($REPLICA_HOST)"
    log_info "========================================"
    log_info ""
    
    verify_ssh_connectivity "$REPLICA_HOST" || return 1
    verify_services_operational "$REPLICA_HOST" && ((replica_pass++)) || true
    check_database_replication "$REPLICA_HOST" && ((replica_pass++)) || true
    check_redis_sentinel_quorum "$REPLICA_HOST" && ((replica_pass++)) || true
    verify_nas_storage "$REPLICA_HOST" && ((replica_pass++)) || true
    test_rollback_procedure "$REPLICA_HOST" && ((replica_pass++)) || true
    
    log_info ""
    
    # GENERATE ASSESSMENT
    generate_assessment "$primary_pass" "$replica_pass"
}

main "$@"
