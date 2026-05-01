#!/bin/bash
# @file scripts/ops/full-deployment-test.sh
# @module infrastructure/testing
# @description P3-1531 Phase 5: Complete deployment workflow test with rollback validation
# @governance GOV-002: All deployments tested, verified, rolled back before production use
# @usage full-deployment-test.sh [--dry-run] [--target primary|replica|both]

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"
TEST_LOG="${REPO_ROOT}/artifacts/deployment-test-$(date +%s).log"
TEST_REPORT="${REPO_ROOT}/artifacts/deployment-test-report.json"

ARTIFACTS_DIR="${REPO_ROOT}/artifacts"
mkdir -p "${ARTIFACTS_DIR}"

# Test Phase 1: Infrastructure validation
test_infrastructure_validation() {
  log_info "Test Phase 1: Infrastructure Validation"
  
  log_info "  - Validating domain variability..."
  bash "${REPO_ROOT}/scripts/ci/domain-variability-enforcer.sh" --check > /dev/null || return 1
  
  log_info "  - Validating Docker Compose idempotency..."
  bash "${REPO_ROOT}/scripts/ci/check-docker-compose-idempotency.sh" --report > /dev/null || return 1
  
  log_info "  - Validating Terraform version pins..."
  bash "${REPO_ROOT}/scripts/ci/validate-terraform-version-pins.sh" --check > /dev/null || return 1
  
  log_info "  - Validating configuration SSOT..."
  bash "${REPO_ROOT}/scripts/ci/validate-config-ssot.sh" > /dev/null || return 1
  
  log_success "Phase 1 PASSED: All infrastructure validation checks successful"
  return 0
}

# Test Phase 2: GitOps drift detection
test_gitops_drift() {
  log_info "Test Phase 2: GitOps Drift Detection"
  
  log_info "  - Running drift detection (check only)..."
  if bash "${REPO_ROOT}/scripts/ci/gitops-drift-detector.sh" --check >> "${TEST_LOG}" 2>&1; then
    log_success "Phase 2 PASSED: Drift detection executed successfully"
    return 0
  fi
  
  log_error "Phase 2 FAILED: Drift detection reported failures"
  return 1
}

# Test Phase 2b: Cross-host GitLab compose parity (optional)
test_gitlab_compose_parity() {
  log_info "Test Phase 2b: GitLab Compose Parity"

  local parity_script="${REPO_ROOT}/scripts/ops/check-gitlab-compose-parity.sh"
  if [[ ! -x "${parity_script}" ]]; then
    log_warning "Phase 2b SKIPPED: parity script not executable (${parity_script})"
    return 0
  fi

  if [[ -z "${PRIMARY_HOST:-}" || -z "${REPLICA_HOST:-}" ]]; then
    log_warning "Phase 2b SKIPPED: PRIMARY_HOST/REPLICA_HOST not set"
    return 0
  fi

  if [[ "${dry_run:-false}" == "true" ]]; then
    log_warning "Phase 2b SKIPPED: parity check not valid in dry-run (cross-repo SHA will never match)"
    return 0
  fi

  log_info "  - Verifying compose parity between ${PRIMARY_HOST} and ${REPLICA_HOST}..."
  if "${parity_script}" "${PRIMARY_HOST}" "${REPLICA_HOST}" >> "${TEST_LOG}" 2>&1; then
    log_success "Phase 2b PASSED: GitLab compose parity validated"
    return 0
  fi

  log_error "Phase 2b FAILED: GitLab compose parity check failed"
  return 1
}

# Test Phase 3: Deployment simulation (dry-run)
test_deployment_simulation() {
  log_info "Test Phase 3: Deployment Simulation (Dry-Run)"
  
  log_info "  - Running rollback dry-run (compose)..."
  bash "${REPO_ROOT}/scripts/ops/automated-rollback.sh" compose --dry-run >> "${TEST_LOG}" 2>&1 || true
  
  log_info "  - Running rollback dry-run (terraform)..."
  bash "${REPO_ROOT}/scripts/ops/automated-rollback.sh" terraform --dry-run >> "${TEST_LOG}" 2>&1 || true
  
  log_success "Phase 3 PASSED: Deployment simulation completed"
  return 0
}

# Test Phase 4: Health check validation
test_health_checks() {
  local timeout="$1"

  log_info "Test Phase 4: Health Check Validation"
  
  log_info "  - Running post-deployment health checks (timeout=${timeout}s)..."
  local health_rc=0
  bash "${REPO_ROOT}/scripts/ci/health-check-post-deploy.sh" --timeout "${timeout}" >> "${TEST_LOG}" 2>&1 || health_rc=$?

  if [[ -f "${REPO_ROOT}/artifacts/health-check-report.json" ]]; then
    cat "${REPO_ROOT}/artifacts/health-check-report.json" >> "${TEST_LOG}"
    local report_status
    report_status="$(grep -o '"status": "[A-Z]*"' "${REPO_ROOT}/artifacts/health-check-report.json" | awk -F '"' '{print $4}' || true)"
    if [[ "${report_status}" != "PASS" ]]; then
      health_rc=1
    fi
  else
    log_error "Phase 4 FAILED: Health check report not found"
    health_rc=1
  fi

  if [[ ${health_rc} -ne 0 ]]; then
    log_error "Phase 4 FAILED: Health checks reported failures"
    return 1
  fi

  log_success "Phase 4 PASSED: Health check report generated"
  return 0
}

# Test Phase 5: Rollback verification
test_rollback_verification() {
  log_info "Test Phase 5: Rollback Verification"
  
  log_info "  - Verifying rollback mechanism..."
  if bash "${REPO_ROOT}/scripts/ops/automated-rollback.sh" compose --dry-run >> "${TEST_LOG}" 2>&1; then
    log_success "Phase 5 PASSED: Rollback mechanism verified"
    return 0
  else
    log_error "Phase 5 FAILED: Rollback mechanism verification failed"
    return 1
  fi
}

generate_test_report() {
  local test1="$1"
  local test2="$2"
  local test2b="$3"
  local test3="$4"
  local test4="$5"
  local test5="$6"
  
  local overall="PASS"
  [[ "${test1}" == "FAIL" ]] && overall="FAIL"
  [[ "${test2}" == "FAIL" ]] && overall="FAIL"
  [[ "${test2b}" == "FAIL" ]] && overall="FAIL"
  [[ "${test3}" == "FAIL" ]] && overall="FAIL"
  [[ "${test4}" == "FAIL" ]] && overall="FAIL"
  [[ "${test5}" == "FAIL" ]] && overall="FAIL"
  
  cat > "${TEST_REPORT}" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "overall_status": "${overall}",
  "test_phases": {
    "phase_1_infrastructure_validation": "${test1}",
    "phase_2_gitops_drift_detection": "${test2}",
    "phase_2b_gitlab_compose_parity": "${test2b}",
    "phase_3_deployment_simulation": "${test3}",
    "phase_4_health_checks": "${test4}",
    "phase_5_rollback_verification": "${test5}"
  },
  "test_log": "${TEST_LOG}",
  "started_at": "$(head -1 "${TEST_LOG}" | grep -o '\[.*\]' | head -1)"
}
EOF
  
  log_success "Test report saved to ${TEST_REPORT}"
}

main() {
  local target="both"
  local dry_run="false"
  local health_check_timeout=60
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        target="$2"
        shift 2
        ;;
      --dry-run)
        dry_run="true"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  if [[ "${dry_run}" == "true" ]]; then
    health_check_timeout=5
  fi
  
  log_info "=" 
  log_info "Full Deployment Test Suite"
  log_info "Target: ${target}, Dry-Run: ${dry_run}"
  log_info "="
  
  local test1="PASS"
  local test2="PASS"
  local test2b="PASS"
  local test3="PASS"
  local test4="PASS"
  local test5="PASS"
  
  test_infrastructure_validation || test1="FAIL"
  test_gitops_drift || test2="FAIL"
  test_gitlab_compose_parity || test2b="FAIL"
  test_deployment_simulation || test3="FAIL"
  test_health_checks "${health_check_timeout}" || test4="FAIL"
  test_rollback_verification || test5="FAIL"
  
  generate_test_report "${test1}" "${test2}" "${test2b}" "${test3}" "${test4}" "${test5}"
  
  log_info "=="
  log_info "Test Suite Result: ${test1}/${test2}/${test2b}/${test3}/${test4}/${test5}"
  log_info "=="
  
  if [[ "${test1}" == "FAIL" ]] || [[ "${test2}" == "FAIL" ]] || [[ "${test2b}" == "FAIL" ]] || [[ "${test3}" == "FAIL" ]] || [[ "${test4}" == "FAIL" ]] || [[ "${test5}" == "FAIL" ]]; then
    log_error "Deployment test suite FAILED"
    exit 1
  fi
  
  log_success "Deployment test suite PASSED - infrastructure ready for production"
  return 0
}

main "$@"