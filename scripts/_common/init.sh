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

# Load optional modules when present (do not fail if absent)
[[ -f "$_COMMON_DIR/docker.sh" ]] && source "$_COMMON_DIR/docker.sh"
[[ -f "$_COMMON_DIR/ssh.sh"    ]] && source "$_COMMON_DIR/ssh.sh"

# Ensure common safe-execution flags are set for the calling script
set -euo pipefail

# Global non-interactive defaults for automation reliability.
export CLOUDSDK_CORE_DISABLE_PROMPTS="${CLOUDSDK_CORE_DISABLE_PROMPTS:-1}"
export TF_INPUT="${TF_INPUT:-0}"
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

unset _COMMON_DIR
unset -f _load

log_debug "✓ _common/init.sh loaded (config + logging + utils + error-handler)"
