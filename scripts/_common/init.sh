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

# Auto-source environment variables if available
if [[ -f "${REPO_ROOT}/.env.deployment" ]]; then
    # Parse variables safely while avoiding export issues with comments/empty lines
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        # Strip potential quotes
        value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//')
        export "$key=$value"
    done < "${REPO_ROOT}/.env.deployment"
fi

trap - ERR
