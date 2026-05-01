#!/usr/bin/env bash
# @file scripts/ci/pre-integration-check.sh
# @description Pre-integration gate: verifies prerequisites before running the
#              integration test suite. Checks service availability, required
#              env vars, and test data fixtures are in place.
# @usage pre-integration-check.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *)         shift ;;
  esac
done

PASS=0; FAIL=0

require_env() {
  local var="$1"
  if [[ -n "${!var:-}" ]]; then
    log_info "  ✅ ${var} set"; PASS=$((PASS+1))
  else
    log_info "  ⚠️  ${var} not set (using default)"; PASS=$((PASS+1))
  fi
}

require_url() {
  local name="$1" url="$2"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] ${name}"; PASS=$((PASS+1)); return; fi
  if curl -sf --max-time 5 "${url}" >/dev/null 2>&1; then
    log_info "  ✅ ${name} reachable"; PASS=$((PASS+1))
  else
    log_error "  ❌ ${name} unreachable at ${url}"; FAIL=$((FAIL+1))
  fi
}

require_file() {
  local path="$1"
  if [[ -f "${path}" ]]; then
    log_info "  ✅ ${path} exists"; PASS=$((PASS+1))
  else
    log_error "  ❌ required file missing: ${path}"; FAIL=$((FAIL+1))
  fi
}

# Main
log_info "Pre-Integration Check — dry-run=${DRY_RUN}"
log_info "================================================"

log_info "Environment variables:"
require_env "BASE_URL"
require_env "PRIMARY_HOST"
require_env "REPLICA_HOST"

log_info "Service availability:"
require_url "platform health"   "http://${BASE_URL:-localhost:8080}/health"
require_url "prometheus"        "http://${PRIMARY_HOST:-localhost}:9090/-/healthy"

log_info "Required files:"
require_file "${REPO_ROOT}/docker-compose.enterprise.yml"
require_file "${REPO_ROOT}/.env.image-versions"
require_file "${REPO_ROOT}/configs/otel/collector-config.yaml"

log_info "Terraform state:"
if [[ "${DRY_RUN}" == "true" ]]; then
  log_info "  ✅ [dry-run] terraform state"; PASS=$((PASS+1))
elif terraform -chdir="${REPO_ROOT}/terraform/environments/private" \
    state list >/dev/null 2>&1; then
  log_info "  ✅ terraform state accessible"; PASS=$((PASS+1))
else
  log_error "  ❌ terraform state inaccessible"; FAIL=$((FAIL+1))
fi

log_info "================================================"
log_info "Pre-check: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]] && { log_info "✅ Pre-integration checks passed"; exit 0; } || \
  { log_error "❌ Pre-integration checks failed — fix issues before running tests"; exit 1; }
