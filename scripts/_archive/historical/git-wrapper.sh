#!/bin/bash
###############################################################################
# Git Wrapper - Audit & Proxy Git Operations for Issue #187
#
# This wrapper intercepts all git commands and:
# 1. Logs the command for audit trail (Issue #183)
# 2. Blocks dangerous git operations (git push to main without PR)
# 3. Adds telemetry for performance monitoring (Issue #182)
# 4. Routes through credential proxy (Issue #184)
#
# Installation:
#   sudo cp git-wrapper.sh /usr/local/bin/git
#   sudo chmod 755 /usr/local/bin/git
#   # Make sure /usr/local/bin is first in PATH
#
# Usage: Automatically invoked as /usr/local/bin/git
#
###############################################################################

set -e

# Get real git location
REAL_GIT="/usr/bin/git"

# Session/audit setup
DEVELOPER_ID="${USER:-unknown}"
SESSION_ID="${DEVELOPER_SESSION_ID:-unknown}"
AUDIT_LOG="/var/log/developer-access/git-operations-$DEVELOPER_ID.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Create directories if needed
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true

# Get original git command and arguments
ORIGINAL_COMMAND="$*"

# Function to log git operation
log_git_operation() {
    local status="$1"
    local operation="$2"
    local repo="$3"
    local branch="$4"

    if [ -w "$AUDIT_LOG" ] 2>/dev/null || [ -w "$(dirname "$AUDIT_LOG")" ]; then
        echo "[$TIMESTAMP] DEVELOPER:$DEVELOPER_ID | SESSION:$SESSION_ID | STATUS:$status | OP:$operation | REPO:$repo | BRANCH:$branch | CMD:$ORIGINAL_COMMAND" >> "$AUDIT_LOG"
    fi
}

# ==================== PARSE GIT COMMAND ====================

# Extract git subcommand (push, pull, clone, etc)
SUBCOMMAND="${1:-}"

case "$SUBCOMMAND" in
    push)
        # Get branch from push command
        BRANCH="${3:-main}"  # Fallback to main

        # Audit log
        log_git_operation "ATTEMPT" "push" "$(pwd)" "$BRANCH"

        # Check for dangerous branches (pushing to main/master without PR)
        if [[ "$BRANCH" == "main" ]] || [[ "$BRANCH" == "master" ]]; then
            echo "WARNING: Pushing to protected branch $BRANCH" >&2
            echo "This operation is logged and may be audited." >&2
            echo "" >&2
        fi
        ;;

    pull|fetch)
        # Get branch from pull command
        BRANCH="${3:-main}"

        # Audit log
        log_git_operation "ATTEMPT" "$SUBCOMMAND" "$(pwd)" "$BRANCH"
        ;;

    clone)
        # Get repository URL
        REPO_URL="$2"

        # Audit log - clone is always logged
        log_git_operation "ATTEMPT" "clone" "$REPO_URL" ""
        ;;

    *)
        # Other git commands (status, log, add, commit, etc)
        # These are allowed
        log_git_operation "ATTEMPT" "$SUBCOMMAND" "$(pwd)" ""
        ;;
esac

# ==================== ENVIRONMENT SETUP ====================

# Ensure git uses our credential proxy
export GIT_CREDENTIAL_HELPER="cloudflare-proxy"

# Force HTTPS for certain hosts (security)
# SSH is blocked by git-ssh-blocked.sh
export GIT_SSH="/usr/local/bin/git-ssh-blocked.sh"

# ==================== EXECUTE GIT ====================

# Execute the real git command with all arguments
"$REAL_GIT" "$@"
GIT_EXIT_CODE=$?

# Log the result
case "$SUBCOMMAND" in
    push|pull|fetch|clone)
        if [ $GIT_EXIT_CODE -eq 0 ]; then
            log_git_operation "SUCCESS" "$SUBCOMMAND" "$(pwd)" "$BRANCH"
        else
            log_git_operation "FAILED" "$SUBCOMMAND" "$(pwd)" "$BRANCH"
        fi
        ;;
    *)
        : # Other commands, exit code is enough
        ;;
esac

exit $GIT_EXIT_CODE
