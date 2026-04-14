#!/bin/bash
################################################################################
# Shared: logging.sh
# Purpose: Standardized logging functions for all scripts
# Usage: source "$(dirname "$0")/../_common/logging.sh"
# Level: Support debug, info, warn, error, fatal with colored output
# Requirements: bash 4.0+
# Exit Codes: 0=success, 1=error (for log_error/log_fatal)
# Author: DevOps Team
# Last Updated: April 14, 2026
################################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

# Color codes (can be disabled with LOG_NO_COLOR=1)
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_GRAY='\033[0;37m'
readonly COLOR_RESET='\033[0m'

# Log level configuration (0=debug, 1=info, 2=warn, 3=error, 4=fatal)
LOG_LEVEL="${LOG_LEVEL:-1}"
LOG_NO_COLOR="${LOG_NO_COLOR:-0}"
LOG_FILE="${LOG_FILE:-}"

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Get timestamp in ISO 8601 format
_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Get log level name
_level_name() {
    case "$1" in
        0) echo "DEBUG" ;;
        1) echo "INFO" ;;
        2) echo "WARN" ;;
        3) echo "ERROR" ;;
        4) echo "FATAL" ;;
        *) echo "UNKNOWN" ;;
    esac
}

# Apply color to level name
_colorize_level() {
    local level=$1
    local name=$2

    if [ "$LOG_NO_COLOR" == "1" ]; then
        echo "$name"
        return
    fi

    case "$level" in
        0) echo -e "${COLOR_GRAY}${name}${COLOR_RESET}" ;;      # DEBUG: gray
        1) echo -e "${COLOR_GREEN}${name}${COLOR_RESET}" ;;      # INFO: green
        2) echo -e "${COLOR_YELLOW}${name}${COLOR_RESET}" ;;     # WARN: yellow
        3) echo -e "${COLOR_RED}${name}${COLOR_RESET}" ;;        # ERROR: red
        4) echo -e "${COLOR_RED}${name}${COLOR_RESET}" ;;        # FATAL: red
        *) echo "$name" ;;
    esac
}

# Core logging function — supports both human text and JSON (Loki/Grafana) output
_log() {
    local level=$1
    shift
    local msg="$*"
    local level_name
    level_name=$(_level_name "$level")
    local timestamp
    timestamp=$(_timestamp)

    # Only log if level meets minimum threshold
    if [ "$level" -lt "$LOG_LEVEL" ]; then
        return 0
    fi

    # ── JSON mode (LOG_FORMAT=json) — for Loki / Grafana / log aggregation ──
    if [[ "${LOG_FORMAT:-text}" == "json" ]]; then
        # Escape double-quotes and backslashes in msg for valid JSON
        local json_msg="${msg//\\/\\\\}"
        json_msg="${json_msg//\"/\\\"}"
        local json_line="{\"ts\":\"$timestamp\",\"level\":\"$level_name\",\"script\":\"${SCRIPT_NAME:-$(basename "$0")}\",\"msg\":\"$json_msg\"}"
        case "$level" in
            0|1) echo "$json_line" >&1 ;;
            2|3|4) echo "$json_line" >&2 ;;
        esac
        if [ -n "${LOG_FILE:-}" ]; then
            echo "$json_line" >> "$LOG_FILE"
        fi
        return 0
    fi

    # ── Text mode (default) ──
    local colored_level
    colored_level=$(_colorize_level "$level" "$level_name")
    local formatted="[$timestamp] [$colored_level] $msg"
    local plain="[$timestamp] [$level_name] $msg"

    case "$level" in
        0|1) echo -e "$formatted" >&1 ;;
        2|3|4) echo -e "$formatted" >&2 ;;
    esac

    # Write plain (no ANSI) to log file if configured
    if [ -n "${LOG_FILE:-}" ]; then
        echo "$plain" >> "$LOG_FILE"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC LOGGING FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

log_debug() {
    _log 0 "$@"
}

log_info() {
    _log 1 "$@"
}

log_warn() {
    _log 2 "$@"
}

log_error() {
    _log 3 "$@"
    return 1
}

log_fatal() {
    _log 4 "$@"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# HELPER LOGGING FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Log a command before executing it
log_exec() {
    local cmd="$@"
    log_info "Executing: $cmd"
    "$@"
}

# Log variable state (useful for debugging)
log_var() {
    local name=$1
    local value=${!name:-<unset>}
    log_debug "$name=$value"
}

# Log section header
log_section() {
    local title="$@"
    echo ""
    log_info "───────────────────────────────────────────────────────────────"
    log_info "$title"
    log_info "───────────────────────────────────────────────────────────────"
}

# Log success message
log_success() {
    if [ "$LOG_NO_COLOR" == "1" ]; then
        log_info "✓ $@"
    else
        echo -e "${COLOR_GREEN}✓ $@${COLOR_RESET}"
    fi
}

# Log failure message
log_failure() {
    if [ "$LOG_NO_COLOR" == "1" ]; then
        log_error "✗ $@"
    else
        echo -e "${COLOR_RED}✗ $@${COLOR_RESET}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# EXPORT
# ─────────────────────────────────────────────────────────────────────────────

export LOG_LEVEL LOG_NO_COLOR LOG_FILE
