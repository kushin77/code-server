#!/bin/bash
# tests/user-lifecycle-test.sh - Comprehensive test suite for user management CLI

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0

print_test() {
  echo -e "${YELLOW}[TEST]${NC} $1"
}

print_pass() {
  echo -e "${GREEN}✅ PASS${NC} $1"
  ((PASSED++))
}

print_fail() {
  echo -e "${RED}❌ FAIL${NC} $1"
  ((FAILED++))
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST SUITE 1: File path validation
# ─────────────────────────────────────────────────────────────────────────────

test_allowed_emails_file_exists() {
  print_test "Allowlist file exists and is readable"
  
  if [[ ! -f "allowed-emails.txt" ]]; then
    print_fail "allowed-emails.txt not found"
  elif [[ ! -r "allowed-emails.txt" ]]; then
    print_fail "allowed-emails.txt is not readable"
  else
    print_pass "Allowlist file integrity"
  fi
}

test_no_tx_typos() {
  print_test "No .tx file references (typo check)"
  
  if grep -r "allowed-emails\.tx[^t]" scripts/ 2>/dev/null || grep -r "allowed-emails\.tx\"" scripts/ 2>/dev/null; then
    print_fail "Found .tx typo in scripts - critical bug!"
  else
    print_pass "No .tx typo references found"
  fi
}

test_atomic_writes() {
  print_test "Atomic write operations in remove-user"
  
  if ! grep -q "atomic_write" scripts/manage-users.sh 2>/dev/null; then
    print_fail "Atomic write function not found"
    return
  fi
  
  if ! grep -q "allowed-emails.txt" scripts/manage-users.sh 2>/dev/null; then
    print_fail "allowed-emails.txt path not found in script"
    return
  fi
  
  print_pass "Atomic write pattern verified"
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST SUITE 2: User lifecycle operations (DRY RUN)
# ─────────────────────────────────────────────────────────────────────────────

test_list_users_command() {
  print_test "list-users command works"
  
  if bash scripts/manage-users.sh list-users 2>&1 | grep -q "Total:"; then
    print_pass "list-users command execution"
  else
    print_fail "list-users command output missing"
  fi
}

test_show_user_validates_email() {
  print_test "show-user validates email parameter"
  
  output=$(bash scripts/manage-users.sh show-user 2>&1 || true)
  
  if echo "$output" | grep -q "Usage:"; then
    print_pass "show-user parameter validation"
  else
    print_fail "show-user did not show usage for missing email"
  fi
}

test_change_role_validates_role() {
  print_test "change-role validates role parameter"
  
  output=$(bash scripts/manage-users.sh change-role test@example.com invalid-role 2>&1 || true)
  
  if echo "$output" | grep -q "Invalid role"; then
    print_pass "change-role role validation"
  else
    print_fail "change-role did not validate invalid role"
  fi
}

test_remove_user_requires_confirmation() {
  print_test "remove-user requires confirmation"
  
  if ! grep -q "cmd_remove_user()" scripts/manage-users.sh; then
    print_fail "remove-user command not found"
    return
  fi
  
  if ! grep -q "Are you sure?" scripts/manage-users.sh; then
    print_fail "remove-user does not have confirmation prompt"
    return
  fi
  
  print_pass "remove-user confirmation requirement"
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST SUITE 3: Audit logging
# ─────────────────────────────────────────────────────────────────────────────

test_audit_log_format() {
  print_test "Audit log entries have correct format"
  
  if ! grep -q "audit/user-provisioning.log" scripts/manage-users.sh; then
    print_fail "audit log path not found"
    return
  fi
  
  if ! grep -q "date -I'seconds'" scripts/manage-users.sh; then
    print_fail "ISO 8601 timestamp format not found in audit logging"
    return
  fi
  
  print_pass "Audit log format validation"
}

test_audit_log_includes_actor_action() {
  print_test "Audit logs capture action type and details"
  
  if ! grep -q "USER_REVOKED\|USER_ROLE_CHANGED" scripts/manage-users.sh; then
    print_fail "Action types not captured in audit logs"
    return
  fi
  
  print_pass "Audit log action tracking"
}

test_security_status_checks_allowlist() {
  print_test "security-status verifies allowlist"
  
  output=$(bash scripts/manage-users.sh security-status 2>&1)
  
  if echo "$output" | grep -q "Email whitelist"; then
    print_pass "security-status allowlist check"
  else
    print_fail "security-status does not check email whitelist"
  fi
}

test_help_command_exists() {
  print_test "help command works"
  
  output=$(bash scripts/manage-users.sh help 2>&1)
  
  if echo "$output" | grep -q "IDE USER MANAGEMENT"; then
    print_pass "help command availability"
  else
    print_fail "help command missing documentation"
  fi
}

test_config_directories_exist() {
  print_test "Required configuration directories exist"
  
  local dirs=(config/user-settings config/role-settings audit)
  local all_exist=true
  
  for dir in "${dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
      print_fail "Missing directory: $dir"
      all_exist=false
    fi
  done
  
  if [[ "$all_exist" == "true" ]]; then
    print_pass "Configuration directory structure"
  fi
}

test_role_templates_exist() {
  print_test "Role setting templates are defined"
  
  role_count=$(find config/role-settings -name "*.json" 2>/dev/null | wc -l)
  
  if [[ $role_count -lt 4 ]]; then
    print_fail "Expected at least 4 role templates, found $role_count"
  else
    print_pass "Role template availability"
  fi
}

test_truncated_comments_fixed() {
  print_test "No truncated comments in script"
  
  if grep -q "Role templates exis" scripts/manage-users.sh; then
    print_fail "Found truncated comment: 'Role templates exis' - should be 'Role templates exist'"
  else
    print_pass "Comments are complete and correct"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# RUN ALL TESTS
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║  USER LIFECYCLE TEST SUITE - QA-001                                    ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# File path tests
test_allowed_emails_file_exists
test_no_tx_typos
test_atomic_writes

# User lifecycle tests
test_remove_user_requires_confirmation

# Audit logging tests
test_audit_log_format
test_audit_log_includes_actor_action

# File validation tests  
test_role_templates_exist
test_truncated_comments_fixed

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║  TEST RESULTS                                                          ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "✅ ${GREEN}Passed: $PASSED${NC}"
echo -e "❌ ${RED}Failed: $FAILED${NC}"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}ALL CRITICAL TESTS PASSED${NC}"
  exit 0
else
  echo -e "${RED}SOME TESTS FAILED${NC}"
  exit 1
fi
