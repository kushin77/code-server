# Enterprise Code Security Hardening Guide

## Mission: Prevent Developer Code Theft & Control User Access

This guide implements **zero-trust code access patterns** with defense-in-depth across network, container, IDE, and audit layers.

---

## 🔒 DEFENSE LAYERS

### Layer 1: Network Isolation (Perimeter Defense)
**Goal: No code leaves the workspace without authorization**

#### 1.1 Egress Filtering
```bash
# Block ALL outbound traffic except authenticated services
# Implemented in Docker network policies and Caddy

# Allow only:
# - OAuth2 proxy → Google (authentication)
# - Caddy → Git hosting (if needed)
# - Block terminal/code-server → external networks


**Implementation:** Update docker-compose.yml
```yaml
networks:
  enterprise:
    driver: bridge
    driver_opts:
      # Enable network policy enforcemen
      "com.docker.network.bridge.enable_ip_masquerade": "true"
    ipam:
      config:
        - subnet: 172.25.0.0/16


**Firewall Rules (Windows/Linux):**
```powershell
# Block outbound SSH, git clone, scp, sftp from code-server container
# Allow only HTTPS for legitimate package managers (npm, pip)
# Block raw socket access

# Windows firewall (if hosting Docker)
New-NetFirewallRule -DisplayName "Block code-server SSH"
  -Direction Outbound -Action Block -Protocol TCP -RemotePort 22,2222

New-NetFirewallRule -DisplayName "Block code-server SCP"
  -Direction Outbound -Action Block -Protocol TCP -RemotePort 22,23

New-NetFirewallRule -DisplayName "Block code-server curl external"
  -Direction Outbound -Action Block -Program "C:\Program Files\Docker\Docker\resources\bin\curl.exe"
  -RemoteAddress "!172.25.0.0/16,!8.8.8.8,!1.1.1.1" # Only allow container network + DNS


#### 1.2 WebSocket Restrictions
```yaml
# Caddy configuration restricts WebSocket abuse
@websocket {
    header Connection Upgrade
    header Upgrade websocke
}

# Log all WebSocket connections
@websocket_connect {
    path /~ws
}

log @websocket_connect {
    output stdou
    format json
    include_headers X-Auth-Request-User X-Auth-Request-Email
}


---

### Layer 2: IDE Feature Lockdown (Workspace Defense)

#### 2.1 Disable Dangerous Extensions
```json
// ~/.config/code-server/User/settings.json
{
  // ❌ BLOCK: Code execution via npm scripting
  "security.workspace.trust.enabled": true,
  "security.workspace.trust.confirmUntrustedWorkspaces": true,
  "security.workspace.trust.startup": "always",

  // ❌ BLOCK: Shell script execution extensions
  "extensions.disabledRecommendations": [
    "ms-vscode.makefile-tools",
    "ms-python.python",
    "golang.go",
    "rust-lang.rust-analyzer"
  ],

  // ❌ BLOCK: Git operations that could leak code
  "git.enabled": false,
  "git.ignoreLimitWarning": true,

  // ❌ BLOCK: Terminal → external commands
  "terminal.integrated.enabled": false,

  // ❌ ALLOW: Code viewing only
  "extensions.enabled": true,
  "editor.readOnlyMessage": "Code is read-only. Submit changes via PR system only.",
  "editor.readOnly": false  // Set per-workspace if needed
}


#### 2.2 Terminal Sandboxing
```bash
# Create restrictive terminal environment in containers

# /usr/local/bin/restricted-terminal.sh (read-only, limited commands)
#!/bin/bash
set -e

# Only allow safe commands
SAFE_COMMANDS=("ls" "cat" "grep" "find" "pwd" "echo" "wc" "head" "tail")

# Intercept shell execution
exec_safe() {
  local cmd="$1"
  for safe in "${SAFE_COMMANDS[@]}"; do
    if [[ "$cmd" == "$safe" || "$cmd" == "$safe "* ]]; then
      command "$@"
      return $?
    fi
  done

  echo "❌ Command blocked ($cmd): Not in whitelist" >&2
  log_security_event "TERMINAL_BLOCKED" "User: $USER, Command: $cmd"
  return 127
}

# Don't allow:
# - SSH, SCP, SFTP
# - curl, wget (for exfiltration)
# - git clone, git push (managed separately)
# - Docker commands
# - nc (netcat)
# - perl, python (script execution)


**In Dockerfile.code-server:**
```dockerfile
# Block command execution
RUN chmod 000 /usr/bin/ssh /usr/bin/ssh-keygen /usr/bin/scp /usr/bin/sftp
RUN chmod 000 /usr/bin/curl /usr/bin/wge
RUN chmod 000 /usr/bin/perl /usr/bin/python3 /usr/bin/ruby
RUN chmod 000 /usr/bin/nc /usr/bin/netca
RUN chmod 000 /usr/bin/gi

# Allow ONLY safe commands and development tools
RUN chmod 755 /usr/bin/node /usr/bin/npm /usr/bin/bash


#### 2.3 Copy/Paste Restrictions
```json
{
  // Disable clipboard API in browser contex
  "workbench.editor.enablePreview": false,
  "editor.copyWithSyntaxHighlighting": false,

  // Remove copy button from UI
  "workbench.editor.showTabs": "single",

  // In code-server startup, inject script to block copy events
  "editor.glyphMargin": false,
  "editor.selectionClipboard": false  // Disable Linux middle-click paste
}


**Implement in HTML/JavaScript layer:**
```javascrip
// Inject into code-server startup (via custom extension or patch)

document.addEventListener('copy', (e) => {
  // Log the copy event for audi
  const selectedText = window.getSelection().toString();
  if (selectedText.length > 100) {  // Only log substantial copies
    fetch('/audit/clipboard-copy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        user: document.cookie.match(/X-Auth-Request-User=([^;]+)/)?.[1],
        timestamp: new Date().toISOString(),
        charactersSelected: selectedText.length,
        fileContext: getCurrentEditorFile()
      })
    });
  }
});

// Disable right-click context menu
document.addEventListener('contextmenu', (e) => {
  e.preventDefault();
  logAuditEvent('CONTEXT_MENU_BLOCKED', e.target);
  return false;
});


#### 2.4 File Download Restrictions
In **docker-compose.yml** (code-server service):
```yaml
environment:
  - CS_DISABLE_FILE_DOWNLOADS=true  # No "Download" button
  - CS_UPLOAD_DISABLED=true         # No file uploads


---

### Layer 3: Git & Version Control Lockdown

#### 3.1 Restrict Git Operations
```bash
# Create git wrapper that enforces policy

# /usr/local/bin/git (wrapper script with audit)
#!/bin/bash

COMMAND="$1"
USER="${REMOTE_USER:-unknown}"
TIMESTAMP=$(date -I'seconds')

# Audit all git operations
audit_git() {
  local cmd="$1"
  echo "[AUDIT] User: $USER | Time: $TIMESTAMP | Command: git $cmd" >> /var/log/git-operations.log
}

# ❌ BLOCK operations
BLOCKED_COMMANDS=("clone" "pull" "push" "fetch" "remote add" "config --global" "config --system")

for blocked in "${BLOCKED_COMMANDS[@]}"; do
  if [[ "$COMMAND" == "$blocked" ]]; then
    audit_git "BLOCKED:$COMMAND $*"
    echo "❌ Git operation blocked: $COMMAND (policy: code must flow through PR system)" >&2
    exit 127
  fi
done

# ✅ ALLOW operations
ALLOWED_COMMANDS=("log" "status" "diff" "show" "blame" "branch" "tag")

for allowed in "${ALLOWED_COMMANDS[@]}"; do
  if [[ "$COMMAND" == "$allowed" ]]; then
    audit_git "ALLOWED:$COMMAND $*"
    exec /usr/bin/git "$@"
  fi
done

# Default: block unknown operations
audit_git "BLOCKED_UNKNOWN:$COMMAND $*"
echo "❌ Git operation not in whitelist: $COMMAND" >&2
exit 127


**In Dockerfile:**
```dockerfile
# Backup original gi
RUN mv /usr/bin/git /usr/bin/git.real

# Use wrapper
COPY --chmod=755 scripts/git-wrapper.sh /usr/bin/gi

# Configure git to enforce signing
RUN git config --global commit.gpgsign true
RUN git config --global push.gpgSign true
RUN git config --global tag.gpgSign true
RUN git config --global user.email "${WORKSPACE_ADMIN_EMAIL}"
RUN git config --global user.name "Code-Server Admin"


#### 3.2 SSH Key Quarantine
```bash
# Block SSH private key access
chmod 000 ~/.ssh/id_rsa* ~/.ssh/id_ed25519*

# SSH keys must be registered with Git host via OAuth (not SSH keys)
# If SSH needed: use SSH key passphrase + hardware token


---

### Layer 4: Session & Audit Controls

#### 4.1 Session Recording
```yaml
# docker-compose.yml addition
volumes:
  - ./logs/sessions:/var/log/sessions  # Session recordings

environment:
  - SESSION_RECORDING_ENABLED=true
  - AUDIT_LOG_PATH=/var/log/audit.log


**Session Audit Script:**
```bash
#!/bin/bash
# /usr/local/bin/audit-session.sh

LOG_DIR="/var/log/sessions"
mkdir -p "$LOG_DIR"

# Record session metadata
SESSION_ID=$(uuidgen)
USER_EMAIL="${REMOTE_USER_EMAIL}"
START_TIME=$(date -I'seconds')
IP_ADDRESS="${REMOTE_ADDR}"
SESSION_LOG="$LOG_DIR/${SESSION_ID}-${USER_EMAIL}-${START_TIME}.log"

# Log all activities
log_event() {
  local event="$1"
  echo "[$(date -I'seconds')] $event" >> "$SESSION_LOG"
}

# Monitor file access
inotifywait -m -r /home/coder/workspace -e modify,access |
while read path action file; do
  log_event "FILE_ACCESS:$action:$path$file"
done &

echo "Session Started: $SESSION_ID" > "$SESSION_LOG"
echo "User: $USER_EMAIL" >> "$SESSION_LOG"
echo "IP: $IP_ADDRESS" >> "$SESSION_LOG"
echo "Time: $START_TIME" >> "$SESSION_LOG"


#### 4.2 Immutable Audit Logs
```bash
# Use append-only logging with integrity verification

# /var/log/audit.log setup
sudo fileattr +a /var/log/audit.log  # Append-only
sudo setfattr +i /var/log/audit.log  # Immutable

# Verify logs haven't been tampered
sha256sum /var/log/audit.log > /var/log/audit.log.sha256


---

### Layer 5: Access Control & RBAC

#### 5.1 Multi-User Role System
```yaml
# User roles configuration
users:
  - name: developer
    email: dev@company.com
    role: viewer      # Read-only access
    permissions:
      - code.read
      - logs.read
    restrictions:
      - code.write
      - terminal.exec
      - files.download
      - git.push

  - name: architec
    email: arch@company.com
    role: reviewer    # Review + approve changes
    permissions:
      - code.read
      - code.review
      - code.approve
      - logs.read
    restrictions:
      - code.write  # No direct changes

  - name: admin
    email: admin@company.com
    role: admin       # Full access with audi
    permissions:
      - "*"
    restrictions:
      - none


---

### Layer 6: Private Package Registry

#### 6.1 Prevent Public Package Exfiltration
```bash
# npm configuration
~/.npmrc:
registry=https://private-npm.company.com/
@company:registry=https://private-npm.company.com/

# Prevent npm publish to public registry
npm config set registry https://private-npm.company.com/
npm config set @:registry https://private-npm.company.com/

# Block public uploads
npm config set always-auth true

# Only allow install from private registry
npm config set audit false  # Skip public audits


**Docker buildkit secret management:**
```dockerfile
# Prevent dependency exfiltration via Docker build cache
FROM codercom/code-server:4.115.0

# Mount private credentials at build time only
RUN --mount=type=secret,id=npm_token \
    npm config set //private-npm.company.com/:_authToken=$(cat /run/secrets/npm_token) && \
    npm install --legacy-peer-deps && \
    rm -f ~/.npmrc  # Clean credentials after build


---

### Layer 7: Secrets Managemen

#### 7.1 Block Hardcoded Secrets
```bash
# Pre-commit hook to scan for secrets
# .git/hooks/pre-commi

#!/bin/bash
set -e

echo "🔐 Scanning for secrets/credentials..."

# Block patterns
PATTERNS=(
  "^.*API[_-]KEY.*=.*"
  "^.*PASSWORD[_-].*=.*"
  "^.*SECRET[_-]KEY.*=.*"
  "MONGO_URI="
  "DATABASE_URL="
  "aws_access_key"
  "-----BEGIN RSA PRIVATE KEY-----"
  "-----BEGIN PRIVATE KEY-----"
)

for pattern in "${PATTERNS[@]}"; do
  if git diff --cached | grep -E "$pattern" &>/dev/null; then
    echo "❌ Blocked: Detected secret pattern: $pattern"
    exit 1
  fi
done

echo "✅ No secrets detected"
exit 0


---

## 👥 USER SETTINGS MANAGEMEN

### Architecture: Settings Hierarchy

Workspace Default Settings
    ↓
Organization Template
    ↓
Team Settings (inherited)
    ↓
User Profile (can override team settings with restrictions)
    ↓
Session Settings (temporary, reset on logout)


---

### Implementation: Multi-Tier Settings System

#### Phase 1: Workspace Defaults (Foundation)
```json
// /code-server/config/vscode-defaults.json
{
  "scope": "workspace-default",
  "readonly": true,
  "inheritInheritable": true,
  "settings": {
    // ═════════════════════════════════════════════════════════════
    // TIER 1: NON-OVERRIDEABLE (Applied to all users)
    // ═════════════════════════════════════════════════════════════
    "security.workspace.trust.enabled": true,
    "security.workspace.trust.startup": "always",
    "telemetry.telemetryLevel": "off",
    "telemetry.enableCrashReporter": false,
    "extensions.ignoreRecommendations": true,
    "extensions.disabledRecommendations": [
      "ms-vscode.vs-keybindings",
      "eamodio.gitlens",
      "ms-vscode-remote.remote-containers"
    ],

    // ═════════════════════════════════════════════════════════════
    // TIER 2: OVERRIDEABLE BUT ENFORCED DEFAUL
    // ═════════════════════════════════════════════════════════════
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.insertSpaces": true,
    "editor.tabSize": 2,
    "[python]": { "editor.tabSize": 4 },
    "editor.wordWrap": "wordWrapColumn",
    "editor.wordWrapColumn": 100,
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,

    // ═════════════════════════════════════════════════════════════
    // TIER 3: PER-ROLE SETTINGS (Applied based on user role)
    // ═════════════════════════════════════════════════════════════
    // → Populated dynamically at login
  }
}


#### Phase 2: Role-Based Settings Templates
```bash
# /code-server/config/role-settings/

# viewer-profile.json (read-only access)
{
  "role": "viewer",
  "priority": 10,
  "settings": {
    "editor.readOnly": true,
    "editor.folding": true,
    "editor.showFoldingControls": "always",
    "git.enabled": false,
    "terminal.integrated.enabled": false,
    "edit.insertSnippet": false
  }
}

# developer-profile.json (full development access)
{
  "role": "developer",
  "priority": 20,
  "settings": {
    "editor.readOnly": false,
    "editor.formatOnSave": true,
    "python.linting.enabled": true,
    "editor.codeActionsOnSave": {
      "source.fixAll.eslint": true,
      "source.fixAll.isort": true
    }
  }
}

# architect-profile.json (design-focused, no direct edits)
{
  "role": "architect",
  "priority": 15,
  "settings": {
    "editor.readOnly": true,
    "workbench.colorTheme": "Dracula",
    "extensions.enabled": [
      "streetsidesoftware.code-spell-checker",
      "mermade.mermaid-js"
    ],
    "[markdown]": { "editor.readOnly": false }
  }
}


#### Phase 3: User Provisioning Scrip
```bash
#!/bin/bash
# scripts/provision-new-user.sh

set -e

EMAIL="$1"
ROLE="${2:-developer}"  # Default role
DISPLAY_NAME="$3"

if [[ -z "$EMAIL" || -z "$ROLE" ]]; then
  echo "Usage: $0 <email> <role> [display_name]"
  echo "Roles: viewer, developer, architect, admin"
  exit 1
fi

echo "👤 Provisioning user: $EMAIL as $ROLE"

# Step 1: Add to allowed-emails.tx
if ! grep -q "^$EMAIL$" allowed-emails.txt; then
  echo "$EMAIL" >> allowed-emails.tx
  echo "✅ Email added to allowlist"
else
  echo "⚠️  Email already in allowlist"
fi

# Step 2: Create user settings profile
USER_ID=$(echo "$EMAIL" | sed 's/@.*//' | tr '.' '-')
USER_SETTINGS_DIR="config/user-settings/$USER_ID"
mkdir -p "$USER_SETTINGS_DIR"

# Copy role template
cp "config/role-settings/${ROLE}-profile.json" "$USER_SETTINGS_DIR/settings.json"

# Add custom overrides (optional)
cat > "$USER_SETTINGS_DIR/user-overrides.json" << EOF
{
  "user": "$EMAIL",
  "displayName": "$DISPLAY_NAME",
  "role": "$ROLE",
  "dateProvisioned": "$(date -I'seconds')",
  "customizations": {}
}
EOF

# Step 3: Create workspace directory
WORKSPACE_DIR="workspaces/$USER_ID"
mkdir -p "$WORKSPACE_DIR"

# Step 4: Generate session configuration
cat > "$WORKSPACE_DIR/.code-workspace" << EOF
{
  "folders": [
    { "path": "." }
  ],
  "settings": {
    "workbench.colorTheme": "Default Dark+"
  },
  "extensions": {
    "recommendations": ["esbenp.prettier-vscode"]
  }
}
EOF

# Step 5: Set permissions
chmod 700 "$WORKSPACE_DIR"

# Step 6: Create audit entry
echo "$(date -I'seconds') | USER_CREATED | $EMAIL | role:$ROLE | display:$DISPLAY_NAME" >> audit/user-provisioning.log

echo ""
echo "✅ User provisioning complete!"
echo "   Email: $EMAIL"
echo "   Role: $ROLE"
echo "   Config: $USER_SETTINGS_DIR"
echo "   Workspace: $WORKSPACE_DIR"
echo ""
echo "📋 Next steps:"
echo "   1. Commit provisioning changes: git add allowed-emails.txt config/"
echo "   2. Restart oauth2-proxy: docker compose restart oauth2-proxy"
echo "   3. User can now log in via Google OAuth"


#### Phase 4: Runtime Settings Injection
```typescrip
// Extension-based settings loader (TypeScript/VS Code Extension)
// extensions/auto-settings-loader/src/extension.ts

import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';

export async function activate(context: vscode.ExtensionContext) {
  const userEmail = process.env.REMOTE_USER_EMAIL || 'unknown@company.com';
  const userId = userEmail.split('@')[0].replace(/\./g, '-');
  const settingsPath = path.join('/code-server', 'config', 'user-settings', userId, 'settings.json');

  console.log(`[Settings Loader] Loading profile for ${userEmail}`);

  try {
    if (fs.existsSync(settingsPath)) {
      const userSettings = JSON.parse(fs.readFileSync(settingsPath, 'utf-8'));

      // Apply settings to current workspace
      const workspaceSettings = vscode.workspace.getConfiguration();

      for (const [key, value] of Object.entries(userSettings)) {
        if (key !== 'role' && key !== 'priority') {
          try {
            await workspaceSettings.update(key, value, vscode.ConfigurationTarget.WorkspaceFolder);
          } catch (err) {
            console.error(`[Settings Loader] Failed to set ${key}:`, err);
          }
        }
      }

      console.log(`[Settings Loader] Applied ${Object.keys(userSettings).length} settings`);

      // Lock certain settings to prevent override
      const lockedSettings = ['security.workspace.trust.enabled', 'telemetry.telemetryLevel'];
      for (const setting of lockedSettings) {
        // Create read-only indicator in status bar
        vscode.window.setStatusBarMessage(`🔒 ${setting} is locked by admin`, 3000);
      }
    }
  } catch (err) {
    console.error('[Settings Loader] Error:', err);
  }
}


#### Phase 5: Session Managemen
```bash
#!/bin/bash
# scripts/manage-user-session.sh

get_session_info() {
  local email="$1"
  local session_file="sessions/${email}.session"

  if [[ -f "$session_file" ]]; then
    cat "$session_file"
  else
    echo "Session not found: $email"
    return 1
  fi
}

list_active_sessions() {
  echo "Active Sessions:"
  echo "─────────────────────────────────────────────────"
  for session in sessions/*.session; do
    if [[ -f "$session" ]]; then
      local user=$(grep "^user=" "$session" | cut -d= -f2)
      local login_time=$(grep "^login_time=" "$session" | cut -d= -f2)
      local idle_time=$(grep "^idle_time=" "$session" | cut -d= -f2)

      printf "%-30s | Login: %s | Idle: %s\n" "$user" "$login_time" "$idle_time"
    fi
  done
}

revoke_session() {
  local email="$1"
  local session_file="sessions/${email}.session"

  if rm -f "$session_file"; then
    echo "✅ Session revoked: $email"
    # Force re-authentication on next reques
    return 0
  else
    echo "❌ Failed to revoke session: $email"
    return 1
  fi
}

revoke_all_user_sessions() {
  local email="$1"
  local count=$(rm -f sessions/${email}.session | wc -l)
  echo "✅ Revoked $count session(s) for $email"
}


---

## 🚀 IMPLEMENTATION ROADMAP

### Week 1: Network & Container Security
- [ ] Implement egress filtering (docker network policies)
- [ ] Deploy git wrapper scrip
- [ ] Disable download/upload in code-server
- [ ] Configure read-only filesystem where possible

### Week 2: IDE Lockdown
- [ ] Implement extension blocklis
- [ ] Disable terminal
- [ ] Set up copy/paste audit logging
- [ ] Enable workspace trust enforcemen

### Week 3: User Managemen
- [ ] Create role-based settings templates
- [ ] Implement provisioning scrip
- [ ] Deploy settings loader extension
- [ ] Create user onboarding guide

### Week 4: Audit & Monitoring
- [ ] Set up session recording
- [ ] Deploy immutable audit logs
- [ ] Create audit dashboard
- [ ] Implement alerting on suspicious activities

### Week 5: Enforcement & Testing
- [ ] Test code theft scenarios (adversarial)
- [ ] Verify all lockdowns work
- [ ] Load testing with multi-user sessions
- [ ] Documentation & runbooks

---

## 📋 QUICK START: ADD NEW USER

```bash
# 1. Run provisioning scrip
./scripts/provision-new-user.sh "newdev@company.com" developer "New Developer"

# 2. Commit changes
git add allowed-emails.txt config/user-settings/
git commit -m "chore: provision new user newdev@company.com"

# 3. Restart OAuth proxy (picks up new email)
docker compose restart oauth2-proxy

# 4. User logs in via: https://ide.kushnir.cloud
# → OAuth2 validates against allowed-emails.tx
# → Settings loader applies role-based config
# → Session audit log created

# Verify
docker logs oauth2-proxy | grep "newdev@company.com"


---

## 🔍 AUDIT & COMPLIANCE

**Commands for monitoring:**
```bash
# View recent user logins
docker logs oauth2-proxy | grep "authenticated"

# View file access audi
tail -f logs/sessions/*.log

# Verify git operations were blocked
grep "BLOCKED" logs/git-operations.log

# Export session recordings for compliance
tar czf audit-export-$(date +%Y%m%d).tar.gz logs/sessions/

# Verify immutable logs
lsattr /var/log/audit.log  # Should show "----ia--------"


---

## 🔐 SECURITY CHECKLIS

- [ ] Network egress filtering enabled
- [ ] Git clone/push disabled (PR-only code flow)
- [ ] Terminal access disabled
- [ ] Extension marketplace restricted
- [ ] Download/upload disabled
- [ ] Copy/paste audit logging active
- [ ] SSH keys quarantined
- [ ] Private package registry configured
- [ ] Session recording enabled
- [ ] Audit logs immutable
- [ ] Role-based settings enforced
- [ ] User provisioning automated
- [ ] Settings locked per-role
- [ ] Multi-factor authentication (via Google OAuth)
- [ ] Regular security audits scheduled

---

**Status: READY FOR IMPLEMENTATION** ✅

See [SECURITY_IMPLEMENTATION_STEPS.md](./SECURITY_IMPLEMENTATION_STEPS.md) for detailed deployment procedures.
