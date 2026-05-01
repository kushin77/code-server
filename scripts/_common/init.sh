#!/usr/bin/env bash
# @file scripts/_common/init.sh
# @description Robust initialization for infrastructure scripts

set -u
set -o pipefail

# Error handling - minimalist to avoid recursion
trap 'echo "[FATAL] Initialization failure at line $LINENO" >&2; exit 1' ERR

# Logging functions without subshells
log_info() {
    printf "\033[0;34m[INFO]\033[0m    | $(date +'%Y-%m-%d %H:%M:%S') | %s\n" "${1:-}"
}
log_success() {
    printf "\033[0;32m[SUCCESS]\033[0m | $(date +'%Y-%m-%d %H:%M:%S') | %s\n" "${1:-}"
}
log_warning() {
    printf "\033[1;33m[WARNING]\033[0m | $(date +'%Y-%m-%d %H:%M:%S') | %s\n" "${1:-}"
}
log_error() {
    printf "\033[0;31m[ERROR]\033[0m   | $(date +'%Y-%m-%d %H:%M:%S') | %s\n" "${1:-}" >&2
}

# Path discovery
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT
mkdir -p "${REPO_ROOT}/artifacts"

# Compliance helpers
validate_required_env() {
    for var in "$@"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable $var is missing."
            return 1
        fi
    done
}

# Safely source KEY=VALUE style env files with optional comments and CRLF endings.
source_env_file() {
    local env_file="${1:-}"
    if [[ -z "${env_file}" || ! -f "${env_file}" ]]; then
        return 0
    fi

    # shellcheck disable=SC1090
    set -a
    source "${env_file}"
    set +a
}

# Auto-source environment variables with SSOT consolidation pattern
# Phase 3: .env consolidation - Load common defaults, then environment overrides
export ENVIRONMENT=${ENVIRONMENT:-private}

# Always load shared defaults
if [[ -f "${REPO_ROOT}/.env/_common/defaults" ]]; then
    source_env_file "${REPO_ROOT}/.env/_common/defaults"
else
    log_warning "Shared .env defaults not found at ${REPO_ROOT}/.env/_common/defaults"
fi

# Load environment-specific overrides
case "${ENVIRONMENT}" in
    private)
        if [[ -f "${REPO_ROOT}/.env/private/overrides" ]]; then
            source_env_file "${REPO_ROOT}/.env/private/overrides"
        fi
        ;;
    air-gapped)
        if [[ -f "${REPO_ROOT}/.env/air-gapped/overrides" ]]; then
            source_env_file "${REPO_ROOT}/.env/air-gapped/overrides"
        fi
        ;;
    *)
        log_warning "Unknown environment: ${ENVIRONMENT}. Defaults will be used."
        ;;
esac

# Legacy compatibility: Still source .env.deployment if it exists
if [[ -f "${REPO_ROOT}/.env.deployment" ]]; then
    source_env_file "${REPO_ROOT}/.env.deployment"
fi

trap - ERR
