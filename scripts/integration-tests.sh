#!/bin/bash
###############################################################################
# integration-tests.sh
###############################################################################
# Top-level integration test runner for Code Server Enterprise
#
# Orchestrates all integration test suites:
#   1. Service health checks (all apps respond on their ports)
#   2. Inter-service communication tests
#   3. CI integration test suite (extended)
#   4. External service connectivity (Kafka, Redis, PostgreSQL)
#
# Usage:
#   bash scripts/integration-tests.sh [--fast] [--service <name>] [--dry-run]
#
# Options:
#   --fast        Skip slow/extended tests
#   --service     Run tests for a specific service only
#   --dry-run     Print what would run without executing
#
# Exit codes:
#   0: All suites passed
#   1: One or more suites failed
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"

source "${REPO_ROOT}/scripts/_common/init.sh"

trap 'log_error "Integration tests failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup complete"; rm -f /tmp/integration-test.*.tmp 2>/dev/null || true' EXIT

# ── Defaults ──────────────────────────────────────────────────────────────────
FAST_MODE=false
TARGET_SERVICE=""
DRY_RUN=false
REPORT_FILE="/tmp/integration-test-report.$(date +%Y%m%d-%H%M%S).json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast)        FAST_MODE=true; shift ;;
    --service)     TARGET_SERVICE="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=true; shift ;;
    *)             shift ;;
  esac
done

# ── Counters ──────────────────────────────────────────────────────────────────
SUITE_PASS=0
SUITE_FAIL=0
SUITE_SKIP=0

_run_suite() {
  local name="$1"; shift
  local cmd=("$@")
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  [DRY-RUN] Would run: ${cmd[*]}"
    ((SUITE_SKIP++))
    return 0
  fi
  log_info "  Running: ${name}..."
  if "${cmd[@]}" 2>&1; then
    log_info "  ✓ ${name} PASSED"
    ((SUITE_PASS++))
  else
    log_error "  ✗ ${name} FAILED"
    ((SUITE_FAIL++))
  fi
}

_skip_suite() {
  log_info "  ⊘ Skipping: $1 ($2)"
  ((SUITE_SKIP++))
}

# ── Suite 1: Health checks ────────────────────────────────────────────────────
log_info "=== Integration Test Suite: Health Checks ==="

if [[ -z "${TARGET_SERVICE}" || "${TARGET_SERVICE}" == "health" ]]; then
  if [[ -f "${REPO_ROOT}/scripts/ci/health-check-post-deploy.sh" ]]; then
    _run_suite "Post-deploy health checks" \
      bash "${REPO_ROOT}/scripts/ci/health-check-post-deploy.sh"
  elif [[ -f "${REPO_ROOT}/scripts/ci/pre-deployment-health-check.sh" ]]; then
    _run_suite "Pre-deployment health checks" \
      bash "${REPO_ROOT}/scripts/ci/pre-deployment-health-check.sh"
  else
    _skip_suite "Health check suite" "no health-check script found"
  fi
fi

# ── Suite 2: Extended integration tests ───────────────────────────────────────
log_info "=== Integration Test Suite: Extended CI Tests ==="

if [[ -z "${TARGET_SERVICE}" || "${TARGET_SERVICE}" == "extended" ]]; then
  if [[ -f "${REPO_ROOT}/scripts/ci/integration-test-extended.sh" ]]; then
    _run_suite "Extended integration tests" \
      bash "${REPO_ROOT}/scripts/ci/integration-test-extended.sh"
  else
    _skip_suite "Extended integration tests" "script not found"
  fi
fi

# ── Suite 3: External service connectivity ────────────────────────────────────
log_info "=== Integration Test Suite: External Services ==="

if [[ -z "${TARGET_SERVICE}" || "${TARGET_SERVICE}" == "external" ]]; then
  if [[ "${FAST_MODE}" == "true" ]]; then
    _skip_suite "External service tests" "--fast mode"
  elif [[ -f "${REPO_ROOT}/scripts/ci/external-service-tests.sh" ]]; then
    _run_suite "External service connectivity" \
      bash "${REPO_ROOT}/scripts/ci/external-service-tests.sh"
  else
    _skip_suite "External service tests" "script not found"
  fi
fi

# ── Suite 4: Python unit tests via pytest ─────────────────────────────────────
log_info "=== Integration Test Suite: Python Service Tests ==="

if [[ -z "${TARGET_SERVICE}" || "${TARGET_SERVICE}" == "python" ]]; then
  if command -v pytest &>/dev/null; then
    PYTEST_ARGS=(-q --tb=short --no-header)
    [[ "${FAST_MODE}" == "true" ]] && PYTEST_ARGS+=(-m "not slow and not integration")
    if [[ "${DRY_RUN}" == "true" ]]; then
      log_info "  [DRY-RUN] Would run: pytest apps/ ${PYTEST_ARGS[*]}"
      ((SUITE_SKIP++))
    else
      FAILED_APPS=()
      for test_dir in "${REPO_ROOT}"/apps/*/tests/; do
        app_name=$(basename "$(dirname "${test_dir}")")
        [[ -n "${TARGET_SERVICE}" && "${app_name}" != "${TARGET_SERVICE}" ]] && continue
        if pytest "${test_dir}" "${PYTEST_ARGS[@]}" 2>&1; then
          log_info "  ✓ ${app_name} tests PASSED"
          ((SUITE_PASS++))
        else
          log_error "  ✗ ${app_name} tests FAILED"
          FAILED_APPS+=("${app_name}")
          ((SUITE_FAIL++))
        fi
      done
    fi
  else
    _skip_suite "Python tests" "pytest not available"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
log_info ""
log_info "═══════════════════════════════════════════"
log_info "Integration Test Results:"
log_info "  Passed:  ${SUITE_PASS}"
log_info "  Failed:  ${SUITE_FAIL}"
log_info "  Skipped: ${SUITE_SKIP}"
log_info "═══════════════════════════════════════════"

if [[ ${SUITE_FAIL} -gt 0 ]]; then
  log_error "Integration tests FAILED — ${SUITE_FAIL} suite(s) failed"
  exit 1
fi

log_info "Integration tests PASSED"
exit 0
