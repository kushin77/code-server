#!/bin/bash
###############################################################################
# DEVELOPER RESTRICTIONS PROFILE
# Issue #187: Read-Only IDE Access Control
#
# This script is sourced by /etc/profile.d/ to set up the restricted
# development environment for code-server terminal sessions.
#
# Installation:
#   sudo cp developer-restrictions.sh /etc/profile.d/
#   sudo chmod 644 /etc/profile.d/developer-restrictions.sh
#
###############################################################################

# Only run once per session
if [ -n "$__DEVELOPER_RESTRICTIONS_LOADED" ]; then
    return 0
fi
export __DEVELOPER_RESTRICTIONS_LOADED=1

# ==================== SESSION SETUP ====================

export DEVELOPER_SESSION_ID="${DEVELOPER_SESSION_ID:-$(uuidgen 2>/dev/null || echo 'unknown')}"
export DEVELOPER_USERNAME="${USER:-unknown}"
export DEVELOPER_HOSTNAME="${HOSTNAME:-localhost}"
export SESSION_START_TIME=$(date +%s)

# Log file for developer session
export DEVELOPER_SESSION_LOG="/var/log/developer-session-${DEVELOPER_USERNAME}-${DEVELOPER_SESSION_ID:0:8}.log"

# ==================== PATH CONFIGURATION ====================

# Ensure restricted shell is in PATH (if not already)
if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
    export PATH="/usr/local/bin:$PATH"
fi

# Add git proxy to PATH
export PATH="/usr/local/bin/git-credential-cloudflare-proxy:$PATH"

# ==================== SHELL ALIASES (SAFE VERSIONS) ====================

# Aliases are more user-friendly than blocking everything
# These provide "safe" alternatives to dangerous commands

# Safe archive operations (within /tmp/dev-session only)
alias archive_work='tar -czf /tmp/dev-session/archive-$(date +%s).tar.gz /home/${USER}/code/${PWD##*/}'
alias unarchive='tar -xzf'

# Safe git operations (all proxied)
alias git='git'  # Uses proxy via credential helper

# Safe file operations within project
alias edit='nano'  # Text editor (read/write to project files)
alias view='less'  # File viewer (read-only)

# Debugging and development (safe)
alias build='make'
alias test='./scripts/test.sh'
alias run='./scripts/run.sh'

# Navigation (safe)
alias code='cd /home/${USER}/code'
alias work='cd /tmp/dev-session'
alias logs='tail -f /var/log/*.log 2>/dev/null || echo "No logs readable"'

# ==================== FUNCTION DEFINITIONS ====================

# Safe git operations with logging
git() {
    # Log the git operation
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] GIT: $@" >> "$DEVELOPER_SESSION_LOG"
    
    # Allow git operations (credential helper will handle SSH key access)
    command git "$@"
}

# Safe project export (for code review purposes)
export_project_review() {
    local format="${1:-tar}"
    local output_dir="/tmp/dev-session"
    
    echo "Exporting project for review..."
    
    case "$format" in
        tar)
            echo "Creating tar.gz archive..."
            tar --exclude='.env' --exclude='*.key' --exclude='.ssh' \
                --exclude='.git/objects' --exclude='node_modules' \
                -czf "${output_dir}/project-review-$(date +%s).tar.gz" \
                /home/${USER}/code
            echo "Archive created: ${output_dir}/project-review-*.tar.gz"
            echo "Note: This file contains code ONLY (secrets filtered)"
            ;;
        zip)
            echo "Creating zip archive..."
            zip -r  -x '.env' '*.key' '.ssh*' 'node_modules/*' '.git/objects/*' \
                "${output_dir}/project-review-$(date +%s).zip" \
                /home/${USER}/code
            echo "Archive created: ${output_dir}/project-review-*.zip"
            ;;
        *)
            echo "Usage: export_project_review [tar|zip]"
            return 1
            ;;
    esac
}

# Security status check
security_status() {
    echo "=== DEVELOPER SESSION SECURITY STATUS ==="
    echo ""
    echo "Session Information:"
    echo "  User: ${DEVELOPER_USERNAME}"
    echo "  Session ID: ${DEVELOPER_SESSION_ID}"
    echo "  Started: $(date -d @${SESSION_START_TIME} 2>/dev/null || echo 'unknown')"
    echo "  Duration: $(($(date +%s) - SESSION_START_TIME)) seconds"
    echo ""
    echo "Shell Protection:"
    echo "  Shell: $(echo $0 | rev | cut -d/ -f1 | rev)"
    echo "  Restricted Shell: $(which restricted-shell 2>/dev/null || echo 'NOT FOUND')"
    echo ""
    echo "Directory Access:"
    echo "  Current Directory: $(pwd)"
    echo "  Allowed Work Areas:"
    for dir in /home/${USER}/code /tmp/dev-session /var/tmp/dev-work; do
        if [ -d "$dir" ]; then
            echo "    ✓ $dir ($(du -sh "$dir" 2>/dev/null | cut -f1 || echo '?'))"
        fi
    done
    echo ""
    echo "Restricted Paths (not accessible):"
    echo "    ✗ /root"
    echo "    ✗ ~/.ssh"
    echo "    ✗ ~/.aws"
    echo "    ✗ ~/.docker"
    echo ""
    echo "Session Log: $DEVELOPER_SESSION_LOG"
    echo ""
    echo "To view blocked commands:"
    echo "  tail -f /var/log/developer-commands.log"
    echo ""
}

# Session timeout warning
session_remaining() {
    local session_limit=14400  # 4 hours (matches Cloudflare Access default)
    local elapsed=$(($(date +%s) - SESSION_START_TIME))
    local remaining=$((session_limit - elapsed))
    
    if [ $remaining -le 0 ]; then
        echo "SESSION EXPIRED - Please reauthenticate"
        return 1
    fi
    
    local hours=$((remaining / 3600))
    local minutes=$(( (remaining % 3600) / 60 ))
    
    echo "Session time remaining: ${hours}h ${minutes}m"
}

# ==================== ENVIRONMENT VARIABLES ====================

# GIT Configuration for proxy
export GIT_PROXY_HOST="${GIT_PROXY_HOST:-git-proxy.ide.kushnir.cloud}"
export GIT_CREDENTIAL_CACHE_DAEMON_TIMEOUT=3600  # 1 hour

# Cloudflare Access Token (set via environment at login)
# This is injected by the authentication system
# export CLOUDFLARE_ACCESS_TOKEN="<token>"

# Node.js package manager (use npm, not yarn for security)
export NPM_REGISTRY="https://registry.npmjs.org"

# Python package manager (trusted index only)
export PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.org/simple}"

# ==================== SESSION INITIALIZATION ====================

# Create session log file
mkdir -p "$(dirname "$DEVELOPER_SESSION_LOG")" 2>/dev/null || true

# Log session start
{
    echo "=== DEVELOPER SESSION START ==="
    echo "User: ${DEVELOPER_USERNAME}"
    echo "Session ID: ${DEVELOPER_SESSION_ID}"
    echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Shell: $SHELL"
    echo "Working Directory: $(pwd)"
    echo "=========================="
    echo ""
} >> "$DEVELOPER_SESSION_LOG" 2>/dev/null || true

# ==================== STARTUP MESSAGE ====================

if [ -t 1 ]; then  # Only if connected to terminal
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                    CODE-SERVER READ-ONLY SESSION                          ║
╚════════════════════════════════════════════════════════════════════════════╝

SECURITY FEATURES ACTIVE:
  • SSH keys are protected on the home server (not accessible here)
  • Downloaded files are blocked (wget, curl -O, scp, etc.)
  • All commands are logged and monitored
  • Session expires after 4 hours (Cloudflare Access timeout)
  • Git operations are proxied through authenticated gateway

ALLOWED OPERATIONS:
  • View and edit code in /home/$USER/code
  • Run tests and builds
  • Use git (push/pull/commit) via proxy
  • Create temporary files in /tmp/dev-session
  • View logs and status information

BLOCKED OPERATIONS:
  • Download code files (wget, curl -O, scp)
  • Access to ~/.ssh, ~/.aws, ~/.docker, etc.
  • Direct SSH cloning (git@github.com)
  • SSH key operations
  • Low-level file manipulation (dd, strings, hexdump)

USEFUL COMMANDS:
  • security_status        - Shows session details and restrictions
  • session_remaining      - Shows time left in session
  • export_project_review  - Export code for review (secrets filtered)
  • git push/pull/clone    - All proxied through home server
  • code                   - Jump to project directory
  • work                   - Jump to temp work area

SUPPORT:
  If you encounter issues, contact your administrator.
  Session log: $DEVELOPER_SESSION_LOG
  All activity is logged for security audit.

════════════════════════════════════════════════════════════════════════════

EOF
fi

# ==================== CLEANUP (SESSION END) ====================

# Cleanup function to run when session exits
cleanup_session() {
    local session_duration=$(($(date +%s) - SESSION_START_TIME))
    
    {
        echo ""
        echo "=== DEVELOPER SESSION END ==="
        echo "End Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Duration: $((session_duration / 60)) minutes"
        echo "=========================="
    } >> "$DEVELOPER_SESSION_LOG" 2>/dev/null || true
    
    # Clean up credential cache
    rm -rf "/tmp/dev-git-creds-${DEVELOPER_USERNAME}-${DEVELOPER_SESSION_ID:0:8}" 2>/dev/null || true
    
    echo "Session logged. Thank you for using code-server."
}

trap cleanup_session EXIT

###############################################################################
# NOTES:
# 
# This profile script is sourced by /bin/bash when starting the shell.
# It sets up a secure environment for developers using code-server
# with read-only access.
#
# The restrictions are enforced through multiple layers:
# 1. Shell alias redirection (convenience)
# 2. restricted-shell wrapper (command blocking)
# 3. code-server config (IDE feature restrictions)
# 4. Cloudflare Access (network-level authentication)
# 5. Audit logging (detection and accountability)
#
###############################################################################
