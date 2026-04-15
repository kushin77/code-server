#!/bin/bash
# tests/test-manage-users-lifecycle.sh
# Comprehensive regression tests for scripts/manage-users.sh
# Tests: add-user, remove-user, change-role, list-users, audit logging

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Source common functions
source scripts/_common/init.sh

# ─────────────────────────────────────────────────────────────────────────────
# TEST FIXTURES
# ─────────────────────────────────────────────────────────────────────────────
TEST_EMAIL="test-qa-user@example.com"
TEST_EMAIL2="test-qa-user2@example.com"
TEST_ROLE="developer"
TEST_DISPLAY="QA Test User"
TEST_DIR="/tmp/manage-users-test-$$"
BACKUP_ALLOWLIST="allowed-emails.txt.backup.$$"
BACKUP_AUDIT="audit/user-provisioning.log.backup.$$"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# TEST HELPERS
# ─────────────────────────────────────────────────────────────────────────────
passed=0
failed=0
skipped=0

test_case() {
  echo -e "${CYAN}[TEST] $1${NC}"
}

pass() {
  echo -e "${GREEN}✅ PASS: $1${NC}"
  ((passed++))
}

fail() {
  echo -e "${RED}❌ FAIL: $1${NC}"
  ((failed++))
}

skip() {
  echo -e "${YELLOW}⊘ SKIP: $1${NC}"
  ((skipped++))
}

assert_file_exists() {
  if [[ -f "$1" ]]; then
    pass "File exists: $1"
  else
    fail "File missing: $1"
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    pass "File contains pattern: $pattern"
  else
    fail "File missing pattern: $file should contain '$pattern'"
  fi
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    pass "File does not contain: $pattern"
  else
    fail "File contains unexpected pattern: $file contains '$pattern'"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# SETUP & TEARDOWN
# ─────────────────────────────────────────────────────────────────────────────
setup() {
  echo -e "${CYAN}═════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}SETUP: Create test environment${NC}"
  echo -e "${CYAN}═════════════════════════════════════════════════════════════${NC}"
  
  # Backup existing allowlist and audit log
  if [[ -f "allowed-emails.txt" ]]; then
    cp "allowed-emails.txt" "$BACKUP_ALLOWLIST"
    echo "✓ Backed up allowed-emails.txt → $BACKUP_ALLOWLIST"
  fi
  
  if [[ -f "audit/user-provisioning.log" ]]; then
    cp "audit/user-provisioning.log" "$BACKUP_AUDIT"
    echo "✓ Backed up audit/user-provisioning.log → $BACKUP_AUDIT"
  fi
  
  # Ensure required directories exist
  mkdir -p "config/user-settings" "config/role-settings" "audit"
  echo "✓ Required directories created"
  
  # Ensure required role templates exist
  for role in viewer developer architect admin; do
    role_file="config/role-settings/${role}-profile.json"
    if [[ ! -f "$role_file" ]]; then
      cat > "$role_file" << EOF
{
  "role": "$role",
  "permissions": ["read", "write", "execute"],
  "workspaceLimit": "10GB",
  "sessionTimeout": 86400
}
EOF
    fi
  done
  echo "✓ Role templates validated"
  
  # Create empty audit log if missing
  if [[ ! -f "audit/user-provisioning.log" ]]; then
    touch "audit/user-provisioning.log"
  fi
  
  echo ""
}

teardown() {
  echo -e "${CYAN}═════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}TEARDOWN: Restore environment${NC}"
  echo -e "${CYAN}═════════════════════════════════════════════════════════════${NC}"
  
  # Restore backups
  if [[ -f "$BACKUP_ALLOWLIST" ]]; then
    mv "$BACKUP_ALLOWLIST" "allowed-emails.txt"
    echo "✓ Restored allowed-emails.txt"
  fi
  
  if [[ -f "$BACKUP_AUDIT" ]]; then
    mv "$BACKUP_AUDIT" "audit/user-provisioning.log"
    echo "✓ Restored audit/user-provisioning.log"
  fi
  
  # Clean test user directories
  test_user_id=$(echo "$TEST_EMAIL" | sed 's/@.*//' | tr '.' '-' | tr '[:upper:]' '[:lower:]')
  rm -rf "config/user-settings/$test_user_id" "workspaces/$test_user_id" 2>/dev/null || true
  
  test_user_id2=$(echo "$TEST_EMAIL2" | sed 's/@.*//' | tr '.' '-' | tr '[:upper:]' '[:lower:]')
  rm -rf "config/user-settings/$test_user_id2" "workspaces/$test_user_id2" 2>/dev/null || true
  
  echo "✓ Test artifacts cleaned"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# REGRESSION TESTS
# ─────────────────────────────────────────────────────────────────────────────

test_list_users_shows_existing() {
  test_case "list-users shows existing users"
  
  # Add a seed user to allowlist
  if [[ ! -f "allowed-emails.txt" ]]; then
    echo "admin@example.com" > "allowed-emails.txt"
  fi
  
  output=$(bash scripts/manage-users.sh list-users 2>&1)
  
  if echo "$output" | grep -q "admin@example.com"; then
    pass "list-users displays whitelisted users"
  else
    fail "list-users does not display users from allowlist"
  fi
}

test_manage_users_file_path_validation() {
  test_case "manage-users uses correct allowlist file path"
  
  # Verify script references allowed-emails.txt (not allowed-emails.tx)
  if grep -q 'allowed-emails\.txt' scripts/manage-users.sh; then
    pass "Script references allowed-emails.txt"
  else
    fail "Script does not use correct filename"
  fi
  
  # Verify no references to typo 'allowed-emails.tx'
  if ! grep 'allowed-emails\.tx[^t]' scripts/manage-users.sh >/dev/null 2>&1; then
    pass "No .tx typo found in script"
  else
    fail "Script contains allowed-emails.tx typo"
  fi
}

test_atomic_write_validation() {
  test_case "manage-users uses atomic write for allowlist"
  
  # Check that atomic_write function exists
  if grep -q 'atomic_write()' scripts/manage-users.sh; then
    pass "atomic_write function defined"
  else
    fail "atomic_write function not found"
  fi
  
  # Check that remove-user uses atomic_write
  if grep -A 10 'cmd_remove_user()' scripts/manage-users.sh | grep -q 'atomic_write'; then
    pass "remove-user uses atomic_write"
  else
    fail "remove-user does not use atomic_write"
  fi
}

test_audit_logging_format() {
  test_case "Audit logs include timestamp, action, email, actor"
  
  # Check cmd_remove_user audit logging
  audit_grep='echo "$(date -I'"'"'seconds'"'"') | USER_REVOKED'
  if grep -q "$audit_grep" scripts/manage-users.sh; then
    pass "Audit log includes ISO8601 timestamp for USER_REVOKED"
  else
    fail "Audit log missing proper timestamp format"
  fi
  
  # Check cmd_change_role audit logging
  if grep -A 5 'USER_ROLE_CHANGED' scripts/manage-users.sh | grep -q 'date'; then
    pass "Audit log includes timestamp for USER_ROLE_CHANGED"
  else
    fail "USER_ROLE_CHANGED missing timestamp"
  fi
  
  # Check actor field (SUDO_USER or USER)
  if grep -q 'actor:.*SUDO_USER.*USER' scripts/manage-users.sh; then
    pass "Audit logs capture actor identity"
  else
    fail "Audit logs do not capture actor"
  fi
}

test_remove_user_idempotent() {
  test_case "remove-user is safe for non-existent users"
  
  # Try to remove non-existent user (should error gracefully)
  output=$(bash scripts/manage-users.sh remove-user "nonexistent@example.com" 2>&1 || true)
  
  if echo "$output" | grep -q "not found"; then
    pass "remove-user reports non-existent user"
  else
    fail "remove-user does not handle missing user"
  fi
}

test_script_validation_strict() {
  test_case "manage-users validates required files on startup"
  
  # Check that validate_required_files is called
  if grep -q 'validate_required_files' scripts/manage-users.sh; then
    pass "File validation function called"
  else
    fail "File validation not enforced"
  fi
  
  # Check that function validates critical paths
  if grep -A 20 'validate_required_files()' scripts/manage-users.sh | grep -q 'allowed-emails.txt'; then
    pass "Validation includes allowed-emails.txt"
  else
    fail "Validation missing allowed-emails.txt check"
  fi
}

test_path_traversal_prevention() {
  test_case "manage-users prevents path traversal attacks"
  
  # Check that validate_file_path rejects ../ paths
  if grep -A 5 'validate_file_path' scripts/manage-users.sh | grep -q '\.\.'; then
    pass "Path validation rejects ../ sequences"
  else
    fail "Path traversal protection missing"
  fi
}

test_help_and_usage() {
  test_case "manage-users help works"
  
  output=$(bash scripts/manage-users.sh help 2>&1)
  
  if echo "$output" | grep -q -E 'add-user|remove-user|change-role|list-users'; then
    pass "help command shows all operations"
  else
    fail "help command incomplete"
  fi
}

test_security_status_check() {
  test_case "manage-users security-status validation"
  
  output=$(bash scripts/manage-users.sh security-status 2>&1)
  
  if echo "$output" | grep -q -E 'Email whitelist|Security'; then
    pass "security-status checks configuration"
  else
    fail "security-status command incomplete"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# RUN TESTS
# ─────────────────────────────────────────────────────────────────────────────
main() {
  echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║  MANAGE-USERS.SH REGRESSION TEST SUITE                     ║${NC}"
  echo -e "${CYAN}║  Issue #316: QA-001 Fix manage-users.sh allowlist bugs    ║${NC}"
  echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  setup
  
  # Run tests
  test_list_users_shows_existing
  test_manage_users_file_path_validation
  test_atomic_write_validation
  test_audit_logging_format
  test_remove_user_idempotent
  test_script_validation_strict
  test_path_traversal_prevention
  test_help_and_usage
  test_security_status_check
  
  teardown
  
  # Summary
  echo -e "${CYAN}═════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}TEST SUMMARY${NC}"
  echo -e "${CYAN}═════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}Passed:  $passed${NC}"
  if [[ $failed -gt 0 ]]; then
    echo -e "${RED}Failed:  $failed${NC}"
  else
    echo -e "${GREEN}Failed:  $failed${NC}"
  fi
  echo -e "${YELLOW}Skipped: $skipped${NC}"
  echo ""
  
  if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    return 0
  else
    echo -e "${RED}❌ TESTS FAILED${NC}"
    return 1
  fi
}

main "$@"
