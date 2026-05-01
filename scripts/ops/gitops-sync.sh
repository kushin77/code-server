#!/usr/bin/env bash
# @file scripts/ops/gitops-sync.sh
# @description GitOps reconciliation loop — compares live Terraform state to desired
#              state in Git, detects drift, and re-applies if in auto-sync mode.
# @usage gitops-sync.sh [--auto-apply] [--dry-run] [--once]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
AUTO_APPLY=false
RUN_ONCE=false
SYNC_INTERVAL=60
TF_DIR="${REPO_ROOT}/terraform/environments/private"
SYNC_LOG="${REPO_ROOT}/artifacts/gitops-sync-$(date +%s).log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --auto-apply) AUTO_APPLY=true; shift ;;
    --once)       RUN_ONCE=true; shift ;;
    *)            shift ;;
  esac
done

mkdir -p "${REPO_ROOT}/artifacts"

tf_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] terraform -chdir=${TF_DIR} $*"
    return 0
  fi
  terraform -chdir="${TF_DIR}" "$@"
}

git_pull() {
  log_info "Pulling latest Git state from origin..."
  if [[ "${DRY_RUN}" != "true" ]]; then
    git -C "${REPO_ROOT}" fetch --quiet origin
    git -C "${REPO_ROOT}" merge --ff-only origin/release/v1.0.0-production || {
      log_error "  Git fast-forward failed — local commits exist, skipping auto-apply"
      return 1
    }
  fi
  log_info "  Git state up to date"
}

detect_drift() {
  log_info "Running Terraform plan to detect drift..."
  local plan_out
  plan_out=$(mktemp /tmp/tf-plan-XXXXXX.tmp)
  if [[ "${DRY_RUN}" != "true" ]]; then
    if terraform -chdir="${TF_DIR}" plan -detailed-exitcode -out="${plan_out}" \
        -compact-warnings 2>&1 | tee -a "${SYNC_LOG}"; then
      log_info "  ✅ No drift detected — infrastructure matches desired state"
      rm -f "${plan_out}"
      return 0
    else
      local exit_code=$?
      if [[ ${exit_code} -eq 2 ]]; then
        log_info "  ⚠️  Drift detected — changes required"
        echo "${plan_out}"   # return plan file path via stdout
        return 2
      fi
      log_error "  Terraform plan failed (exit ${exit_code})"
      rm -f "${plan_out}"
      return 1
    fi
  else
    log_info "[DRY-RUN] would run: terraform plan -detailed-exitcode"
    rm -f "${plan_out}"
    return 0
  fi
}

apply_drift() {
  local plan_file="$1"
  log_info "Applying Terraform plan to resolve drift..."
  if [[ "${DRY_RUN}" != "true" ]]; then
    terraform -chdir="${TF_DIR}" apply "${plan_file}"
    log_info "  ✅ Drift resolved — infrastructure reconciled"
  else
    log_info "[DRY-RUN] would run: terraform apply <plan>"
  fi
  rm -f "${plan_file}"
}

sync_once() {
  local current_sha
  current_sha=$(git -C "${REPO_ROOT}" rev-parse --short HEAD)
  log_info "GitOps sync — git_sha=${current_sha}"

  git_pull || return 0

  local plan_file
  plan_file=$(detect_drift)
  local drift_code=$?

  if [[ ${drift_code} -eq 2 ]]; then
    if [[ "${AUTO_APPLY}" == "true" ]]; then
      apply_drift "${plan_file}"
    else
      log_info "  Drift detected. Run with --auto-apply to reconcile, or apply manually."
    fi
  fi
}

# Main
log_info "GitOps Sync — auto-apply=${AUTO_APPLY} dry-run=${DRY_RUN}" | tee -a "${SYNC_LOG}"
log_info "================================================"

if [[ "${RUN_ONCE}" == "true" ]]; then
  sync_once
else
  log_info "Starting GitOps sync loop (interval=${SYNC_INTERVAL}s)..."
  while true; do
    sync_once
    log_info "Sleeping ${SYNC_INTERVAL}s until next sync..."
    sleep "${SYNC_INTERVAL}"
  done
fi

log_info "================================================"
log_info "GitOps sync complete"
