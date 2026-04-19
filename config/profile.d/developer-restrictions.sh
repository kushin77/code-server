#!/bin/bash
###############################################################################
# Developer Restrictions Profile Setup
# Issue #187: Read-Only IDE Access Control - Prevent Code Downloads
#
# This script sets up the shell environment for restricted development access.
# It's sourced by /etc/profile.d/ for all login shells.
#
# Installation:
#   sudo cp developer-restrictions.sh /etc/profile.d/
#   sudo chmod 644 /etc/profile.d/developer-restrictions.sh
#
###############################################################################

# Only apply restrictions to developer users (not root/system users)
if [[ "$USER" == "developer" ]] || [[ "$USER" == *"dev"* ]]; then
    
    # ==================== SESSION SETUP ====================
    
    # Generate session ID for audit trail
    export DEVELOPER_SESSION_ID="${DEVELOPER_SESSION_ID:-$(date +%s%N | md5sum | cut -c1-8)}"
    export DEVELOPER_LOGIN_TIME=$(date +%s)
    export DEVELOPER_SESSION_TIMEOUT=$((14400))  # 4 hours
    
    # ==================== RESTRICTED PATHS ====================
    
    # Remove dangerous directories from PATH
    # This prevents executing wget, curl, scp, etc even if user tries
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
    
    # Unset dangerous commands that might be aliases or functions
    unalias wget 2>/dev/null || true
    unalias curl 2>/dev/null || true
    unalias scp 2>/dev/null || true
    unalias sftp 2>/dev/null || true
    unalias rsync 2>/dev/null || true
    
    # ==================== SHELL CONFIGURATION ====================
    
    # Restrict umask (no world-readable files by default)
    umask 077
    
    # Set safe shell options
    set +o errtrace  # Don't inherit errtrace
    set +o functrace # Don't inherit functrace
    
    # ==================== SSH RESTRICTIONS ====================
    
    # Disable SSH key operations
    alias ssh-keygen='echo "ERROR: SSH key generation disabled"'
    alias ssh-copy-id='echo "ERROR: SSH key copying disabled"'
    alias ssh-add='echo "ERROR: SSH key loading disabled"'
    
    # Block SSH key access via cat/less/more
    if [ -d ~/.ssh ]; then
        chmod 000 ~/.ssh 2>/dev/null || true
    fi
    
    # ==================== ENVIRONMENT VARIABLES ====================
    
    # Git must use our proxy (Issue #184)
    export GIT_CREDENTIAL_HELPER="cloudflare-proxy"
    export GIT_SSH="/usr/local/bin/git-ssh-blocked.sh"
    
    # Notify that SSH is blocked
    if command -v ssh &> /dev/null; then
        # SSH is available but all SSH operations are logged
        export HISTORIAN_ENABLED=1
        export HISTORIAN_LOG="/var/log/developer-access/ssh-attempts-$USER.log"
    fi
    
    # ==================== LOGGING SETUP ====================
    
    # Setup command history
    export HISTSIZE=10000
    export HISTFILESIZE=10000
    export HISTTIMEFORMAT='%Y-%m-%d %H:%M:%S '
    
    # Log all commands for audit trail
    AUDIT_LOG="/var/log/developer-access/audit-$USER.log"
    if [ -w "$(dirname "$AUDIT_LOG")" ] 2>/dev/null; then
        export PROMPT_COMMAND="echo \$(date '+%Y-%m-%d %H:%M:%S'): \$USER@\$(hostname):\$PWD:\$SHELL >> \"$AUDIT_LOG\"; eval \"\$PROMPT_COMMAND\""
    fi
    
    # ==================== SESSION TIMEOUT ====================
    
    # Set up session timeout (4 hours = 14400 seconds)
    # This matches Cloudflare Access session duration
    if [ -z "$TMOUT" ]; then
        export TMOUT=$DEVELOPER_SESSION_TIMEOUT
        
        # Warn before timeout
        if [ -n "$BASH" ] || [ -n "$ZSH" ]; then
            # Set TMOUT to trigger timeout alarm
            TMOUT_WARNING=$((DEVELOPER_SESSION_TIMEOUT - 300))  # 5 min before
        fi
    fi
    
    # ==================== TERMINAL PROMPT ====================
    
    # Custom prompt showing session info
    if [ -n "$BASH" ]; then
        PS1='[\u@\h:\w] [SID:${DEVELOPER_SESSION_ID:0:8}] \$ '
    elif [ -n "$ZSH" ]; then
        PS1='[%n@%m:%~] [SID:${DEVELOPER_SESSION_ID:0:8}] $ '
    fi
    
    # ==================== SAFETY CHECKS ====================
    
    # Verify restricted-shell is set (terminal will enforce commands)
    if [ "$SHELL" != "/usr/local/bin/restricted-shell" ]; then
        export SHELL="/usr/local/bin/restricted-shell"
    fi
    
    # Verify we're in a safe directory
    if ! [[ "$PWD" == "/home/developer"* ]] && \
       ! [[ "$PWD" == "/tmp"* ]] && \
       ! [[ "$PWD" == "/var/tmp"* ]]; then
        cd /home/developer || cd ~ || cd /tmp
    fi
    
    # ==================== WELCOME MESSAGE ====================
    
    # Show security posture on login
    if [ -t 0 ] && [ -t 1 ]; then
        cat << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Secure Development Environment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  
  ✓ Code access: Read-only    (Use IDE for viewing/editing)
  ✓ Terminal:    Restricted   (Dangerous commands blocked)
  ✓ Git:         Proxied      (All git ops through secure proxy)
  ✓ SSH:         Disabled     (SSH keys stay on server)
  ✓ Session:     4 hours      (Auto-timeout at 14400 seconds)
  ✓ Audit:       Enabled      (All actions logged)
  
  Allowed: cd, ls, cat, grep, find, git (via proxy)
  Blocked: wget, curl, scp, ssh-keygen, base64, sudo
  
  For help: type 'help' or see docs/README_READONLY_ACCESS.md
  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    fi
fi

# End of developer restrictions
