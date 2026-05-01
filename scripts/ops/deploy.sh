#!/bin/bash
# @file deploy.sh
# @module infrastructure
# @description Idempotent deployment script - safe to run multiple times
# @idempotent YES - Checks state before any modifications
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

readonly DEPLOYMENT_ID="deployment-$(date +%s)"
readonly STATE_DIR="${REPO_ROOT}/state/deployments"
readonly LOG_FILE="${REPO_ROOT}/artifacts/deploy-${DEPLOYMENT_ID}.log"

mkdir -p "$STATE_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_warn() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" | tee -a "$LOG_FILE"
}

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Deployment failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/deploy-*.tmp 2>/dev/null || true' EXIT

# Idempotent deployment
deploy() {
  log "Starting idempotent deployment: $DEPLOYMENT_ID"
  
  local state_file="${STATE_DIR}/${DEPLOYMENT_ID}.state"
  
  # Check if already deployed
  if [[ -f "$state_file" ]] && grep -q "deployed" "$state_file"; then
    log "✅ Deployment already completed in state file: $(cat "$state_file" | tail -1)"
    return 0
  fi
  
  log "Pre-deployment checks..."
  
  # Verify Docker is running
  if ! docker ps &>/dev/null; then
    log_error "Docker daemon not running"
    return 1
  fi
  
  # Verify docker-compose.yml exists
  if [[ ! -f ./docker-compose.yml ]]; then
    log_error "docker-compose.yml not found"
    return 1
  fi
  
  log "Pulling latest images..."
  docker compose pull
  
  log "Starting services..."
  docker compose up -d
  
  log "Waiting for health checks..."
  if ! wait_for_healthy_services; then
    log_error "Services did not become healthy in time"
    return 1
  fi
  
  # Verify all services are healthy
  local unhealthy=0
  for service in $(docker compose ps --services); do
    if ! docker compose ps "$service" | grep -q "healthy\|running"; then
      log_warn "Service $service not healthy"
      unhealthy+=1 || true
    fi
  done
  
  if [[ $unhealthy -eq 0 ]]; then
    log "✅ All services healthy"
    echo "deployed:$(date '+%s')" >> "$state_file"
    return 0
  else
    log_error "$unhealthy services not healthy"
    return 1
  fi
}

main() {
  deploy
}

main "$@"
