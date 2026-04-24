#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/execute-cluster-parity-validation.sh
# @module      ops/validation
# @description Execute comprehensive cluster parity validation across all replicas
# @owner       operations
# @status      stable
#
# USAGE
#   scripts/ops/execute-cluster-parity-validation.sh [--replicas HOSTS] [--dry-run] [--verbose]
#
# ENVIRONMENT VARIABLES
#   REPLICA_HOSTS     - Comma-separated replica IPs (default: 192.168.168.31,192.168.168.42)
#   SSH_USER          - SSH user (default: akushnir)
#   DRY_RUN           - Preview mode (0 or 1)
#   VERBOSE           - Verbose output (0 or 1)
#
# EXIT CODES
#   0 - All replicas in parity
#   1 - Parity mismatch detected
#   2 - Configuration error
#
# IaC, IMMUTABLE, IDEMPOTENT
#   - Read-only validation, no modifications
#   - Safe to run multiple times
#   - Suitable for automated monitoring
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

init_repo
source "${SCRIPT_DIR}/../fetch-gsm-secrets.sh"

# Configuration
REPLICA_HOSTS="${REPLICA_HOSTS:-192.168.168.31,192.168.168.42}"
SSH_USER="${SSH_USER:-${DEPLOY_USER:-akushnir}}"
DRY_RUN="${DRY_RUN:-0}"
VERBOSE="${VERBOSE:-0}"
VALIDATION_REPORT="${VALIDATION_REPORT:-artifacts/ops/cluster-parity-$(date +%Y%m%d-%H%M%S).log}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --replicas) REPLICA_HOSTS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    *) log_error "Unknown option: $1"; exit 2 ;;
  esac
done

# Create report directory
mkdir -p "$(dirname "$VALIDATION_REPORT")"

# Convert comma-separated hosts to array
IFS=',' read -ra REPLICAS <<< "$REPLICA_HOSTS"
PARITY_FAILED=0

################################################################################
# VALIDATION FUNCTIONS
################################################################################

run_validation() {
  local name=$1
  local cmd=$2
  local expected=$3
  
  local results=()
  
  log_info "Validating: $name"
  
  for host in "${REPLICAS[@]}"; do
    local result
    result=$(ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no \
      "${SSH_USER}@${host}" "$cmd" 2>/dev/null || echo "ERROR")
    
    results+=("$result")
    
    if [[ $VERBOSE -eq 1 ]]; then
      log_info "  [$host]: $result"
    fi
  done
  
  # Check if all results match expected (or first result if no expected)
  if [[ -z "$expected" ]]; then
    expected="${results[0]}"
  fi
  
  local match=1
  for result in "${results[@]}"; do
    if [[ "$result" != "$expected" ]]; then
      match=0
      break
    fi
  done
  
  if [[ $match -eq 1 ]]; then
    log_info "✓ $name: PASS"
    return 0
  else
    log_error "✗ $name: FAIL (mismatch detected)"
    for i in "${!REPLICAS[@]}"; do
      log_error "  [${REPLICAS[$i]}]: ${results[$i]}"
    done
    PARITY_FAILED=1
    return 1
  fi
}

################################################################################
# MAIN VALIDATION
################################################################################

log_section "CLUSTER PARITY VALIDATION"
log_info "Replicas: $(IFS=, echo "${REPLICAS[@]}")"
log_info "User: $SSH_USER"
log_info "Report: $VALIDATION_REPORT"

{
  echo "# Cluster Parity Validation Report"
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Replicas: $(IFS=, echo "${REPLICAS[@]}")"
  echo ""
} > "$VALIDATION_REPORT"

# Phase 1: Connectivity
log_section "Phase 1: Connectivity"
for host in "${REPLICAS[@]}"; do
  if ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
      "${SSH_USER}@${host}" "echo OK" > /dev/null 2>&1; then
    log_info "✓ Reachable: $host"
  else
    log_error "✗ Unreachable: $host"
    PARITY_FAILED=1
  fi
done

if [[ $PARITY_FAILED -eq 1 ]]; then
  log_fatal "Cannot validate parity - replicas unreachable"
fi

# Phase 2: Code Version
log_section "Phase 2: Code Version Consistency"
run_validation "Git commit SHA" \
  "cd /home/${SSH_USER}/code-server-enterprise && git rev-parse HEAD"

# Phase 3: Docker Services
log_section "Phase 3: Docker Services Status"
run_validation "Running service count" \
  "cd /home/${SSH_USER}/code-server-enterprise && docker compose ps --status running -q | wc -l"

# Phase 4: PostgreSQL
log_section "Phase 4: PostgreSQL Connectivity"
run_validation "PostgreSQL ready" \
  "cd /home/${SSH_USER}/code-server-enterprise && docker compose exec -T postgres pg_isready -U postgres 2>&1 | grep 'accepting'"

# Phase 5: Redis
log_section "Phase 5: Redis Connectivity"
run_validation "Redis ready" \
  "cd /home/${SSH_USER}/code-server-enterprise && docker compose exec -T redis redis-cli ping 2>&1 | grep -i PONG"

# Phase 6: Environment Config
log_section "Phase 6: Configuration Hash"
run_validation "Environment file hash" \
  "md5sum /home/${SSH_USER}/code-server-enterprise/.env.production 2>/dev/null | awk '{print \$1}'"

# Summary
log_section "VALIDATION SUMMARY"

{
  echo ""
  echo "## Validation Results"
  echo ""
  if [[ $PARITY_FAILED -eq 0 ]]; then
    echo "Status: PASSED"
    echo ""
    echo "All replicas are in parity:"
    echo "- Code versions synchronized"
    echo "- Services running count consistent"
    echo "- Databases responding"
    echo "- Configuration hashes match"
  else
    echo "Status: FAILED"
    echo ""
    echo "Parity mismatches detected. See details above."
  fi
  echo ""
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "$VALIDATION_REPORT"

log_info "Report saved: $VALIDATION_REPORT"

if [[ $PARITY_FAILED -eq 0 ]]; then
  log_info "✓ CLUSTER PARITY VALIDATION PASSED"
  exit 0
else
  log_error "✗ CLUSTER PARITY VALIDATION FAILED"
  exit 1
fi
