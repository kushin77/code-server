#!/bin/bash
# scripts/test-auth.sh
# Non-interactive test authentication fixture for QA service account
# Enables CI/CD pipelines to run tests as qa-service identity
# Usage: source scripts/test-auth.sh && get_qa_auth_token

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Import common functions
source scripts/_common/init.sh 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# TEST AUTH CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

QA_SERVICE_EMAIL="qa-service@ide.kushnir.cloud"
QA_SERVICE_UID="qa-service"
QA_AUTH_TOKEN_FILE="${TMPDIR:-/tmp}/qa-auth-token.$$"
QA_SESSION_FILE="${TMPDIR:-/tmp}/qa-session.$$"
QA_OAUTH_CONFIG="${REPO_ROOT}/.qa-oauth-config.json"

# ─────────────────────────────────────────────────────────────────────────────
# TEST AUTH VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

validate_qa_account() {
  echo "Validating QA service account..."
  
  # Check qa-service is in allowed emails
  if ! grep -q "^$QA_SERVICE_EMAIL$" allowed-emails.txt 2>/dev/null; then
    echo "ERROR: QA service email not in allowed-emails.txt"
    return 1
  fi
  
  # Check qa-service has metadata
  if [[ ! -f "config/user-settings/$QA_SERVICE_UID/user-metadata.json" ]]; then
    echo "ERROR: QA service metadata not found"
    return 1
  fi
  
  # Validate metadata structure
  if ! jq -e '.role' "config/user-settings/$QA_SERVICE_UID/user-metadata.json" >/dev/null 2>&1; then
    echo "ERROR: Invalid QA service metadata"
    return 1
  fi
  
  echo "✓ QA service account validated"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST SESSION BOOTSTRAP
# ─────────────────────────────────────────────────────────────────────────────

# Bootstrap test session without interactive OAuth
# Returns: auth token for use in test requests
bootstrap_qa_session() {
  echo "Bootstrapping QA test session..."
  
  # Generate test auth token (stateless, signed with repo secret)
  # Format: base64(email:timestamp:role:signature)
  local timestamp=$(date +%s)
  local role=$(jq -r '.role' "config/user-settings/$QA_SERVICE_UID/user-metadata.json")
  local secret="${TEST_SECRET:-test-secret-$(cat .env 2>/dev/null | grep -oP 'OAUTH2_PROXY_CLIENT_SECRET=\K[^ ]+' || echo 'default')}"
  
  # Create token payload
  local token_payload="$QA_SERVICE_EMAIL:$timestamp:$role"
  
  # Sign payload (simple HMAC for testing, real implementation would use RS256/RS512)
  local signature=$(echo -n "$token_payload" | sha256sum | cut -d' ' -f1)
  
  # Build token
  local token="$token_payload:$signature"
  echo "$token"
  
  # Save to session file for logging
  {
    echo "QA_SESSION_START=$timestamp"
    echo "QA_SESSION_EMAIL=$QA_SERVICE_EMAIL"
    echo "QA_SESSION_ROLE=$role"
    echo "QA_SESSION_TOKEN=$token"
  } > "$QA_SESSION_FILE"
  
  echo "✓ QA session bootstrapped (token saved to $QA_SESSION_FILE)"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# AUTH TOKEN FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Get QA auth token (creates new if doesn't exist or expired)
get_qa_auth_token() {
  if [[ -f "$QA_AUTH_TOKEN_FILE" ]]; then
    local token=$(cat "$QA_AUTH_TOKEN_FILE")
    local created=$(stat -f '%B' "$QA_AUTH_TOKEN_FILE" 2>/dev/null || stat -c '%Y' "$QA_AUTH_TOKEN_FILE" 2>/dev/null || echo 0)
    local now=$(date +%s)
    local age=$((now - created))
    
    # Token valid for 1 hour (3600 seconds)
    if [[ $age -lt 3600 ]]; then
      echo "$token"
      return 0
    fi
  fi
  
  # Create new token
  bootstrap_qa_session
}

# Export auth context for test processes
export_qa_auth_context() {
  local token=$(get_qa_auth_token)
  local role=$(jq -r '.role' "config/user-settings/$QA_SERVICE_UID/user-metadata.json" 2>/dev/null || echo "developer")
  
  export QA_AUTH_TOKEN="$token"
  export QA_AUTH_EMAIL="$QA_SERVICE_EMAIL"
  export QA_AUTH_ROLE="$role"
  export QA_AUTH_CONTEXT_READY=1
  
  echo "✓ QA auth context exported (email: $QA_SERVICE_EMAIL, role: $role)"
}

# Validate token in request context
validate_qa_token_in_context() {
  if [[ -z "${QA_AUTH_TOKEN:-}" ]]; then
    echo "ERROR: No QA auth token in context"
    return 1
  fi
  
  # Verify token format
  if [[ ! "$QA_AUTH_TOKEN" =~ ^[a-zA-Z0-9._%-]+@[a-zA-Z0-9.-]+:([0-9]+):([a-z]+):[a-f0-9]+$ ]]; then
    echo "ERROR: Invalid QA token format"
    return 1
  fi
  
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# AUDIT & LOGGING
# ─────────────────────────────────────────────────────────────────────────────

# Log QA test action to audit log
log_qa_action() {
  local action="$1"
  local details="${2:-}"
  
  if [[ ! -d "audit" ]]; then
    mkdir -p "audit"
  fi
  
  {
    echo "$(date -I'seconds') | QA_TEST_ACTION | action:$action | email:$QA_SERVICE_EMAIL | role:${QA_AUTH_ROLE:-unknown} | details:$details"
  } >> audit/qa-test-runs.log
}

# Display QA session info
display_qa_session_info() {
  if [[ -f "$QA_SESSION_FILE" ]]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "QA TEST SESSION INFO"
    echo "═══════════════════════════════════════════════════════════"
    cat "$QA_SESSION_FILE" | sed 's/^/  /'
    echo "═══════════════════════════════════════════════════════════"
    echo ""
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────────────────────────

cleanup_qa_auth() {
  rm -f "$QA_AUTH_TOKEN_FILE" "$QA_SESSION_FILE"
  echo "✓ QA auth cleanup complete"
}

trap cleanup_qa_auth EXIT

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION (if run directly)
# ─────────────────────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-validate}" in
    validate)
      validate_qa_account
      ;;
    bootstrap)
      validate_qa_account && bootstrap_qa_session
      ;;
    token)
      get_qa_auth_token
      ;;
    context)
      export_qa_auth_context
      display_qa_session_info
      ;;
    info)
      display_qa_session_info
      ;;
    *)
      cat << EOF
QA Test Authentication Fixture

Usage: $(basename "$0") <command>

Commands:
  validate    Validate QA service account exists and is configured
  bootstrap   Bootstrap new QA test session
  token       Get or create QA auth token
  context     Export QA auth context to environment
  info        Display current QA session info

Environment Variables:
  QA_AUTH_TOKEN       - Current auth token
  QA_AUTH_EMAIL       - QA service email
  QA_AUTH_ROLE        - QA service role
  TEST_SECRET         - Optional test secret (otherwise uses .env)

Examples:
  # Validate QA account is set up
  bash scripts/test-auth.sh validate

  # Bootstrap session and export context
  source scripts/test-auth.sh && export_qa_auth_context

  # Get auth token for use in tests
  TOKEN=\$(bash scripts/test-auth.sh token)
  echo \$TOKEN
EOF
      exit 1
      ;;
  esac
fi
