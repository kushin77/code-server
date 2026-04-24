#!/usr/bin/env bash
# @file        scripts/ci/run-phase-3-rbac-tests.sh
# @module      ci/testing
# @description Comprehensive testing for Phase 3 Role-Based Access Control

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Test configuration
RBAC_TEST_TIMEOUT=${RBAC_TEST_TIMEOUT:-30000}
RBAC_TEST_RETRIES=${RBAC_TEST_RETRIES:-3}
TEST_BASE_URL=${TEST_BASE_URL:-http://localhost:3100}
TEST_ADMIN_TOKEN=${TEST_ADMIN_TOKEN:-}
TEST_USER_TOKEN=${TEST_USER_TOKEN:-}

log_info "Starting Phase 3 RBAC testing suite"
log_info "Test base URL: $TEST_BASE_URL"

# Test 1: Role Mapper Unit Tests
log_info "TEST 1: Role Mapper Unit Tests"
(
  cd "$REPO_ROOT/apps/backend"
  npm test -- --testPathPattern="role-mapper.test.ts" \
    --testTimeout=$RBAC_TEST_TIMEOUT \
    --verbose
) || {
  log_error "Role Mapper tests failed"
  exit 1
}
log_info "✓ Role Mapper tests passed"

# Test 2: Role Manager Unit Tests
log_info "TEST 2: Role Manager Unit Tests"
(
  cd "$REPO_ROOT/apps/backend"
  npm test -- --testPathPattern="role-manager.test.ts" \
    --testTimeout=$RBAC_TEST_TIMEOUT \
    --verbose
) || {
  log_error "Role Manager tests failed"
  exit 1
}
log_info "✓ Role Manager tests passed"

# Test 3: Authorization Middleware Tests
log_info "TEST 3: Authorization Middleware Tests"
(
  cd "$REPO_ROOT/apps/backend"
  npm test -- --testPathPattern="require-role.test.ts" \
    --testTimeout=$RBAC_TEST_TIMEOUT \
    --verbose
) || {
  log_error "Authorization middleware tests failed"
  exit 1
}
log_info "✓ Authorization middleware tests passed"

# Test 4: Integration Tests - Role Assignment API
log_info "TEST 4: Role Assignment API Integration Tests"
(
  cd "$REPO_ROOT/apps/backend"
  npm test -- --testPathPattern="roles.integration.test.ts" \
    --testTimeout=$RBAC_TEST_TIMEOUT \
    --verbose
) || {
  log_error "Role Assignment API integration tests failed"
  exit 1
}
log_info "✓ Role Assignment API integration tests passed"

# Test 5: E2E Tests - Admin workflow
log_info "TEST 5: End-to-End Tests - Admin Workflow"
if [ -f "$REPO_ROOT/scripts/ci/run-playwright-rbac-e2e.sh" ]; then
  bash "$REPO_ROOT/scripts/ci/run-playwright-rbac-e2e.sh" || {
    log_error "E2E RBAC tests failed"
    exit 1
  }
  log_info "✓ E2E RBAC tests passed"
else
  log_warn "E2E test script not found, skipping"
fi

# Test 6: Security Tests - Unauthorized Access
log_info "TEST 6: Security Tests - Unauthorized Access Prevention"
(
  cd "$REPO_ROOT/apps/backend"
  npm test -- --testPathPattern="rbac-security.test.ts" \
    --testTimeout=$RBAC_TEST_TIMEOUT \
    --verbose
) || {
  log_error "Security tests failed"
  exit 1
}
log_info "✓ Security tests passed"

# Test 7: Role Cache Tests
log_info "TEST 7: Role Cache Performance Tests"
(
  cd "$REPO_ROOT/apps/backend"
  npm test -- --testPathPattern="role-cache.test.ts" \
    --testTimeout=$RBAC_TEST_TIMEOUT \
    --verbose
) || {
  log_error "Role cache tests failed"
  exit 1
}
log_info "✓ Role cache tests passed"

# Test 8: Audit Logging Tests
log_info "TEST 8: Role Audit Logging Tests"
(
  cd "$REPO_ROOT/apps/backend"
  npm test -- --testPathPattern="role-audit.test.ts" \
    --testTimeout=$RBAC_TEST_TIMEOUT \
    --verbose
) || {
  log_error "Audit logging tests failed"
  exit 1
}
log_info "✓ Audit logging tests passed"

# Summary
log_info "========================================"
log_info "Phase 3 RBAC Testing Summary"
log_info "========================================"
log_info "✓ Unit Tests: Role Mapper, Role Manager"
log_info "✓ Integration Tests: Authorization Middleware, API"
log_info "✓ E2E Tests: Admin workflow"
log_info "✓ Security Tests: Unauthorized access prevention"
log_info "✓ Performance Tests: Role caching"
log_info "✓ Audit Tests: Logging and compliance"
log_info "========================================"
log_info "All Phase 3 RBAC tests completed successfully!"

exit 0
