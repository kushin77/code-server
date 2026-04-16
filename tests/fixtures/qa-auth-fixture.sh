#!/bin/bash
# tests/fixtures/qa-auth-fixture.sh
# Test fixture for QA service account authentication
# Use in test scripts: source tests/fixtures/qa-auth-fixture.sh

# Source test-auth.sh
FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$FIXTURES_DIR/../.." && pwd)"
cd "$REPO_ROOT"

source scripts/test-auth.sh

# ─────────────────────────────────────────────────────────────────────────────
# HTTP Request Helpers with QA Auth
# ─────────────────────────────────────────────────────────────────────────────

# Make HTTP request as QA service account
qa_curl() {
  local method="${1:-GET}"
  local url="$2"
  local data="${3:-}"
  
  # Ensure QA context is ready
  if [[ -z "${QA_AUTH_CONTEXT_READY:-}" ]]; then
    export_qa_auth_context
  fi
  
  # Build curl command with QA auth headers
  local curl_opts=(
    -X "$method"
    -H "Authorization: Bearer $QA_AUTH_TOKEN"
    -H "X-QA-Service-Email: $QA_AUTH_EMAIL"
    -H "X-QA-Service-Role: $QA_AUTH_ROLE"
    -H "Content-Type: application/json"
  )
  
  # Add data if provided
  if [[ -n "$data" ]]; then
    curl_opts+=(-d "$data")
  fi
  
  # Execute request
  curl "${curl_opts[@]}" "$url"
}

# Make GET request as QA
qa_get() {
  qa_curl GET "$1"
}

# Make POST request as QA
qa_post() {
  qa_curl POST "$1" "$2"
}

# Make PUT request as QA
qa_put() {
  qa_curl PUT "$1" "$2"
}

# Check endpoint response as QA service
qa_assert_endpoint_available() {
  local url="$1"
  local expected_code="${2:-200}"
  
  if [[ -z "${QA_AUTH_CONTEXT_READY:-}" ]]; then
    export_qa_auth_context
  fi
  
  local response=$(qa_curl GET "$url" 2>&1)
  local http_code=$(echo "$response" | grep -oP 'HTTP/\d\.\d \K\d+' || echo "000")
  
  if [[ "$http_code" == "$expected_code" ]]; then
    return 0
  else
    echo "Expected HTTP $expected_code, got $http_code from $url"
    echo "Response: $response"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# QA Session Assertion Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Assert QA can read a file
qa_assert_can_read() {
  local path="$1"
  
  if [[ ! -r "$path" ]]; then
    echo "FAIL: QA cannot read $path"
    return 1
  fi
  return 0
}

# Assert QA can write to a directory
qa_assert_can_write() {
  local path="$1"
  local test_file="${path}/.qa-write-test"
  
  if ! touch "$test_file" 2>/dev/null; then
    echo "FAIL: QA cannot write to $path"
    return 1
  fi
  
  rm -f "$test_file"
  return 0
}

# Assert action is logged under QA identity
qa_assert_action_logged() {
  local action="$1"
  
  if ! grep -q "qa-service" audit/qa-test-runs.log 2>/dev/null; then
    echo "FAIL: QA action not logged"
    return 1
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Test Context Management
# ─────────────────────────────────────────────────────────────────────────────

# Begin QA test section (sets up context and logging)
qa_test_begin() {
  local test_name="$1"
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "QA TEST: $test_name"
  echo "════════════════════════════════════════════════════════════"
  echo ""
  
  # Initialize context
  export_qa_auth_context
  
  # Log test start
  log_qa_action "TEST_BEGIN" "test:$test_name"
  
  return 0
}

# End QA test section (cleanup and summary)
qa_test_end() {
  local test_name="$1"
  local passed="${2:-true}"
  
  if [[ "$passed" == "true" ]]; then
    log_qa_action "TEST_PASSED" "test:$test_name"
    echo "✓ QA test passed: $test_name"
  else
    log_qa_action "TEST_FAILED" "test:$test_name"
    echo "✗ QA test failed: $test_name"
  fi
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Initialize on source
# ─────────────────────────────────────────────────────────────────────────────

# Validate QA account immediately
if ! validate_qa_account >/dev/null 2>&1; then
  echo "WARNING: QA service account not fully configured"
  echo "Run: bash scripts/test-auth.sh validate"
fi

# Export QA context for all sourcing scripts
export_qa_auth_context
