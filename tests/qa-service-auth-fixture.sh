#!/bin/bash
# tests/qa-service-auth-fixture.sh - QA Service Account Test Fixture
# Purpose: Provides QA service authentication context for E2E tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ─────────────────────────────────────────────────────────────────────────────
# QA Service Identity
# ─────────────────────────────────────────────────────────────────────────────
QA_SERVICE_EMAIL="qa-service@ide.kushnir.cloud"
QA_SERVICE_ROLE="developer"
QA_SERVICE_ID="qa-service"

# ─────────────────────────────────────────────────────────────────────────────
# Export QA Service Context (for child processes)
# ─────────────────────────────────────────────────────────────────────────────
export QA_SERVICE_EMAIL
export QA_SERVICE_ROLE
export QA_SERVICE_ID

# ─────────────────────────────────────────────────────────────────────────────
# Setup QA Service Session
# ─────────────────────────────────────────────────────────────────────────────
setup_qa_session() {
  echo "[QA-FIXTURE] Setting up QA service session..."
  
  # Bootstrap QA service session
  export TEST_AUTH_MODE="mock"
  bash scripts/qa-service-bootstrap.sh bootstrap || {
    echo "[QA-FIXTURE] ERROR: Failed to bootstrap QA session"
    return 1
  }
  
  # Verify QA user exists in allowlist
  if ! grep -q "^${QA_SERVICE_EMAIL}$" allowed-emails.txt; then
    echo "[QA-FIXTURE] ERROR: QA service not in allowlist"
    return 1
  fi
  
  # Verify QA user configuration exists
  if [[ ! -f "config/user-settings/${QA_SERVICE_ID}/user-metadata.json" ]]; then
    echo "[QA-FIXTURE] ERROR: QA user metadata not found"
    return 1
  fi
  
  echo "[QA-FIXTURE] ✅ QA service session ready"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Get QA Service Session Token
# ─────────────────────────────────────────────────────────────────────────────
get_qa_token() {
  bash scripts/qa-service-bootstrap.sh token
}

# ─────────────────────────────────────────────────────────────────────────────
# Run Test as QA Service
# ─────────────────────────────────────────────────────────────────────────────
# Usage: run_as_qa_service <test_command> [args...]
run_as_qa_service() {
  local test_cmd="$1"
  shift || true
  
  echo "[QA-FIXTURE] Running as QA service: $test_cmd"
  
  # Setup session if not already setup
  if [[ ! -f ".qa-sessions/session-token" ]]; then
    setup_qa_session || return 1
  fi
  
  # Get current token
  local token=$(get_qa_token)
  
  # Export QA context
  export QA_SESSION_TOKEN="$token"
  export TEST_USER_IDENTITY="$QA_SERVICE_EMAIL"
  export TEST_USER_ROLE="$QA_SERVICE_ROLE"
  
  # Execute test command
  "$test_cmd" "$@"
}

# ─────────────────────────────────────────────────────────────────────────────
# Verify QA Service Configuration
# ─────────────────────────────────────────────────────────────────────────────
verify_qa_config() {
  echo "[QA-FIXTURE] Verifying QA service configuration..."
  
  local checks_passed=0
  local checks_total=4
  
  # Check 1: QA service in allowlist
  if grep -q "^${QA_SERVICE_EMAIL}$" allowed-emails.txt; then
    echo "[QA-FIXTURE] ✅ QA service email in allowlist"
    ((checks_passed++))
  else
    echo "[QA-FIXTURE] ❌ QA service email NOT in allowlist"
  fi
  
  # Check 2: QA user metadata exists
  if [[ -f "config/user-settings/${QA_SERVICE_ID}/user-metadata.json" ]]; then
    echo "[QA-FIXTURE] ✅ QA user metadata exists"
    ((checks_passed++))
  else
    echo "[QA-FIXTURE] ❌ QA user metadata NOT found"
  fi
  
  # Check 3: QA user role is correct
  if jq -e ".role == \"$QA_SERVICE_ROLE\"" "config/user-settings/${QA_SERVICE_ID}/user-metadata.json" > /dev/null 2>&1; then
    echo "[QA-FIXTURE] ✅ QA user role is correct ($QA_SERVICE_ROLE)"
    ((checks_passed++))
  else
    echo "[QA-FIXTURE] ❌ QA user role is incorrect"
  fi
  
  # Check 4: QA bootstrap script exists
  if [[ -f "scripts/qa-service-bootstrap.sh" ]]; then
    echo "[QA-FIXTURE] ✅ QA bootstrap script exists"
    ((checks_passed++))
  else
    echo "[QA-FIXTURE] ❌ QA bootstrap script NOT found"
  fi
  
  echo "[QA-FIXTURE] Configuration check: $checks_passed/$checks_total passed"
  
  if [[ $checks_passed -eq $checks_total ]]; then
    return 0
  else
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup QA Session
# ─────────────────────────────────────────────────────────────────────────────
cleanup_qa_session() {
  echo "[QA-FIXTURE] Cleaning up QA service session..."
  bash scripts/qa-service-bootstrap.sh revoke || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Main: If sourced, provide functions. If executed, run verification.
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-verify}" in
    verify)
      verify_qa_config
      ;;
    setup)
      setup_qa_session
      ;;
    cleanup)
      cleanup_qa_session
      ;;
    *)
      echo "Usage: $0 [verify|setup|cleanup]"
      exit 1
      ;;
  esac
fi
