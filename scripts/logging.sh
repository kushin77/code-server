#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
# scripts/logging.sh
# Shared logging functions for all bash deployment scripts.
# Source this file to get structured logging with timestamps.
# 
# USAGE:
#   source "$(dirname "$0")/logging.sh"
#   log "INFO" "Starting deployment..."
#   log "ERROR" "Something failed"
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Log file location (override if needed)
readonly LOG_FILE="${LOG_FILE:-.logs/deployment.log}"
readonly LOG_DIR="$(dirname "$LOG_FILE")"

# Ensure logs directory exists
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR" || true
fi

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

log() {
    <# Log message with timestamp and level
    Usage: log "INFO" "Message text"
           log "ERROR" "Error message"
    #>
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level="${1:-INFO}"
    shift  # Remove $1 from arguments
    local message="$*"
    
    local formatted
    formatted="[$timestamp] [$level] $message"
    
    # Color output based on level
    case "$level" in
        ERROR)
            echo -e "${RED}${formatted}${NC}" >&2
            ;;
        WARN|WARNING)
            echo -e "${YELLOW}${formatted}${NC}" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}${formatted}${NC}"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}${formatted}${NC}"
            fi
            ;;
        *)
            echo -e "${CYAN}${formatted}${NC}"
            ;;
    esac
    
    # Always write to file
    echo "$formatted" >> "$LOG_FILE"
}

log_info() {
    # Convenience function for INFO level
    log "INFO" "$@"
}

log_error() {
    # Convenience function for ERROR level
    log "ERROR" "$@"
}

log_warn() {
    # Convenience function for WARN level
    log "WARN" "$@"
}

log_success() {
    # Convenience function for SUCCESS level
    log "SUCCESS" "$@"
}

log_debug() {
    # Convenience function for DEBUG level
    log "DEBUG" "$@"
}

log_section() {
    # Log a section header with separator
    local title="$1"
    log "INFO" "════════════════════════════════════════════════════════════════════════════"
    log "INFO" "$title"
    log "INFO" "════════════════════════════════════════════════════════════════════════════"
}

# ─────────────────────────────────────────────────────────────────────────────
# ERROR HANDLING
# ─────────────────────────────────────────────────────────────────────────────

on_error() {
    # Called automatically on script error
    local line_number="$1"
    local error_code="$2"
    log_error "Command exited with status $error_code at line $line_number"
    exit "$error_code"
}

# Set error trap
trap 'on_error ${LINENO} $?' ERR

# ─────────────────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

run_command() {
    # Run a command with logging
    local description="$1"
    shift
    local command="$@"
    
    log_info "Running: $description"
    log_debug "Command: $command"
    
    if $command; then
        log_success "✓ $description completed successfully"
        return 0
    else
        log_error "✗ $description failed with exit code $?"
        return 1
    fi
}

verify_command_exists() {
    # Verify that a required command exists
    local cmd="$1"
    local description="${2:-$cmd}"
    
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$description is not installed or not in PATH"
        return 1
    fi
    
    log_debug "✓ $description found: $(command -v $cmd)"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# INITIALIZATION
# ─────────────────────────────────────────────────────────────────────────────

log_info "Logging system initialized (log file: $LOG_FILE)"
