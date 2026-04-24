#!/usr/bin/env bash
# @file        scripts/ops/collab-9-deploy.sh
# @module      ops/collab-9-deploy
# @description Deploy Collab-9 to the production replicas
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

DEPLOY_HOSTS_RAW="${DEPLOY_HOSTS:-${DEPLOY_HOST:-}}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
DEPLOY_DIR="${DEPLOY_DIR:-code-server-enterprise}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-10}"
HEALTH_CHECK_RETRY_DELAY="${HEALTH_CHECK_RETRY_DELAY:-5}"
DRY_RUN=0
TARGETS=()
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3)

if [[ -n "$DEPLOY_HOSTS_RAW" ]]; then
  IFS=',' read -r -a TARGETS <<< "$DEPLOY_HOSTS_RAW"
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  for host in "${DEPLOY_HOST:-}" "${STANDBY_HOST:-}"; do
    if [[ -n "$host" ]]; then
      TARGETS+=("$host")
    fi
  done
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --hosts)
      IFS=',' read -r -a TARGETS <<< "${2:-}"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

filtered_targets=()
for host in "${TARGETS[@]}"; do
  if [[ -n "$host" ]]; then
    filtered_targets+=("$host")
  fi
done
TARGETS=("${filtered_targets[@]}")

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  log_fatal "No deployment hosts configured"
fi

log_info "Collab-9 production deployment"
log_info "Deploy user: $DEPLOY_USER"
log_info "Deploy dir: $DEPLOY_DIR"
log_info "Targets: ${TARGETS[*]}"
log_info "Dry run: $([[ $DRY_RUN -eq 1 ]] && echo yes || echo no)"

verify_ssh_access() {
  local host="$1"

  if ! ssh "${SSH_OPTS[@]}" "${DEPLOY_USER}@${host}" true; then
    log_fatal "SSH access check failed for ${DEPLOY_USER}@${host}. Configure key-based authentication before deploying."
  fi
}

if [[ $DRY_RUN -eq 0 ]]; then
  for host in "${TARGETS[@]}"; do
    verify_ssh_access "$host"
  done
fi

deploy_to_replica() {
  local host="$1"
  local remote_cmd="cd \"$DEPLOY_DIR\" && git pull --ff-only origin main && docker compose pull && docker compose up -d"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[dry-run] ssh ${SSH_OPTS[*]} ${DEPLOY_USER}@${host} '$remote_cmd'"
    return 0
  fi

  log_info "Deploying to $host"
  if ! ssh "${SSH_OPTS[@]}" "${DEPLOY_USER}@${host}" "$remote_cmd"; then
    log_error "SSH deployment failed on $host. Ensure key-based auth is configured for ${DEPLOY_USER}@${host}."
    return 1
  fi
  log_info "Deployment completed on $host"
}

verify_replica_health() {
  local host="$1"
  local health_url="http://${host}:${APP_PORT:-3000}/health/ready"
  local attempt=1

  while [[ $attempt -le $HEALTH_CHECK_RETRIES ]]; do
    if curl -fsS "$health_url" >/dev/null; then
      log_info "Health check passed for $host"
      return 0
    fi

    log_warn "Health check failed for $host (attempt $attempt/$HEALTH_CHECK_RETRIES)"
    if [[ $attempt -lt $HEALTH_CHECK_RETRIES ]]; then
      sleep "$HEALTH_CHECK_RETRY_DELAY"
    fi
    attempt=$((attempt + 1))
  done

  log_error "Health check failed for $host"
  return 1
}

pids=()
for host in "${TARGETS[@]}"; do
  deploy_to_replica "$host" &
  pids+=("$!")
done

failed=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    failed=1
  fi
done

if [[ $failed -ne 0 ]]; then
  log_fatal "At least one deployment failed"
fi

for host in "${TARGETS[@]}"; do
  verify_replica_health "$host"
done

log_info "Collab-9 deployment completed successfully"
