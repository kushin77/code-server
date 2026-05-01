#!/usr/bin/env bash
# @file scripts/ops/promote-environment.sh
# @description Promote a build artifact/image tag from staging to production.
#              Updates .env.image-versions (SSOT), re-applies Terraform, forces a
#              rolling restart of the affected containers.
# @usage promote-environment.sh --service <name> --tag <image-tag> [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
SERVICE=""
IMAGE_TAG=""
ENV_SSOT="${REPO_ROOT}/.env.image-versions"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --service)  SERVICE="$2"; shift 2 ;;
    --tag)      IMAGE_TAG="$2"; shift 2 ;;
    *)          shift ;;
  esac
done

[[ -z "${SERVICE}" ]] && { log_error "Usage: $0 --service <name> --tag <image-tag>"; exit 1; }
[[ -z "${IMAGE_TAG}" ]] && { log_error "Usage: $0 --service <name> --tag <image-tag>"; exit 1; }

run_or_dry() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] $*"
  else
    "$@"
  fi
}

validate_tag() {
  log_info "Validating image tag ${IMAGE_TAG} for service ${SERVICE}..."
  # Ensure the tag follows semver or sha-based format
  if ! echo "${IMAGE_TAG}" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+)?$|^[0-9a-f]{7,40}$'; then
    log_error "  Tag '${IMAGE_TAG}' does not match expected semver or sha pattern"
    return 1
  fi
  log_info "  ✅ Tag format valid"
}

update_ssot() {
  log_info "Updating SSOT (.env.image-versions): ${SERVICE} → ${IMAGE_TAG}"
  if [[ ! -f "${ENV_SSOT}" ]]; then
    log_error "  SSOT file not found: ${ENV_SSOT}"
    return 1
  fi

  # Convert service name to env var format: code-server-api → CODE_SERVER_API_VERSION
  local env_var
  env_var=$(echo "${SERVICE}" | tr '[:lower:]-' '[:upper:]_')_VERSION

  if grep -q "^${env_var}=" "${ENV_SSOT}"; then
    run_or_dry sed -i "s|^${env_var}=.*|${env_var}=${IMAGE_TAG}|" "${ENV_SSOT}"
    log_info "  ✅ Updated ${env_var}=${IMAGE_TAG} in ${ENV_SSOT}"
  else
    log_info "  Adding new entry: ${env_var}=${IMAGE_TAG}"
    run_or_dry bash -c "echo '${env_var}=${IMAGE_TAG}' >> '${ENV_SSOT}'"
  fi
}

commit_ssot_change() {
  log_info "Committing SSOT update..."
  run_or_dry git -C "${REPO_ROOT}" add "${ENV_SSOT}"
  run_or_dry git -C "${REPO_ROOT}" commit \
    -m "chore: promote ${SERVICE} to ${IMAGE_TAG} [skip ci]" || {
      log_info "  Nothing to commit (SSOT unchanged)"
    }
}

terraform_apply() {
  log_info "Applying Terraform to update container image..."
  run_or_dry terraform -chdir="${REPO_ROOT}/terraform/environments/private" \
    apply -auto-approve \
    -target="module.code_server_primary.docker_container.${SERVICE}" \
    -target="module.code_server_replica.docker_container.${SERVICE}" \
    2>&1 | tee -a "${REPO_ROOT}/artifacts/promote-${SERVICE}-${IMAGE_TAG}.log"
}

rolling_restart() {
  log_info "Performing rolling restart of ${SERVICE}..."
  for host in "${PRIMARY_HOST:-localhost}" "${REPLICA_HOST:-localhost}"; do
    log_info "  Restarting ${SERVICE} on ${host}"
    if [[ "${DRY_RUN}" != "true" ]]; then
      ssh -o BatchMode=yes "${REMOTE_USER:-akushnir}@${host}" \
        "docker pull ${SERVICE}:${IMAGE_TAG} && docker restart code-server-${SERVICE}" \
        2>&1 || log_error "  Failed to restart on ${host}"
    else
      log_info "[DRY-RUN] would restart code-server-${SERVICE} on ${host}"
    fi
    sleep 5
  done
}

# Main
log_info "Promote — service=${SERVICE} tag=${IMAGE_TAG} dry-run=${DRY_RUN}"
log_info "============================================================"

validate_tag
update_ssot
commit_ssot_change
terraform_apply
rolling_restart

log_info "============================================================"
log_info "Promotion complete: ${SERVICE}@${IMAGE_TAG} is now production"
