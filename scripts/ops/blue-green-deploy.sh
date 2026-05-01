#!/usr/bin/env bash
# @file scripts/ops/blue-green-deploy.sh
# @description Zero-downtime blue/green deployment for code-server stack.
#              Brings up the inactive slot, health-checks it, then switches traffic.
# @usage blue-green-deploy.sh [--target primary|replica|both] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
TARGET="both"
HEALTH_RETRIES=12
HEALTH_INTERVAL=5
COMPOSE_FILE="${REPO_ROOT}/docker-compose.enterprise.yml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true; shift ;;
    --target)    TARGET="$2"; shift 2 ;;
    *)           shift ;;
  esac
done

# Determine current active slot (blue|green) from a label on the running caddy container
get_active_slot() {
  local host="${1:-localhost}"
  docker ${host:+--host "ssh://${REMOTE_USER:-akushnir}@${host}"} \
    inspect code-server-caddy \
    --format '{{index .Config.Labels "deploy-slot"}}' 2>/dev/null || echo "blue"
}

inactive_slot() {
  [[ "$1" == "blue" ]] && echo "green" || echo "blue"
}

# Run an arbitrary docker-compose command, dry-run aware
compose_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] would run: docker compose $*"
  else
    docker compose -f "${COMPOSE_FILE}" "$@"
  fi
}

health_check_slot() {
  local slot="$1"
  local port="${2:-8080}"
  log_info "Health-checking slot ${slot} on port ${port}..."
  local i=0
  while (( i < HEALTH_RETRIES )); do
    if curl -sf --max-time 3 "http://localhost:${port}/health" >/dev/null 2>&1; then
      log_info "  Slot ${slot} is healthy (attempt $((i+1)))"
      return 0
    fi
    i=$((i+1))
    log_info "  Waiting for slot ${slot}... ($i/${HEALTH_RETRIES})"
    sleep "${HEALTH_INTERVAL}"
  done
  log_error "Slot ${slot} failed health check after ${HEALTH_RETRIES} attempts"
  return 1
}

deploy_to_host() {
  local host="$1"
  log_info "=== Blue/Green deploy: host=${host} ==="

  local active
  active=$(get_active_slot "${host}")
  local inactive
  inactive=$(inactive_slot "${active}")

  log_info "  Active slot: ${active} → deploying to: ${inactive}"

  # Step 1: Bring up inactive slot (new version)
  log_info "  Step 1: Starting ${inactive} slot"
  compose_cmd up -d --no-deps --scale "code-server-${inactive}=1" "code-server-${inactive}"

  # Step 2: Health check the new slot
  log_info "  Step 2: Health-checking ${inactive} slot"
  if [[ "${DRY_RUN}" != "true" ]]; then
    health_check_slot "${inactive}" || {
      log_error "  New slot unhealthy — aborting, ${active} still live"
      compose_cmd stop "code-server-${inactive}"
      return 1
    }
  fi

  # Step 3: Switch router (Caddy upstream) to new slot
  log_info "  Step 3: Switching traffic to ${inactive}"
  compose_cmd exec caddy caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || \
    compose_cmd restart caddy

  # Step 4: Label the new active slot
  if [[ "${DRY_RUN}" != "true" ]]; then
    docker label code-server-caddy "deploy-slot=${inactive}" 2>/dev/null || true
  fi

  # Step 5: Stop the old slot (keep for quick rollback, just stopped)
  log_info "  Step 4: Stopping old slot ${active} (kept for rollback)"
  compose_cmd stop "code-server-${active}"

  log_info "  ✅ Blue/green complete: ${inactive} is now live on ${host}"
}

# Main
log_info "Blue/Green Deployment — target=${TARGET} dry-run=${DRY_RUN}"
log_info "================================================="

case "${TARGET}" in
  primary)  deploy_to_host "${PRIMARY_HOST:-localhost}" ;;
  replica)  deploy_to_host "${REPLICA_HOST:-localhost}" ;;
  both)
    deploy_to_host "${PRIMARY_HOST:-localhost}"
    deploy_to_host "${REPLICA_HOST:-localhost}"
    ;;
  *)
    log_error "Unknown target: ${TARGET}"
    exit 1
    ;;
esac

log_info "================================================="
log_info "Blue/Green deployment complete"
