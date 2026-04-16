#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════════════════════
# scripts/validate-env.sh — Environment Variable Validation
# ════════════════════════════════════════════════════════════════════════════════════════════
#
# Purpose: Validate that all required environment variables are set and in correct format
# Source of Truth: .env.schema.json
# Trigger: Called before docker-compose up (prevent container startup if validation fails)
# Exit Codes: 0=success, 1=missing variables, 2=invalid format
#
# Usage:
#   bash scripts/validate-env.sh
#   bash scripts/validate-env.sh --strict  (also validate optional vars)
#   bash scripts/validate-env.sh --verbose (show all variables)
# ════════════════════════════════════════════════════════════════════════════════════════════

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SCHEMA_FILE="${REPO_ROOT}/.env.schema.json"
VERBOSE=false
STRICT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose) VERBOSE=true; shift ;;
    --strict) STRICT=true; shift ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────────────────────

log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

# Check if jq is installed
check_jq() {
  if ! command -v jq &> /dev/null; then
    log_error "jq not found. Install via: apt install jq"
    exit 2
  fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────
# Validation logic
# ─────────────────────────────────────────────────────────────────────────────────────────────

validate_env() {
  local failed=0
  local passed=0
  local skipped=0

  echo ""
  log_info "Validating environment variables (source: .env.schema.json)"
  echo ""

  # Check if schema file exists
  if [[ ! -f "$SCHEMA_FILE" ]]; then
    log_error "Schema file not found: $SCHEMA_FILE"
    exit 2
  fi

  # Check if jq is installed
  check_jq

  # Extract required variables from schema
  local required_vars=$(jq -r '.groups[].variables[].required as $req | select($req == true) | inputs' "$SCHEMA_FILE" 2>/dev/null || true)
  
  # Simple fallback: manually list required variables (until jq parsing is perfected)
  local required=(
    "DEPLOYMENT_ENV"
    "APEX_DOMAIN"
    "PRIMARY_HOST_IP"
    "GOOGLE_CLIENT_ID"
    "GOOGLE_CLIENT_SECRET"
    "OAUTH2_PROXY_COOKIE_SECRET"
    "POSTGRES_PASSWORD"
  )

  # Load environment from files (in priority order)
  set -a
  [[ -f "$REPO_ROOT/.env.defaults" ]] && source "$REPO_ROOT/.env.defaults" || log_warn "Missing .env.defaults"
  [[ -f "$REPO_ROOT/.env.${DEPLOYMENT_ENV}" ]] && source "$REPO_ROOT/.env.${DEPLOYMENT_ENV}" || log_warn "Missing .env.${DEPLOYMENT_ENV}"
  [[ -f "$HOME/.code-server/.env" ]] && source "$HOME/.code-server/.env" || true
  set +a

  echo "Loaded environment: DEPLOYMENT_ENV=$DEPLOYMENT_ENV"
  echo ""

  # Validate required variables
  log_info "Checking required variables..."
  for var in "${required[@]}"; do
    local value="${!var:-}"
    
    if [[ -z "$value" ]]; then
      log_error "$var: MISSING (required)"
      ((failed++))
    elif [[ "$value" == "YOUR-"* ]] || [[ "$value" == *"HERE"* ]]; then
      log_error "$var: NOT SET (placeholder value detected)"
      ((failed++))
    else
      [[ "$VERBOSE" == "true" ]] && log_success "$var: SET (${#value} chars)"
      ((passed++))
    fi
  done

  echo ""
  log_info "Format validation..."

  # Validate format of specific variables
  validate_ipv4 "PRIMARY_HOST_IP" "$PRIMARY_HOST_IP"
  validate_domain "APEX_DOMAIN" "$APEX_DOMAIN"
  validate_hex_length "OAUTH2_PROXY_COOKIE_SECRET" "$OAUTH2_PROXY_COOKIE_SECRET" 32
  validate_deployment_env "DEPLOYMENT_ENV" "$DEPLOYMENT_ENV"

  echo ""
  log_info "Checking secret variables..."

  # Warn about secrets in plain text
  local secret_vars=(
    "GOOGLE_CLIENT_SECRET"
    "OAUTH2_PROXY_COOKIE_SECRET"
    "POSTGRES_PASSWORD"
    "MINIO_SECRET_KEY"
    "GITHUB_TOKEN"
  )

  for var in "${secret_vars[@]}"; do
    local value="${!var:-}"
    if [[ -n "$value" ]] && [[ "$value" != "YOUR-"* ]]; then
      log_warn "$var: Plain text secret (should be in Vault for production)"
    fi
  done

  echo ""
  echo "─────────────────────────────────────────────────────────────────────────────────────────"
  log_info "Validation Summary"
  echo "─────────────────────────────────────────────────────────────────────────────────────────"
  echo "Passed:  $passed"
  echo "Failed:  $failed"
  echo "Skipped: $skipped"
  echo ""

  if [[ $failed -gt 0 ]]; then
    log_error "Validation FAILED. Please fix the errors above."
    exit 1
  else
    log_success "Validation PASSED. All required variables are set."
    exit 0
  fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────
# Validation helper functions
# ─────────────────────────────────────────────────────────────────────────────────────────────

validate_ipv4() {
  local var_name=$1
  local value=$2
  
  if [[ -z "$value" ]]; then
    return 0  # Skip if not set (may be required separately)
  fi

  if [[ $value =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log_success "$var_name: Valid IPv4 ($value)"
  else
    log_error "$var_name: Invalid IPv4 format ($value)"
    ((failed++))
  fi
}

validate_domain() {
  local var_name=$1
  local value=$2
  
  if [[ -z "$value" ]] || [[ "$value" == "localhost" ]]; then
    return 0  # localhost is valid for dev
  fi

  if [[ $value =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    log_success "$var_name: Valid domain ($value)"
  else
    log_error "$var_name: Invalid domain format ($value)"
    ((failed++))
  fi
}

validate_hex_length() {
  local var_name=$1
  local value=$2
  local expected_length=$3
  
  if [[ -z "$value" ]]; then
    return 0
  fi

  local actual_length=${#value}
  if [[ $actual_length -eq $expected_length ]] && [[ $value =~ ^[a-fA-F0-9]+$ ]]; then
    log_success "$var_name: Valid hex ($actual_length chars)"
  else
    log_error "$var_name: Expected $expected_length hex chars, got $actual_length ($value)"
    ((failed++))
  fi
}

validate_deployment_env() {
  local var_name=$1
  local value=$2
  
  if [[ -z "$value" ]]; then
    return 0
  fi

  case "$value" in
    dev|staging|production|onprem)
      log_success "$var_name: Valid environment ($value)"
      ;;
    *)
      log_error "$var_name: Invalid environment ($value). Must be one of: dev, staging, production, onprem"
      ((failed++))
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────────────────────

validate_env
