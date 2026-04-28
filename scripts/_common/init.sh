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
