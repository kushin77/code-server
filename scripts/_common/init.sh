#!/usr/bin/env bash
################################################################################
# File:          scripts/_common/init.sh
# Owner:         Platform Engineering
# Purpose:       Single bootstrap entrypoint for ALL scripts.
#                Replace 3-4 individual source lines with ONE.
# Compatibility: bash 4.0+
# Dependencies:  _common/config.sh, logging.sh, utils.sh, error-handler.sh
#
# USAGE (in every script — this is the ONLY source line needed)
#
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../_common/init.sh"
#
#   For scripts at the root of scripts/:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_common/init.sh"
#
# WHAT IT DOES
#   1. Sources config.sh     — environment constants (DEPLOY_HOST, DOMAIN, etc.)
#   2. Sources logging.sh    — log_info / log_warn / log_error / log_fatal functions
#   3. Sources utils.sh      — retry / require_command / require_file helpers
#   4. Sources error-handler.sh — ERR trap, stack trace, DEBUG mode
#   5. Sets shared safe flags: set -euo pipefail
#
# Last Updated:  April 14, 2026
################################################################################

# Guard against double-sourcing
[[ -n "${_COMMON_INIT_LOADED:-}" ]] && return 0
readonly _COMMON_INIT_LOADED=1

# Locate this file's directory regardless of where the caller lives
_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─────────────────────────────────────────────────────────────────────────────
# LOAD ORDER IS SIGNIFICANT:
#   config   → no dependencies
#   logging  → no dependencies
#   utils    → depends on logging (calls log_fatal / log_debug)
#   error-handler → depends on logging (calls log_error)
# ─────────────────────────────────────────────────────────────────────────────

_load() {
    local lib="$_COMMON_DIR/$1"
    if [[ ! -f "$lib" ]]; then
        echo "FATAL [init.sh]: Required library not found: $lib" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$lib"
}

_load "config.sh"
_load "logging.sh"
_load "utils.sh"
_load "error-handler.sh"

_ensure_pnpm() {
    if command -v pnpm >/dev/null 2>&1; then
        return 0
    fi

    if command -v corepack >/dev/null 2>&1; then
        corepack enable >/dev/null 2>&1 || true
        if command -v pnpm >/dev/null 2>&1; then
            return 0
        fi
    fi

    if command -v npm >/dev/null 2>&1; then
        pnpm() {
            npm exec --yes pnpm@9.15.4 -- "$@"
        }
        export -f pnpm
        log_debug "pnpm shim enabled via npm exec fallback"
        return 0
    fi

    log_warn "pnpm is unavailable; install pnpm or corepack for workspace scripts"
}

_ensure_pnpm

# Load optional modules when present (do not fail if absent)
[[ -f "$_COMMON_DIR/docker.sh" ]] && source "$_COMMON_DIR/docker.sh"
[[ -f "$_COMMON_DIR/ssh.sh"    ]] && source "$_COMMON_DIR/ssh.sh"

# ─────────────────────────────────────────────────────────────────────────────
# CORE LIFECYCLE FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Initialize repository context and environment
# Mandated by Rule 4: "initialize repo context"
init_repo() {
    log_debug "Initializing repository context..."
    
    # 1. Ensure we are in the repository root
    local root_dir
    root_dir="$(cd "$_COMMON_DIR/../.." && pwd)"
    cd "$root_dir" || log_fatal "Could not change directory to repository root: $root_dir"
    export REPO_ROOT="$root_dir"
    
    # 2. Load .env if present (Rule 3: GSM first, .env fallback)
    if [[ -f ".env" ]]; then
        log_debug "Found local .env, loading..."
        load_env ".env"
    fi
    
    # 3. Validation: Ensure essential vars from config.sh or .env exist
    # (Add critical vars here as needed)
    
    log_debug "✓ Repository context initialized at $REPO_ROOT"
}

# Ensure script is running as root
# Mandated by Rule 4
ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        log_fatal "This script must be run as root"
    fi
}

# Ensure script is NOT running as root
# Mandated by Rule 4
ensure_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_fatal "This script must not be run as root"
    fi
}

export -f init_repo ensure_root ensure_not_root

# Ensure common safe-execution flags are set for the calling script
set -euo pipefail

unset -f _load
unset -f _ensure_pnpm

log_debug "✓ _common/init.sh loaded (config + logging + utils + error-handler)"
