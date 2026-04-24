#!/bin/bash
# @file deploy-idempotent.sh
# @module infrastructure
# @description Idempotent deployment script - safe to run multiple times
# @idempotent YES - Checks state before any modifications
set -euo pipefail

readonly DEPLOYMENT_ID="deployment-$(date +%s)"
readonly STATE_DIR="./state/deployments"
readonly LOG_FILE="./artifacts/deploy-${DEPLOYMENT_ID}.log"

mkdir -p "$STATE_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if services are already running
services_running() {
  docker compose ps --services 2>/dev/null | wc -l | tr -d ' '
}

# Wait for all services to report healthy
wait_for_healthy_services() {
  local expected_count
  expected_count=$(services_running)

  local attempt=0
  while [[ $attempt -lt 24 ]]; do
    local healthy_count
    healthy_count=$(docker compose ps 2>/dev/null | grep -c "(healthy)" || true)

    if [[ "$healthy_count" -ge "$expected_count" && "$expected_count" -gt 0 ]]; then
      return 0
    fi

    sleep 5
    ((attempt++))
  done

  return 1
}

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
    echo "ERROR: Docker daemon not running" >&2
    return 1
  fi
  
  # Verify docker-compose.yml exists
  if [[ ! -f ./docker-compose.yml ]]; then
    echo "ERROR: docker-compose.yml not found" >&2
    return 1
  fi
  
  log "Pulling latest images..."
  docker compose pull
  
  log "Starting services..."
  docker compose up -d
  
  log "Waiting for health checks..."
  if ! wait_for_healthy_services; then
    echo "ERROR: Services did not become healthy in time" >&2
    return 1
  fi
  
  # Verify all services are healthy
  local unhealthy=0
  for service in $(docker compose ps --services); do
    if ! docker compose ps "$service" | grep -q "healthy\|running"; then
      echo "WARNING: Service $service not healthy" >&2
      ((unhealthy++)) || true
    fi
  done
  
  if [[ $unhealthy -eq 0 ]]; then
    log "✅ All services healthy"
    echo "deployed:$(date '+%s')" >> "$state_file"
    return 0
  else
    echo "ERROR: $unhealthy services not healthy" >&2
    return 1
  fi
}

main() {
  deploy
}

main "$@"
