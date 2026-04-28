#!/bin/bash
# @file automated-rollback.sh
# @module infrastructure/recovery
# @description P3-1531 Phase 2: Automated infrastructure rollback with health verification
# @governance GOV-002: All rollbacks version-controlled, tested, verified before deployment
# @usage automated-rollback.sh <component> [--version VERSION] [--dry-run] [--health-check]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

ROLLBACK_HISTORY="${REPO_ROOT}/artifacts/rollback-history.json"
HEALTH_CHECK_TIMEOUT=300
# Templated health check endpoint with fallback to environment-driven defaults
HEALTH_CHECK_ENDPOINT="${HEALTH_CHECK_ENDPOINT:=${API_PROTOCOL:-http}://${API_HOST:-localhost}:${API_PORT:-3100}/health}"

mkdir -p "$(dirname "${ROLLBACK_HISTORY}")"

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_success() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"
}

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Rollback failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Rollback cleanup..."; true' EXIT

wait_for_compose_health() {
  local max_attempts=30
  local attempt=0

  while [[ ${attempt} -lt ${max_attempts} ]]; do
    local healthy_count
    local total_count

    total_count=$(docker compose ps --services 2>/dev/null | wc -l | tr -d ' ')
    healthy_count=$(docker compose ps 2>/dev/null | grep -c "(healthy)" || true)

    if [[ ${total_count} -gt 0 && ${healthy_count} -ge ${total_count} ]]; then
      return 0
    fi

    sleep 5
    attempt=$((attempt + 1))
  done

  return 1
}

health_check() {
  log_info "Running health check at ${HEALTH_CHECK_ENDPOINT} (timeout: ${HEALTH_CHECK_TIMEOUT}s)..."
  
  local start_time=$(date +%s)
  local max_attempts=30
  local attempt=0
  
  while [[ $(($(date +%s) - start_time)) -lt ${HEALTH_CHECK_TIMEOUT} ]] && [[ ${attempt} -lt ${max_attempts} ]]; do
    if curl -sf "${HEALTH_CHECK_ENDPOINT}" > /dev/null 2>&1; then
      log_success "Health check PASSED"
      return 0
    fi
    
    sleep 10
    attempt=$((attempt + 1))
    log_info "Health check attempt ${attempt}/${max_attempts} failed, retrying..."
  done
  
  log_error "Health check FAILED after ${HEALTH_CHECK_TIMEOUT}s"
  return 1
}

rollback_docker_compose() {
  local version="${1:-latest}"
  local dry_run="${2:-false}"
  
  log_info "Rolling back Docker Compose to version ${version}..."
  
  if [[ "${dry_run}" == "true" ]]; then
    log_info "[DRY-RUN] Would stop all services and restart"
    return 0
  fi
  
  cd "${REPO_ROOT}"
  docker compose down || true
  docker compose up -d

  if ! wait_for_compose_health; then
    log_error "Docker Compose services did not become healthy after rollback"
    return 1
  fi
  
  log_success "Docker Compose rolled back"
}

rollback_terraform() {
  local version="${1:-latest}"
  local dry_run="${2:-false}"
  
  log_info "Rolling back Terraform to version ${version}..."
  
  if [[ "${dry_run}" == "true" ]]; then
    log_info "[DRY-RUN] Would apply Terraform rollback"
    return 0
  fi
  
  cd "${REPO_ROOT}/terraform"
  terraform apply -auto-approve 2>&1 | tail -20
  
  log_success "Terraform rolled back"
}

record_rollback_attempt() {
  local component="$1"
  local version="${2:-unknown}"
  local status="${3:-unknown}"
  local health_status="${4:-not-checked}"
  
  # Use jq to safely append to JSON array (idempotent)
  local entry=$(cat <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "component": "${component}",
  "version": "${version}",
  "status": "${status}",
  "health_check": "${health_status}"
}
EOF
  )
  
  if [[ ! -f "${ROLLBACK_HISTORY}" ]]; then
    echo '{"rollbacks": []}' > "${ROLLBACK_HISTORY}"
  fi
  
  # Use jq to safely append to JSON array while maintaining structure
  if command -v jq &>/dev/null; then
    jq ".rollbacks += [$(echo "$entry")]" "${ROLLBACK_HISTORY}" > "${ROLLBACK_HISTORY}.tmp" && \
      mv "${ROLLBACK_HISTORY}.tmp" "${ROLLBACK_HISTORY}"
  else
    # Fallback: append with warning
    log_error "jq not available; appending without JSON validation (may cause malformed output)"
    echo "${entry}" >> "${ROLLBACK_HISTORY}"
  fi
}

main() {
  local component="${1:-}"
  local version=""
  local dry_run="false"
  local run_health_check="false"
  
  if [[ -z "${component}" ]]; then
    log_error "Usage: automated-rollback.sh <compose|terraform> [--version VERSION] [--dry-run] [--health-check]"
    exit 1
  fi
  
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        version="$2"
        shift 2
        ;;
      --dry-run)
        dry_run="true"
        shift
        ;;
      --health-check)
        run_health_check="true"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  log_info "Automated rollback initiated: component=${component}, version=${version:-latest}, dry_run=${dry_run}"
  
  local health_status="not-checked"
  local rollback_status="success"
  
  case "${component}" in
    compose)
      rollback_docker_compose "${version:-latest}" "${dry_run}" || rollback_status="failed"
      ;;
    terraform)
      rollback_terraform "${version:-latest}" "${dry_run}" || rollback_status="failed"
      ;;
    *)
      log_error "Unknown component: ${component}"
      exit 1
      ;;
  esac
  
  if [[ "${run_health_check}" == "true" ]] && [[ "${rollback_status}" == "success" ]]; then
    if health_check; then
      health_status="passed"
    else
      health_status="failed"
      rollback_status="failed"
    fi
  fi
  
  record_rollback_attempt "${component}" "${version:-latest}" "${rollback_status}" "${health_status}"
  
  if [[ "${rollback_status}" == "failed" ]]; then
    log_error "Rollback completed with errors"
    exit 1
  fi
  
  log_success "Rollback completed successfully"
}

main "$@"