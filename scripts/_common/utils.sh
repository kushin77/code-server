#!/bin/bash
################################################################################
# Shared: utils.sh
# Purpose: Common utility functions for all scripts
# Usage: source "$(dirname "$0")/../_common/utils.sh"
# Features: Retry logic, prerequisite checks, cleanup handlers
# Requirements: bash 4.0+
# Exit Codes: 0=success, 1=error
# Author: DevOps Team
# Last Updated: April 14, 2026
################################################################################

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# RETRY LOGIC
# ─────────────────────────────────────────────────────────────────────────────

# Retry a command with exponential backoff
# Usage: retry 3 docker pull image:tag
retry() {
    local max_attempts=$1
    shift
    local cmd="$@"
    local attempt=1
    local delay=1
    
    while [ $attempt -le "$max_attempts" ]; do
        if eval "$cmd"; then
            return 0
        fi
        
        if [ $attempt -lt "$max_attempts" ]; then
            log_warn "Command failed (attempt $attempt/$max_attempts). Retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    log_error "Command failed after $max_attempts attempts: $cmd"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# PREREQUISITE CHECKING
# ─────────────────────────────────────────────────────────────────────────────

# Check if command exists
require_command() {
    local cmd=$1
    if ! command -v "$cmd" &>/dev/null; then
        log_fatal "Required command not found: $cmd"
    fi
    log_debug "✓ Found required command: $cmd"
}

# Check multiple commands
require_commands() {
    for cmd in "$@"; do
        require_command "$cmd"
    done
}

# Check if file exists
require_file() {
    local file=$1
    if [ ! -f "$file" ]; then
        log_fatal "Required file not found: $file"
    fi
    log_debug "✓ Found required file: $file"
}

# Check if directory exists
require_dir() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        log_fatal "Required directory not found: $dir"
    fi
    log_debug "✓ Found required directory: $dir"
}

# Check if environment variable is set
require_var() {
    local var=$1
    if [ -z "${!var:-}" ]; then
        log_fatal "Required environment variable not set: $var"
    fi
    log_debug "✓ Found required environment variable: $var"
}

# Ensure GitHub CLI/API auth is available.
# Priority:
#   1) GH_TOKEN/GITHUB_TOKEN from environment
#   2) Google Secret Manager PAT fallback (if gcloud available)
bootstrap_github_auth() {
    # Normalize token env vars first.
    if [[ -n "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]]; then
        export GITHUB_TOKEN="$GH_TOKEN"
    elif [[ -n "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]]; then
        export GH_TOKEN="$GITHUB_TOKEN"
    fi

    if [[ -n "${GH_TOKEN:-}" ]]; then
        log_debug "GitHub token already present in environment"
        return 0
    fi

    if ! command -v gcloud >/dev/null 2>&1; then
        log_warn "gcloud not found; cannot fetch GitHub PAT from GSM"
        return 1
    fi

    local gsm_project="${GSM_PROJECT:-nexusshield-prod}"
    local configured_secret="${GSM_GITHUB_TOKEN_SECRET:-}"
    local candidates=()

    if [[ -n "$configured_secret" ]]; then
        candidates+=("$configured_secret")
    fi
    candidates+=(
        "prod-github-token"
        "prod-github-pat"
        "prod-code-server-github-token"
        "github-token"
    )

    local secret_id value
    for secret_id in "${candidates[@]}"; do
        value=$(CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud --quiet secrets versions access latest \
            --secret="$secret_id" \
            --project="$gsm_project" 2>/dev/null || true)

        if [[ -n "$value" ]]; then
            export GITHUB_TOKEN="$value"
            export GH_TOKEN="$value"
            log_info "Loaded GitHub PAT from GSM secret: $secret_id"
            return 0
        fi
    done

    log_warn "No GitHub PAT secret found in GSM project '$gsm_project'"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP HANDLERS
# ─────────────────────────────────────────────────────────────────────────────

# Add cleanup function to be called on exit
add_cleanup() {
    local cleanup_func=$1
    if [ -z "${_CLEANUP_HANDLERS:-}" ]; then
        _CLEANUP_HANDLERS=()
        trap '_run_cleanup_handlers' EXIT INT TERM
    fi
    _CLEANUP_HANDLERS+=("$cleanup_func")
}

# Run all registered cleanup handlers
_run_cleanup_handlers() {
    local exit_code=$?
    for handler in "${_CLEANUP_HANDLERS[@]}"; do
        if declare -f "$handler" > /dev/null; then
            log_debug "Running cleanup: $handler"
            $handler || true  # Don't fail on cleanup errors
        fi
    done
    exit $exit_code
}

# ─────────────────────────────────────────────────────────────────────────────
# FILE OPERATIONS
# ─────────────────────────────────────────────────────────────────────────────

# Create temporary directory and register cleanup
mktemp_dir() {
    local temp_dir
    temp_dir=$(mktemp -d)
    log_debug "Created temporary directory: $temp_dir"
    
    _cleanup_tempdir() {
        if [ -d "$temp_dir" ]; then
            rm -rf "$temp_dir"
            log_debug "Cleaned up temporary directory: $temp_dir"
        fi
    }
    add_cleanup _cleanup_tempdir
    
    echo "$temp_dir"
}

# Safe copy with verification
copy_file() {
    local src=$1
    local dst=$2
    require_file "$src"
    cp "$src" "$dst"
    
    if ! diff -q "$src" "$dst" > /dev/null 2>&1; then
        log_error "File verification failed after copy: $src -> $dst"
        return 1
    fi
    log_info "✓ Copied file: $src -> $dst"
}

# ─────────────────────────────────────────────────────────────────────────────
# STRING UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

# Check if string contains substring
string_contains() {
    local string=$1
    local substring=$2
    if [[ "$string" == *"$substring"* ]]; then
        return 0
    else
        return 1
    fi
}

# Check if string matches regex
string_match() {
    local string=$1
    local regex=$2
    if [[ $string =~ $regex ]]; then
        return 0
    else
        return 1
    fi
}

# Trim whitespace
str_trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"  # Remove leading whitespace
    str="${str%"${str##*[![:space:]]}"}"  # Remove trailing whitespace
    echo "$str"
}

# ─────────────────────────────────────────────────────────────────────────────
# ARRAY UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

# Check if array contains element
array_contains() {
    local element=$1
    shift
    local arr=("$@")
    
    for item in "${arr[@]}"; do
        if [ "$item" == "$element" ]; then
            return 0
        fi
    done
    return 1
}

# Join array elements with separator
array_join() {
    local separator=$1
    shift
    local arr=("$@")
    
    local result=""
    for ((i=0; i<${#arr[@]}; i++)); do
        if [ $i -gt 0 ]; then
            result+="$separator"
        fi
        result+="${arr[i]}"
    done
    
    echo "$result"
}

# ─────────────────────────────────────────────────────────────────────────────
# DOCKER UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

# Check if Docker is running
docker_ready() {
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker is not running or not accessible"
        return 1
    fi
    log_debug "✓ Docker is ready"
}

# Wait for container to be healthy
docker_wait_healthy() {
    local container=$1
    local timeout=${2:-60}
    local elapsed=0
    local interval=2
    
    log_info "Waiting for container to be healthy: $container"
    
    while [ $elapsed -lt "$timeout" ]; do
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
        
        if [ "$health" == "healthy" ]; then
            log_success "Container is healthy: $container"
            return 0
        fi
        
        log_debug "Container health: $health (${elapsed}s/$timeout)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Container did not become healthy within ${timeout}s: $container"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# EXPORT
# ─────────────────────────────────────────────────────────────────────────────

export -f retry require_command require_commands require_file require_dir require_var
export -f add_cleanup mktemp_dir copy_file string_contains string_match str_trim
export -f array_contains array_join docker_ready docker_wait_healthy
export -f bootstrap_github_auth
