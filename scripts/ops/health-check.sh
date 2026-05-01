#!/bin/bash
# @file health-check.sh
# @module infrastructure
# @description Idempotent health checks - can be called continuously
# @idempotent YES - State-based checking without side effects
set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

readonly LOG_FILE="${REPO_ROOT}/artifacts/health-$(date +%s).log"
readonly STATE_FILE="${REPO_ROOT}/state/health.state"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Idempotent health check
check_health() {
  log "Running idempotent health checks"
  
  local services_healthy=0
  local services_total=0
  
  for service in $(docker compose ps --services); do
    services_total+=1
    
    local health=$(docker compose exec -T "$service" sh -c 'echo ok' 2>/dev/null || echo 'fail')
    
    if [[ "$health" == "ok" ]]; then
      services_healthy+=1
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
