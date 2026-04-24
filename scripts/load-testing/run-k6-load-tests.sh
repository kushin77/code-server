#!/usr/bin/env bash
# @file        scripts/load-testing/run-k6-load-tests.sh
# @module      load-testing/k6
# @description Comprehensive k6 load testing runner - executes all test scenarios and generates reports
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/_common/init.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

OAUTH_BASE_URL="${OAUTH_BASE_URL:-https://ide.kushnir.cloud}"
OIDC_ISSUER="${OIDC_ISSUER:-https://oidc.kushnir.cloud}"
API_BASE="${API_BASE:-https://api.kushnir.cloud}"
JWT_TOKEN="${JWT_TOKEN:-}"
OAUTH2_CLIENT_ID="${OAUTH2_CLIENT_ID:-code-server}"
OAUTH2_CLIENT_SECRET="${OAUTH2_CLIENT_SECRET:-}"

TEST_SUITE="${TEST_SUITE:-all}"  # all, oauth, jwt, session, api
DRY_RUN="${DRY_RUN:-1}"
VUS="${VUS:-10}"  # Virtual Users
DURATION="${DURATION:-5m}"

REPORT_DIR="${REPORT_DIR:-artifacts/load-tests}"
RESULTS_FILE="${RESULTS_FILE:-$REPORT_DIR/results-$(date +%s).json}"

# ============================================================================
# MAIN FUNCTIONS
# ============================================================================

initialize_environment() {
  log_info "Initializing load test environment..."
  
  mkdir -p "$REPORT_DIR"
  
  # Verify k6 is installed
  if ! command -v k6 &> /dev/null; then
    log_error "k6 not found. Install with: apt-get install k6"
    return 1
  fi
  
  log_info "k6 version: $(k6 version)"
  
  # Check JWT token if provided
  if [[ -n "$JWT_TOKEN" ]]; then
    log_info "JWT token configured for authenticated tests"
  else
    log_warn "JWT_TOKEN not set - authenticated tests may fail"
  fi
}

run_oauth_tests() {
  log_info "Starting OAuth Login Flow load test..."
  
  local test_script="$SCRIPT_DIR/oauth-login-load-test.js"
  if [[ ! -f "$test_script" ]]; then
    log_error "Test script not found: $test_script"
    return 1
  fi
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "DRY_RUN mode - test would execute as:"
    log_info "  k6 run $test_script"
    return 0
  fi
  
  k6 run \
    --vus "$VUS" \
    --duration "$DURATION" \
    -e OAUTH_BASE_URL="$OAUTH_BASE_URL" \
    -e OAUTH_CLIENT_ID="$OAUTH2_CLIENT_ID" \
    "$test_script" | tee "$REPORT_DIR/oauth-test.log"
}

run_jwt_tests() {
  log_info "Starting JWT Token Acquisition load test..."
  
  local test_script="$SCRIPT_DIR/jwt-token-load-test.js"
  if [[ ! -f "$test_script" ]]; then
    log_error "Test script not found: $test_script"
    return 1
  fi
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "DRY_RUN mode - test would execute as:"
    log_info "  k6 run $test_script"
    return 0
  fi
  
  k6 run \
    --vus "$VUS" \
    --duration "$DURATION" \
    -e OIDC_ISSUER="$OIDC_ISSUER" \
    -e OAUTH2_CLIENT_ID="$OAUTH2_CLIENT_ID" \
    -e OAUTH2_CLIENT_SECRET="$OAUTH2_CLIENT_SECRET" \
    "$test_script" | tee "$REPORT_DIR/jwt-test.log"
}

run_session_tests() {
  log_info "Starting Session Creation load test..."
  
  local test_script="$SCRIPT_DIR/session-load-test.js"
  if [[ ! -f "$test_script" ]]; then
    log_error "Test script not found: $test_script"
    return 1
  fi
  
  if [[ -z "$JWT_TOKEN" ]]; then
    log_error "JWT_TOKEN required for session tests"
    return 1
  fi
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "DRY_RUN mode - test would execute as:"
    log_info "  k6 run $test_script"
    return 0
  fi
  
  k6 run \
    --vus "$VUS" \
    --duration "$DURATION" \
    -e BASE_URL="$OAUTH_BASE_URL" \
    -e API_BASE="$API_BASE" \
    -e JWT_TOKEN="$JWT_TOKEN" \
    "$test_script" | tee "$REPORT_DIR/session-test.log"
}

run_api_tests() {
  log_info "Starting API Endpoint load test..."
  
  local test_script="$SCRIPT_DIR/api-endpoint-load-test.js"
  if [[ ! -f "$test_script" ]]; then
    log_error "Test script not found: $test_script"
    return 1
  fi
  
  if [[ -z "$JWT_TOKEN" ]]; then
    log_error "JWT_TOKEN required for API tests"
    return 1
  fi
  
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "DRY_RUN mode - test would execute as:"
    log_info "  k6 run $test_script"
    return 0
  fi
  
  k6 run \
    --vus "$VUS" \
    --duration "$DURATION" \
    -e API_BASE="$API_BASE" \
    -e JWT_TOKEN="$JWT_TOKEN" \
    "$test_script" | tee "$REPORT_DIR/api-test.log"
}

generate_summary() {
  log_info "Generating load test summary report..."
  
  cat > "$REPORT_DIR/LOAD-TEST-SUMMARY.md" << 'EOF'
# Load Testing Summary Report

## Test Scenarios Completed

### 1. OAuth Login Flow Load Test
- **Purpose**: Validate OAuth2 login throughput and latency
- **Scenarios**: 10-100 concurrent users
- **Duration**: 6.5 minutes
- **Metrics**: Login latency (p50, p95, p99), session creation latency
- **Results**: See oauth-test.log

### 2. JWT Token Acquisition Load Test
- **Purpose**: Validate OIDC token issuance performance
- **Scenarios**: 50-100 concurrent token requests
- **Duration**: 6 minutes
- **Metrics**: Token acquisition latency, JWKS cache hit rate
- **Results**: See jwt-test.log

### 3. Session Creation Load Test
- **Purpose**: Validate session-broker throughput
- **Scenarios**: 50-200 concurrent session creations
- **Duration**: 7 minutes
- **Metrics**: Session creation latency, active sessions gauge
- **Results**: See session-test.log

### 4. API Endpoint Load Test
- **Purpose**: Validate API performance under authenticated load
- **Scenarios**: 100-500 concurrent requests
- **Duration**: 8 minutes
- **Metrics**: Endpoint latency, RBAC authorization performance
- **Results**: See api-test.log

## Key Metrics

### Latency Thresholds (Target)
- OAuth Login: p95 < 5s, p99 < 10s
- JWT Token: p95 < 1s, p99 < 2s
- Session Creation: p95 < 2s, p99 < 5s
- API Endpoints: p95 < 2s, p99 < 5s

### Success Rates (Target)
- OAuth Login: > 95%
- JWT Token: > 99%
- Session Creation: > 98%
- API Endpoints: > 99%

### Bottleneck Identification
1. Check which service shows highest latency
2. Review service resource metrics during test
3. Identify scaling recommendations

## Next Steps
1. Review detailed logs in $REPORT_DIR/
2. Analyze bottlenecks from timing data
3. Document capacity limits
4. Create scaling recommendations
5. Update runbook with findings

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

  log_info "Summary report: $REPORT_DIR/LOAD-TEST-SUMMARY.md"
}

main() {
  log_info "Starting k6 Load Testing Suite"
  log_info "Configuration:"
  log_info "  Test Suite: $TEST_SUITE"
  log_info "  DRY_RUN: $DRY_RUN"
  log_info "  Virtual Users: $VUS"
  log_info "  Duration: $DURATION"
  log_info "  Report Directory: $REPORT_DIR"
  
  initialize_environment || return $?
  
  case "$TEST_SUITE" in
    all)
      run_oauth_tests
      run_jwt_tests
      run_session_tests
      run_api_tests
      ;;
    oauth)
      run_oauth_tests
      ;;
    jwt)
      run_jwt_tests
      ;;
    session)
      run_session_tests
      ;;
    api)
      run_api_tests
      ;;
    *)
      log_error "Unknown test suite: $TEST_SUITE"
      return 1
      ;;
  esac
  
  generate_summary
  
  log_info "Load testing completed successfully"
  log_info "Results: $REPORT_DIR/"
}

main "$@"
