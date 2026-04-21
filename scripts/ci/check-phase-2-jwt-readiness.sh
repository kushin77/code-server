#!/usr/bin/env bash
# @file        scripts/ci/check-phase-2-jwt-readiness.sh
# @module      ci/validation
# @description Validates Phase 2 JWT service-to-service auth configuration readiness
# @status      ACTIVE

set -euo pipefail

# Import shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ────────────────────────────────────────────────────────────────────────────
# Configuration Readiness Checks
# ────────────────────────────────────────────────────────────────────────────

check_env_variables() {
  log_info "Checking Phase 2 JWT environment variables..."
  
  local required_vars=(
    "OIDC_ISSUER_URL"
    "OIDC_ISSUER_SIGNING_KEY"
    "SERVICE_CLIENT_SESSION_BROKER_ID"
    "SERVICE_CLIENT_SESSION_BROKER_SECRET"
    "SERVICE_CLIENT_BACKEND_ID"
    "SERVICE_CLIENT_BACKEND_SECRET"
    "IDE_SESSION_LB_SECRET"
  )
  
  local missing=()
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required Phase 2 variables: ${missing[*]}"
    return 1
  fi
  
  log_info "✓ All Phase 2 environment variables set"
  return 0
}

check_oidc_issuer_url() {
  log_info "Validating OIDC issuer connectivity..."
  
  local config_url="${OIDC_ISSUER_URL%/}/.well-known/openid-configuration"
  
  # Try up to 3 times with 2-second delay (service may be starting)
  for attempt in 1 2 3; do
    if curl -sf "$config_url" > /dev/null 2>&1; then
      log_info "✓ OIDC issuer responding at $OIDC_ISSUER_URL"
      return 0
    fi
    
    if [[ $attempt -lt 3 ]]; then
      log_warn "OIDC issuer not responding (attempt $attempt/3), retrying..."
      sleep 2
    fi
  done
  
  log_error "✗ OIDC issuer not responding at $OIDC_ISSUER_URL"
  return 1
}

check_jwks_endpoint() {
  log_info "Validating JWKS public key endpoint..."
  
  local jwks_url="${OIDC_ISSUER_URL%/}/.well-known/jwks.json"
  
  if ! curl -sf "$jwks_url" > /dev/null 2>&1; then
    log_error "✗ JWKS endpoint not responding at $jwks_url"
    return 1
  fi
  
  log_info "✓ JWKS endpoint accessible"
  return 0
}

check_token_issuance() {
  log_info "Testing JWT token acquisition..."
  
  local token_url="${OIDC_ISSUER_URL%/}/oauth2/token"
  
  # Request token using session-broker credentials
  local response
  response=$(curl -s -X POST "$token_url" \
    -d "grant_type=client_credentials" \
    -d "client_id=$SERVICE_CLIENT_SESSION_BROKER_ID" \
    -d "client_secret=$SERVICE_CLIENT_SESSION_BROKER_SECRET" \
    -d "scope=read:sessions write:sessions" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    2>&1)
  
  if echo "$response" | grep -q "access_token"; then
    log_info "✓ Token issuance successful for session-broker"
    return 0
  else
    log_error "✗ Token issuance failed: $response"
    return 1
  fi
}

check_variable_escaping() {
  log_info "Validating variable escaping (shell injection safety)..."
  
  # Check for unescaped special characters in secrets
  local secrets=(
    "SERVICE_CLIENT_SESSION_BROKER_SECRET"
    "SERVICE_CLIENT_BACKEND_SECRET"
    "IDE_SESSION_LB_SECRET"
  )
  
  local unsafe_patterns=('$' '`' '"' "'" ';' '|' '&' '<' '>')
  
  for secret_var in "${secrets[@]}"; do
    local secret_value="${!secret_var}"
    for pattern in "${unsafe_patterns[@]}"; do
      if [[ "$secret_value" == *"$pattern"* ]]; then
        log_warn "Potential shell injection character '$pattern' in $secret_var"
      fi
    done
  done
  
  log_info "✓ Variable escaping check complete"
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Docker Compose Integration Check
# ────────────────────────────────────────────────────────────────────────────

check_docker_compose_config() {
  log_info "Validating docker-compose Phase 2 configuration..."
  
  if ! grep -q "SERVICE_CLIENT_SESSION_BROKER_ID" docker-compose.yml; then
    log_error "✗ docker-compose.yml missing Phase 2 JWT variables"
    return 1
  fi
  
  log_info "✓ docker-compose.yml has Phase 2 JWT configuration"
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Main Execution
# ────────────────────────────────────────────────────────────────────────────

main() {
  log_info "=========================================="
  log_info "Phase 2 JWT Service-to-Service Readiness"
  log_info "=========================================="
  
  local checks=(
    "check_env_variables"
    "check_docker_compose_config"
    "check_oidc_issuer_url"
    "check_jwks_endpoint"
    "check_token_issuance"
    "check_variable_escaping"
  )
  
  local passed=0
  local failed=0
  
  for check in "${checks[@]}"; do
    if $check; then
      ((passed++))
    else
      ((failed++))
    fi
  done
  
  log_info ""
  log_info "Results: $passed passed, $failed failed"
  
  if [[ $failed -eq 0 ]]; then
    log_info "✓ Phase 2 JWT configuration is ready for deployment"
    return 0
  else
    log_error "✗ Phase 2 JWT configuration has $failed issue(s)"
    return 1
  fi
}

main "$@"
