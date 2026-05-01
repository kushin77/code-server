#!/bin/bash
set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"
# @file gh-wrapper.sh
# @module governance/ci
# @description Unified GitHub CLI wrapper with rate-limit awareness, retry logic, and governance enforcement
# @governance GOV-002

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# Configuration
# ============================================================================
readonly LOG_FILE="${LOG_FILE:-artifacts/gh-automation.log}"
readonly RETRY_COUNT="${RETRY_COUNT:-3}"
readonly RETRY_DELAY="${RETRY_DELAY:-5}"
readonly MAX_RETRIES_ON_RATE_LIMIT="${MAX_RETRIES_ON_RATE_LIMIT:-5}"
readonly RATE_LIMIT_THRESHOLD="${RATE_LIMIT_THRESHOLD:-100}"
readonly GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"

# ============================================================================
# Utilities
# ============================================================================

log() {
    local level="$1"
    local msg="$2"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$level] [GH-WRAPPER] $msg" | tee -a "$LOG_FILE"
}

validate_token() {
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log "ERROR" "GITHUB_TOKEN not set"
        return 1
    fi
    log "DEBUG" "GitHub token validation: OK"
    return 0
}

check_rate_limit() {
    local remaining limit
    # Add --repo for governance compliance
    remaining=$(gh api rate-limit --repo "$GITHUB_REPO" --jq '.resources.core.remaining' 2>/dev/null || echo "unknown")
    limit=$(gh api rate-limit --repo "$GITHUB_REPO" --jq '.resources.core.limit' 2>/dev/null || echo "unknown")
    
    if [[ "$remaining" != "unknown" ]]; then
        if [ "$remaining" -lt "$RATE_LIMIT_THRESHOLD" ]; then
            log "WARN" "Rate limit WARNING: $remaining/$limit remaining (threshold: $RATE_LIMIT_THRESHOLD)"
            return 1
        fi
        log "DEBUG" "Rate limit: $remaining/$limit"
    fi
    return 0
}

calculate_backoff() {
    local attempt=$1
    # Exponential backoff: 5s, 10s, 20s, 40s, etc.
    echo $((RETRY_DELAY * (2 ** (attempt - 1))))
}

# ============================================================================
# GitHub CLI Call Wrapper
# ============================================================================

gh_call() {
    local cmd=("$@")
    local attempt=1
    local exit_code
    local backoff
    
    log "DEBUG" "Executing: gh ${cmd[*]}"
    
    while [ $attempt -le $RETRY_COUNT ]; do
        # Always add --repo flag if not already present
        if [[ ! "${cmd[@]}" =~ --repo ]]; then
            cmd+=(--repo "$GITHUB_REPO")
            log "DEBUG" "Auto-adding --repo $GITHUB_REPO"
        fi
        
        # Try the call
        if gh "${cmd[@]}" 2>>"$LOG_FILE"; then
            log "INFO" "Command succeeded (Attempt $attempt/$RETRY_COUNT): gh ${cmd[*]}"
            return 0
        fi
        
        exit_code=$?
        log "WARN" "Command failed with exit code $exit_code (Attempt $attempt/$RETRY_COUNT): gh ${cmd[*]}"
        
        # Handle specific error codes
        if [ $exit_code -eq 429 ]; then
            log "WARN" "Rate limit (429) detected - backing off..."
            if [ $attempt -lt "$MAX_RETRIES_ON_RATE_LIMIT" ]; then
                backoff=$(calculate_backoff $attempt)
                log "WARN" "Sleeping for ${backoff}s before retry..."
                sleep "$backoff"
            else
                log "ERROR" "Max rate limit retries exceeded"
                return 1
            fi
        elif [ $exit_code -eq 403 ]; then
            log "WARN" "Permission denied (403) - checking token and repo scope..."
            if validate_token; then
                backoff=$(calculate_backoff $attempt)
                log "WARN" "Sleeping for ${backoff}s before retry..."
                sleep "$backoff"
            else
                log "ERROR" "Token invalid or insufficient scope"
                return 1
            fi
        elif [ $exit_code -eq 401 ]; then
            log "ERROR" "Authentication failed (401) - invalid or expired token"
            return 1
        else
            # Other errors: retry with backoff
            backoff=$(calculate_backoff $attempt)
            log "WARN" "Sleeping for ${backoff}s before retry..."
            sleep "$backoff"
        fi
        
        attempt+=1
    done
    
    log "ERROR" "Command failed permanently after $RETRY_COUNT attempts: gh ${cmd[*]}"
    return 1
}

# ============================================================================
# Public Subcommands
# ============================================================================

# Consolidated issue creation with governance enforcement
gh_issue_create() {
    local title="${1:-}"
    local body="${2:-}"
    local labels="${3:-P3}"
    
    if [[ -z "$title" ]]; then
        log "ERROR" "Issue title required"
        return 1
    fi
    
    # Ensure priority label is present
    if ! [[ "$labels" =~ P[0-3] ]]; then
        log "WARN" "No priority label detected - adding P3"
        labels="P3,$labels"
    fi
    
    log "INFO" "Creating issue: $title"
    gh_call issue create \
        --title "$title" \
        --body "$body" \
        $(for label in $(echo "$labels" | tr ',' '\n'); do echo "--label"; echo "$label"; done)
}

# List issues with repo scope
gh_issue_list() {
    gh_call issue list "$@"
}

# View issue with repo scope
gh_issue_view() {
    gh_call issue view "$@"
}

# Comment on issue with repo scope
gh_issue_comment() {
    gh_call issue comment "$@"
}

# Edit issue with repo scope
gh_issue_edit() {
    gh_call issue edit "$@"
}

# Close issue with repo scope
gh_issue_close() {
    gh_call issue close "$@"
}

# List PRs with repo scope
gh_pr_list() {
    gh_call pr list "$@"
}

# Comment on PR with repo scope
gh_pr_comment() {
    gh_call pr comment "$@"
}

# ============================================================================
# Main Entry Point
# ============================================================================

if [[ $# -eq 0 ]]; then
    log "ERROR" "Usage: $0 <command> [args...]"
    echo "Commands:"
    echo "  issue-create <title> [body] [labels]  - Create issue with governance"
    echo "  issue-list [gh-args...]               - List issues"
    echo "  issue-view [gh-args...]               - View issue"
    echo "  issue-comment [gh-args...]            - Comment on issue"
    echo "  issue-edit [gh-args...]               - Edit issue"
    echo "  issue-close [gh-args...]              - Close issue"
    echo "  pr-list [gh-args...]                  - List PRs"
    echo "  pr-comment [gh-args...]               - Comment on PR"
    exit 1
fi

# Validate setup
validate_token || exit 1
check_rate_limit || log "WARN" "Rate limit check failed"

# Route to subcommand
case "$1" in
    "issue-create")
        shift
        gh_issue_create "$@"
        ;;
    "issue-list")
        shift
        gh_issue_list "$@"
        ;;
    "issue-view")
        shift
        gh_issue_view "$@"
        ;;
    "issue-comment")
        shift
        gh_issue_comment "$@"
        ;;
    "issue-edit")
        shift
        gh_issue_edit "$@"
        ;;
    "issue-close")
        shift
        gh_issue_close "$@"
        ;;
    "pr-list")
        shift
        gh_pr_list "$@"
        ;;
    "pr-comment")
        shift
        gh_pr_comment "$@"
        ;;
    "rate-limit-check")
        check_rate_limit
        ;;
    *)
        log "ERROR" "Unknown command: $1"
        exit 1
        ;;
esac
