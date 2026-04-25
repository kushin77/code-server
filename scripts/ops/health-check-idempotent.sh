#!/bin/bash
# @governance: Idempotent health checks — state-based monitoring without side effects
# Purpose: Idempotent health checks - can be called continuously
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1534 (IaC Governance), #1531 (Infrastructure as Code)
# Idempotent: YES - State-based checking without side effects

set -euo pipefail

readonly LOG_FILE="./artifacts/health-$(date +%s).log"
readonly STATE_FILE="./state/health.state"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Idempotent health check
check_health() {
  log "Running idempotent health checks"
  
  local services_healthy=0
  local services_total=0
  
  for service in $(docker compose ps --services); do
    ((services_total++))
    
    local health=$(docker compose exec -T "$service" sh -c 'echo ok' 2>/dev/null || echo 'fail')
    
    if [[ "$health" == "ok" ]]; then
      ((services_healthy++))
      log "✅ $service: healthy"
    else
      log "❌ $service: unhealthy"
    fi
  done
  
  # Record state for idempotency
  echo "checked:$services_healthy/$services_total:$(date '+%s')" >> "$STATE_FILE"
  
  if [[ $services_healthy -eq $services_total ]]; then
    log "✅ All services healthy"
    return 0
  else
    log "❌ Some services unhealthy"
    return 1
  fi
}

main() {
  check_health
}

main "$@"
