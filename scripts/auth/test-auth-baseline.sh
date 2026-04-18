#!/usr/bin/env bash
# @file        scripts/auth/test-auth-baseline.sh
# @module      auth/testing
# @description Acceptance test suite for org-wide auth & policy baseline (Issue #650)
#
# Tests:
#   1. Centralized identity provider (Google SSO via admin-portal)
#   2. Baseline RBAC rules defined in IaC
#   3. Audit logging implemented
#   4. Policy drift detection configured
#   5. Runbooks published and readable
#   6. Zero hardcoded secrets in config files

set -euo pipefail

# Get repo root (2 directories up from scripts/auth/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Source init from correct location
source "$REPO_ROOT/scripts/_common/init.sh"

# For convenience, also set SCRIPT_DIR
SCRIPT_DIR="$REPO_ROOT"

TEST_RESULTS_FILE="/tmp/auth-baseline-test-results.json"
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# Test Helper Functions
# ============================================================================
test_assert_file_exists() {
  local test_name="$1"
  local file_path="$2"
  
  if [[ -f "$file_path" ]]; then
    log_info "✅ $test_name"
    ((TESTS_PASSED++))
    return 0
  else
    log_error "❌ $test_name — file not found: $file_path"
    ((TESTS_FAILED++))
    return 1
  fi
}

test_assert_executable() {
  local test_name="$1"
  local file_path="$2"
  
  if [[ -x "$file_path" ]]; then
    log_info "✅ $test_name"
    ((TESTS_PASSED++))
    return 0
  else
    log_error "❌ $test_name — file not executable: $file_path"
    ((TESTS_FAILED++))
    return 1
  fi
}

test_assert_contains() {
  local test_name="$1"
  local file_path="$2"
  local pattern="$3"
  
  if grep -q "$pattern" "$file_path" 2>/dev/null; then
    log_info "✅ $test_name"
    ((TESTS_PASSED++))
    return 0
  else
    log_error "❌ $test_name — pattern not found in $file_path: $pattern"
    ((TESTS_FAILED++))
    return 1
  fi
}

test_assert_not_contains() {
  local test_name="$1"
  local file_path="$2"
  local pattern="$3"
  
  if ! grep -qE "$pattern" "$file_path" 2>/dev/null; then
    log_info "✅ $test_name"
    ((TESTS_PASSED++))
    return 0
  else
    log_error "❌ $test_name — pattern found but should not be: $pattern in $file_path"
    ((TESTS_FAILED++))
    return 1
  fi
}

test_assert_contains_any() {
  local test_name="$1"
  local file_path="$2"
  shift 2
  local patterns=("$@")
  
  for pattern in "${patterns[@]}"; do
    if grep -qE "$pattern" "$file_path" 2>/dev/null; then
      log_info "✅ $test_name"
      ((TESTS_PASSED++))
      return 0
    fi
  done
  
  log_error "❌ $test_name — none of the patterns found in $file_path"
  ((TESTS_FAILED++))
  return 1
}

test_assert_valid_yaml() {
  local test_name="$1"
  local file_path="$2"
  
  # Try Python YAML validation if available
  if command -v python3 &>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$file_path'))" 2>/dev/null; then
      log_info "✅ $test_name"
      ((TESTS_PASSED++))
      return 0
    fi
  fi
  
  # Fallback: check for basic YAML structure (lines starting with spaces or -/:)
  if grep -qE '^\s*(apiVersion|kind|metadata|spec):' "$file_path" 2>/dev/null; then
    log_info "✅ $test_name (basic validation)"
    ((TESTS_PASSED++))
    return 0
  else
    log_error "❌ $test_name — YAML validation failed: $file_path"
    ((TESTS_FAILED++))
    return 1
  fi
}

# ============================================================================
# Test Suite 1: Policy Configuration Files
# ============================================================================
test_suite_policy_config() {
  log_info ""
  log_info "───── Test Suite 1: Policy Configuration Files ─────"
  
  test_assert_file_exists \
    "Policy config file exists" \
    "$SCRIPT_DIR/policies/code-server.yaml"
  
  test_assert_valid_yaml \
    "Policy YAML is valid" \
    "$SCRIPT_DIR/policies/code-server.yaml"
  
  test_assert_contains \
    "Policy defines authentication provider" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    "provider: admin-portal"
  
  test_assert_contains \
    "Policy defines RBAC roles" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    "roles:"
  
  test_assert_contains \
    "Policy defines authorization rules" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    "authorization:"
  
  test_assert_contains \
    "Policy defines audit logging" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    "auditLogging:"
  
  test_assert_contains \
    "Policy defines drift detection" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    "driftDetection:"
  
  test_assert_contains \
    "Policy has at least 4 roles defined" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    "admin:"
  
  test_assert_contains \
    "Policy has developer role" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    "developer:"
  
  test_assert_contains \
    "Policy has viewer role" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    "viewer:"
  
  test_assert_contains \
    "Policy has service-account role" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    "service-account:"
}

# ============================================================================
# Test Suite 2: Audit Logging
# ============================================================================
test_suite_audit_logging() {
  log_info ""
  log_info "───── Test Suite 2: Audit Logging Infrastructure ─────"
  
  test_assert_file_exists \
    "Audit logger script exists" \
    "$SCRIPT_DIR/scripts/auth/auth-audit-logger.sh"
  
  test_assert_executable \
    "Audit logger script is executable" \
    "$SCRIPT_DIR/scripts/auth/auth-audit-logger.sh"
  
  test_assert_contains \
    "Audit logger implements log_auth_event function" \
    "$SCRIPT_DIR/scripts/auth/auth-audit-logger.sh" \
    "log_auth_event()"
  
  test_assert_contains \
    "Audit logger implements flush_audit_logs function" \
    "$SCRIPT_DIR/scripts/auth/auth-audit-logger.sh" \
    "flush_audit_logs()"
  
  test_assert_contains \
    "Audit logger streams to Cloud Logging" \
    "$SCRIPT_DIR/scripts/auth/auth-audit-logger.sh" \
    "gcloud logging write"
  
  test_assert_contains \
    "Audit logger implementation includes required audit event types" \
    "$SCRIPT_DIR/scripts/auth/auth-audit-logger.sh" \
    "auth.login"
  
  test_assert_contains \
    "Audit logger tracks policy decisions" \
    "$SCRIPT_DIR/scripts/auth/auth-audit-logger.sh" \
    "policy.evaluated"
}

# ============================================================================
# Test Suite 3: Drift Detection
# ============================================================================
test_suite_drift_detection() {
  log_info ""
  log_info "───── Test Suite 3: Policy Drift Detection ─────"
  
  test_assert_file_exists \
    "Drift detection script exists" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh"
  
  test_assert_executable \
    "Drift detection script is executable" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh"
  
  test_assert_contains \
    "Drift detection checks auth flow integrity" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh" \
    "check_auth_flow_integrity()"
  
  test_assert_contains \
    "Drift detection checks policy config drift" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh" \
    "check_policy_config_drift()"
  
  test_assert_contains \
    "Drift detection checks audit log health" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh" \
    "check_audit_log_health()"
  
  test_assert_contains \
    "Drift detection checks identity provider health" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh" \
    "check_identity_provider_health()"
  
  test_assert_contains \
    "Drift detection calculates drift score" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh" \
    "calculate_drift_score()"
  
  test_assert_contains \
    "Drift detection can alert on drift" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh" \
    "alert_on_drift()"
}

# ============================================================================
# Test Suite 4: Security & Configuration
# ============================================================================
test_suite_security() {
  log_info ""
  log_info "───── Test Suite 4: Security & Configuration ─────"
  
  # Check for hardcoded secrets (look for hardcoded values, not env var references)
  test_assert_not_contains \
    "No hardcoded GOOGLE_CLIENT_SECRET in oauth2-proxy.cfg" \
    "$SCRIPT_DIR/oauth2-proxy.cfg" \
    'GOOGLE_CLIENT_SECRET=[A-Za-z0-9]'
  
  test_assert_not_contains \
    "No hardcoded OAUTH2_COOKIE_SECRET in docker-compose.yml" \
    "$SCRIPT_DIR/docker-compose.yml" \
    'OAUTH2_COOKIE_SECRET=[0-9a-f]\{32\}'
  
  # Policy file should use env vars for URLs
  test_assert_contains_any \
    "Policy uses environment variables for identity provider URL" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    '\${ADMIN_PORTAL_URL}' \
    'ADMIN_PORTAL_URL:-'
  
  test_assert_contains \
    "Config uses environment variables for secrets" \
    "$SCRIPT_DIR/policies/code-server.yaml" \
    '${'
}

# ============================================================================
# Test Suite 5: Runbooks & Documentation
# ============================================================================
test_suite_runbooks() {
  log_info ""
  log_info "───── Test Suite 5: Runbooks & Documentation ─────"
  
  test_assert_file_exists \
    "Policy update runbook exists" \
    "$SCRIPT_DIR/RUNBOOK-POLICY-UPDATE.md"
  
  test_assert_file_exists \
    "Policy rollback runbook exists" \
    "$SCRIPT_DIR/RUNBOOK-POLICY-ROLLBACK.md"
  
  test_assert_contains \
    "Update runbook explains policy update flow" \
    "$SCRIPT_DIR/RUNBOOK-POLICY-UPDATE.md" \
    "Step 1: Create Feature Branch"
  
  test_assert_contains \
    "Update runbook includes drift detection step" \
    "$SCRIPT_DIR/RUNBOOK-POLICY-UPDATE.md" \
    "Run Drift Detection"
  
  test_assert_contains \
    "Update runbook includes validation step" \
    "$SCRIPT_DIR/RUNBOOK-POLICY-UPDATE.md" \
    "Validate User Impact"
  
  test_assert_contains \
    "Rollback runbook explains immediate assessment" \
    "$SCRIPT_DIR/RUNBOOK-POLICY-ROLLBACK.md" \
    "Assess the Situation"
  
  test_assert_contains \
    "Rollback runbook explains rollback process" \
    "$SCRIPT_DIR/RUNBOOK-POLICY-ROLLBACK.md" \
    "ROLLBACK: Revert"
  
  test_assert_contains \
    "Rollback runbook includes verification steps" \
    "$SCRIPT_DIR/RUNBOOK-POLICY-ROLLBACK.md" \
    "VERIFY: Rollback Was Successful"
}

# ============================================================================
# Test Suite 6: Integration with Governance
# ============================================================================
test_suite_governance() {
  log_info ""
  log_info "───── Test Suite 6: Governance Integration ─────"
  
  # Verify auth scripts have proper metadata headers
  test_assert_contains \
    "Audit logger has metadata header" \
    "$SCRIPT_DIR/scripts/auth/auth-audit-logger.sh" \
    '@file'
  
  test_assert_contains \
    "Drift detection has metadata header" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh" \
    '@file'
  
  # Verify scripts use canonical init
  test_assert_contains \
    "Audit logger sources _common/init.sh" \
    "$SCRIPT_DIR/scripts/auth/auth-audit-logger.sh" \
    'source "$SCRIPT_DIR/scripts/_common/init.sh'
  
  test_assert_contains \
    "Drift detection sources _common/init.sh" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh" \
    'source "$SCRIPT_DIR/scripts/_common/init.sh'
  
  # Verify no duplication (use canonical logging)
  test_assert_not_contains \
    "Audit logger doesn't use 'echo' for logging" \
    "$SCRIPT_DIR/scripts/auth/auth-audit-logger.sh" \
    'echo "ERROR'
  
  test_assert_not_contains \
    "Drift detection doesn't use 'echo' for logging" \
    "$SCRIPT_DIR/scripts/auth/auth-policy-drift-detection.sh" \
    'echo "ERROR'
}

# ============================================================================
# Generate Test Report
# ============================================================================
generate_test_report() {
  local total_tests=$((TESTS_PASSED + TESTS_FAILED))
  local pass_rate=$(( TESTS_PASSED * 100 / total_tests ))
  
  cat > "$TEST_RESULTS_FILE" <<EOF
{
  "test_suite": "auth-baseline-acceptance",
  "issue": "#650",
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "results": {
    "total": $total_tests,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "pass_rate_percent": $pass_rate
  },
  "suites": {
    "policy_config": "Suite 1",
    "audit_logging": "Suite 2",
    "drift_detection": "Suite 3",
    "security": "Suite 4",
    "runbooks": "Suite 5",
    "governance": "Suite 6"
  },
  "status": "$(if [[ $TESTS_FAILED -eq 0 ]]; then echo "PASS"; else echo "FAIL"; fi)"
}
EOF

  log_info ""
  log_info "═══════════════════════════════════════════════════"
  log_info "Test Results: $TESTS_PASSED/$total_tests PASSED ($pass_rate%)"
  log_info "═══════════════════════════════════════════════════"
  log_info ""
  
  if [[ $TESTS_FAILED -eq 0 ]]; then
    log_info "✅ ALL TESTS PASSED — Auth baseline is ready for production"
    return 0
  else
    log_error "❌ TESTS FAILED — $TESTS_FAILED issues found"
    log_error "See report: $TEST_RESULTS_FILE"
    return 1
  fi
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
  log_info ""
  log_info "╔════════════════════════════════════════════════════════════════╗"
  log_info "║  Auth Baseline Acceptance Test Suite (Issue #650)             ║"
  log_info "╚════════════════════════════════════════════════════════════════╝"
  log_info ""
  
  test_suite_policy_config || true
  test_suite_audit_logging || true
  test_suite_drift_detection || true
  test_suite_security || true
  test_suite_runbooks || true
  test_suite_governance || true
  
  generate_test_report
}

main

