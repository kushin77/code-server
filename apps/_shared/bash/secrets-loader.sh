#!/usr/bin/env bash
# @file apps/_shared/bash/secrets-loader.sh
# @module shared/security
# @description Secure secrets loading from environment and external sources
# @governance GOV-003: Centralized secrets management with audit trail
# @exports load_secret, load_secret_file, validate_secret_configured, list_required_secrets

# Trap handlers for library
trap 'exit 1' ERR
trap ':' EXIT

# Prevent multiple sourcing
if [[ -n "${_SECRETS_LOADER_SOURCED:-}" ]]; then
  return 0
fi
_SECRETS_LOADER_SOURCED="true"

# Color codes
readonly COLOR_SUCCESS='\033[0;32m'
readonly COLOR_WARN='\033[1;33m'
readonly COLOR_ERROR='\033[0;31m'
readonly COLOR_RESET='\033[0m'

# Secrets audit log
SECRETS_AUDIT_LOG="${SECRETS_AUDIT_LOG:-./.secrets-audit.log}"
SECRETS_LOADED=()
SECRETS_MISSING=()

# ============================================================================
# CORE SECRET LOADING
# ============================================================================

load_secret() {
  local secret_name="$1"
  local default_value="${2:-}"
  local allow_empty="${3:-false}"
  
  # Check environment variable first
  if [[ -v "$secret_name" ]]; then
    local secret_value="${!secret_name}"
    
    if [[ -z "$secret_value" ]]; then
      if [[ "$allow_empty" == "false" ]]; then
        echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Secret empty: $secret_name"
        SECRETS_MISSING+=("$secret_name")
        return 1
      fi
    fi
    
    SECRETS_LOADED+=("$secret_name")
    echo -e "${COLOR_SUCCESS}[SecretsLoader]${COLOR_RESET} Loaded from env: $secret_name"
    echo "$secret_value"
    return 0
  fi
  
  # Check default value
  if [[ -n "$default_value" ]]; then
    echo -e "${COLOR_WARN}[SecretsLoader]${COLOR_RESET} Using default for: $secret_name"
    SECRETS_LOADED+=("$secret_name:default")
    echo "$default_value"
    return 0
  fi
  
  echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Secret not found: $secret_name"
  SECRETS_MISSING+=("$secret_name")
  return 1
}

load_secret_file() {
  local secret_name="$1"
  local file_path="$2"
  local allow_missing="${3:-false}"
  
  if [[ ! -f "$file_path" ]]; then
    if [[ "$allow_missing" == "true" ]]; then
      echo -e "${COLOR_WARN}[SecretsLoader]${COLOR_RESET} Secret file not found (allowed): $file_path"
      return 0
    else
      echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Secret file not found: $file_path"
      SECRETS_MISSING+=("$secret_name:file")
      return 1
    fi
  fi
  
  # Verify file permissions (should be readable only by owner)
  local file_perms=$(stat -c %a "$file_path" 2>/dev/null || echo "unknown")
  if [[ ! "$file_perms" =~ ^[4567]00$ ]]; then
    echo -e "${COLOR_WARN}[SecretsLoader]${COLOR_RESET} Secret file permissions loose: $file_path ($file_perms)"
  fi
  
  SECRETS_LOADED+=("$secret_name:file")
  echo -e "${COLOR_SUCCESS}[SecretsLoader]${COLOR_RESET} Loaded from file: $secret_name ($file_path)"
  
  cat "$file_path"
  return 0
}

# ============================================================================
# SECRET VALIDATION
# ============================================================================

validate_secret_configured() {
  local secret_name="$1"
  
  if [[ ! -v "$secret_name" ]] && [[ ${#SECRETS_LOADED[@]} -eq 0 ]]; then
    echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Secret not configured: $secret_name"
    return 1
  fi
  
  echo -e "${COLOR_SUCCESS}[SecretsLoader]${COLOR_RESET} Secret configured: $secret_name"
  return 0
}

validate_secret_not_empty() {
  local secret_name="$1"
  
  if [[ ! -v "$secret_name" ]]; then
    echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Secret not set: $secret_name"
    return 1
  fi
  
  if [[ -z "${!secret_name}" ]]; then
    echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Secret empty: $secret_name"
    return 1
  fi
  
  echo -e "${COLOR_SUCCESS}[SecretsLoader]${COLOR_RESET} Secret valid: $secret_name"
  return 0
}

validate_secret_format() {
  local secret_name="$1"
  local format_regex="$2"
  
  if [[ ! -v "$secret_name" ]]; then
    echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Secret not set: $secret_name"
    return 1
  fi
  
  local secret_value="${!secret_name}"
  
  if [[ ! "$secret_value" =~ $format_regex ]]; then
    echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Secret format invalid: $secret_name"
    return 1
  fi
  
  echo -e "${COLOR_SUCCESS}[SecretsLoader]${COLOR_RESET} Secret format valid: $secret_name"
  return 0
}

validate_secret_length() {
  local secret_name="$1"
  local min_length="${2:-8}"
  
  if [[ ! -v "$secret_name" ]]; then
    echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Secret not set: $secret_name"
    return 1
  fi
  
  local secret_value="${!secret_name}"
  local actual_length=${#secret_value}
  
  if [[ $actual_length -lt $min_length ]]; then
    echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Secret too short: $secret_name (${actual_length} < ${min_length})"
    return 1
  fi
  
  echo -e "${COLOR_SUCCESS}[SecretsLoader]${COLOR_RESET} Secret length valid: $secret_name (${actual_length})"
  return 0
}

# ============================================================================
# SECRETS MANAGEMENT
# ============================================================================

list_required_secrets() {
  shift
  local secrets=("$@")
  
  echo -e "${COLOR_SUCCESS}[SecretsLoader]${COLOR_RESET} Required secrets:"
  for secret in "${secrets[@]}"; do
    echo "  - $secret"
  done
}

validate_all_secrets() {
  shift
  local secrets=("$@")
  local failed=0
  
  for secret in "${secrets[@]}"; do
    if ! validate_secret_not_empty "$secret"; then
      failed+=1
    fi
  done
  
  if [[ $failed -eq 0 ]]; then
    echo -e "${COLOR_SUCCESS}[SecretsLoader]${COLOR_RESET} All ${#secrets[@]} required secrets configured"
    return 0
  else
    echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} ${failed} secrets missing or empty"
    return 1
  fi
}

# ============================================================================
# AUDIT AND LOGGING
# ============================================================================

audit_secret_access() {
  local secret_name="$1"
  local action="${2:-load}"
  
  local audit_entry="$(date -u +%Y-%m-%dT%H:%M:%SZ) [$action] $secret_name (user: $(whoami)@$(hostname))"
  echo "$audit_entry" >> "$SECRETS_AUDIT_LOG"
}

log_secrets_summary() {
  local total_loaded=${#SECRETS_LOADED[@]}
  local total_missing=${#SECRETS_MISSING[@]}
  
  echo
  echo -e "${COLOR_SUCCESS}[SecretsLoader]${COLOR_RESET} Summary:"
  echo "  Loaded:  $total_loaded"
  echo "  Missing: $total_missing"
  
  if [[ $total_missing -gt 0 ]]; then
    echo
    echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Missing secrets:"
    for secret in "${SECRETS_MISSING[@]}"; do
      echo "    - $secret"
    done
    return 1
  fi
  
  return 0
}

# ============================================================================
# COMMON SECRET PATTERNS
# ============================================================================

load_database_secrets() {
  local db_type="${1:-postgresql}"
  
  case "$db_type" in
    postgresql)
      load_secret "DATABASE_PASSWORD" || return 1
      load_secret "DATABASE_USER" "postgres"
      load_secret "DATABASE_HOST" "localhost"
      load_secret "DATABASE_PORT" "5432"
      ;;
    redis)
      load_secret "REDIS_PASSWORD" "" true  # Optional
      load_secret "REDIS_HOST" "localhost"
      load_secret "REDIS_PORT" "6379"
      ;;
    *)
      echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} Unknown database type: $db_type"
      return 1
      ;;
  esac
}

load_auth_secrets() {
  load_secret "AUTH_SECRET" || return 1
  load_secret "JWT_SECRET" || return 1
  load_secret "OAUTH_CLIENT_ID" || return 1
  load_secret "OAUTH_CLIENT_SECRET" || return 1
}

load_api_secrets() {
  load_secret "API_KEY" || return 1
  load_secret "API_SECRET" || return 1
  load_secret "API_TIMEOUT" "30"
}

# ============================================================================
# SECURE SECRET CLEARING
# ============================================================================

clear_secret() {
  local secret_name="$1"
  
  if [[ -v "$secret_name" ]]; then
    unset "$secret_name"
    echo -e "${COLOR_SUCCESS}[SecretsLoader]${COLOR_RESET} Secret cleared: $secret_name"
    audit_secret_access "$secret_name" "clear"
  fi
}

clear_all_secrets() {
  for secret in "${SECRETS_LOADED[@]}"; do
    secret_name="${secret%%:*}"
    clear_secret "$secret_name"
  done
}

# ============================================================================
# DEBUG MODE
# ============================================================================

enable_secrets_debug() {
  echo -e "${COLOR_WARN}[SecretsLoader]${COLOR_RESET} DEBUG: Secret sources loaded:"
  for secret in "${SECRETS_LOADED[@]}"; do
    echo "  - $secret"
  done
  
  if [[ ${#SECRETS_MISSING[@]} -gt 0 ]]; then
    echo -e "${COLOR_ERROR}[SecretsLoader]${COLOR_RESET} DEBUG: Missing secrets:"
    for secret in "${SECRETS_MISSING[@]}"; do
      echo "  - $secret"
    done
  fi
}

# Export all functions
export -f load_secret
export -f load_secret_file
export -f validate_secret_configured
export -f validate_secret_not_empty
export -f validate_secret_format
export -f validate_secret_length
export -f list_required_secrets
export -f validate_all_secrets
export -f audit_secret_access
export -f log_secrets_summary
export -f load_database_secrets
export -f load_auth_secrets
export -f load_api_secrets
export -f clear_secret
export -f clear_all_secrets
export -f enable_secrets_debug
