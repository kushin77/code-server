#!/usr/bin/env bash
# @file        scripts/_common/init.sh
# @module      common/init
# @description Canonical bootstrap script for IaC lifecycle control (#1531)
# @governance GOV-002: All scripts MUST source this file for immutable, idempotent behavior
# @standard This file is the authoritative entry point for all deployment operations
set -euo pipefail

# Source guards to prevent duplicate sourcing
[[ "${_SCRIPT_INIT_SOURCED:-0}" == "1" ]] && return 0
readonly _SCRIPT_INIT_SOURCED=1

# ==============================================================================
# PHASE 1: Determine repo root and load canonical configuration
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

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

# JSON Formatter for SLOG integration
_slog_json() {
  local level="$1"
  shift
  local message="$*"
  # Sanitize message for JSON (escape double quotes)
  local sanitized_message="${message//\"/\\\"}"
  printf '{"timestamp": "%s", "level": "%s", "message": "%s", "host": "%s", "epic": "1532", "service": "shell-script"}\n' \
    "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$level" "$sanitized_message" "${HOSTNAME:-unknown}"
}

log_info() {
  if [[ "${STRUCTURED_LOGGING:-0}" == "1" ]]; then
    _slog_json "INFO" "$*"
  else
    printf '[%s] [INFO] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
  fi
}

log_success() {
  if [[ "${STRUCTURED_LOGGING:-0}" == "1" ]]; then
    _slog_json "SUCCESS" "$*"
  else
    printf '[%s] [SUCCESS] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
  fi
}

log_warn() {
  if [[ "${STRUCTURED_LOGGING:-0}" == "1" ]]; then
    _slog_json "WARN" "$*" >&2
  else
    printf '[%s] [WARN] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
  fi
}

log_warning() {
  log_warn "$@"
}

log_error() {
  if [[ "${STRUCTURED_LOGGING:-0}" == "1" ]]; then
    _slog_json "ERROR" "$*" >&2
  else
    printf '[%s] [ERROR] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
  fi
}

export -f log_info log_success log_warn log_warning log_error _slog_json

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

# Validate required environment variables
validate_required_env() {
  local required=("APEX_DOMAIN" "PRIMARY_HOST" "ADMIN_EMAIL")
  for var in "${required[@]}"; do
    if [ -z "${!var:-}" ]; then
      log_error "Required environment variable \$${var} is not set"
      return 1
    fi
  done
  return 0
}

export -f source_env_file verify_git_clean get_git_sha validate_required_env

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