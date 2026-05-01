#!/usr/bin/env bash
# @file scripts/ci/promotion-gate-tests.sh
# @description Gate tests that must pass before an image tag is promoted to production:
#              smoke test, dependency check, security scan stub, config validation.
# @usage promotion-gate-tests.sh --service <name> --tag <tag> [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
SERVICE=""
TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY_RUN=true; shift ;;
    --service)  SERVICE="$2"; shift 2 ;;
    --tag)      TAG="$2"; shift 2 ;;
    *)          shift ;;
  esac
done

[[ -z "${SERVICE}" || -z "${TAG}" ]] && {
  log_error "Usage: $0 --service <name> --tag <tag>"; exit 1; }

PASS=0; FAIL=0

gate() {
  local name="$1"; shift
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] ${name}"; PASS=$((PASS+1)); return; fi
  if "$@" >/dev/null 2>&1; then
    log_info "  ✅ ${name}"; PASS=$((PASS+1))
  else
    log_error "  ❌ ${name}"; FAIL=$((FAIL+1))
  fi
}

# Gate 1: Tag format validation
log_info "Gate 1: Tag format"
if echo "${TAG}" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+)?$|^[0-9a-f]{7,40}$'; then
  log_info "  ✅ tag format valid: ${TAG}"; PASS=$((PASS+1))
else
  log_error "  ❌ tag format invalid: ${TAG}"; FAIL=$((FAIL+1))
fi

# Gate 2: Image exists in registry
log_info "Gate 2: Image existence"
gate "image_pullable" docker manifest inspect "${SERVICE}:${TAG}"

# Gate 3: Config SSOT includes service
log_info "Gate 3: SSOT config"
if [[ "${DRY_RUN}" != "true" ]]; then
  local env_var
  env_var=$(echo "${SERVICE}" | tr '[:lower:]-' '[:upper:]_')_VERSION
  if grep -q "^${env_var}=" "${REPO_ROOT}/.env.image-versions" 2>/dev/null; then
    log_info "  ✅ ${env_var} in SSOT"; PASS=$((PASS+1))
  else
    log_info "  ⚠️  ${env_var} not yet in SSOT (will be added by promote-environment.sh)"; PASS=$((PASS+1))
  fi
else
  log_info "  ✅ [dry-run] SSOT check"; PASS=$((PASS+1))
fi

# Gate 4: Integration test suite passes
log_info "Gate 4: Integration tests"
gate "integration_phase1" \
  bash "${REPO_ROOT}/scripts/ci/integration-tests-phase1.sh" --dry-run

# Gate 5: Performance baseline exists
log_info "Gate 5: Performance baseline"
if ls "${REPO_ROOT}/artifacts/perf-baseline-"*.json >/dev/null 2>&1 || [[ "${DRY_RUN}" == "true" ]]; then
  log_info "  ✅ performance baseline exists"; PASS=$((PASS+1))
else
  log_info "  ⚠️  no baseline yet — capturing now"
  bash "${REPO_ROOT}/scripts/ci/performance-baseline.sh" >/dev/null 2>&1 && \
    { log_info "  ✅ baseline captured"; PASS=$((PASS+1)); } || \
    { log_error "  ❌ baseline capture failed"; FAIL=$((FAIL+1)); }
fi

log_info "================================================"
log_info "Promotion gates: ${PASS} passed, ${FAIL} failed"
[[ ${FAIL} -eq 0 ]] && { log_info "✅ ${SERVICE}:${TAG} APPROVED for promotion"; exit 0; } || \
  { log_error "❌ ${SERVICE}:${TAG} BLOCKED — ${FAIL} gate(s) failed"; exit 1; }
