#!/usr/bin/env bash
# @file        scripts/_common/init.sh
# @module      common/init
# @description Canonical bootstrap script for IaC lifecycle control (#1531)
# @governance GOV-002: All scripts MUST source this file for immutable, idempotent behavior
# @standard This file is the authoritative entry point for all deployment operations
set -euo pipefail

# Error handling (only applies to direct execution, not sourcing)
trap 'echo "Script failed at line $LINENO"; exit 1' ERR 2>/dev/null || true
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT 2>/dev/null || true

# Source guards to prevent duplicate sourcing
[[ "${_SCRIPT_INIT_SOURCED:-0}" == "1" ]] && return 0
readonly _SCRIPT_INIT_SOURCED=1

# ==============================================================================
# PHASE 1: Determine repo root and load canonical configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

# Load repo-local defaults first so strict canonical validation can pass in
# local dry-run and validation workflows without requiring callers to export
# every deployment variable up front.
if [ -f "${SCRIPT_DIR}/config.env" ]; then
  source <(tr -d '\r' < "${SCRIPT_DIR}/config.env")
fi

# Load canonical config (SSOT for all environment variables)
if [ -f "${SCRIPT_DIR}/_base-config.env" ]; then
  source <(tr -d '\r' < "${SCRIPT_DIR}/_base-config.env")
else
  echo "⚠️  WARNING: Canonical config not found at ${SCRIPT_DIR}/_base-config.env" >&2
fi

export REPO_ROOT SCRIPT_DIR

# ==============================================================================
# PHASE 2: Logging helpers (maintain backward compatibility)
# ==============================================================================

log_info() {
  printf '[%s] [INFO] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

log_success() {
  printf '[%s] [SUCCESS] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

log_warn() {
  printf '[%s] [WARN] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

log_warning() {
  log_warn "$@"
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

export -f log_info log_success log_warn log_warning log_error

# ==============================================================================
# PHASE 2.5: Color constants for terminal output (SSOT for all scripts)
# ==============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

export RED GREEN BLUE NC

# ==============================================================================
# PHASE 3: Utility functions for IaC compliance
# ==============================================================================

source_env_file() {
  local env_file="$1"

  if [[ -f "${env_file}" ]]; then
    source <(tr -d '\r' < "${env_file}")
  fi
}

# Verify git state is clean (idempotency requirement)
verify_git_clean() {
  if [ -n "$(cd "${REPO_ROOT}" && git status --porcelain 2>/dev/null)" ]; then
    log_warn "Git repository has uncommitted changes - idempotency may be affected"
    return 1
  fi
  return 0
}

# Get current Git SHA for immutable image tagging
get_git_sha() {
  cd "${REPO_ROOT}" && git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

# Validate required environment variables (fail-fast pattern)
validate_required_env() {
  # Allow custom validation via function override
  if declare -f _validate_required_env >/dev/null 2>&1; then
    _validate_required_env
    return $?
  fi

  # Default required variables for deployment
  local required=("APEX_DOMAIN" "PRIMARY_HOST" "REPLICA_HOST" "NAS_HOST" "ADMIN_EMAIL")
  
  # Allow caller to override with REQUIRED_ENV_VARS array
  if declare -p REQUIRED_ENV_VARS >/dev/null 2>&1; then
    required=("${REQUIRED_ENV_VARS[@]}")
  fi

  local missing_vars=()
  local var
  for var in "${required[@]}"; do
    if [ -z "${!var:-}" ]; then
      missing_vars+=("$var")
    fi
  done

  if [ ${#missing_vars[@]} -gt 0 ]; then
    log_error "Missing required environment variables: ${missing_vars[*]}"
    log_error "Ensure these are set before running deployment scripts"
    return 1
  fi

  return 0
}

# Require environment variable or fail fast (convenience wrapper)
require_env() {
  local var_name="$1"
  local default_value="${2:-}"
  
  if [ -z "${!var_name:-}" ] && [ -z "$default_value" ]; then
    log_error "Required environment variable \$${var_name} is not set"
    return 1
  fi
  
  if [ -z "${!var_name:-}" ]; then
    eval "export ${var_name}=\"${default_value}\""
    log_warn "Using default for ${var_name}: ${default_value}"
  fi
  return 0
}

# Validate a variable is not empty (fail-fast)
require_vars() {
  local -a missing=()
  for var in "$@"; do
    if [ -z "${!var:-}" ]; then
      missing+=("$var")
    fi
  done
  
  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Required environment variables missing: ${missing[*]}"
    return 1
  fi
  return 0
}

export -f source_env_file verify_git_clean get_git_sha validate_required_env require_env require_vars

# ==============================================================================
# PHASE 3.5: Docker Compose health check helpers (SSOT for deployment validation)
# ==============================================================================

# Count services in docker-compose configuration
services_running() {
  docker compose ps --services 2>/dev/null | wc -l | tr -d ' '
}

# Wait for all services to reach healthy state
wait_for_healthy_services() {
  local expected_count
  expected_count=$(services_running)

  local attempt=0
  while [[ $attempt -lt 24 ]]; do
    local healthy_count
    healthy_count=$(docker compose ps 2>/dev/null | grep -c "(healthy)" || true)

    if [[ "$healthy_count" -ge "$expected_count" && "$expected_count" -gt 0 ]]; then
      return 0
    fi

    sleep 5
    ((attempt++))
  done

  return 1
}

export -f services_running wait_for_healthy_services

# ==============================================================================
# PHASE 4: IaC idempotency tracking
# ==============================================================================

# Record bootstrap state for drift detection
BOOTSTRAP_STATE_DIR="${REPO_ROOT}/.bootstrap-state"
mkdir -p "${BOOTSTRAP_STATE_DIR}"

# Track initialization
cat > "${BOOTSTRAP_STATE_DIR}/init-$(date +%s).json" <<EOF 2>/dev/null || true
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "git_sha": "$(get_git_sha)",
  "git_branch": "$(cd "${REPO_ROOT}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')",
  "deployment_mode": "${DEPLOYMENT_MODE:-production}",
  "apex_domain": "${APEX_DOMAIN:-unknown}",
  "primary_host": "${PRIMARY_HOST:-unknown}"
}
EOF

log_info "Bootstrap initialized (source: ${BASH_SOURCE[0]})"

# ==============================================================================
# PHASE 5: GitHub API utilities (optional)
# ==============================================================================

# Source GitHub API client for scripts that need GitHub functionality
if [[ -f "${SCRIPT_DIR}/github-api-client.sh" ]]; then
    source "${SCRIPT_DIR}/github-api-client.sh"
fi

return 0 2>/dev/null || true