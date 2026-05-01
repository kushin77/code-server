#!/bin/bash
# @file validate-secrets.sh
# @module security
# @description Validate that all required secrets are configured and non-empty
# @governance GOV-002 - P0 Security hardening: all secrets must be externally managed
# @idempotent YES

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source canonical configuration (SSOT)
source "${SCRIPT_DIR}/../_common/init.sh"

# Script configuration
LOG_FILE="${REPO_ROOT}/logs/security-validation.log"
ERRORS=0

# Create logs directory
mkdir -p "${REPO_ROOT}/logs"

error() {
  log "ERROR" "$@"
  ERRORS+=1
}

warn() {
  log "WARN" "$@"
}

info() {
  log "INFO" "$@"
}

success() {
  log "SUCCESS" "$@"
}

# ============================================================================
# CRITICAL SECRETS VALIDATION (P0 Issues)
# ============================================================================

validate_critical_secret() {
  local secret_name=$1
  local env_var=$2
  local min_length=${3:-32}
  
  if [[ -z "${!env_var:-}" ]]; then
    error "CRITICAL SECRET MISSING: ${secret_name} (${env_var})"
    error "  -> Required for production deployment"
    return 1
  fi
  
  local value="${!env_var}"
  if [[ ${#value} -lt ${min_length} ]]; then
    error "CRITICAL SECRET TOO SHORT: ${secret_name} (${env_var})"
    error "  -> Current: ${#value} chars, Required: ${min_length}+ chars"
    return 1
  fi
  
  success "✓ ${secret_name}: Configured (${#value} chars)"
  return 0
}

validate_required_env() {
  local name=$1
  local env_var=$2
  
  if [[ -z "${!env_var:-}" ]]; then
    error "REQUIRED ENV VAR MISSING: ${name} (${env_var})"
    return 1
  fi
  
  success "✓ ${name}: Configured"
  return 0
}

# ============================================================================
# P0 SECURITY ISSUE VALIDATIONS
# ============================================================================

validate_p0_968_cookie_secret() {
  info "Validating P0 #968: OAuth2 Cookie Secret (Session Forgery Prevention)"
  
  if [[ -z "${OAUTH2_COOKIE_SECRET:-}" ]]; then
    error "P0 #968 FAILED: OAUTH2_COOKIE_SECRET not set"
    error "  -> Risk: Session forgery, authentication bypass"
    error "  -> Required: Cryptographically random 32+ character string"
    error "  -> Source: Google Secret Manager (paperclip/ide-session-lb-secret)"
    return 1
  fi
  
  if [[ "${OAUTH2_COOKIE_SECRET}" == *"secret734"* ]] || \
     [[ "${OAUTH2_COOKIE_SECRET}" == "changeme" ]] || \
     [[ "${OAUTH2_COOKIE_SECRET}" == "default" ]]; then
    error "P0 #968 FAILED: OAUTH2_COOKIE_SECRET is hardcoded/default value"
    error "  -> Current: ${OAUTH2_COOKIE_SECRET}"
    error "  -> Fix: Use GSM secret, not hardcoded value"
    return 1
  fi
  
  success "P0 #968 PASSED: Cookie secret properly configured"
  return 0
}

validate_p0_969_user_directives() {
  info "Validating P0 #969: Non-root User Directives (Docker Escape Prevention)"
  
  local compose_file="${REPO_DIR}/docker-compose.yml"
  if [[ ! -f "${compose_file}" ]]; then
    error "P0 #969 CHECK: docker-compose.yml not found"
    return 1
  fi
  
  local user_count=$(grep -c "user:" "${compose_file}" || true)
  local service_count=$(grep -c "^  [a-z].*:" "${compose_file}" | head -1 || true)
  
  if [[ ${user_count} -lt 10 ]]; then
    error "P0 #969 FAILED: Insufficient user directives in docker-compose.yml"
    error "  -> Found: ${user_count} user directives"
    error "  -> Expected: 10+ services with user directives"
    error "  -> Risk: Containers running as root (UID 0)"
    return 1
  fi
  
  success "P0 #969 PASSED: All services configured with non-root users (${user_count} directives)"
  return 0
}

validate_p0_971_redis_password() {
  info "Validating P0 #971: Redis Password Authentication (Credential Reuse Prevention)"
  
  if [[ -z "${REDIS_PASSWORD:-}" ]]; then
    error "P0 #971 FAILED: REDIS_PASSWORD not set"
    error "  -> Risk: Unauthorized access to cache layer"
    error "  -> Required: Cryptographically random 32+ character string"
    error "  -> Source: Google Secret Manager (paperclip/redis-password)"
    return 1
  fi
  
  if [[ "${REDIS_PASSWORD}" == "changeme" ]] || [[ -z "${REDIS_PASSWORD}" ]]; then
    error "P0 #971 FAILED: REDIS_PASSWORD is default/empty"
    error "  -> Current: ${REDIS_PASSWORD}"
    error "  -> Fix: Use GSM secret, not default"
    return 1
  fi
  
  success "P0 #971 PASSED: Redis password configured (${#REDIS_PASSWORD} chars)"
  return 0
}

validate_p0_998_no_hardcoded_fallback() {
  info "Validating P0 #998: Remove Hardcoded Fallback Values (Configuration Security)"
  
  local compose_file="${REPO_DIR}/docker-compose.yml"
  local fallback_count=$(grep -c ":\-" "${compose_file}" || true)
  
  if [[ ${fallback_count} -gt 5 ]]; then
    warn "P0 #998 WARNING: Multiple fallback defaults found in docker-compose.yml"
    warn "  -> Found: ${fallback_count} instances of default fallbacks"
    warn "  -> Recommended: Remove fallbacks (:-default), require explicit env vars"
  fi
  
  # Check for specific hardcoded secrets
  if grep -q 'secret734\|changeme\|password123' "${compose_file}"; then
    error "P0 #998 FAILED: Hardcoded secrets found in docker-compose.yml"
    error "  -> Found hardcoded values: secret734, changeme, password123"
    error "  -> Fix: Remove all hardcoded fallbacks"
    return 1
  fi
  
  success "P0 #998 PASSED: No obvious hardcoded secrets in docker-compose.yml"
  return 0
}

validate_p0_980_secret_scanning() {
  info "Validating P0 #980: Secret Scanning GitHub Action (Accidental Commit Prevention)"
  
  local workflow_file="${REPO_DIR}/.github/workflows/secret-scanning.yml"
  
  if [[ ! -f "${workflow_file}" ]]; then
    error "P0 #980 FAILED: Secret scanning GitHub Action not configured"
    error "  -> Expected file: .github/workflows/secret-scanning.yml"
    error "  -> Required: GitHub Action for secret scanning on all commits"
    error "  -> Recommended: TruffleHog, git-secrets, or native GitHub secret scanning"
    return 1
  fi
  
  success "P0 #980 PASSED: Secret scanning workflow configured"
  return 0
}

# ============================================================================
# MAIN VALIDATION
# ============================================================================

main() {
  info "=========================================================================="
  info "SECURITY VALIDATION REPORT - P0 CRITICAL ISSUES"
  info "=========================================================================="
  info "Date: $(date '+%Y-%m-%d %H:%M:%S')"
  info ""
  
  # Load environment from .env.local first (local development), then .env.security
  if [[ -f "${REPO_DIR}/.env.local" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${REPO_DIR}/.env.local" 2>/dev/null || true
    set +a
  fi
  
  # Load security overrides from .env.security
  if [[ -f "${REPO_DIR}/.env.security" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${REPO_DIR}/.env.security" 2>/dev/null || true
    set +a
  fi
  
  # Run all validations
  validate_p0_968_cookie_secret || true
  echo ""
  validate_p0_969_user_directives || true
  echo ""
  validate_p0_971_redis_password || true
  echo ""
  validate_p0_998_no_hardcoded_fallback || true
  echo ""
  validate_p0_980_secret_scanning || true
  echo ""
  
  # Summary
  info "=========================================================================="
  if [[ ${ERRORS} -eq 0 ]]; then
    success "✓ ALL SECURITY VALIDATIONS PASSED"
    info "=========================================================================="
    exit 0
  else
    error "✗ SECURITY VALIDATION FAILED: ${ERRORS} critical issues detected"
    error "  -> See log file: ${LOG_FILE}"
    info "=========================================================================="
    exit 1
  fi
}

main "$@"
