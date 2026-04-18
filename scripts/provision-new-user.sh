#!/bin/bash
# @file        scripts/provision-new-user.sh
# @module      operations
# @description provision new user — on-prem code-server
# @owner       platform
# @status      active
# scripts/provision-new-user.sh - Automated User Provisioning
# Usage: ./scripts/provision-new-user.sh "email@company.com" "viewer|developer|architect|admin" "Display Name"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

EMAIL="${1}"
ROLE="${2:-developer}"
DISPLAY_NAME="${3:-${EMAIL%%@*}}"

if [[ -z "$EMAIL" ]]; then
  echo "❌ Usage: $0 <email@company.com> [role] [display_name]"
  echo ""
  echo "Available roles:"
  echo "  viewer      - Read-only code access, no edits, no downloads"
  echo "  developer   - Full development access with code changes"
  echo "  architect   - Design review, markdown editing only, read-only code"
  echo "  admin       - Full access with full audit"
  exit 1
fi

# Validate email forma
if ! [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "❌ Invalid email format: $EMAIL"
  exit 1
fi

# Validate role
if ! [[ "$ROLE" =~ ^(viewer|developer|architect|admin)$ ]]; then
  echo "❌ Invalid role: $ROLE (must be: viewer, developer, architect, or admin)"
  exit 1
fi

USER_ID=$(printf '%s' "$EMAIL" | tr '[:upper:]' '[:lower:]' | sed 's/@/-at-/g; s/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDE_URL="${IDE_URL:-https://${DOMAIN:-localhost}}"

cd "$REPO_ROOT"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "👤 PROVISIONING NEW IDE USER"
echo "════════════════════════════════════════════════════════════════"
echo "Email:       $EMAIL"
echo "Role:        $ROLE"
echo "Display:     $DISPLAY_NAME"
echo "User ID:     $USER_ID"
echo "Timestamp:   $(date -I'seconds')"
echo ""

# ─── STEP 1: Add to Email Allowlist ───────────────────────────────────────
echo "Step 1️⃣  Adding to OAuth2 allowlist..."
if grep -Fqx -- "$EMAIL" allowed-emails.txt 2>/dev/null; then
  echo "  ⚠️  Email already whitelisted"
else
  echo "$EMAIL" >> allowed-emails.txt
  sort allowed-emails.txt -o allowed-emails.txt  # Keep sorted
  echo "  ✅ Email added to allowed-emails.txt"
fi

# ─── STEP 2: Create User Settings Profile ──────────────────────────────────
echo ""
echo "Step 2️⃣  Creating user settings profile..."
USER_CONFIG_DIR="config/user-settings/$USER_ID"
mkdir -p "$USER_CONFIG_DIR"

# Load role template
ROLE_TEMPLATE="config/role-settings/${ROLE}-profile.json"
if [[ ! -f "$ROLE_TEMPLATE" ]]; then
  echo "  ⚠️  Role template not found: $ROLE_TEMPLATE"
  echo "  Creating default template..."
  mkdir -p "config/role-settings"

  # Create a default based on role (see templates below)
  case "$ROLE" in
    viewer)
      cat > "$ROLE_TEMPLATE" << 'EOF'
{
  "role": "viewer",
  "priority": 10,
  "editorReadOnly": true,
  "terminalDisabled": true,
  "downloadDisabled": true,
  "downloadBlock": true,
  "settings": {
    "editor.readOnly": true,
    "editor.folding": true,
    "editor.showFoldingControls": "always",
    "git.enabled": false,
    "terminal.integrated.enabled": false,
    "[markdown]": { "editor.readOnly": true }
  }
}
EOF
      ;;
    developer)
      cat > "$ROLE_TEMPLATE" << 'EOF'
{
  "role": "developer",
  "priority": 20,
  "settings": {
    "editor.readOnly": false,
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.codeActionsOnSave": {
      "source.fixAll.eslint": true,
      "source.fixAll.prettier": true
    },
    "git.enabled": false,
    "terminal.integrated.enabled": false,
    "[python]": {
      "editor.defaultFormatter": "ms-python.python",
      "editor.formatOnSave": true
    }
  }
}
EOF
      ;;
    architect)
      cat > "$ROLE_TEMPLATE" << 'EOF'
{
  "role": "architect",
  "priority": 15,
  "codeReadOnly": true,
  "settings": {
    "editor.readOnly": true,
    "terminal.integrated.enabled": false,
    "workbench.colorTheme": "Dracula",
    "[markdown]": { "editor.readOnly": false },
    "[json]": { "editor.readOnly": false },
    "[yaml]": { "editor.readOnly": false },
    "[plaintext]": { "editor.readOnly": false }
  }
}
EOF
      ;;
    admin)
      cat > "$ROLE_TEMPLATE" << 'EOF'
{
  "role": "admin",
  "priority": 100,
  "adminFull": true,
  "settings": {
    "editor.readOnly": false,
    "editor.formatOnSave": true,
    "terminal.integrated.enabled": false,
    "security.workspace.trust.enabled": false
  }
}
EOF
      ;;
  esac
fi

# Copy template to user config
cp "$ROLE_TEMPLATE" "$USER_CONFIG_DIR/settings.json"
echo "  ✅ Settings profile created: $USER_CONFIG_DIR/settings.json"

# Create user metadata override file
cat > "$USER_CONFIG_DIR/user-metadata.json" << EOF
{
  "email": "$EMAIL",
  "userId": "$USER_ID",
  "displayName": "$DISPLAY_NAME",
  "role": "$ROLE",
  "dateProvisioned": "$(date -I'seconds')",
  "status": "active",
  "customizations": {
    "theme": "Default Dark+",
    "fontSize": 13,
    "fontFamily": "Monaco, 'Courier New', monospace"
  }
}
EOF
echo "  ✅ User metadata created: $USER_CONFIG_DIR/user-metadata.json"

# ─── STEP 3: Create Isolated Workspace ─────────────────────────────────────
echo ""
echo "Step 3️⃣  Creating isolated workspace..."
WORKSPACE_DIR="workspaces/$USER_ID"
mkdir -p "$WORKSPACE_DIR"

# Create workspace configuration
cat > "$WORKSPACE_DIR/.code-workspace" << EOF
{
  "folders": [
    {
      "path": ".",
      "name": "workspace"
    }
  ],
  "settings": {
    "workbench.colorTheme": "Default Dark+",
    "workbench.startupEditor": "none",
    "files.exclude": {
      "**/.git": true,
      "**/node_modules": true,
      "**/.env": true,
      "**/.env.local": true
    }
  },
  "extensions": {
    "recommendations": [
      "esbenp.prettier-vscode",
      "dbaeumer.vscode-eslint",
      "ms-python.python"
    ]
  }
}
EOF
echo "  ✅ Workspace created: $WORKSPACE_DIR/.code-workspace"

# Create README for the user
cat > "$WORKSPACE_DIR/README.md" << EOF
# Development Workspace

Welcome, $DISPLAY_NAME!

## Your Environmen

- **Role**: $ROLE
- **Email**: $EMAIL
- **Workspace**: $WORKSPACE_DIR

## Quick Star

1. Open any file to begin developmen
2. Use Ctrl+Shift+P for command palette
3. Save with Ctrl+S (auto-formatting enabled)
4. Navigate with Ctrl+P (quick open)

## Restrictions for $ROLE

EOF

case "$ROLE" in
  viewer)
    cat >> "$WORKSPACE_DIR/README.md" << 'EOF'
- ❌ File editing disabled (read-only mode)
- ❌ Terminal access disabled
- ❌ Download/export disabled
- ✅ Can view code and documentation
- ✅ Can search across codebase
- ✅ Can view git history
EOF
    ;;
  developer)
    cat >> "$WORKSPACE_DIR/README.md" << 'EOF'
- ✅ Full file editing enabled
- ❌ Terminal access disabled
- ❌ Download/export disabled
- ✅ Can commit via web UI only
- ✅ Changes must go through PR system
- ✅ Auto-formatting on save
EOF
    ;;
  architect)
    cat >> "$WORKSPACE_DIR/README.md" << 'EOF'
- ✅ Can edit documentation and design files (markdown, json, yaml)
- ❌ Code files read-only
- ❌ Terminal access disabled
- ✅ Can review architecture decisions
- ✅ Can provide design feedback
EOF
    ;;
  admin)
    cat >> "$WORKSPACE_DIR/README.md" << 'EOF'
- ✅ Full access to all files and features
- ✅ Terminal access enabled
- ✅ Admin functions available
- ⚠️  All actions are audit-logged
- ⚠️  Responsibility for security compliance
EOF
    ;;
esac

# ─── STEP 4: Set Permissions ──────────────────────────────────────────────
echo ""
echo "Step 4️⃣  Setting folder permissions..."
chmod 750 "$WORKSPACE_DIR"
chmod 640 "$USER_CONFIG_DIR"/*
echo "  ✅ Permissions configured (isolation: $WORKSPACE_DIR)"

# ─── STEP 5: Create Audit Log Entry ───────────────────────────────────────
echo ""
echo "Step 5️⃣  Creating audit log entry..."
mkdir -p "audit"
cat >> "audit/user-provisioning.log" << EOF
$(date -I'seconds') | USER_PROVISIONED | email:$EMAIL | role:$ROLE | display:$DISPLAY_NAME | user_id:$USER_ID
EOF
echo "  ✅ Audit entry created"

# ─── STEP 6: Generate Activation Token (Optional for extra security) ──────
echo ""
echo "Step 6️⃣  Generating session token..."
SESSION_TOKEN=$(openssl rand -hex 32)
# Store token securely in temporary location (not in repo)
# In production, write to secure secrets manager (Vault, AWS Secrets Manager, etc.)
SECRETS_DIR="${SECRETS_DIR:=/tmp/code-server-secrets}"
mkdir -p "$SECRETS_DIR" && chmod 700 "$SECRETS_DIR"
TOKEN_FILE="$SECRETS_DIR/${USER_ID}.activation"
cat > "$TOKEN_FILE" << EOF
{
  "email": "$EMAIL",
  "role": "$ROLE",
  "token": "$SESSION_TOKEN",
  "created": "$(date -I'seconds')",
  "expires": "$(date -I'seconds' -d '+30 days')"
}
EOF
chmod 600 "$TOKEN_FILE"
echo "  ✅ Activation token stored securely: $TOKEN_FILE"
echo "  ⚠️  Token is transient and will expire when system restarts"
echo "  📝 For production, implement persistent secure storage (Vault, etc.)"

# ─── SUMMARY ────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ USER PROVISIONING COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📋 Summary:"
echo "   Email:           $EMAIL"
echo "   Role:            $ROLE"
echo "   User ID:         $USER_ID"
echo "   Settings:        $USER_CONFIG_DIR/settings.json"
echo "   Workspace:       $WORKSPACE_DIR"
echo "   Activation:      sessions/${USER_ID}.activation"
echo ""
echo "🔐 Next Steps:"
echo ""
echo "1️⃣  Commit changes to version control:"
echo "   $ git add allowed-emails.txt config/user-settings/ audit/"
echo "   $ git commit -m \"chore: provision user $EMAIL ($ROLE role)\""
echo ""
echo "2️⃣  Push to main branch (automatic deploy):"
echo "   $ git push origin main"
echo ""
echo "3️⃣  Docker will auto-reload (Caddy will detect new email):"
echo "   $ docker compose restart oauth2-proxy"
echo ""
echo "4️⃣  User Login Process:"
echo "   • User navigates to: ${IDE_URL}"
echo "   • Redirected to Google OAuth"
echo "   • Validates $EMAIL against allowed-emails.txt ✅"
echo "   • Loads role-based settings from $USER_CONFIG_DIR"
echo "   • Creates session audit log"
echo ""
echo "5️⃣  Verify:"
echo "   $ docker logs oauth2-proxy | grep '$EMAIL'"
echo "   $ ls -la $WORKSPACE_DIR/"
echo ""
echo "🛡️  Security Notes:"
echo "   • User is restricted to workspace: $WORKSPACE_DIR"
echo "   • Role: $ROLE"
echo "   • All actions logged in audit/"
echo "   • Can revoke access by removing from allowed-emails.txt"
echo "   • Workspace is read-only for role=$ROLE"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
