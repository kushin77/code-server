#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# /usr/local/bin/restricted-shell
# Terminal command interceptor for read-only IDE access (Layer 3)
# 
# P1 Issue #187: Read-Only IDE Access Control
# Author: Platform Engineering
# License: AGPL-3.0
#
# This script wraps bash/sh and blocks dangerous commands while allowing
# developers to work productively within safe boundaries.
#
# Installation:
#   sudo cp scripts/restricted-shell.sh /usr/local/bin/restricted-shell
#   sudo chmod 755 /usr/local/bin/restricted-shell
#   
# Usage:
#   # Automatically invoked via code-server settings.json
#   # Or manually: /usr/local/bin/restricted-shell
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Source audit logging utilities
source "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-logger.sh" || true

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

readonly LOG_FILE="${LOG_FILE:-/var/log/code-server-audit.log}"
readonly DEVELOPER_ID="${DEVELOPER_ID:-${USER}}"
readonly SESSION_START="$(date -u +%s)"
readonly SESSION_ID="${SESSION_ID:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n1)}"

# Safe directories (developers CAN access)
readonly SAFE_DIRS=(
  "/home/${USER}/code"           # Project code
  "/home/${USER}/workspace"      # Workspace
  "/tmp/dev-session-${USER}"     # Named temp directory
  "/dev/null"                     # Utility
  "/dev/stdout"
  "/dev/stderr"
  "/dev/stdin"
)

# Dangerous commands (BLOCKED unconditionally)
readonly BLOCKED_COMMANDS=(
  "wget"
  "curl"                          # All curl variants
  "scp"
  "sftp"
  "rsync"
  "ftp"
  "nc"
  "ncat"
  "socat"
  "ssh-keygen"
  "ssh-copy-id"
  "ssh-agent"
  "ssh-add"
  "gpg"
  "openssl"
  "base64"                        # Can be used for key exfil
  "od"                            # Can dump binary data
  "xxd"
  "hexdump"
)

# Protected paths (developers CANNOT read)
readonly PROTECTED_PATHS=(
  ".env"
  ".env.*"
  "*.key"
  "*.pem"
  "*.p12"
  "*.pfx"
  "*.keystore"
  ".ssh"
  ".git/hooks"
  ".aws"
  ".kube"
  ".config/gcloud"
  ".vault-token"
)

# ─────────────────────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────────────────────

log_command() {
  local cmd="$1"
  local exit_code="${2:-0}"
  local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  echo "[${timestamp}] USER=${DEVELOPER_ID} SESSION=${SESSION_ID} CMD='${cmd}' EXIT=${exit_code}" >> "${LOG_FILE}" 2>/dev/null || true
}

check_blocked_command() {
  local cmd="$1"
  local cmd_base="$(basename "$cmd" 2>/dev/null || echo "$cmd")"
  
  for blocked in "${BLOCKED_COMMANDS[@]}"; do
    if [[ "$cmd_base" =~ ^${blocked}$ ]]; then
      return 0  # Command IS blocked
    fi
    # Catch variants: curl-config, wget-ssl, etc.
    if [[ "$cmd_base" =~ ^${blocked}[^a-z] ]]; then
      return 0
    fi
  done
  
  return 1  # Command is NOT blocked
}

is_safe_path() {
  local path="$1"
  local abs_path="$(cd "$(dirname "$path" 2>/dev/null)" && pwd)/$(basename "$path" 2>/dev/null)" || echo "$path"
  
  # Check protected patterns
  for protected in "${PROTECTED_PATHS[@]}"; do
    if [[ "$abs_path" =~ $protected ]]; then
      return 1  # Unsafe
    fi
  done
  
  # Check safe directories
  for safe in "${SAFE_DIRS[@]}"; do
    if [[ "$abs_path" =~ ^${safe} ]]; then
      return 0  # Safe
    fi
  done
  
  return 1  # Not in safe paths
}

deny_access() {
  local reason="$1"
  local cmd="${2:-unknown}"
  log_command "DENIED: $cmd ($reason)" 120
  echo "❌ Access denied: $reason" >&2
  exit 120
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Shell Loop
# ─────────────────────────────────────────────────────────────────────────────

# Session timeout: 4 hours (Cloudflare Access session duration)
readonly SESSION_TIMEOUT=$((4 * 3600))

# Start the restricted shell
function start_shell() {
  echo "🔒 Developer Session Started (Read-Only IDE)"
  echo "   Session ID: $SESSION_ID"
  echo "   User: $DEVELOPER_ID"
  echo "   Safe directories: ${SAFE_DIRS[0]}, ${SAFE_DIRS[1]}, ${SAFE_DIRS[2]}"
  echo "   All commands are being logged to: $LOG_FILE"
  echo ""
  
  # Set shell options for interception
  set +m  # Disable job control for easier command parsing
  
  # Main input loop - read and validate each command
  HISTFILE=""  # Disable history file (logs only to audit)
  
  while true; do
    PS1='developer@readonly:~$ '
    read -e -p "$PS1" cmd || true
    
    [[ -z "$cmd" ]] && continue
    
    # Check for session timeout
    local elapsed=$(($(date +%s) - SESSION_START))
    if [[ $elapsed -gt $SESSION_TIMEOUT ]]; then
      log_command "TIMEOUT: Session exceeded 4 hours" 124
      echo "❌ Session timeout exceeded (4 hour limit)"
      exit 124
    fi
    
    # Extract command name
    local cmd_array=($cmd)
    local cmd_name="${cmd_array[0]}"
    
    # Check for blocked commands
    if check_blocked_command "$cmd_name"; then
      deny_access "Command '${cmd_name}' is blocked in read-only mode" "$cmd"
      continue
    fi
    
    # Special handling for file operations
    case "$cmd_name" in
      cat|less|more|head|tail|grep|awk|sed)
        # Check if any arguments are protected files
        for arg in "${cmd_array[@]:1}"; do
          if is_safe_path "$arg"; then
            :  # Safe
          elif [[ "$arg" =~ ^- ]]; then
            :  # Is a flag
          else
            deny_access "Cannot access file: $arg" "$cmd"
            continue 2
          fi
        done
        ;;
      
      cd)
        local target="${cmd_array[1]:-.}"
        if ! is_safe_path "$target"; then
          deny_access "Cannot change to directory: $target" "$cmd"
          continue
        fi
        ;;
      
      rm|mv|cp|rmdir|mkdir)
        deny_access "File modification operations are disabled" "$cmd"
        continue
        ;;
    esac
    
    # Execute command in restricted context
    local exit_code=0
    {
      eval "$cmd"
    } || exit_code=$?
    
    log_command "$cmd" "$exit_code"
  done
}

# Start the restricted shell session
start_shell
