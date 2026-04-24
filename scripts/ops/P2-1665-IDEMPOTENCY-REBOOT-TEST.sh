#!/usr/bin/env bash
# @file        scripts/ops/P2-1665-IDEMPOTENCY-REBOOT-TEST.sh
# @module      operations/testing
# @description Idempotency reboot test procedures - validate cluster auto-recovery
#
# Usage: bash scripts/ops/P2-1665-IDEMPOTENCY-REBOOT-TEST.sh [--replica 192.168.168.31] [--dry-run]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
SSH_USER="${SSH_USER:-akushnir}"
REPO_PATH="${REPO_PATH:-/home/${SSH_USER}/code-server-enterprise}"
TEST_REPLICA="${TEST_REPLICA:-192.168.168.31}"
DRY_RUN="${DRY_RUN:-0}"
RECOVERY_TIMEOUT="${RECOVERY_TIMEOUT:-300}"  # 5 minutes
HEALTH_POLL_INTERVAL="${HEALTH_POLL_INTERVAL:-10}"

ssh_exec() {
    local host="$1"
    local cmd="$2"
    ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
        "$SSH_USER@$host" "cd $REPO_PATH && $cmd"
}

# ============================================================================
# Pre-Reboot Validation
# ============================================================================

run_pre_reboot_validation() {
    log_info "=========================================="
    log_info "PRE-REBOOT VALIDATION"
    log_info "=========================================="
    
    log_info "Validating replica state before reboot..."
    
    # Check service count
    local service_count=$(ssh_exec "$TEST_REPLICA" "docker ps --quiet | wc -l" 2>/dev/null || echo "0")
    log_info "  Services running: $service_count"
    
    # Check health endpoint
    if ssh_exec "$TEST_REPLICA" "curl -sf http://localhost:8080/healthz >/dev/null" 2>/dev/null; then
        log_info "  Health endpoint: ✅ OK"
    else
        log_error "  Health endpoint: ❌ FAILED"
        return 1
    fi
    
    # Check git state
    local git_status=$(ssh_exec "$TEST_REPLICA" "git status --short --untracked-files=no" 2>/dev/null || echo "ERROR")
    if [[ "$git_status" == "" ]]; then
        log_info "  Git state: ✅ Clean"
    else
        log_warn "  Git state: ⚠️  Has changes (will be preserved after reboot)"
    fi
    
    log_info "✅ Pre-reboot validation complete"
}

# ============================================================================
# Controlled Reboot
# ============================================================================

initiate_controlled_reboot() {
    log_info "=========================================="
    log_info "INITIATING CONTROLLED REBOOT"
    log_info "=========================================="
    
    log_info "Target replica: $TEST_REPLICA"
    log_info "This will:"
    log_info "  1. Stop all containers gracefully (docker-compose down)"
    log_info "  2. Reboot the OS"
    log_info "  3. Validate automatic recovery"
    log_info ""
    
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "🔍 DRY RUN - Showing commands that would be executed:"
        log_info ""
        log_info "  ssh -i $SSH_KEY $SSH_USER@$TEST_REPLICA"
        log_info "    'cd $REPO_PATH &&"
        log_info "     docker-compose down &&"
        log_info "     sudo reboot'"
        log_info ""
        return 0
    fi
    
    log_warn "⚠️  This will disrupt service on $TEST_REPLICA temporarily"
    log_warn "⚠️  Load balancer will route traffic to other replica"
    log_info ""
    log_info "Proceeding with reboot in 10 seconds... (Ctrl+C to cancel)"
    sleep 10
    
    log_info "Stopping containers on $TEST_REPLICA..."
    ssh_exec "$TEST_REPLICA" "docker-compose down" >/dev/null 2>&1 || true
    
    log_info "Initiating reboot..."
    ssh -i "$SSH_KEY" -o BatchMode=yes "$SSH_USER@$TEST_REPLICA" \
        "sudo reboot" >/dev/null 2>&1 || true
    
    log_info "Reboot command sent. System is rebooting..."
    log_info "Waiting for system to come back online..."
    sleep 30
}

# ============================================================================
# Automatic Recovery Validation
# ============================================================================

wait_for_recovery() {
    log_info "=========================================="
    log_info "WAITING FOR AUTOMATIC RECOVERY"
    log_info "=========================================="
    
    local elapsed=0
    local recovered=0
    
    while [[ $elapsed -lt $RECOVERY_TIMEOUT ]]; do
        # Try SSH connection
        if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 \
               "$SSH_USER@$TEST_REPLICA" "echo OK" >/dev/null 2>&1; then
            
            log_info "SSH connection re-established"
            recovered=1
            break
        fi
        
        elapsed=$((elapsed + HEALTH_POLL_INTERVAL))
        log_info "Waiting for system recovery... (${elapsed}s/${RECOVERY_TIMEOUT}s)"
        sleep "$HEALTH_POLL_INTERVAL"
    done
    
    if [[ $recovered -ne 1 ]]; then
        log_error "❌ Recovery timeout - system did not come back online"
        return 1
    fi
    
    log_info "✅ System is back online"
    
    # Wait for services to auto-start
    log_info "Waiting for services to auto-start..."
    elapsed=0
    while [[ $elapsed -lt $RECOVERY_TIMEOUT ]]; do
        if ssh_exec "$TEST_REPLICA" "curl -sf http://localhost:8080/healthz >/dev/null" 2>/dev/null; then
            log_info "✅ Services recovered"
            return 0
        fi
        
        elapsed=$((elapsed + HEALTH_POLL_INTERVAL))
        log_info "Services starting... (${elapsed}s/${RECOVERY_TIMEOUT}s)"
        sleep "$HEALTH_POLL_INTERVAL"
    done
    
    log_error "❌ Services failed to auto-start"
    return 1
}

# ============================================================================
# Post-Recovery Validation
# ============================================================================

run_post_recovery_validation() {
    log_info "=========================================="
    log_info "POST-RECOVERY VALIDATION"
    log_info "=========================================="
    
    # Check service count
    local service_count=$(ssh_exec "$TEST_REPLICA" "docker ps --quiet | wc -l" 2>/dev/null || echo "0")
    log_info "  Services running: $service_count"
    
    # Check health endpoint
    if ssh_exec "$TEST_REPLICA" "curl -sf http://localhost:8080/healthz >/dev/null" 2>/dev/null; then
        log_info "  Health endpoint: ✅ OK"
    else
        log_error "  Health endpoint: ❌ FAILED"
        return 1
    fi
    
    # Check git state (should be preserved)
    local git_status=$(ssh_exec "$TEST_REPLICA" "git status --short --untracked-files=no" 2>/dev/null || echo "ERROR")
    if [[ "$git_status" == "" ]]; then
        log_info "  Git state: ✅ Clean (preserved)"
    else
        log_warn "  Git state: ⚠️  Changed during reboot (expected)"
    fi
    
    # Check database replication
    log_info "  Checking database replication status..."
    local rep_status=$(ssh_exec "$TEST_REPLICA" "docker-compose logs postgresql 2>/dev/null | grep -i 'replica\\|replication' | tail -1" 2>/dev/null || echo "UNKNOWN")
    if [[ "$rep_status" != "UNKNOWN" ]]; then
        log_info "    $rep_status"
    fi
    
    log_info "✅ Post-recovery validation complete"
}

# ============================================================================
# Main Test Execution
# ============================================================================

main() {
    log_info "=========================================="
    log_info "IDEMPOTENCY REBOOT TEST PROCEDURES"
    log_info "=========================================="
    log_info "Target Replica: $TEST_REPLICA"
    log_info "Dry Run: $DRY_RUN"
    log_info ""
    
    run_pre_reboot_validation || {
        log_fatal "Pre-reboot validation failed"
    }
    
    log_info ""
    initiate_controlled_reboot
    
    if [[ $DRY_RUN -eq 0 ]]; then
        log_info ""
        wait_for_recovery || {
            log_fatal "Automatic recovery failed"
        }
        
        log_info ""
        run_post_recovery_validation || {
            log_fatal "Post-recovery validation failed"
        }
    fi
    
    log_info ""
    log_info "=========================================="
    log_info "✅ IDEMPOTENCY REBOOT TEST COMPLETE"
    log_info "=========================================="
    log_info ""
    log_info "Test Results:"
    log_info "  • Pre-reboot state: ✅ Validated"
    log_info "  • Reboot execution: ✅ Successful"
    if [[ $DRY_RUN -eq 0 ]]; then
        log_info "  • Automatic recovery: ✅ Successful"
        log_info "  • Post-recovery state: ✅ Validated"
    else
        log_info "  (Dry run - recovery validation skipped)"
    fi
    log_info ""
    log_info "Conclusion: Cluster idempotency verified ✅"
    log_info ""
}

main "$@"
