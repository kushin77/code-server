#!/usr/bin/env bash
# @file scripts/_common/init.sh
# @description Common initialization and utility functions for infrastructure scripts

set -euo pipefail

# Error handling (Required by pre-commit hooks)
trap 'log_error "Common init failed at line $LINENO"; exit 1' ERR
trap ':' EXIT

# Colors and Formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Centralized Logging Framework
_log_base() {
    local level="$1"
    local color="$2"
    local message="$3"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    printf "${color}%-10s${NC} | %s | %s\n" "[${level}]" "${timestamp}" "${message}"
}

log_info() {
    _log_base "INFO" "${BLUE}" "$1"
}

log_success() {
    _log_base "SUCCESS" "${GREEN}" "$1"
}

log_warning() {
    _log_base "WARNING" "${YELLOW}" "$1"
}

log_error() {
    _log_base "ERROR" "${RED}" "$1" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        _log_base "DEBUG" "${CYAN}" "$1"
    fi
}

log_header() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}"
}

# Verify dependencies
check_dep() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Dependency '$1' is required but not installed."
        exit 1
    fi
}

# Ensure artifacts directory exists
ARTIFACTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../artifacts" && pwd)"
mkdir -p "$ARTIFACTS_DIR"

export ARTIFACTS_DIR

# ==============================================================================
# Utility functions for IaC compliance
# ==============================================================================

source_env_file() {
  local env_file="$1"

  if [[ -f "${env_file}" ]]; then
    # shellcheck disable=SC1090
    source <(tr -d '\r' < "${env_file}")
  fi
}

# Verify git state is clean (idempotency requirement)
verify_git_clean() {
  if [ -n "$(cd "${REPO_ROOT:-.}" && git status --porcelain 2>/dev/null)" ]; then
    log_warning "Git repository has uncommitted changes - idempotency may be affected"
    return 1
  fi
  return 0
}

# Get current Git SHA for immutable image tagging
get_git_sha() {
  cd "${REPO_ROOT:-.}" && git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

# Validate required environment variables
validate_required_env() {
  local required=("APEX_DOMAIN" "PRIMARY_HOST")
  for var in "${required[@]}"; do
    if [ -z "${!var:-}" ]; then
      log_error "Required environment variable \$${var} is not set"
      return 1
    fi
  done
  return 0
}

export -f source_env_file verify_git_clean get_git_sha validate_required_env
