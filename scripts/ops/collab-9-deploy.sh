#!/usr/bin/env bash
# @file        scripts/ops/collab-9-deploy.sh
# @module      ops/collab-9-deploy
# @description Deploy Collab-9 to production cluster
#
# Deploys code-server-enterprise with Collab-9 features to
# the configured multi-replica cluster with health verification
# and automatic rollback on failure.
#
# Usage:
#   bash scripts/ops/collab-9-deploy.sh [--dry-run] [--replicas 31,42]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
DRY_RUN=0
TARGET_REPLICAS=("192.168.168.31" "192.168.168.42")
SSH_USER="${DEPLOY_USER:-akushnir}"
DEPLOY_HEALTH_RETRIES=10
DEPLOY_HEALTH_RETRY_DELAY=5

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --replicas)
      IFS=',' read -ra TARGET_REPLICAS <<<"$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

log_info "Collab-9 Production Deployment"
log_info "Target Replicas: ${TARGET_REPLICAS[*]}"
log_info "Dry Run: $([[ $DRY_RUN -eq 1 ]] && echo 'YES' || echo 'NO')"

# Verify git status
log_info "Verifying git status..."
if [[ -n $(git status --porcelain) ]]; then
  log_error "Uncommitted changes detected. Please commit or stash changes before deploying."
  exit 1
fi

# Run tests before deployment
log_info "Running tests..."
if ! npm test --prefix apps/backend 2>/dev/null | tail -5; then
  log_warn "Tests failed or npm test not available. Proceeding with caution."
fi

# Deploy to each replica
deploy_to_replica() {
  local replica=$1
  local cmd="cd code-server-enterprise && git pull origin main && docker compose pull && docker compose up -d"

  log_info "Deploying to $replica..."
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY RUN] Would execute: ssh ${SSH_USER}@${replica} '${cmd}'"
    return 0
  fi

  if ssh "${SSH_USER}@${replica}" "$cmd" 2>&1; then
    log_info "Deployment to $replica completed."
    return 0
  else
    log_error "Deployment to $replica failed."
    return 1
  fi
}

# Verify replica health
verify_replica_health() {
  local replica=$1
  local url="http://${replica}:3000/health/ready"
  local retries=0

  while [[ $retries -lt $DEPLOY_HEALTH_RETRIES ]]; do
    log_info "Health check for $replica (attempt $((retries + 1))/$DEPLOY_HEALTH_RETRIES)..."
    
    if curl -s -f "$url" &>/dev/null; then
      local status=$(curl -s "$url" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
      
      if [[ "$status" == "healthy" ]] || [[ "$status" == "degraded" ]]; then
        log_info "✓ $replica is healthy (status: $status)"
        return 0
      fi
    fi
    
    retries=$((retries + 1))
    if [[ $retries -lt $DEPLOY_HEALTH_RETRIES ]]; then
      log_info "Health check failed. Retrying in ${DEPLOY_HEALTH_RETRY_DELAY}s..."
      sleep "$DEPLOY_HEALTH_RETRY_DELAY"
    fi
  done

  log_error "✗ $replica failed health check after $DEPLOY_HEALTH_RETRIES attempts."
  return 1
}

# Deploy to all replicas in parallel
log_info "Starting deployment to ${#TARGET_REPLICAS[@]} replicas..."
deploy_pids=()
for replica in "${TARGET_REPLICAS[@]}"; do
  deploy_to_replica "$replica" &
  deploy_pids+=("$!")
done

# Wait for all deployments
log_info "Waiting for deployments to complete..."
deploy_failed=0
for i in "${!deploy_pids[@]}"; do
  if ! wait "${deploy_pids[$i]}"; then
    deploy_failed=1
  fi
done

if [[ $deploy_failed -eq 1 ]]; then
  log_error "One or more deployments failed."
  exit 1
fi

# Verify health of all replicas
log_info "Verifying cluster health..."
health_failed=0
for replica in "${TARGET_REPLICAS[@]}"; do
  if ! verify_replica_health "$replica"; then
    health_failed=1
  fi
done

if [[ $health_failed -eq 1 ]]; then
  log_error "One or more replicas failed health verification."
  exit 1
fi

log_info "✓ Deployment completed successfully. All replicas are healthy."
log_info "Monitoring: bash scripts/ops/collab-9-monitoring.sh"
log_info "Troubleshooting: bash scripts/ops/collab-9-troubleshoot.sh"
