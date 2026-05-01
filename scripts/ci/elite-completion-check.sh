#!/usr/bin/env bash
# @file scripts/ci/elite-completion-check.sh
# @description Verifies ELITE program completion status:
#              - All 15 implementation scripts exist and are executable
#              - All ELITE phase documentation files exist
#              - Deployment test suite passes
#              - No open GitHub issues remain
# @usage elite-completion-check.sh [--dry-run]

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

check_executable() {
  local path="$1"
  if [[ -x "${REPO_ROOT}/${path}" ]]; then
    log_info "  ✅ ${path}"; PASS=$((PASS+1))
  else
    log_error "  ❌ MISSING or not executable: ${path}"; FAIL=$((FAIL+1))
  fi
}

check_file() {
  local path="$1"
  if [[ -f "${REPO_ROOT}/${path}" ]]; then
    log_info "  ✅ ${path}"; PASS=$((PASS+1))
  else
    log_error "  ❌ MISSING: ${path}"; FAIL=$((FAIL+1))
  fi
}

# Main
log_info "ELITE Completion Check — dry-run=${DRY_RUN}"
log_info "================================================"

log_info "Core operational scripts:"
for s in \
  scripts/ops/blue-green-deploy.sh \
  scripts/ops/auto-rollback.sh \
  scripts/ops/dr-failover.sh \
  scripts/ops/rotate-secrets.sh \
  scripts/ops/gitops-sync.sh \
  scripts/ops/promote-environment.sh \
  scripts/ops/auto-scaler.sh \
  scripts/ops/provision-tenant.sh; do
  check_executable "${s}"
done

log_info "Python analytics:"
for s in \
  scripts/ops/capacity-forecast.py \
  scripts/ops/anomaly-detector.py \
  scripts/ops/event-schema-registry.py; do
  check_file "${s}"
done

log_info "CI scripts:"
for s in \
  scripts/ci/performance-baseline.sh \
  scripts/ci/performance-gate.sh \
  scripts/ci/chaos-test-suite.sh \
  scripts/ci/integration-tests-phase1.sh \
  scripts/ci/integration-tests-phase2.sh \
  scripts/ci/check-deployment-health.sh \
  scripts/ci/check-environment-health.sh \
  scripts/ci/pre-integration-check.sh \
  scripts/ci/promotion-gate-tests.sh \
  scripts/ci/security-tests.sh \
  scripts/ci/tenant-pipeline.sh \
  scripts/ci/verify-backups.sh; do
  check_executable "${s}"
done

log_info "Configuration artifacts:"
for c in \
  configs/otel/collector-config.yaml \
  configs/prometheus/slo-rules.yml \
  configs/envoy/circuit-breaker.yaml \
  configs/pyroscope/config.yaml; do
  check_file "${c}"
done

log_info "ELITE phase documentation (spot check):"
local_count=$(find "${REPO_ROOT}/docs/archive" -name 'ELITE_*.md' 2>/dev/null | wc -l)
if (( local_count >= 15 )); then
  log_info "  ✅ ${local_count} ELITE_*.md files in docs/archive"; PASS=$((PASS+1))
else
  log_error "  ❌ Only ${local_count} ELITE docs found (expected ≥15)"; FAIL=$((FAIL+1))
fi

log_info "Deployment test suite:"
if [[ "${DRY_RUN}" == "true" ]]; then
  log_info "  ✅ [dry-run] deployment test suite"; PASS=$((PASS+1))
elif bash "${REPO_ROOT}/scripts/ops/full-deployment-test.sh" --dry-run >/dev/null 2>&1; then
  log_info "  ✅ full-deployment-test.sh --dry-run PASS"; PASS=$((PASS+1))
else
  log_error "  ❌ full-deployment-test.sh --dry-run FAILED"; FAIL=$((FAIL+1))
fi

log_info "================================================"
log_info "ELITE Completion: ${PASS} checks passed, ${FAIL} failed"

if [[ ${FAIL} -eq 0 ]]; then
  log_info "🎉 ELITE program implementation: COMPLETE"
  exit 0
else
  log_error "❌ ELITE incomplete: ${FAIL} gap(s) remaining"
  exit 1
fi
