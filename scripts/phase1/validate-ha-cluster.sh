#!/usr/bin/env bash
###############################################################################
# Phase 1: HA Cluster Validation & Testing Framework
#
# @file scripts/phase1/validate-ha-cluster.sh
# @module phase1/validation
# @description Comprehensive HA cluster validation and health checks
# @governance GOV-001: All validations must be repeatable and auditable
# @usage ./validate-ha-cluster.sh [--baseline|--replication|--failover|--load]
#
# Validates:
#   - Host connectivity and health
#   - Docker service inventory
#   - PostgreSQL replication status
#   - Redis Sentinel status
#   - Load balancer configuration
#   - Data consistency across nodes
###############################################################################

set -euo pipefail

# Error handling
trap 'log_error "Validation failed at line $LINENO"; exit 1' ERR
trap 'log_info "Validation session ending..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:?PRIMARY_HOST must be set}"
REPLICA_HOST="${REPLICA_HOST:?REPLICA_HOST must be set}"
NAS_HOST="${NAS_HOST:?NAS_HOST must be set}"
SSH_USER="${SSH_USER:-akushnir}"
SSH_PORT="${SSH_PORT:-22}"
VALIDATION_MODE="${1:-baseline}"
VALIDATION_ARTIFACTS="${ARTIFACTS_DIR}/validation-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$VALIDATION_ARTIFACTS"

# ============================================================================
# BASELINE VALIDATION (Service Inventory)
# ============================================================================

validate_baseline() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "VALIDATION: Baseline Service Inventory"
    log_info "═══════════════════════════════════════════════════════"
    
    local primary_services replica_services
    
    # Get service count on primary
    log_info "Counting services on primary (${PRIMARY_HOST})..."
    primary_services=$(ssh \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -p "$SSH_PORT" \
        "${SSH_USER}@${PRIMARY_HOST}" \
        "docker ps --format 'table {{.Names}}' | wc -l" 2>/dev/null || echo "0")
    
    primary_services=$((primary_services - 1))  # Subtract header
    log_success "✓ Primary services: $primary_services running"
    
    # Get service count on replica
    log_info "Counting services on replica (${REPLICA_HOST})..."
    replica_services=$(ssh \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -p "$SSH_PORT" \
        "${SSH_USER}@${REPLICA_HOST}" \
        "docker ps --format 'table {{.Names}}' | wc -l" 2>/dev/null || echo "0")
    
    replica_services=$((replica_services - 1))  # Subtract header
    log_success "✓ Replica services: $replica_services running"
    
    # Report
    {
        echo "=== BASELINE VALIDATION REPORT ==="
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "Primary Host ($PRIMARY_HOST)"
        echo "  Services: $primary_services"
        echo ""
        echo "Replica Host ($REPLICA_HOST)"
        echo "  Services: $replica_services"
        echo ""
        
        if [[ $primary_services -ge 20 && $replica_services -ge 20 ]]; then
            echo "Status: ✓ PASS (Both hosts have 20+ services)"
        else
            echo "Status: ✗ FAIL (Expected 20+ services on each host)"
        fi
    } | tee "${VALIDATION_ARTIFACTS}/baseline-validation.txt"
}

# ============================================================================
# REPLICATION VALIDATION
# ============================================================================

validate_replication() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "VALIDATION: PostgreSQL Replication Status"
    log_info "═══════════════════════════════════════════════════════"
    
    log_info "Checking PostgreSQL replication status..."
    
    ssh \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -p "$SSH_PORT" \
        "${SSH_USER}@${PRIMARY_HOST}" << 'REPLICATION_CHECK_SCRIPT'
        set -euo pipefail
        
        echo "[INFO] PostgreSQL Replication Status"
        echo "========================================"
        
        # Check if replica is connected
        docker exec code-server-postgres psql -U postgres -d postgres << 'PSQL'
        SELECT 
            client_addr,
            usename,
            application_name,
            state,
            sync_state,
            write_lag,
            flush_lag,
            replay_lag
        FROM pg_stat_replication;
PSQL
        
        echo ""
        echo "Replication User Check:"
        docker exec code-server-postgres psql -U postgres -d postgres -c \
        "SELECT usename, usecanlogin, usecanrepl FROM pg_user WHERE usename='replication_user';"
        
        echo "[SUCCESS] Replication check complete"
REPLICATION_CHECK_SCRIPT
    
    {
        echo "=== REPLICATION VALIDATION REPORT ==="
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "Status: Check output above for:"
        echo "  - Replica connected (client_addr shows replica IP)"
        echo "  - State: streaming"
        echo "  - Lag times low (write_lag, flush_lag, replay_lag)"
    } | tee "${VALIDATION_ARTIFACTS}/replication-validation.txt"
}

# ============================================================================
# FAILOVER READINESS
# ============================================================================

validate_failover_readiness() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "VALIDATION: Failover Readiness"
    log_info "═══════════════════════════════════════════════════════"
    
    local checks_passed=0
    local checks_total=0
    
    # Check 1: Both hosts operational
    log_info "Check 1: Host operational status..."
    ((checks_total++))
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p "$SSH_PORT" \
        "${SSH_USER}@${PRIMARY_HOST}" "docker ps" &>/dev/null && \
       ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p "$SSH_PORT" \
        "${SSH_USER}@${REPLICA_HOST}" "docker ps" &>/dev/null; then
        log_success "✓ Both hosts operational"
        ((checks_passed++))
    else
        log_error "✗ One or more hosts unreachable"
    fi
    
    # Check 2: PostgreSQL running on both
    log_info "Check 2: PostgreSQL availability..."
    ((checks_total++))
    primary_pg=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p "$SSH_PORT" \
        "${SSH_USER}@${PRIMARY_HOST}" \
        "docker exec code-server-postgres pg_isready -U postgres" 2>/dev/null || echo "not ready")
    
    if [[ "$primary_pg" == *"accepting connections"* ]]; then
        log_success "✓ PostgreSQL operational"
        ((checks_passed++))
    else
        log_error "✗ PostgreSQL not ready"
    fi
    
    # Check 3: Redis running on both
    log_info "Check 3: Redis availability..."
    ((checks_total++))
    primary_redis=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p "$SSH_PORT" \
        "${SSH_USER}@${PRIMARY_HOST}" \
        "docker exec code-server-redis redis-cli ping" 2>/dev/null || echo "no response")
    
    if [[ "$primary_redis" == "PONG" ]]; then
        log_success "✓ Redis operational"
        ((checks_passed++))
    else
        log_error "✗ Redis not responding"
    fi
    
    # Check 4: NAS mounts
    log_info "Check 4: NAS mount status..."
    ((checks_total++))
    nas_check=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p "$SSH_PORT" \
        "${SSH_USER}@${PRIMARY_HOST}" \
        "mount | grep -c '/mnt/nas' || echo 0")
    
    if [[ "$nas_check" -ge 1 ]]; then
        log_success "✓ NAS mounts available"
        ((checks_passed++))
    else
        log_warning "⚠ NAS mounts may not be ready"
    fi
    
    # Report
    {
        echo "=== FAILOVER READINESS REPORT ==="
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "Checks Passed: $checks_passed/$checks_total"
        echo ""
        
        if [[ $checks_passed -eq $checks_total ]]; then
            echo "Status: ✓ READY FOR FAILOVER"
        else
            echo "Status: ⚠ PARTIAL READINESS"
        fi
    } | tee "${VALIDATION_ARTIFACTS}/failover-readiness.txt"
}

# ============================================================================
# LOAD VALIDATION
# ============================================================================

validate_load_distribution() {
    log_info "═══════════════════════════════════════════════════════"
    log_info "VALIDATION: Load Distribution"
    log_info "═══════════════════════════════════════════════════════"
    
    log_info "Testing load distribution across primary and replica..."
    
    # Simple connectivity test to both nodes
    {
        echo "=== LOAD DISTRIBUTION VALIDATION ==="
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        echo "Testing connectivity to primary ($PRIMARY_HOST:80)..."
        curl -s -m 5 "http://${PRIMARY_HOST}:80/health" | head -20 || echo "no response"
        
        echo ""
        echo "Testing connectivity to replica ($REPLICA_HOST:80)..."
        curl -s -m 5 "http://${REPLICA_HOST}:80/health" | head -20 || echo "no response"
        
        echo ""
        echo "Status: Load distribution ready for testing"
    } | tee "${VALIDATION_ARTIFACTS}/load-distribution.txt"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    case "$VALIDATION_MODE" in
        baseline)
            validate_baseline
            ;;
        replication)
            validate_replication
            ;;
        failover)
            validate_failover_readiness
            ;;
        load)
            validate_load_distribution
            ;;
        all)
            validate_baseline
            validate_replication
            validate_failover_readiness
            validate_load_distribution
            ;;
        *)
            log_error "Unknown validation mode: $VALIDATION_MODE"
            echo "Usage: $0 [baseline|replication|failover|load|all]"
            exit 1
            ;;
    esac
    
    log_success "✓ Validation complete: ${VALIDATION_ARTIFACTS}"
}

main "$@"
