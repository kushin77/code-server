#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/validate-cluster-parity-all-replicas.sh
# @module      ops/verify
# @description Validate parity across all active cluster replicas (code, config, state)
# @owner       infrastructure
# @status      stable
#
# USAGE
#   scripts/ops/validate-cluster-parity-all-replicas.sh [--dry-run] [--verbose]
#
# ENVIRONMENT VARIABLES
#   REPLICA_1_IP      - First replica IP (from GSM)
#   REPLICA_2_IP      - Second replica IP (from GSM)
#   SSH_USER          - SSH user for replicas (from DEPLOY_USER)
#   SSH_KEY           - Path to SSH key (~/.ssh/id_rsa)
#
# EXIT CODES
#   0 - All replicas in parity (success)
#   1 - Parity mismatch detected (failure)
#   2 - Configuration error
#
# NOTES
#   - IaC, immutable, idempotent pattern: safe to run multiple times
#   - Validates code, config, and state consistency
#   - No modifications to cluster state
#   - Output suitable for monitoring systems
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

# Configuration - use GSM-sourced variables, not hardcoded defaults
H_D="ide.${APEX_DOMAIN}"
REPLICA_1_IP="${REPLICA_1_IP}"
REPLICA_2_IP="${REPLICA_2_IP}"
SSH_USER="${SSH_USER:-${DEPLOY_USER}}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"
DRY_RUN="${DRY_RUN:-0}"
VERBOSE="${VERBOSE:-0}"

# Validate required IPs
require_var "REPLICA_1_IP" "cluster replica 1 IP"
require_var "REPLICA_2_IP" "cluster replica 2 IP"
require_var "DEPLOY_USER" "SSH user for deployment"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

PARITY_FAILED=0

################################################################################
# HELPER FUNCTIONS
################################################################################

ssh_exec() {
  local host=$1
  local cmd=$2
  local desc="${3:-}"
  
  if [[ -z "$cmd" ]]; then
    log_error "No command provided for ssh_exec"
    return 1
  fi
  
  if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
      "${SSH_USER}@${host}" "$cmd" 2>/dev/null; then
    [[ $VERBOSE -eq 1 ]] && log_info "  ✓ [${host}] $desc"
    return 0
  else
    log_error "  ✗ [${host}] Failed: $desc"
    return 1
  fi
}

check_replica_reachable() {
  local host=$1
  log_info "Checking reachability: ${host}"
  
  if ssh_exec "$host" "echo 1" "Connectivity check"; then
    log_info "✓ ${host} is reachable"
    return 0
  else
    log_error "✗ ${host} is UNREACHABLE"
    return 1
  fi
}

validate_code_version() {
  local replica1=$1
  local replica2=$2
  
  log_section "Code Version Consistency"
  
  local commit1 commit2
  commit1=$(ssh_exec "$replica1" "cd /home/akushnir/code-server-enterprise && git rev-parse HEAD" "Get commit" 2>/dev/null || echo "ERROR")
  commit2=$(ssh_exec "$replica2" "cd /home/akushnir/code-server-enterprise && git rev-parse HEAD" "Get commit" 2>/dev/null || echo "ERROR")
  
  if [[ "$commit1" == "$commit2" && "$commit1" != "ERROR" ]]; then
    log_info "✓ Code version matches: $commit1"
    return 0
  else
    log_error "✗ Code version MISMATCH:"
    log_error "  Replica 1 ($replica1): $commit1"
    log_error "  Replica 2 ($replica2): $commit2"
    PARITY_FAILED=1
    return 1
  fi
}

validate_config_consistency() {
  local replica1=$1
  local replica2=$2
  
  log_section "Configuration Consistency"
  
  # Compare environment checksums
  local env_hash1 env_hash2
  env_hash1=$(ssh_exec "$replica1" "md5sum /home/akushnir/code-server-enterprise/.env.production 2>/dev/null | awk '{print \$1}'" "Get env hash" 2>/dev/null || echo "ERROR")
  env_hash2=$(ssh_exec "$replica2" "md5sum /home/akushnir/code-server-enterprise/.env.production 2>/dev/null | awk '{print \$1}'" "Get env hash" 2>/dev/null || echo "ERROR")
  
  if [[ "$env_hash1" == "$env_hash2" && "$env_hash1" != "ERROR" ]]; then
    log_info "✓ Configuration matches: $env_hash1"
    return 0
  else
    log_error "✗ Configuration MISMATCH:"
    log_error "  Replica 1 ($replica1): $env_hash1"
    log_error "  Replica 2 ($replica2): $env_hash2"
    PARITY_FAILED=1
    return 1
  fi
}

validate_service_status() {
  local replica1=$1
  local replica2=$2
  
  log_section "Service Status Consistency"
  
  # Check Docker Compose status on both replicas
  local status1 status2
  status1=$(ssh_exec "$replica1" "cd /home/akushnir/code-server-enterprise && docker compose ps --quiet --status running | wc -l" "Count running services" 2>/dev/null || echo "ERROR")
  status2=$(ssh_exec "$replica2" "cd /home/akushnir/code-server-enterprise && docker compose ps --quiet --status running | wc -l" "Count running services" 2>/dev/null || echo "ERROR")
  
  if [[ "$status1" == "$status2" && "$status1" != "ERROR" ]]; then
    log_info "✓ Running services match: $status1 services"
    return 0
  else
    log_error "✗ Service count MISMATCH:"
    log_error "  Replica 1 ($replica1): $status1 services"
    log_error "  Replica 2 ($replica2): $status2 services"
    PARITY_FAILED=1
    return 1
  fi
}

validate_database_state() {
  local replica1=$1
  local replica2=$2
  
  log_section "Database State Consistency"
  
  # Check if both replicas can connect to database
  local db_check1 db_check2
  db_check1=$(ssh_exec "$replica1" "cd /home/akushnir/code-server-enterprise && docker compose exec -T postgres pg_isready -U postgres" "DB connectivity" 2>/dev/null || echo "FAIL")
  db_check2=$(ssh_exec "$replica2" "cd /home/akushnir/code-server-enterprise && docker compose exec -T postgres pg_isready -U postgres" "DB connectivity" 2>/dev/null || echo "FAIL")
  
  if [[ "$db_check1" != "FAIL" && "$db_check2" != "FAIL" ]]; then
    log_info "✓ Database accessible on both replicas"
    return 0
  else
    log_error "✗ Database connectivity issues:"
    [[ "$db_check1" == "FAIL" ]] && log_error "  Replica 1 ($replica1): DB unreachable"
    [[ "$db_check2" == "FAIL" ]] && log_error "  Replica 2 ($replica2): DB unreachable"
    PARITY_FAILED=1
    return 1
  fi
}

################################################################################
# MAIN VALIDATION
################################################################################

log_section "CLUSTER PARITY VALIDATION"
log_info "Target domain: ${H_D}"
log_info "Replica 1: ${REPLICA_1_IP}"
log_info "Replica 2: ${REPLICA_2_IP}"
[[ $DRY_RUN -eq 1 ]] && log_info "Mode: DRY-RUN (no changes)"

# Phase 1: Connectivity
log_section "Phase 1: Replica Connectivity"
check_replica_reachable "$REPLICA_1_IP" || PARITY_FAILED=1
check_replica_reachable "$REPLICA_2_IP" || PARITY_FAILED=1

if [[ $PARITY_FAILED -eq 1 ]]; then
  log_fatal "Replicas unreachable; cannot validate parity"
fi

# Phase 2: Code consistency
validate_code_version "$REPLICA_1_IP" "$REPLICA_2_IP" || true

# Phase 3: Configuration consistency
validate_config_consistency "$REPLICA_1_IP" "$REPLICA_2_IP" || true

# Phase 4: Service status
validate_service_status "$REPLICA_1_IP" "$REPLICA_2_IP" || true

# Phase 5: Database state
validate_database_state "$REPLICA_1_IP" "$REPLICA_2_IP" || true

# Summary
log_section "VALIDATION SUMMARY"
if [[ $PARITY_FAILED -eq 0 ]]; then
  log_info "✓ ALL PARITY CHECKS PASSED"
  exit 0
else
  log_error "✗ PARITY VALIDATION FAILED"
  exit 1
fi
