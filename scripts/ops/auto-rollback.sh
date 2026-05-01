#!/usr/bin/env bash
# @file scripts/ops/auto-rollback.sh
# @description Automated rollback: detects failure signals and reverts to the last
#              known-good git ref + terraform state. Triggered by health-check failure
#              or called directly from CI/CD.
# @usage auto-rollback.sh [--env primary|replica|both] [--ref <git-sha>] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
ENV="both"
ROLLBACK_REF=""
ROLLBACK_LOG="${REPO_ROOT}/artifacts/rollback-$(date +%s).log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --env)     ENV="$2"; shift 2 ;;
    --ref)     ROLLBACK_REF="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

mkdir -p "${REPO_ROOT}/artifacts"

# Resolve rollback ref: use provided, else previous git commit
resolve_rollback_ref() {
  if [[ -n "${ROLLBACK_REF}" ]]; then
    echo "${ROLLBACK_REF}"
    return
  fi
  # Last commit before HEAD
  git -C "${REPO_ROOT}" log --oneline -2 | tail -1 | awk '{print $1}'
}

run_or_dry() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] would run: $*"
  else
    "$@"
  fi
}

rollback_git() {
  local ref
  ref=$(resolve_rollback_ref)
  log_info "Rolling back Git to ref: ${ref}"
  run_or_dry git -C "${REPO_ROOT}" checkout "${ref}" -- \
    terraform/ docker-compose.enterprise.yml docker-compose.yml configs/
  log_info "  Git rollback to ${ref} applied"
}

rollback_terraform() {
  log_info "Re-applying Terraform at rollback ref..."
  run_or_dry terraform -chdir="${REPO_ROOT}/terraform/environments/private" \
    apply -auto-approve -parallelism=4
  log_info "  Terraform rollback apply complete"
}

rollback_compose() {
  log_info "Restarting compose services at rollback state..."
  run_or_dry docker compose -f "${REPO_ROOT}/docker-compose.enterprise.yml" \
    up -d --no-recreate
  log_info "  Compose rollback complete"
}

verify_rollback() {
  log_info "Verifying rollback health..."
  local healthy=0
  local attempts=0
  while (( attempts < 6 )); do
    if curl -sf --max-time 5 "http://${PRIMARY_HOST:-localhost}:8080/health" >/dev/null 2>&1; then
      healthy=1
      break
    fi
    attempts=$((attempts+1))
    sleep 10
  done
  if [[ ${healthy} -eq 1 ]]; then
    log_info "  ✅ Rollback verified — platform healthy"
  else
    log_error "  ❌ Rollback verification failed — manual intervention required"
    return 1
  fi
}

# Main
log_info "Auto-Rollback — env=${ENV} dry-run=${DRY_RUN}" | tee -a "${ROLLBACK_LOG}"
log_info "============================================"

rollback_git
rollback_terraform
rollback_compose

if [[ "${DRY_RUN}" != "true" ]]; then
  verify_rollback
fi

log_info "============================================"
log_info "Auto-Rollback complete — log: ${ROLLBACK_LOG}"
