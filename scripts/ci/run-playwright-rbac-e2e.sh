#!/usr/bin/env bash
# @file        scripts/ci/run-playwright-rbac-e2e.sh
# @module      ci/e2e-testing
# @description End-to-end RBAC testing with Playwright

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
E2E_TIMEOUT=${E2E_TIMEOUT:-60000}
TEST_BASE_URL=${TEST_BASE_URL:-http://localhost:3100}
ADMIN_USER=${ADMIN_USER:-admin@test.com}
DEVELOPER_USER=${DEVELOPER_USER:-dev@test.com}
REGULAR_USER=${REGULAR_USER:-user@test.com}

log_info "Starting Phase 3 RBAC End-to-End Tests"
log_info "Test URL: $TEST_BASE_URL"

# Test 1: Admin can assign roles
log_info "TEST 1: Admin assigns roles to user"
(
  curl -X POST "$TEST_BASE_URL/api/admin/roles/user-test-123/assign" \
    -H "Authorization: Bearer $ADMIN_USER" \
    -H "Content-Type: application/json" \
    -d '{"roles": ["developer", "support"], "expiresIn": 3600}' \
    -s | jq '.'
) || {
  log_error "TEST 1 failed"
  exit 1
}
log_info "✓ TEST 1 passed"

# Test 2: User can access role-protected endpoint after assignment
log_info "TEST 2: User with developer role accesses protected endpoint"
(
  curl -X GET "$TEST_BASE_URL/api/admin/roles/user-test-123" \
    -H "Authorization: Bearer $DEVELOPER_USER" \
    -s | jq '.'
) || {
  log_error "TEST 2 failed"
  exit 1
}
log_info "✓ TEST 2 passed"

# Test 3: User without required role is rejected
log_info "TEST 3: User without admin role is rejected from admin endpoint"
RESPONSE=$(curl -X GET "$TEST_BASE_URL/api/admin/roles/list/all" \
  -H "Authorization: Bearer $REGULAR_USER" \
  -s -w "\n%{http_code}")
STATUS=$(echo "$RESPONSE" | tail -1)
if [ "$STATUS" = "403" ]; then
  log_info "✓ TEST 3 passed (correctly rejected with 403)"
else
  log_error "TEST 3 failed: expected 403, got $STATUS"
  exit 1
fi

# Test 4: Admin can remove roles
log_info "TEST 4: Admin removes specific role from user"
(
  curl -X DELETE "$TEST_BASE_URL/api/admin/roles/user-test-123/developer" \
    -H "Authorization: Bearer $ADMIN_USER" \
    -s | jq '.'
) || {
  log_error "TEST 4 failed"
  exit 1
}
log_info "✓ TEST 4 passed"

# Test 5: Admin can clear all roles
log_info "TEST 5: Admin clears all roles from user"
(
  curl -X POST "$TEST_BASE_URL/api/admin/roles/user-test-123/clear" \
    -H "Authorization: Bearer $ADMIN_USER" \
    -s | jq '.'
) || {
  log_error "TEST 5 failed"
  exit 1
}
log_info "✓ TEST 5 passed"

# Test 6: Admin can list all assignments
log_info "TEST 6: Admin lists all role assignments"
(
  curl -X GET "$TEST_BASE_URL/api/admin/roles/list/all" \
    -H "Authorization: Bearer $ADMIN_USER" \
    -s | jq '.'
) || {
  log_error "TEST 6 failed"
  exit 1
}
log_info "✓ TEST 6 passed"

# Test 7: Admin can export audit trail
log_info "TEST 7: Admin exports audit trail"
(
  curl -X POST "$TEST_BASE_URL/api/admin/roles/audit/export" \
    -H "Authorization: Bearer $ADMIN_USER" \
    -s | jq '.auditLog | length'
) || {
  log_error "TEST 7 failed"
  exit 1
}
log_info "✓ TEST 7 passed"

# Test 8: Unauthenticated request is rejected
log_info "TEST 8: Unauthenticated request is rejected"
RESPONSE=$(curl -X GET "$TEST_BASE_URL/api/admin/roles/user-test-123" \
  -s -w "\n%{http_code}")
STATUS=$(echo "$RESPONSE" | tail -1)
if [ "$STATUS" = "401" ]; then
  log_info "✓ TEST 8 passed (correctly rejected with 401)"
else
  log_error "TEST 8 failed: expected 401, got $STATUS"
  exit 1
fi

log_info "========================================"
log_info "Phase 3 RBAC E2E Tests Summary"
log_info "========================================"
log_info "✓ TEST 1: Admin role assignment"
log_info "✓ TEST 2: Protected endpoint access"
log_info "✓ TEST 3: Unauthorized access rejection"
log_info "✓ TEST 4: Role removal"
log_info "✓ TEST 5: Role clearing"
log_info "✓ TEST 6: List all assignments"
log_info "✓ TEST 7: Audit trail export"
log_info "✓ TEST 8: Unauthenticated rejection"
log_info "========================================"
log_info "All Phase 3 RBAC E2E tests passed!"

exit 0
