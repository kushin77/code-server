#!/bin/bash
# GOV-002 ENFORCED: Unified GitHub CLI Utility Wrapper
# This script provides a centralized, rate-limit aware wrapper for `gh` calls.

set -e

# Configuration
LOG_FILE="artifacts/gh-automation.log"
RETRY_COUNT=3
RETRY_DELAY=5

log() {
    local level=$1
    local msg=$2
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$level] [GH-WRAPPER] $msg" | tee -a "$LOG_FILE"
}

gh_call() {
    local cmd=("$@")
    local attempt=1
    
    while [ $attempt -le $RETRY_COUNT ]; do
        if gh "${cmd[@]}" 2>>"$LOG_FILE"; then
            return 0
        fi
        
        local exit_code=$?
        log "WARN" "Command failed with exit code $exit_code (Attempt $attempt/$RETRY_COUNT)"
        
        if [ $exit_code -eq 403 ] || [ $exit_code -eq 429 ]; then
            log "WARN" "Rate limit or permission issue detected. Backing off..."
            sleep $((RETRY_DELAY * attempt))
        fi
        
        ((attempt++))
    done
    
    log "ERROR" "Command failed permanently after $RETRY_COUNT attempts: gh ${cmd[*]}"
    return 1
}

# Subcommands
case "$1" in
    "issue-create")
        shift
        log "INFO" "Creating issue: $1"
        gh_call issue create "$@"
        ;;
    "pr-list")
        shift
        gh_call pr list "$@"
        ;;
    "repo-view")
        shift
        gh_call repo view "$@"
        ;;
    *)
        log "ERROR" "Unknown command: $1"
        exit 1
        ;;
esac
