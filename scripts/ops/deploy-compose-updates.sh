#!/bin/bash
# @file scripts/ops/deploy-compose-updates.sh
# @description Deploy docker-compose configuration updates to infrastructure hosts
# @usage deploy-compose-updates.sh [--dry-run] [--target primary|replica|both]

set -euo pipefail

trap 'log_error "Deployment failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup complete"; rm -f /tmp/compose-deploy-*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

DRY_RUN="${DRY_RUN:-false}"
TARGET="${TARGET:-both}"
REMOTE_USER="${REMOTE_USER:-akushnir}"
REMOTE_PATH="${REMOTE_PATH:-~/code-server-enterprise}"

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_success() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"
}

log_warning() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"
}

deploy_to_host() {
  local host="$1"
  local role="$2"

  log_info "Deploying docker-compose files to ${role} (${host})..."

  # Copy docker-compose files
  for compose_file in docker-compose.yml docker-compose.enterprise.yml docker-compose.minio.yml docker-compose.vault.yml docker-compose.override.yml; do
    if [[ ! -f "${REPO_ROOT}/${compose_file}" ]]; then
      log_warning "Skipping ${compose_file} (not found)"
      continue
    fi

    log_info "  - Syncing ${compose_file}..."
    if [[ "${DRY_RUN}" == "true" ]]; then
      log_info "    [DRY-RUN] Would copy ${compose_file} to ${host}:${REMOTE_PATH}/"
    else
      scp -q "${REPO_ROOT}/${compose_file}" "${REMOTE_USER}@${host}:${REMOTE_PATH}/" || {
        log_error "Failed to copy ${compose_file} to ${host}"
        return 1
      }
    fi
  done

  # Verify deployment
  if [[ "${DRY_RUN}" != "true" ]]; then
    log_info "  - Verifying deployment on ${role}..."
    local deployed_sha
    deployed_sha="$(ssh -q "${REMOTE_USER}@${host}" "cd ${REMOTE_PATH} && sha256sum docker-compose.yml | awk '{print \$1}'")" || {
      log_error "Failed to verify deployment on ${host}"
      return 1
    }
    local local_sha
    local_sha="$(sha256sum "${REPO_ROOT}/docker-compose.yml" | awk '{print $1}')"
    if [[ "${deployed_sha}" == "${local_sha}" ]]; then
      log_success "  - Verification OK: docker-compose.yml matches on ${role}"
    else
      log_error "  - Verification FAILED: SHA mismatch on ${role}"
      return 1
    fi
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --target)
        TARGET="$2"
        shift 2
        ;;
      *)
        log_error "Unknown option: $1"
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  log_info "=========================================="
  log_info "Docker Compose Deployment"
  log_info "=========================================="
  log_info "Mode: $([ "${DRY_RUN}" == "true" ] && echo "DRY-RUN" || echo "APPLY")"
  log_info "Target: ${TARGET}"
  log_info "Repository: ${REPO_ROOT}"
  log_info ""

  local deploy_success=true

  if [[ "${TARGET}" == "primary" || "${TARGET}" == "both" ]]; then
    log_info ">>> DEPLOYING TO PRIMARY <<<"
    if ! deploy_to_host "${PRIMARY_HOST}" "primary"; then
      deploy_success=false
      log_error "Primary deployment FAILED"
    else
      log_success "Primary deployment complete"
    fi
    log_info ""
  fi

  if [[ "${TARGET}" == "replica" || "${TARGET}" == "both" ]]; then
    log_info ">>> DEPLOYING TO REPLICA <<<"
    if ! deploy_to_host "${REPLICA_HOST}" "replica"; then
      deploy_success=false
      log_error "Replica deployment FAILED"
    else
      log_success "Replica deployment complete"
    fi
    log_info ""
  fi

  log_info "=========================================="
  if [[ "${deploy_success}" == "true" ]]; then
    log_success "Docker Compose deployment complete"
    return 0
  else
    log_error "Docker Compose deployment had failures"
    return 1
  fi
}

main "$@"
