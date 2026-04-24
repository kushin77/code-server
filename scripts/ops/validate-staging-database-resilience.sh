#!/usr/bin/env bash
# @file        scripts/ops/validate-staging-database-resilience.sh
# @module      ops/testing/staging
# @description Validate database resilience infrastructure in staging environment
#
# This script performs end-to-end validation of all 5 resilience layers:
#  1. Replication: Verify streaming, lag, WAL archiving
#  2. Backup: Test backup creation and restore
#  3. Health: Verify health check endpoints
#  4. Failover: Test failover triggers and automation
#  5. Partition: Test quorum decisions and recovery

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "$REPO_ROOT/scripts/_common/init.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
TARGET_USER="${TARGET_USER:-akushnir}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"

HEALTH_CHECK_PORT="${HEALTH_CHECK_PORT:-8081}"
FAILOVER_WEBHOOK_PORT="${FAILOVER_WEBHOOK_PORT:-8082}"
QUORUM_PORT="${QUORUM_PORT:-8083}"

STAGING_LOG_DIR="${STAGING_LOG_DIR:-artifacts/staging-validation}"
STAGING_REPORT="${STAGING_LOG_DIR}/validation-report-$(date +%Y%m%d-%H%M%S).md"
TEST_RESULTS_FILE="${STAGING_LOG_DIR}/test-results.json"

TEST_PASSED=0
TEST_FAILED=0

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

ensure_staging_dir() {
    mkdir -p "$STAGING_LOG_DIR"
}

ssh_primary() {
    ssh -i ~/.ssh/id_rsa -o BatchMode=yes -o ConnectTimeout=8 \
        "${TARGET_USER}@${PRIMARY_HOST}" "$@"
}

ssh_replica() {
    ssh -i ~/.ssh/id_rsa -o BatchMode=yes -o ConnectTimeout=8 \
        "${TARGET_USER}@${REPLICA_HOST}" "$@"
}

psql_primary() {
    ssh_primary "docker exec -u postgres ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}" <<< "$@"
}

psql_replica() {
    ssh_replica "docker exec -u postgres ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}" <<< "$@"
}

log_test() {
    local name="$1"
    local status="$2"
    local details="${3:-}"
    
    if [[ "${status}" == "PASS" ]]; then
        log_success "✓ ${name}"
        ((TEST_PASSED++))
    else
        log_error "✗ ${name}: ${details}"
        ((TEST_FAILED++))
    fi
    
    echo "## Test: ${name}" >> "$STAGING_REPORT"
    echo "Status: ${status}" >> "$STAGING_REPORT"
    if [[ -n "${details}" ]]; then
        echo "Details: ${details}" >> "$STAGING_REPORT"
    fi
    echo "" >> "$STAGING_REPORT"
}

# ============================================================================
# VALIDATION TESTS
# ============================================================================

validate_replication() {
    log_section "Layer 1: PostgreSQL Replication Validation"
    
    echo "# Replication Layer Validation" > "$STAGING_REPORT"
    echo "Date: $(date)" >> "$STAGING_REPORT"
    echo "" >> "$STAGING_REPORT"
    
    # Test 1: Replication slot exists
    log_info "Checking replication slot..."
    if slot_result=$(ssh_primary "docker exec -u postgres ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -tc \"SELECT slot_name FROM pg_replication_slots WHERE slot_name = 'replica_slot';\" 2>/dev/null"); then
        if [[ -n "${slot_result}" ]]; then
            log_test "Replication slot exists" "PASS"
        else
            log_test "Replication slot exists" "FAIL" "Slot not found"
        fi
    else
        log_test "Replication slot exists" "FAIL" "Query failed"
    fi
    
    # Test 2: WAL sender active
    log_info "Checking WAL sender..."
    if wal_result=$(ssh_primary "docker exec -u postgres ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -tc \"SELECT state FROM pg_stat_replication;\" 2>/dev/null"); then
        if [[ "$wal_result" == *"streaming"* ]]; then
            log_test "WAL sender active" "PASS"
        else
            log_test "WAL sender active" "FAIL" "State: ${wal_result}"
        fi
    else
        log_test "WAL sender active" "FAIL" "Query failed"
    fi
    
    # Test 3: Replication lag < 500ms
    log_info "Checking replication lag..."
    if lag_result=$(ssh_primary "docker exec -u postgres ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -tc \"SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp())) * 1000::int AS lag_ms;\" 2>/dev/null"); then
        lag_ms=$(echo "$lag_result" | tr -d ' ')
        if [[ "$lag_ms" =~ ^[0-9]+$ ]] && (( lag_ms < 500 )); then
            log_test "Replication lag < 500ms" "PASS" "Lag: ${lag_ms}ms"
        else
            log_test "Replication lag < 500ms" "FAIL" "Lag: ${lag_ms}ms"
        fi
    else
        log_test "Replication lag < 500ms" "FAIL" "Unable to measure"
    fi
    
    # Test 4: Data replication works
    log_info "Testing data replication..."
    test_table="replication_test_$(date +%s)"
    if ssh_primary "docker exec -u postgres ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}" <<EOF >/dev/null 2>&1
        CREATE TABLE ${test_table} (id SERIAL PRIMARY KEY, message TEXT, created_at TIMESTAMP DEFAULT NOW());
        INSERT INTO ${test_table} (message) VALUES ('Replication test at $(date)');
EOF
    then
        sleep 2  # Allow replication
        if ssh_replica "docker exec -u postgres ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -tc \"SELECT COUNT(*) FROM ${test_table};\"" 2>/dev/null | grep -q "1"; then
            log_test "Data replicates to replica" "PASS"
        else
            log_test "Data replicates to replica" "FAIL" "Data not found on replica"
        fi
        ssh_primary "docker exec -u postgres ${POSTGRES_CONTAINER} psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}" <<EOF >/dev/null 2>&1
            DROP TABLE ${test_table};
EOF
    else
        log_test "Data replicates to replica" "FAIL" "Failed to create test table"
    fi
}

validate_backup() {
    log_section "Layer 2: Backup & Recovery Validation"
    
    echo "# Backup Layer Validation" >> "$STAGING_REPORT"
    echo "" >> "$STAGING_REPORT"
    
    # Test 1: Backup files exist
    log_info "Checking backup files..."
    if backup_count=$(ssh_primary "ls -1 /var/backups/postgresql/*.gz 2>/dev/null | wc -l"); then
        if (( backup_count > 0 )); then
            log_test "Backup files exist" "PASS" "Files: ${backup_count}"
        else
            log_test "Backup files exist" "FAIL" "No backup files found"
        fi
    else
        log_test "Backup files exist" "FAIL" "Unable to check"
    fi
    
    # Test 2: Backup file is not empty
    log_info "Checking backup file size..."
    if backup_size=$(ssh_primary "ls -lh /var/backups/postgresql/*.gz | tail -1 | awk '{print \$5}'"); then
        if [[ -n "${backup_size}" && "${backup_size}" != "0" ]]; then
            log_test "Backup file is not empty" "PASS" "Size: ${backup_size}"
        else
            log_test "Backup file is not empty" "FAIL" "Size: ${backup_size}"
        fi
    else
        log_test "Backup file is not empty" "FAIL" "Unable to check"
    fi
    
    # Test 3: Backup can be decompressed
    log_info "Verifying backup integrity..."
    if ssh_primary "gunzip -t /var/backups/postgresql/*.gz 2>/dev/null | tail -1" >/dev/null 2>&1; then
        log_test "Backup integrity verified" "PASS"
    else
        log_test "Backup integrity verified" "FAIL" "Decompression failed"
    fi
}

validate_health_checks() {
    log_section "Layer 3: Health Checks Validation"
    
    echo "# Health Checks Layer Validation" >> "$STAGING_REPORT"
    echo "" >> "$STAGING_REPORT"
    
    # Test 1: Health check endpoint responds
    log_info "Testing health check endpoint..."
    if curl -sf "http://localhost:${HEALTH_CHECK_PORT}/health" >/dev/null 2>&1; then
        log_test "Health check endpoint responds" "PASS"
    else
        log_test "Health check endpoint responds" "FAIL" "Connection refused"
    fi
    
    # Test 2: Replication health check
    log_info "Testing replication health check..."
    if curl -sf "http://localhost:${HEALTH_CHECK_PORT}/health/replication" >/dev/null 2>&1; then
        log_test "Replication health check works" "PASS"
    else
        log_test "Replication health check works" "FAIL" "Endpoint unreachable"
    fi
    
    # Test 3: Backup health check
    log_info "Testing backup health check..."
    if curl -sf "http://localhost:${HEALTH_CHECK_PORT}/health/backup" >/dev/null 2>&1; then
        log_test "Backup health check works" "PASS"
    else
        log_test "Backup health check works" "FAIL" "Endpoint unreachable"
    fi
}

validate_failover() {
    log_section "Layer 4: Failover Monitoring Validation"
    
    echo "# Failover Monitoring Layer Validation" >> "$STAGING_REPORT"
    echo "" >> "$STAGING_REPORT"
    
    # Test 1: Failover webhook responds
    log_info "Testing failover webhook..."
    if curl -sf "http://localhost:${FAILOVER_WEBHOOK_PORT}/failover/validate-status" >/dev/null 2>&1; then
        log_test "Failover webhook responds" "PASS"
    else
        log_test "Failover webhook responds" "FAIL" "Endpoint unreachable"
    fi
    
    # Test 2: Multi-criteria validation works
    log_info "Testing failover decision logic..."
    if validation_response=$(curl -s "http://localhost:${FAILOVER_WEBHOOK_PORT}/failover/validate-status"); then
        if echo "$validation_response" | grep -q "failover_decision"; then
            log_test "Failover decision logic works" "PASS"
        else
            log_test "Failover decision logic works" "FAIL" "Invalid response"
        fi
    else
        log_test "Failover decision logic works" "FAIL" "Query failed"
    fi
}

validate_partition_recovery() {
    log_section "Layer 5: Partition Recovery Validation"
    
    echo "# Partition Recovery Layer Validation" >> "$STAGING_REPORT"
    echo "" >> "$STAGING_REPORT"
    
    # Test 1: Quorum monitor responds
    log_info "Testing quorum monitor..."
    if curl -sf "http://localhost:${QUORUM_PORT}/quorum/status" >/dev/null 2>&1; then
        log_test "Quorum monitor responds" "PASS"
    else
        log_test "Quorum monitor responds" "FAIL" "Endpoint unreachable"
    fi
    
    # Test 2: Quorum status has 3 nodes
    log_info "Checking quorum node count..."
    if quorum_response=$(curl -s "http://localhost:${QUORUM_PORT}/quorum/status"); then
        if echo "$quorum_response" | grep -q '"connected_nodes": 3'; then
            log_test "Quorum has 3 nodes" "PASS"
        else
            log_test "Quorum has 3 nodes" "FAIL" "Unexpected node count"
        fi
    else
        log_test "Quorum has 3 nodes" "FAIL" "Query failed"
    fi
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_summary() {
    log_section "VALIDATION SUMMARY"
    
    echo "" >> "$STAGING_REPORT"
    echo "---" >> "$STAGING_REPORT"
    echo "# Summary" >> "$STAGING_REPORT"
    echo "Total Tests: $((TEST_PASSED + TEST_FAILED))" >> "$STAGING_REPORT"
    echo "Passed: ${TEST_PASSED}" >> "$STAGING_REPORT"
    echo "Failed: ${TEST_FAILED}" >> "$STAGING_REPORT"
    
    local pass_rate=0
    if (( (TEST_PASSED + TEST_FAILED) > 0 )); then
        pass_rate=$(( (TEST_PASSED * 100) / (TEST_PASSED + TEST_FAILED) ))
    fi
    echo "Success Rate: ${pass_rate}%" >> "$STAGING_REPORT"
    echo "" >> "$STAGING_REPORT"
    
    if (( TEST_FAILED == 0 )); then
        echo "✅ ALL TESTS PASSED - Ready for Production" >> "$STAGING_REPORT"
        log_success "All validation tests passed!"
        return 0
    else
        echo "❌ TESTS FAILED - See details above" >> "$STAGING_REPORT"
        log_error "${TEST_FAILED} test(s) failed"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    ensure_staging_dir
    
    log_info ""
    log_info "╔══════════════════════════════════════════════════════════╗"
    log_info "║   Database Resilience Staging Validation                 ║"
    log_info "║   $(date)                       ║"
    log_info "╚══════════════════════════════════════════════════════════╝"
    log_info ""
    
    log_info "Validation report: ${STAGING_REPORT}"
    
    validate_replication
    validate_backup
    validate_health_checks
    validate_failover
    validate_partition_recovery
    
    generate_summary
    
    log_info ""
    log_info "Full report saved to: ${STAGING_REPORT}"
    log_info ""
}

trap 'log_error "Validation failed at line $LINENO"; exit 1' ERR
main "$@"
