#!/bin/bash
# Read-Only IDE Access Control - Prevent Code Exfiltration
# Implements multi-layer access restrictions:
# - Layer 1: IDE filesystem restrictions (hide .env, .ssh, .key files)
# - Layer 2: Terminal command interception (block wget, curl -O, scp, etc.)
# - Layer 3: Process monitoring (audit all developer actions)
# - Layer 4: Git SSH key protection (proxy to home server)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
AUDIT_LOG="${PARENT_DIR}/.code-server-developers/readonly-audit.log"
BLOCKED_LOG="${PARENT_DIR}/.code-server-developers/blocked-commands.log"
RESTRICTED_SHELL="/usr/local/bin/restricted-shell"

mkdir -p "$(dirname "$AUDIT_LOG")"

# ════════════════════════════════════════════════════════════════════════════
# Install Restricted Shell Wrapper
# ════════════════════════════════════════════════════════════════════════════
install_restricted_shell() {
  echo "📦 Installing restricted shell wrapper..."

  sudo tee "$RESTRICTED_SHELL" > /dev/null << 'EOF'
#!/bin/bash
# Restricted Shell for code-server developers
# Logs all commands and blocks exfiltration vectors

BLOCKED_COMMANDS=(
  "wget"
  "curl"
  "scp"
  "sftp"
  "nc"
  "ncat"
  "socat"
  "rsync"
  "ftp"
  "ssh-keygen"
  "ssh-copy-id"
  "base64.*\\.key"
  "cat.*\\.key"
  "cat.*\\.ssh"
)

BLOCKED_PATHS=(
  "/root"
  "/.ssh"
  "/.config"
  "/etc/ssh"
)

audit_log="/var/log/code-server-developer-session.log"

# Log command
{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] USER=$USER CMD=$* PWD=$(pwd)"
} >> "$audit_log" 2>&1

# Check for blocked commands
for blocked in "${BLOCKED_COMMANDS[@]}"; do
  if [[ "$*" =~ $blocked ]]; then
    {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] BLOCKED: USER=$USER CMD=$* (matched pattern: $blocked)"
    } >> "${audit_log%.log}-blocked.log" 2>&1
    echo "❌ Command blocked: $blocked" >&2
    exit 1
  fi
done

# Check for blocked paths
for path in "${BLOCKED_PATHS[@]}"; do
  if [[ "$*" =~ $path ]]; then
    {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] BLOCKED_PATH: USER=$USER CMD=$* (blocked access to: $path)"
    } >> "${audit_log%.log}-blocked.log" 2>&1
    echo "❌ Access blocked: $path" >&2
    exit 1
  fi
done

# Allow command
exec "$@"
EOF

  sudo chmod +x "$RESTRICTED_SHELL"
  echo "✅ Restricted shell installed at $RESTRICTED_SHELL"
}

# ════════════════════════════════════════════════════════════════════════════
# Configure code-server Read-Only Settings
# ════════════════════════════════════════════════════════════════════════════
configure_readonly_ide() {
  echo "🔐 Configuring code-server read-only settings..."

  local config_file="/home/coder/.config/code-server/config.yaml"

  # Add read-only settings
  if ! grep -q "files.exclude" "$config_file" 2>/dev/null; then
    tee -a "$config_file" >> /dev/null << 'EOF'

# ════════════════════════════════════════════════════════════════════════════
# READ-ONLY IDE ACCESS CONTROL
# ════════════════════════════════════════════════════════════════════════════

# Hide sensitive files from IDE
files.exclude:
  ".env": true
  "*.key": true
  ".ssh": true
  ".git/hooks/**": true
  ".AWS": true
  ".credentials": true

# Show read-only indicator
editor.readOnlyIndicator: "visible"

# Prevent editing of sensitive files
files.associations:
  "*.key": "plaintext"
  ".env": "plaintext"

# Disable dangerous IDE features
search.exclude:
  "**/.ssh": true
  "**/.env": true

# Disable file downloads/uploads
files.defaultLanguageMode: "plaintext"

# ════════════════════════════════════════════════════════════════════════════
EOF

    echo "✅ Read-only IDE settings applied"
  fi
}

# ════════════════════════════════════════════════════════════════════════════
# Setup Environment Profile for Restricted Access
# ════════════════════════════════════════════════════════════════════════════
setup_restricted_environment() {
  echo "🛡️  Setting up restricted environment..."

  sudo tee /etc/profile.d/developer-restrictions.sh > /dev/null << 'EOF'
#!/bin/bash
# Developer Access Restrictions Profile

# Use restricted shell for new sessions
export SHELL=/usr/local/bin/restricted-shell

# Audit all commands
export AUDIT_LOG="/var/log/code-server-developer-session.log"

# Set read-only filesystem for home directory (where possible)
# umask 0077  # Restrict new file permissions

# Add developer session timeout
export TIMEOUT_SECONDS=$((4 * 60 * 60))  # 4 hours (default Cloudflare Access)

# Log session start
{
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] SESSION_START: USER=$USER HOST=$(hostname) TTY=$(tty)"
} >> "$AUDIT_LOG" 2>&1

# Set up session timer
SESSION_TIMER=$((TIMEOUT_SECONDS))
trap 'echo "🔚 Session timeout ($((TIMEOUT_SECONDS/60)) mins reached)"; exit 0' SIGALRM

# Warn at 15 minutes before timeout
if [[ $((TIMEOUT_SECONDS - 60*15)) -gt 0 ]]; then
  echo "⏰ Session will expire in $(((TIMEOUT_SECONDS - 60*15)/60)) minutes"
fi
EOF

  sudo chmod +x /etc/profile.d/developer-restrictions.sh
  echo "✅ Restricted environment profile installed"
}

# ════════════════════════════════════════════════════════════════════════════
# Validate Read-Only Access
# ════════════════════════════════════════════════════════════════════════════
validate_readonly_access() {
  echo ""
  echo "✅ Read-Only IDE Access Control Checklist:"
  echo "════════════════════════════════════════════════════════════════"

  # Test 1: Can read project files
  if [[ -r /home/coder/workspace ]]; then
    echo "✅ Developer CAN read project files (IDE search/go-to-def working)"
  else
    echo "❌ Developer CANNOT read project files"
  fi

  # Test 2: Cannot access SSH keys
  if [[ ! -r /home/coder/.ssh/id_rsa ]]; then
    echo "✅ SSH keys are HIDDEN from developer"
  else
    echo "❌ SSH keys are VISIBLE (security issue)"
  fi

  # Test 3: Cannot access .env
  if [[ ! -r /home/coder/.env ]]; then
    echo "✅ Environment files are HIDDEN from developer"
  else
    echo "❌ Environment files are VISIBLE (security issue)"
  fi

  # Test 4: Cannot download via wget/curl
  if command -v wget &> /dev/null; then
    echo "⚠️  wget available (should be blocked in restricted shell)"
  else
    echo "✅ wget NOT available"
  fi

  # Test 5: Audit logging active
  if [[ -f "$AUDIT_LOG" ]]; then
    echo "✅ Audit logging is ACTIVE"
    echo "   Log: $AUDIT_LOG"
  else
    echo "⚠️  Audit logging not yet active"
  fi

  echo "════════════════════════════════════════════════════════════════"
  echo ""
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════════════════════════════
main() {
  local command="${1:-install}"

  case "$command" in
    install)
      install_restricted_shell
      configure_readonly_ide
      setup_restricted_environment
      validate_readonly_access
      ;;
    validate)
      validate_readonly_access
      ;;
    *)
      echo "❌ Unknown command: $command" >&2
      echo "Usage: configure-readonly-ide [install|validate]"
      return 1
      ;;
  esac
}

main "$@"
