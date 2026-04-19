#!/usr/bin/env bash
################################################################################
# @file        scripts/_template.sh
# @module      category/subcategory
# @description Brief one-line purpose of this script
# @owner       platform
# @status      active
#
# USAGE
#   scripts/_template.sh [arg1] [arg2]
#
# ENVIRONMENT VARIABLES (from .env, loaded by _common/init.sh)
#   DEPLOY_HOST       - Production host IP/FQDN (e.g., 192.168.168.31)
#   DEPLOY_USER       - SSH user (e.g., akushnir)
#   DOMAIN            - Public domain (e.g., kushnir.cloud)
#
# EXIT CODES
#   0 - Success
#   1 - General error
#   2 - Config error
#   127 - Missing required command
#
# NOTES
#   - This script follows GOV-001 (Canonical Libraries) and GOV-002 (Metadata Headers)
#   - All configuration comes from environment variables, never hardcoded
#   - All errors use log_error / log_fatal from canonical logging library
#   - See scripts/_common/ for shared functions
#
# Last Updated: April 17, 2026
################################################################################

set -euo pipefail

################################################################################
# INITIALIZATION
################################################################################

# Get directory of this script and source the canonical initialization module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || {
    echo "FATAL: Cannot load _common/init.sh from $SCRIPT_DIR" >&2
    exit 1
}

# Canonical name for this script (used in logging/metrics)
SCRIPT_NAME="$(basename "$0")"

################################################################################
# CONFIGURATION & VALIDATION
################################################################################

# Declare all configuration variables here (sourced from environment by init.sh)
# Example:
# readonly DEPLOY_HOST="${DEPLOY_HOST:-}" # Will be set by .env or error via require_var
# readonly DEPLOY_USER="${DEPLOY_USER:-}"

# Validate required commands exist (use canonical helper from _common/utils.sh)
require_command "docker" "Docker is required to run this script"
require_command "curl" "curl is required for health checks"

# Validate required environment variables (from config.sh / init.sh)
# Example: require_var "DEPLOY_HOST" "Deployment host required"

################################################################################
# HELPER FUNCTIONS (script-specific, not in _common/)
################################################################################

# Example helper — follows canonical logging patterns
my_helper_function() {
    local arg="$1"
    log_info "Running helper with argument: $arg"
    
    # Use canonical error handling
    if [[ -z "$arg" ]]; then
        log_error "Argument cannot be empty"
        return 1
    fi
    
    log_debug "Helper completed successfully"
}

################################################################################
# MAIN SCRIPT LOGIC
################################################################################

main() {
    log_info "Starting $SCRIPT_NAME"
    
    # Example: process arguments
    local arg1="${1:-}"
    if [[ -z "$arg1" ]]; then
        log_error "Usage: $SCRIPT_NAME <arg1>"
        return 2
    fi
    
    # Call helper function with error checking
    if ! my_helper_function "$arg1"; then
        log_fatal "Helper failed, aborting"
    fi
    
    log_info "$SCRIPT_NAME completed successfully"
    return 0
}

################################################################################
# ENTRYPOINT
################################################################################

# Trap signals and ensure cleanup (error-handler.sh provides ERR trap)
trap cleanup EXIT

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "$SCRIPT_NAME exited with code $exit_code"
    fi
    return $exit_code
}

# Run main function and exit with its code
main "$@"
exit $?
