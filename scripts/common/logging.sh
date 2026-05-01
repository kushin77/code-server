#!/bin/bash
# ============================================================================
# Shell Script Logging Library
# Centralized logging functions with structured output and log levels
# Usage: source scripts/common/logging.sh
# ============================================================================

set -e
trap 'return 1' ERR

# Color codes for terminal output
readonly RED='\033[91m'
readonly GREEN='\033[92m'
readonly YELLOW='\033[93m'
readonly BLUE='\033[94m'
readonly CYAN='\033[96m'
readonly GRAY='\033[90m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# Log level configuration (can be overridden via LOG_LEVEL env var)
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FORMAT="${LOG_FORMAT:-text}"  # text, json, compact
SCRIPT_NAME="${SCRIPT_NAME:-$(basename "${BASH_SOURCE[0]}")}"
LOG_FILE="${LOG_FILE:-}"

# ============================================================================
# Utility Functions
# ============================================================================

# Check if output is a terminal (for colorization)
_is_tty() {
    [[ -t 2 ]] && return 0 || return 1
}

# Get current timestamp
_get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get log level value for comparison
_get_level_value() {
    local level="$1"
    case "$level" in
        DEBUG)   echo 0 ;;
        INFO)    echo 1 ;;
        WARN*)   echo 2 ;;
        ERROR)   echo 3 ;;
        FATAL|CRITICAL) echo 4 ;;
        *)       echo 1 ;;
    esac
}

# Check if a message should be logged based on log level
_should_log() {
    local msg_level="$1"
    local current_level="${LOG_LEVEL:-INFO}"
    
    local msg_val=$(_get_level_value "$msg_level")
    local current_val=$(_get_level_value "$current_level")
    
    [[ $msg_val -ge $current_val ]]
}

# ============================================================================
# Output Formatting
# ============================================================================

# Format message based on output format
_format_message() {
    local level="$1"
    local message="$2"
    shift 2
    
    case "$LOG_FORMAT" in
        json)
            # JSON format output
            printf '{"timestamp":"%s","level":"%s","script":"%s","message":"%s"' \
                "$(_get_timestamp)" "$level" "$SCRIPT_NAME" "$message"
            
            # Add context fields if provided
            while [[ $# -gt 0 ]]; do
                printf ',%s' "$1"
                shift
            done
            echo "}"
            ;;
        compact)
            # Compact format: [LEVEL] message
            echo "[$level] $message"
            ;;
        *)
            # Text format: [HH:MM:SS] message
            local timestamp=$(_get_timestamp)
            echo "[$timestamp] $message"
            ;;
    esac
}

# Apply color to message based on level
_colorize_message() {
    local level="$1"
    local message="$2"
    local color=""
    
    if ! _is_tty; then
        echo "$message"
        return
    fi
    
    case "$level" in
        DEBUG)   color="$GRAY" ;;
        INFO)    color="$BLUE" ;;
        WARN*)   color="$YELLOW" ;;
        ERROR)   color="$RED" ;;
        FATAL|CRITICAL) color="${RED}${BOLD}" ;;
        *)       color="$RESET" ;;
    esac
    
    echo -e "${color}${message}${RESET}"
}

# ============================================================================
# Logging Functions
# ============================================================================

log_debug() {
    local message="$1"
    _should_log "DEBUG" || return 0
    
    local formatted=$(_format_message "DEBUG" "$message")
    local output=$(_colorize_message "DEBUG" "$formatted")
    echo -e "$output" >&2
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted" >> "$LOG_FILE"
    fi
}

log_info() {
    local message="$1"
    _should_log "INFO" || return 0
    
    local formatted=$(_format_message "INFO" "$message")
    local output=$(_colorize_message "INFO" "$formatted")
    echo -e "$output" >&2
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted" >> "$LOG_FILE"
    fi
}

log_success() {
    local message="$1"
    _should_log "INFO" || return 0
    
    local msg_with_icon="✓ $message"
    local formatted=$(_format_message "INFO" "$msg_with_icon")
    local output=$(_colorize_message "INFO" "${GREEN}${formatted}${RESET}")
    echo -e "$output" >&2
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted" >> "$LOG_FILE"
    fi
}

log_warn() {
    local message="$1"
    _should_log "WARN" || return 0
    
    local msg_with_icon="⚠ $message"
    local formatted=$(_format_message "WARN" "$msg_with_icon")
    local output=$(_colorize_message "WARN" "$formatted")
    echo -e "$output" >&2
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted" >> "$LOG_FILE"
    fi
}

log_error() {
    local message="$1"
    _should_log "ERROR" || return 0
    
    local msg_with_icon="✗ $message"
    local formatted=$(_format_message "ERROR" "$msg_with_icon")
    local output=$(_colorize_message "ERROR" "$formatted")
    echo -e "$output" >&2
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted" >> "$LOG_FILE"
    fi
}

log_fatal() {
    local message="$1"
    
    local msg_with_icon="FATAL: $message"
    local formatted=$(_format_message "FATAL" "$msg_with_icon")
    local output=$(_colorize_message "FATAL" "${RED}${BOLD}${formatted}${RESET}")
    echo -e "$output" >&2
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted" >> "$LOG_FILE"
    fi
}

# Alias for compatibility
log_critical() {
    log_fatal "$@"
}

# ============================================================================
# Section/Header Logging
# ============================================================================

log_section() {
    local title="$1"
    local width=60
    
    echo "" >&2
    echo "$(printf '=%.0s' {1..60})" >&2
    echo "$title" >&2
    echo "$(printf '=%.0s' {1..60})" >&2
    echo "" >&2
}

log_subsection() {
    local title="$1"
    echo "" >&2
    echo "--- $title ---" >&2
}

# ============================================================================
# Status/Progress Logging
# ============================================================================

log_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-}"
    
    local percentage=$((current * 100 / total))
    local bar_width=20
    local filled=$((bar_width * current / total))
    
    local bar=$(printf '%*s' "$filled" | tr ' ' '=')
    local empty=$(printf '%*s' $((bar_width - filled)) | tr ' ' '-')
    
    local output="[$bar$empty] $percentage% ($current/$total)"
    if [[ -n "$message" ]]; then
        output="$output - $message"
    fi
    
    echo -e "$CYAN$output$RESET" >&2
}

log_table_header() {
    local -a columns=("$@")
    local output=""
    
    for col in "${columns[@]}"; do
        output="$output | $col"
    done
    
    echo "$output" >&2
    echo "$(printf '%*s' ${#output} | tr ' ' '-')" >&2
}

log_table_row() {
    local -a columns=("$@")
    local output=""
    
    for col in "${columns[@]}"; do
        output="$output | $col"
    done
    
    echo "$output" >&2
}

# ============================================================================
# Utility Logging
# ============================================================================

log_command() {
    local cmd="$1"
    log_debug "Executing: $cmd"
    eval "$cmd"
}

log_file() {
    local message="$1"
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    fi
}

# ============================================================================
# Initialization
# ============================================================================

# Export functions for use in subshells
export -f log_debug log_info log_success log_warn log_error log_fatal log_critical
export -f log_section log_subsection
export -f log_progress log_table_header log_table_row
export -f log_command log_file
export LOG_LEVEL LOG_FORMAT SCRIPT_NAME LOG_FILE
