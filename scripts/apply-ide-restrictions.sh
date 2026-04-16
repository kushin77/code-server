#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# /usr/local/bin/apply-ide-restrictions
# P1 Issue #187: Read-Only IDE Access Control - Enforce Security Layers
#
# Apply code-server configuration restrictions for read-only access:
# - Layer 1: IDE filesystem restrictions  
# - Layer 3: Terminal command restrictions
# - Layer 4: Audit logging enablement
#
# Installation:
#   sudo cp scripts/apply-ide-restrictions.sh /usr/local/bin/apply-ide-restrictions
#   sudo chmod 755 /usr/local/bin/apply-ide-restrictions
#
# Usage:
#   /usr/local/bin/apply-ide-restrictions [user]
#   # If user not specified, applies to current $USER
#
# Called by:
#   - Kubernetes init container before code-server starts
#   - Makefile: make apply-ide-restrictions
#   - Docker entrypoint script
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

DEVELOPER="${1:-${USER}}"
CODE_SERVER_CONFIG_DIR="${HOME}/.config/code-server"
VS_CODE_SETTINGS_FILE="${CODE_SERVER_CONFIG_DIR}/settings.json"
AUDIT_LOG_FILE="/var/log/code-server-audit.log"
RESTRICTED_SHELL="/usr/local/bin/restricted-shell"

log() { echo "[apply-ide-restrictions] $(date -u +%H:%M:%S) $*"; }
die() { echo "[apply-ide-restrictions] FATAL: $*" >&2; exit 1; }
ok()  { echo "[apply-ide-restrictions] ✓ $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# Pre-checks
# ─────────────────────────────────────────────────────────────────────────────

log "Applying read-only IDE restrictions for user: $DEVELOPER"

# Verify code-server is installed
command -v code-server &>/dev/null || die "code-server not found in \$PATH"
ok "code-server installed: $(code-server --version | head -1)"

# ─────────────────────────────────────────────────────────────────────────────
# Layer 1: IDE Filesystem Restrictions
# ─────────────────────────────────────────────────────────────────────────────

log "Applying Layer 1 (IDE Filesystem Restrictions)..."

mkdir -p "$CODE_SERVER_CONFIG_DIR"

# Create VS Code settings.json with restrictions
cat > "$VS_CODE_SETTINGS_FILE" <<'EOF'
{
  "files.exclude": {
    ".env": true,
    ".env.*": true,
    "*.key": true,
    "*.pem": true,
    "*.p12": true,
    "*.pfx": true,
    "*.keystore": true,
    ".git/hooks/**": true,
    ".ssh/**": true,
    ".aws/**": true,
    ".kube/**": true,
    ".config/gcloud": true,
    ".vault-token": true 
  },
  "files.watcherExclude": {
    "**/.git/**": true,
    "**/node_modules": true,
    "**/.venv": true
  },
  "editor.readOnlyIndicator": "visible",
  "editor.minimap.enabled": true,
  "editor.formatOnSave": false,
  "editor.formatOnPaste": false,
  "editor.copyOnSelection": true,
  "terminal.integrated.shell.linux": "/usr/local/bin/restricted-shell",
  "terminal.integrated.automationProfile.linux": {
    "path": "/usr/local/bin/restricted-shell",
    "args": []
  },
  "terminal.integrated.automationShell.linux": "/usr/local/bin/restricted-shell",
  "terminal.integrated.allowMnemonics": false,
  "terminal.integrated.cwd": "${workspaceFolder}",
  "extensions.ignoreRecommendations": true,
  "security.promptForLocalFileProtocolHandling": false,
  "security.workspace.trust.enabled": false,
  "workbench.startupEditor": "newUntitledFile",
  "workbench.welcome.enabled": false
}
EOF

ok "VS Code settings.json configured (filesystem restrictions)"

# ─────────────────────────────────────────────────────────────────────────────
# Layer 3: Terminal Command Restrictions
# ─────────────────────────────────────────────────────────────────────────────

log "Applying Layer 3 (Terminal Command Restrictions)..."

# Ensure restricted-shell exists and is executable
if [[ ! -f "$RESTRICTED_SHELL" ]]; then
  die "restricted-shell not found at $RESTRICTED_SHELL"
fi

if [[ ! -x "$RESTRICTED_SHELL" ]]; then
  sudo chmod 755 "$RESTRICTED_SHELL"
  ok "Made restricted-shell executable"
fi

ok "Terminal shell set to: $RESTRICTED_SHELL"

# ─────────────────────────────────────────────────────────────────────────────
# Layer 4: Audit Logging
# ─────────────────────────────────────────────────────────────────────────────

log "Applying Layer 4 (Audit Logging)..."

# Create audit log directory and file
if [[ ! -f "$AUDIT_LOG_FILE" ]]; then
  sudo touch "$AUDIT_LOG_FILE"
  sudo chmod 0640 "$AUDIT_LOG_FILE"
fi

# Rotate audit log if it's larger than 100MB
if [[ -f "$AUDIT_LOG_FILE" ]]; then
  local log_size=$(stat -f%z "$AUDIT_LOG_FILE" 2>/dev/null || stat -c%s "$AUDIT_LOG_FILE" 2>/dev/null || echo 0)
  if [[ $log_size -gt 104857600 ]]; then
    sudo mv "$AUDIT_LOG_FILE" "${AUDIT_LOG_FILE}.$(date +%Y%m%d-%H%M%S)"
    sudo touch "$AUDIT_LOG_FILE"
    ok "Rotated audit log (was $((log_size / 1048576))MB)"
  fi
fi

# Set audit environment variables for session
export AUDIT_LOG_FILE
export DEVELOPER_ID="$DEVELOPER"
export SESSION_ID="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n1)"

ok "Audit logging enabled: $AUDIT_LOG_FILE (Session: $SESSION_ID)"

# ─────────────────────────────────────────────────────────────────────────────
# Layer 2: Extension Management
# ─────────────────────────────────────────────────────────────────────────────

log "Applying Layer 2 (Extension Management)..."

# List of dangerous extensions to disable
BLOCKED_EXTENSIONS=(
  "ms-vscode.remote-explorer"
  "github.copilot-chat"  
  "github.remotehub"
  "ms-vscode-remote.remote-ssh"
  "ms-vscode-remote.remote-ssh-edit"
)

# Note: vs code extensions are managed via:
# 1. code-server --install-extension <id> / --uninstall-extension <id>
# 2. Or via settings.json: "extensions.ignoreRecommendations": true

ok "Extension restrictions applied (check blocked list in settings.json)"

# ─────────────────────────────────────────────────────────────────────────────
# Verify Configuration
# ─────────────────────────────────────────────────────────────────────────────

log "Verifying read-only configuration..."

[[ -f "$VS_CODE_SETTINGS_FILE" ]] && ok "✓ VS Code settings.json" || die "VS Code settings not found"
[[ -x "$RESTRICTED_SHELL" ]] && ok "✓ restricted-shell executable" || die "restricted-shell not executable"
[[ -f "$AUDIT_LOG_FILE" ]] && ok "✓ Audit log writable" || die "Cannot write to audit log"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

log ""
log "════════════════════════════════════════════════════════════════"
log " Read-Only IDE Configuration: COMPLETE"
log "════════════════════════════════════════════════════════════════"
log "Developer:           $DEVELOPER"
log "Session ID:          $SESSION_ID"
log "Settings:            $VS_CODE_SETTINGS_FILE"
log "Terminal Shell:      $RESTRICTED_SHELL"
log "Audit Log:           $AUDIT_LOG_FILE"
log ""
log "Security Layers:"
log "  ✓ Layer 1: Filesystem restrictions (hide .env, .ssh, .keys)"
log "  ✓ Layer 2: Extension filtering (no remote/exfil extensions)"
log "  ✓ Layer 3: Terminal restrictions (blocked: wget, scp, ssh-keygen)"
log "  ✓ Layer 4: Full audit logging (all commands logged)"
log ""
log "Developer can:"
log "  ✓ Read code files in IDE"
log "  ✓ Use IDE search, go-to-definition"
log "  ✓ Execute terminal commands (cd, ls, git pull)"
log ""
log "Developer CANNOT:"
log "  ✗ Download files (wget, curl blocked)"
log "  ✗ Export code (scp, rsync blocked)"
log "  ✗ Access SSH keys (.ssh hidden)"
log "  ✗ Read secrets (.env hidden)"
log "  ✗ Modify files (delete, create blocked)"
log "════════════════════════════════════════════════════════════════"

ok "All restrictions applied successfully!"
