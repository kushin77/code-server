#!/bin/bash
################################################################################
# Shared: error-handler.sh
# Purpose: Centralized error handling and debugging for scripts
# Usage: source "$(dirname "$0")/../_common/error-handler.sh"
# Features: Error trapping, stack traces, debugging mode
# Requirements: bash 4.0+
# Exit Codes: 0=success, 1=error (propagated)
# Author: DevOps Team
# Last Updated: April 14, 2026
################################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

DEBUG="${DEBUG:-0}"
SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─────────────────────────────────────────────────────────────────────────────
# ERROR HANDLING
# ─────────────────────────────────────────────────────────────────────────────

# Enhanced error handler with stack trace
_error_handler() {
    local line_no=$1
    local error_code=$2

    if [ "$error_code" != "0" ]; then
        log_error "Script failed with exit code $error_code at line $line_no"

        # Print stack trace if available
        if [ "$DEBUG" == "1" ]; then
            log_error "Stack trace:"
            local frame=0
            while caller $frame 2>/dev/null; do
                frame=$((frame + 1))
            done
        fi
    fi

    exit "$error_code"
}

# Install error trap
trap '_error_handler $LINENO $?' ERR

# ─────────────────────────────────────────────────────────────────────────────
# DEBUGGING
# ─────────────────────────────────────────────────────────────────────────────

# Enable debug mode (set -x equivalent with custom formatting)
enable_debug() {
    DEBUG=1
    log_info "Debug mode enabled"
    set -x
}

# Disable debug mode
disable_debug() {
    DEBUG=0
    set +x
    log_info "Debug mode disabled"
}

# Print debug information
print_debug() {
    if [ "$DEBUG" == "1" ]; then
        local msg="$@"
        log_debug "[DEBUG] $msg"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ASSERTION FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Assert that command succeeds
assert_success() {
    if ! "$@"; then
        log_fatal "Assertion failed: expected command to succeed: $@"
    fi
}

# Assert that command fails
assert_failure() {
    if "$@"; then
        log_fatal "Assertion failed: expected command to fail: $@"
    fi
}

# Assert equality
assert_equal() {
    local expected=$1
    local actual=$2
    local msg=${3:-""}

    if [ "$expected" != "$actual" ]; then
        log_fatal "Assertion failed: expected '$expected' but got '$actual' $msg"
    fi
}

# Assert not empty
assert_not_empty() {
    local value=$1
    local name=${2:-value}

    if [ -z "$value" ]; then
        log_fatal "Assertion failed: $name must not be empty"
    fi
}

# Assert file exists and is readable
assert_file() {
    local file=$1

    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        log_fatal "Assertion failed: file not found or not readable: $file"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# VALIDATION FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Validate command exit code
validate_exit() {
    local expected_code=$1
    shift
    local cmd="$@"

    "$@" > /dev/null 2>&1
    local actual_code=$?

    if [ "$actual_code" != "$expected_code" ]; then
        log_error "Command '$cmd' returned $actual_code, expected $expected_code"
        return 1
    fi

    log_debug "✓ Command returned expected exit code: $expected_code"
    return 0
}

# Check for required exit code
check_exit() {
    if [ $? -ne 0 ]; then
        log_error "Command failed with exit code: $?"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# CONTEXT STACK (for nested operations)
# ─────────────────────────────────────────────────────────────────────────────

declare -a CONTEXT_STACK=()

push_context() {
    local context=$1
    CONTEXT_STACK+=("$context")
    log_debug "Entering context: $context"
}

pop_context() {
    unset 'CONTEXT_STACK[-1]'
    log_debug "Exiting context"
}

get_context() {
    if [ ${#CONTEXT_STACK[@]} -gt 0 ]; then
        echo "${CONTEXT_STACK[-1]}"
    else
        echo "root"
    fi
}

# Use context for better error messages
with_context() {
    local context=$1
    shift

    push_context "$context"
    local exit_code=0

    if ! "$@"; then
        exit_code=$?
    fi

    pop_context
    return $exit_code
}

# ─────────────────────────────────────────────────────────────────────────────
# EXPORT
# ─────────────────────────────────────────────────────────────────────────────

export DEBUG SCRIPT_NAME SCRIPT_DIR
export -f enable_debug disable_debug print_debug
export -f assert_success assert_failure assert_equal assert_not_empty assert_file
export -f validate_exit check_exit
export -f push_context pop_context get_context with_context

# ─────────────────────────────────────────────────────────────────────────────
# PRECONDITION ASSERTIONS (contract enforcement at script startup)
# ─────────────────────────────────────────────────────────────────────────────

# Assert a required environment variable is set and non-empty
# Usage: assert_env DEPLOY_HOST
#        assert_env PASSWORD "Password must be set before running this script"
assert_env() {
    local var_name="$1"
    local hint="${2:-Set $var_name before running this script}"
    local value="${!var_name:-}"
    if [[ -z "$value" ]]; then
        log_fatal "Required environment variable '$var_name' is not set. $hint"
    fi
    log_debug "✓ Env var $var_name is set"
}

# Assert multiple environment variables are all set
# Usage: assert_envs DEPLOY_HOST DEPLOY_USER DOMAIN
assert_envs() {
    for var in "$@"; do
        assert_env "$var"
    done
}

# Assert Docker daemon is accessible on the remote deploy host
# Requires: ssh.sh to be loaded (uses ssh_exec)
# Usage: assert_docker
assert_docker() {
    if ! type ssh_exec &>/dev/null; then
        log_warn "assert_docker: ssh.sh not loaded — skipping remote docker check"
        return 0
    fi
    if ! ssh_exec "docker info > /dev/null 2>&1"; then
        log_fatal "Docker daemon is not accessible on $DEPLOY_USER@$DEPLOY_HOST"
    fi
    log_debug "✓ Docker daemon accessible on $DEPLOY_HOST"
}

# Assert current user has SSH key access to deploy host
# Usage: assert_deploy_access
assert_deploy_access() {
    if ! type assert_ssh_up &>/dev/null; then
        log_warn "assert_deploy_access: ssh.sh not loaded — skipping"
        return 0
    fi
    assert_ssh_up "$DEPLOY_HOST" "$DEPLOY_USER"
}

export -f assert_env assert_envs assert_docker assert_deploy_access
