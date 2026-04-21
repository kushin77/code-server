#!/usr/bin/env bash
# @file        scripts/ci/run-comprehensive-e2e-tests.sh
# @module      ci/e2e-testing
# @description Comprehensive E2E test runner for OAuth, RBAC, JWT, and failover scenarios
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Test configuration
PLAYWRIGHT_CONFIG="${PLAYWRIGHT_CONFIG:-tests/e2e/playwright.config.ts}"
E2E_SPECS_DIR="${E2E_SPECS_DIR:-tests/e2e/specs}"
TEST_TIMEOUT="${TEST_TIMEOUT:-60000}"
WORKERS="${WORKERS:-2}"

# URLs
PRIMARY_IDE_URL="${PRIMARY_IDE_URL:-https://ide.kushnir.cloud}"
REPLICA_IDE_URL="${REPLICA_IDE_URL:-https://replica.ide.kushnir.cloud}"
PORTAL_BASE_URL="${PORTAL_BASE_URL:-https://kushnir.cloud}"
API_BASE_URL="${API_BASE_URL:-https://api.kushnir.cloud}"

# QA Credentials
E2E_USER_EMAIL="${E2E_USER_EMAIL:-qa@kushnir.cloud}"
E2E_USER_PASSWORD="${E2E_USER_PASSWORD:-}"

# OAuth2 credentials
OAUTH2_CLIENT_SECRET="${OAUTH2_CLIENT_SECRET:-}"

# Test scope
TEST_SUITE="${TEST_SUITE:-all}"  # all, oauth, rbac, jwt, failover, integration
DRY_RUN="${DRY_RUN:-0}"
HEADED="${HEADED:-0}"  # Run in headed mode (shows browser)

# Output
REPORT_DIR="${REPORT_DIR:-artifacts/e2e-test-reports}"
TIMING_FILE="${TIMING_FILE:-${REPORT_DIR}/e2e-timing-$(date +%s).json}"

# Exit tracking
EXIT_CODE=0

# ============================================================================
# INITIALIZATION
# ============================================================================

initialize_test_environment() {
  log_info "Initializing E2E test environment..."
  
  # Create report directory
  mkdir -p "$REPORT_DIR"
  
  # Check prerequisites
  if ! command -v npx &> /dev/null; then
    log_fatal "npx not found - npm/pnpm required"
  fi
  
  # Check Playwright installation
  if ! npx playwright --version &> /dev/null; then
    log_warn "Playwright not found - installing..."
    npm install --save-dev @playwright/test || log_fatal "Failed to install Playwright"
  fi
  
  # Validate configuration
  if [[ -z "$E2E_USER_PASSWORD" ]]; then
    log_warn "E2E_USER_PASSWORD not set - interactive tests will fail"
  fi
  
  log_success "✓ Test environment initialized"
}

# ============================================================================
# TEST EXECUTION
# ============================================================================

run_oauth_tests() {
  log_info ""
  log_info "========================================"
  log_info "SUITE: OAuth Login & Session Management"
  log_info "========================================"
  
  local start_time=$(date +%s%N)
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Would run OAuth tests:"
    log_info "  - oauth-login.spec.ts"
    log_info "  - oauth-login-comprehensive.spec.ts"
    local status=0
  else
    npx playwright test \
      "$E2E_SPECS_DIR/oauth-login.spec.ts" \
      "$E2E_SPECS_DIR/oauth-login-comprehensive.spec.ts" \
      --config="$PLAYWRIGHT_CONFIG" \
      --reporter=json \
      --reporter=html \
      ${HEADED:+--headed} \
      --workers="$WORKERS" \
      --timeout="$TEST_TIMEOUT" \
      --output-dir="$REPORT_DIR/oauth" \
      2>&1 | tee "$REPORT_DIR/oauth-tests.log" || status=$?
  fi
  
  local duration=$(( ($(date +%s%N) - start_time) / 1000000 ))
  echo "{\"suite\": \"oauth\", \"duration_ms\": $duration, \"status\": $status}" >> "$TIMING_FILE"
  
  if [[ $status -ne 0 ]]; then
    EXIT_CODE=1
    log_error "✗ OAuth tests failed"
  else
    log_success "✓ OAuth tests passed"
  fi
}

run_rbac_tests() {
  log_info ""
  log_info "========================================"
  log_info "SUITE: RBAC Authorization"
  log_info "========================================"
  
  local start_time=$(date +%s%N)
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Would run RBAC tests:"
    log_info "  - rbac-authorization.spec.ts"
    local status=0
  else
    npx playwright test \
      "$E2E_SPECS_DIR/rbac-authorization.spec.ts" \
      --config="$PLAYWRIGHT_CONFIG" \
      --reporter=json \
      --reporter=html \
      ${HEADED:+--headed} \
      --workers="$WORKERS" \
      --timeout="$TEST_TIMEOUT" \
      --output-dir="$REPORT_DIR/rbac" \
      2>&1 | tee "$REPORT_DIR/rbac-tests.log" || status=$?
  fi
  
  local duration=$(( ($(date +%s%N) - start_time) / 1000000 ))
  echo "{\"suite\": \"rbac\", \"duration_ms\": $duration, \"status\": $status}" >> "$TIMING_FILE"
  
  if [[ $status -ne 0 ]]; then
    EXIT_CODE=1
    log_error "✗ RBAC tests failed"
  else
    log_success "✓ RBAC tests passed"
  fi
}

run_jwt_tests() {
  log_info ""
  log_info "========================================"
  log_info "SUITE: JWT Token Validation"
  log_info "========================================"
  
  local start_time=$(date +%s%N)
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Would run JWT tests:"
    log_info "  - jwt-token-validation.spec.ts"
    local status=0
  else
    npx playwright test \
      "$E2E_SPECS_DIR/jwt-token-validation.spec.ts" \
      --config="$PLAYWRIGHT_CONFIG" \
      --reporter=json \
      --reporter=html \
      ${HEADED:+--headed} \
      --workers="$WORKERS" \
      --timeout="$TEST_TIMEOUT" \
      --output-dir="$REPORT_DIR/jwt" \
      2>&1 | tee "$REPORT_DIR/jwt-tests.log" || status=$?
  fi
  
  local duration=$(( ($(date +%s%N) - start_time) / 1000000 ))
  echo "{\"suite\": \"jwt\", \"duration_ms\": $duration, \"status\": $status}" >> "$TIMING_FILE"
  
  if [[ $status -ne 0 ]]; then
    EXIT_CODE=1
    log_error "✗ JWT tests failed"
  else
    log_success "✓ JWT tests passed"
  fi
}

run_failover_tests() {
  log_info ""
  log_info "========================================"
  log_info "SUITE: Failover & Multi-Host Scenarios"
  log_info "========================================"
  
  local start_time=$(date +%s%N)
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Would run failover tests:"
    log_info "  - failover-multi-host.spec.ts"
    log_info "  - failover-session-continuity.spec.ts"
    local status=0
  else
    npx playwright test \
      "$E2E_SPECS_DIR/failover-multi-host.spec.ts" \
      "$E2E_SPECS_DIR/failover-session-continuity.spec.ts" \
      --config="$PLAYWRIGHT_CONFIG" \
      --reporter=json \
      --reporter=html \
      ${HEADED:+--headed} \
      --workers=1 \
      --timeout="$TEST_TIMEOUT" \
      --output-dir="$REPORT_DIR/failover" \
      2>&1 | tee "$REPORT_DIR/failover-tests.log" || status=$?
  fi
  
  local duration=$(( ($(date +%s%N) - start_time) / 1000000 ))
  echo "{\"suite\": \"failover\", \"duration_ms\": $duration, \"status\": $status}" >> "$TIMING_FILE"
  
  if [[ $status -ne 0 ]]; then
    EXIT_CODE=1
    log_error "✗ Failover tests failed"
  else
    log_success "✓ Failover tests passed"
  fi
}

run_integration_tests() {
  log_info ""
  log_info "========================================"
  log_info "SUITE: Full Integration"
  log_info "========================================"
  
  local start_time=$(date +%s%N)
  
  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Would run integration tests:"
    log_info "  - ide-operations.spec.ts"
    log_info "  - authenticated-session-persistence.spec.ts"
    local status=0
  else
    npx playwright test \
      "$E2E_SPECS_DIR/ide-operations.spec.ts" \
      "$E2E_SPECS_DIR/authenticated-session-persistence.spec.ts" \
      --config="$PLAYWRIGHT_CONFIG" \
      --reporter=json \
      --reporter=html \
      ${HEADED:+--headed} \
      --workers="$WORKERS" \
      --timeout="$TEST_TIMEOUT" \
      --output-dir="$REPORT_DIR/integration" \
      2>&1 | tee "$REPORT_DIR/integration-tests.log" || status=$?
  fi
  
  local duration=$(( ($(date +%s%N) - start_time) / 1000000 ))
  echo "{\"suite\": \"integration\", \"duration_ms\": $duration, \"status\": $status}" >> "$TIMING_FILE"
  
  if [[ $status -ne 0 ]]; then
    EXIT_CODE=1
    log_error "✗ Integration tests failed"
  else
    log_success "✓ Integration tests passed"
  fi
}

# ============================================================================
# REPORTING
# ============================================================================

generate_test_report() {
  log_info ""
  log_info "========================================"
  log_info "TEST REPORT"
  log_info "========================================"
  
  log_info "Report directory: $REPORT_DIR"
  log_info "Timing data: $TIMING_FILE"
  
  if [[ -f "$REPORT_DIR/index.html" ]]; then
    log_info "HTML report: $REPORT_DIR/index.html"
  fi
  
  if [[ -f "$TIMING_FILE" ]]; then
    log_info ""
    log_info "Timing Summary:"
    cat "$TIMING_FILE" | while read line; do
      echo "  $line"
    done
  fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  log_info "Starting E2E Test Suite - Suite: $TEST_SUITE"
  log_info "Configuration:"
  log_info "  PRIMARY_IDE_URL: $PRIMARY_IDE_URL"
  log_info "  REPLICA_IDE_URL: $REPLICA_IDE_URL"
  log_info "  TEST_SUITE: $TEST_SUITE"
  log_info "  DRY_RUN: $DRY_RUN"
  log_info "  WORKERS: $WORKERS"
  
  # Initialize
  initialize_test_environment
  
  # Initialize timing file
  echo "[" > "$TIMING_FILE"
  
  # Run requested test suites
  case "$TEST_SUITE" in
    all)
      run_oauth_tests
      run_rbac_tests
      run_jwt_tests
      run_failover_tests
      run_integration_tests
      ;;
    oauth)
      run_oauth_tests
      ;;
    rbac)
      run_rbac_tests
      ;;
    jwt)
      run_jwt_tests
      ;;
    failover)
      run_failover_tests
      ;;
    integration)
      run_integration_tests
      ;;
    *)
      log_fatal "Unknown test suite: $TEST_SUITE"
      ;;
  esac
  
  # Close timing file
  echo "]" >> "$TIMING_FILE"
  
  # Generate report
  generate_test_report
  
  # Exit
  if [[ $EXIT_CODE -ne 0 ]]; then
    log_error "✗ E2E tests failed with exit code $EXIT_CODE"
  else
    log_success "✓ All E2E tests passed"
  fi
  
  return $EXIT_CODE
}

main "$@"
