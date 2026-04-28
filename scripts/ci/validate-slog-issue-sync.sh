#!/usr/bin/env bash
# @file scripts/ci/validate-slog-issue-sync.sh
# @description Smoke-check grouped SLOG issue sync dry-run behavior against persisted repo log artifacts.

set -euo pipefail

trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${REPO_ROOT}/scripts/_common/init.sh"

main() {
  local output_file
  output_file="$(mktemp)"

  log_info "Running grouped SLOG sync in dry-run mode"
  if ! (
    cd "${REPO_ROOT}"
    SLOG_DRY_RUN=1 bash sync-slog-to-github.sh >"${output_file}" 2>&1
  ); then
    cat "${output_file}" >&2 || true
    log_error "Grouped SLOG sync dry-run failed"
    rm -f "${output_file}"
    return 1
  fi

  if ! grep -q "Discovered .* grouped slog issue candidate" "${output_file}"; then
    cat "${output_file}" >&2 || true
    log_error "Dry-run output did not report grouped SLOG candidates"
    rm -f "${output_file}"
    return 1
  fi

  if [[ -f "${REPO_ROOT}/logs/drift-detection.log" ]]; then
    if ! grep -q "Docker daemon not available" "${output_file}"; then
      cat "${output_file}" >&2 || true
      log_error "Expected drift-detection warning group was not emitted"
      rm -f "${output_file}"
      return 1
    fi
    log_success "Detected expected grouped drift warning from logs/drift-detection.log"
  fi

  if [[ -f "${REPO_ROOT}/PRODUCTION_FIX_LOG.md" ]]; then
    if ! grep -q 'FATAL: database "gitlabdb" does not exist' "${output_file}"; then
      cat "${output_file}" >&2 || true
      log_error "Expected markdown incident log group was not emitted"
      rm -f "${output_file}"
      return 1
    fi
    log_success "Detected expected grouped markdown incident signal from PRODUCTION_FIX_LOG.md"
  fi

  if ! grep -q "family=deployment" "${output_file}" || ! grep -q "Deployment test suite FAILED\|Phase 5 FAILED: Rollback mechanism verification failed" "${output_file}"; then
    cat "${output_file}" >&2 || true
    log_error "Expected deployment-family grouped signal was not emitted"
    rm -f "${output_file}"
    return 1
  fi
  log_success "Detected expected grouped deployment-family signal from runtime logs"

  log_success "Grouped SLOG sync smoke check passed"
  rm -f "${output_file}"
}

main "$@"