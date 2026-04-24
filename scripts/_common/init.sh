#!/usr/bin/env bash
# @file        scripts/_common/init.sh
# @module      common/init
# @description Shared logging helpers and GitHub API utilities for repository scripts
# @governance GOV-002: Consolidated sourcing reduces dependency chains and improves maintainability
set -euo pipefail

# Source guards to prevent duplicate sourcing
[[ "${_SCRIPT_INIT_SOURCED:-0}" == "1" ]] && return 0
readonly _SCRIPT_INIT_SOURCED=1

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

source_env_file() {
  local env_file="$1"

  if [[ -f "${env_file}" ]]; then
    source <(tr -d '\r' < "${env_file}")
  fi
}

export -f source_env_file

# Source GitHub API client for scripts that need GitHub functionality
# P3 #1533: Consolidated sourcing pattern to reduce dependency chains
SCRIPT_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_COMMON_DIR}/github-api-client.sh" ]]; then
    source "${SCRIPT_COMMON_DIR}/github-api-client.sh"
fi