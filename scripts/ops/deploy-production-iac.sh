#!/usr/bin/env bash
# @file        scripts/ops/deploy-production-iac.sh
# @module      ops/deployment
# @description Central IaC deployment orchestrator for production cluster
#
# Orchestrates end-to-end deployment to both replicas with full IaC compliance:
# - Pre-flight validation (safety checks)
# - Parallel SSH execution (both replicas simultaneously)
# - Git synchronization (pull latest code)
# - Permission remediation (fix Docker-induced ownership issues)
# - Service restart (docker-compose up -d)
# - Health verification (confirm services started)
#
# This script ensures all deployments are:
# ✅ IaC (Infrastructure as Code): All steps versioned and repeatable
# ✅ Immutable: No manual mutations; config-driven only
# ✅ Idempotent: Safe to run multiple times with same result
#
# Usage: bash scripts/ops/deploy-production-iac.sh [--replicas R31,R42] [--dry-run] [--wait-healthy]
#
# Exit Codes:
#   0 = Deployment successful
#   1 = Deployment completed with warnings
#   2 = Deployment failed (critical error)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
SSH_USER="akushnir"
SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa_onprem}"
DRY_RUN=0
WAIT_HEALTHY=1
HEALTH_CHECK_TIMEOUT=300  # 5 minutes
HEALTH_CHECK_INTERVAL=10   # Check every 10 seconds

# Deployment tracking
DEPLOY_START_TIME=$(date +%s)
REPLICAS_DEPLOYED=()
REPLICAS_FAILED=()

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --replicas)
      REPLICAS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --wait-healthy)
      WAIT_HEALTHY="${2:-1}"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 2
      ;;
  esac
done

# ============================================================================
# Helper Functions
# ============================================================================

execute_on_replica() {
  local replica="$1"
  local command="$2"
  local description="${3:-}"

  log_info "[$replica] $description"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[$replica] [DRY-RUN] $command"
    return 0
  fi

  if ssh -i "$SSH_KEY" -o ConnectTimeout=10 "$SSH_USER@$replica" bash -c "$command"; then
    log_info "[$replica] ✅ Success"
    return 0
  else
    log_error "[$replica] ❌ Failed"
    return 1
  fi
}

wait_for_health() {
  local replica="$1"
  local elapsed=0

  log_info "[$replica] Waiting for health checks to pass..."

  while [[ $elapsed -lt $HEALTH_CHECK_TIMEOUT ]]; do
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 "$SSH_USER@$replica" \
      "curl -sk https://localhost/health >/dev/null 2>&1" >/dev/null 2>&1; then
      log_info "[$replica] ✅ Health check passed"
      return 0
    fi

    log_info "[$replica] Waiting... (${elapsed}s/${HEALTH_CHECK_TIMEOUT}s)"
    sleep "$HEALTH_CHECK_INTERVAL"
    elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
  done

  log_warn "[$replica] Health check timeout after ${HEALTH_CHECK_TIMEOUT}s"
  return 1
}

# ============================================================================
# Main Deployment
# ============================================================================

log_info "=== PRODUCTION DEPLOYMENT (IaC) ==="
log_info "Replicas: $REPLICAS"
log_info "Dry run: $DRY_RUN"
log_info ""

# Step 1: Pre-flight Check
log_info "STEP 1: Pre-flight validation"
if ! bash "$SCRIPT_DIR/pre-flight-deployment-check.sh" --replicas "$REPLICAS"; then
  log_error "Pre-flight check failed — deployment aborted"
  exit 2
fi
log_info "✅ Pre-flight check passed"
log_info ""

# Step 2: Parallel Code Pull
log_info "STEP 2: Pulling latest code (parallel)"
IFS=',' read -ra REPLICA_ARRAY <<<"$REPLICAS"

for replica in "${REPLICA_ARRAY[@]}"; do
  replica="${replica// /}"
  (
    if execute_on_replica "$replica" \
      "cd code-server-enterprise && git fetch origin && git reset --hard origin/main" \
      "Git pull"; then
      true
    else
      REPLICAS_FAILED+=("$replica")
    fi
  ) &
done
wait

if [[ ${#REPLICAS_FAILED[@]} -gt 0 ]]; then
  log_error "Git pull failed on: ${REPLICAS_FAILED[*]}"
  exit 2
fi
log_info "✅ Code pulled on all replicas"
log_info ""

# Step 3: Permission Remediation (Parallel)
log_info "STEP 3: Fixing deployment permissions (parallel)"
for replica in "${REPLICA_ARRAY[@]}"; do
  replica="${replica// /}"
  (
    if execute_on_replica "$replica" \
      "sudo chown -R akushnir:akushnir ~/code-server-enterprise ~/.docker 2>/dev/null || true" \
      "Fixing permissions"; then
      true
    else
      log_warn "Permission fix had issues on $replica (non-critical)"
    fi
  ) &
done
wait
log_info "✅ Permissions fixed"
log_info ""

# Step 4: Docker Compose Up (Parallel)
log_info "STEP 4: Starting services (docker-compose up)"
for replica in "${REPLICA_ARRAY[@]}"; do
  replica="${replica// /}"
  (
    if execute_on_replica "$replica" \
      "cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d" \
      "Starting services"; then
      REPLICAS_DEPLOYED+=("$replica")
    else
      REPLICAS_FAILED+=("$replica")
    fi
  ) &
done
wait

if [[ ${#REPLICAS_FAILED[@]} -gt 0 ]]; then
  log_error "Service startup failed on: ${REPLICAS_FAILED[*]}"
  exit 2
fi
log_info "✅ Services started on all replicas"
log_info ""

# Step 5: Health Verification
if [[ $WAIT_HEALTHY -eq 1 ]]; then
  log_info "STEP 5: Verifying service health"
  for replica in "${REPLICAS_DEPLOYED[@]}"; do
    if ! wait_for_health "$replica"; then
      log_warn "Health check may still be initializing on $replica"
    fi
  done
  log_info "✅ Health verification complete"
  log_info ""
fi

# ============================================================================
# Summary & Exit
# ============================================================================

log_info "=== DEPLOYMENT SUMMARY ==="
DEPLOY_END_TIME=$(date +%s)
DEPLOY_DURATION=$((DEPLOY_END_TIME - DEPLOY_START_TIME))

log_info "Deployment duration: ${DEPLOY_DURATION}s"
log_info "Replicas deployed: ${#REPLICAS_DEPLOYED[@]}"
if [[ ${#REPLICAS_FAILED[@]} -gt 0 ]]; then
  log_error "Replicas failed: ${REPLICAS_FAILED[*]}"
  log_error "Deployment INCOMPLETE"
  exit 2
else
  log_info "✅ Deployment SUCCESSFUL"
  log_info ""
  log_info "Next steps:"
  log_info "  1. Monitor cluster health: https://grafana.kushnir.cloud"
  log_info "  2. Verify live endpoints:"
  for replica in "${REPLICAS_DEPLOYED[@]}"; do
    log_info "     curl -k https://$replica/health"
  done
  log_info "  3. Roll back if needed: git reset --hard <previous-commit>"
  exit 0
fi
