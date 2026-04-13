# SECURITY IMPLEMENTATION - Step-by-Step Deployment Guide

This guide deploys all security enhancements **without breaking existing deployments**. Each phase is independent and can be rolled back.

---

## PHASE 1: Immediate Deployment (1 hour) - Start Here! ✨

### 1.1 Enable Email Allowlist Enforcement (Already Configured)

**Status:** ✅ Already active in docker-compose.yml

Verify it's working:
```bash
# Check OAuth2 is using the allowlis
docker exec oauth2-proxy cat /etc/oauth2-proxy/allowed-emails.tx

# Add a test email
echo "testuser@bioenergystrategies.com" >> allowed-emails.tx
docker compose restart oauth2-proxy

# Verify new user can't log in without being in lis
# (they'll get "Invalid Email" error from OAuth)


---

### 1.2 Disable File Downloads

**File:** `docker-compose.yml` (code-server service)

**Change this:**
```yaml
environment:
  - CS_DISABLE_FILE_DOWNLOADS=false


**To this:**
```yaml
environment:
  - CS_DISABLE_FILE_DOWNLOADS=true
  - CS_UPLOAD_DISABLED=true           # Add this line


**Deploy:**
```bash
cd /code-server-enterprise
docker compose up -d --build code-server
docker compose restart code-server


**Verify:**
- Reload IDE in browser: https://ide.kushnir.cloud
- "Download" button should be gone from file explorer
- Users cannot export code files

---

### 1.3 Disable Terminal Access

**File:** `config/settings.json

**Add this setting:**
```json
{
  "terminal.integrated.enabled": false
}


**How to deploy:**
```bash
# Copy to code-server config directory
cp config/settings.json ~/.local/share/code-server/config/settings.json

# Reload IDE
# Users: Press F1 → "Reload Window"


**Verify:**
- Terminal tab should disappear from bottom of IDE
- Users cannot run commands
- No command palette access

---

### 1.4 Enable Git Operations Blocking (Critical!)

**Create wrapper script:**
```bash
# Create: scripts/git-security-wrapper.sh

#!/bin/bash
# Git Security Wrapper - Block dangerous operations

OPERATION="$1"
USER="${REMOTE_USER:-unknown}"
TIMESTAMP=$(date -I'seconds')

# Whitelist of allowed operations
ALLOW_OPS=("log" "show" "diff" "status" "branch" "tag" "blame" "rev-parse" "describe")

# Blacklist of DANGEROUS operations
BLOCK_OPS=("clone" "pull" "push" "fetch" "remote" "config" "init" "rebase" "merge")

# Check if blocked
for blocked in "${BLOCK_OPS[@]}"; do
  if [[ "$OPERATION" == "$blocked" ]]; then
    echo "❌ Git operation blocked: git $OPERATION"
    echo "   Policy: All code changes must go through web PR system"
    echo "   Contact: platform-engineering@company.com"
    exit 127
  fi
done

# Check if allowed
for allowed in "${ALLOW_OPS[@]}"; do
  if [[ "$OPERATION" == "$allowed" ]]; then
    # Audit: log the operation
    echo "[AUDIT] git $* | user=$USER | time=$TIMESTAMP" >> /var/log/git-audit.log
    exec /usr/bin/git.real "$@"
  fi
done

# Default: block unknown operations
echo "❌ Git operation not whitelisted: git $OPERATION"
exit 127


**Deploy into Dockerfile:**
```bash
# Modify: Dockerfile.code-server

FROM codercom/code-server:4.115.0

USER roo

# Backup original gi
RUN mv /usr/bin/git /usr/bin/git.real

# Install security wrapper
COPY scripts/git-security-wrapper.sh /usr/bin/gi
RUN chmod 755 /usr/bin/gi

# Rest of Dockerfile...


**Verify:**
```bash
# Build and deploy
docker compose up -d --build code-server

# Test from IDE terminal (if not disabled)
git clone https://github.com/example/repo.gi
# Should output: ❌ Git operation blocked: git clone

git log
# Should work (whitelisted)


---

### 1.5 Configure Audit Logging

**Create directory:**
```bash
mkdir -p logs/audi
chmod 750 logs/audi


**Add to docker-compose.yml (code-server service):**
```yaml
volumes:
  - coder-data:/home/coder
  - ${WORKSPACE_PATH:-./workspace}:/home/coder/workspace
  - ./logs/audit:/var/log/audit      # New: audit logs

environment:
  - AUDIT_LOG_PATH=/var/log/audit/operations.log


**View audit logs:**
```bash
# Real-time audit stream
docker logs -f code-server 2>&1 | grep AUDI

# Historical logs
tail -f logs/audit/operations.log


---

## PHASE 2: User Role Management (2 hours)

### 2.1 Create Role Templates

**Create directory and templates:**
```bash
mkdir -p config/role-settings


**Create: `config/role-settings/viewer-profile.json`**
```json
{
  "role": "viewer",
  "priority": 10,
  "description": "Read-only access. Can view code, view history, cannot edit or download.",
  "settings": {
    "editor.readOnly": true,
    "editor.folding": true,
    "editor.showFoldingControls": "always",
    "git.enabled": false,
    "terminal.integrated.enabled": false,
    "security.workspace.trust.enabled": true
  }
}


**Create: `config/role-settings/developer-profile.json`**
```json
{
  "role": "developer",
  "priority": 20,
  "description": "Full development access. Can edit code, but cannot clone/push directly.",
  "settings": {
    "editor.readOnly": false,
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.codeActionsOnSave": {
      "source.fixAll.eslint": true,
      "source.fixAll.prettier": true
    },
    "terminal.integrated.enabled": false,
    "git.enabled": false
  }
}


**Create: `config/role-settings/architect-profile.json`**
```json
{
  "role": "architect",
  "priority": 15,
  "description": "Can edit design docs, configuration, markdown. Cannot edit code.",
  "settings": {
    "editor.readOnly": true,
    "terminal.integrated.enabled": false,
    "workbench.colorTheme": "Dracula",
    "[markdown]": { "editor.readOnly": false },
    "[json]": { "editor.readOnly": false },
    "[yaml]": { "editor.readOnly": false }
  }
}


---

### 2.2 Make provision-new-user.sh Executable

```bash
chmod +x scripts/provision-new-user.sh

# Test i
./scripts/provision-new-user.sh "test@bioenergystrategies.com" "developer" "Test User"


---

### 2.3 Provision Your First User

```bash
# Example: Add a developer
./scripts/provision-new-user.sh "developer@bioenergystrategies.com" "developer" "John Developer"

# Example: Add a viewer
./scripts/provision-new-user.sh "viewer@bioenergystrategies.com" "viewer" "Jane Viewer"

# Example: Add an architec
./scripts/provision-new-user.sh "architect@bioenergystrategies.com" "architect" "Bob Architect"

# Commit to gi
git add allowed-emails.txt config/user-settings/ config/role-settings/
git commit -m "chore: add role-based user provisioning and example users"
git push origin main

# Restart OAuth proxy to pick up new emails
docker compose restart oauth2-proxy


---

### 2.4 Verify User Can Login

For each user, test:
```bash
# They see their role-appropriate settings
# They can/cannot edit based on role
# Download button is disabled
# Terminal is disabled


**Manual test:**
1. Open incognito browser (new login session)
2. Navigate to: https://ide.kushnir.cloud
3. Click "Sign in with Google"
4. Use test user email
5. Should land in IDE with restricted settings

---

## PHASE 3: Advanced Security (4 hours)

### 3.1 Setup Copy/Paste Audit Logging

**Create: `scripts/audit-clipboard.js`**
```javascrip
// Inject into code-server at startup
// This logs clipboard copy/paste events to audit trail

document.addEventListener('copy', (e) => {
  const text = window.getSelection().toString();
  if (text.length > 50) {  // Only log substantial copies
    navigator.sendBeacon('/audit/clipboard', JSON.stringify({
      type: 'copy',
      size: text.length,
      timestamp: new Date().toISOString()
    }));
  }
});

document.addEventListener('contextmenu', (e) => {
  navigator.sendBeacon('/audit/clipboard', JSON.stringify({
    type: 'contextmenu_blocked',
    timestamp: new Date().toISOString()
  }));
});


**Add to Dockerfile.code-server:**
```dockerfile
# Cache the audit scrip
COPY scripts/audit-clipboard.js /usr/lib/audit/

# Inject into startup (requires custom extension or HTML modification)


---

### 3.2 Setup Immutable Audit Logs

**In docker-compose.yml (code-server service):**
```yaml
volumes:
  - ./logs/audit:/var/log/audi

# After first run, make logs append-only
# Run on host:
# chattr +a logs/audit/operations.log


---

### 3.3 Session Timeou

**Add to settings.json:**
```json
{
  "session.timeout": 3600000,  // 1 hour in milliseconds
  "session.idleTimeout": 900000  // 15 minutes idle
}


---

## PHASE 4: Monitoring & Enforcement (2 hours)

### 4.1 Create Audit Dashboard

**Create: `audit-status.sh`**
```bash
#!/bin/bash

echo "════════════════════════════════════════════════════════════════"
echo "SECURITY AUDIT DASHBOARD"
echo "════════════════════════════════════════════════════════════════"
echo ""

echo "📊 Active Users:"
docker logs oauth2-proxy 2>&1 | grep "authenticated" | tail -5 | sed 's/^/  /'
echo ""

echo "📋 Recent Git Operations (blocked):"
docker logs code-server 2>&1 | grep "BLOCKED" | tail -5 | sed 's/^/  /'
echo ""

echo "📥 Download Attempts (blocked):"
grep "CS_DISABLE_FILE_DOWNLOADS=true" docker-compose.yml > /dev/null && echo "  ✅ File downloads disabled" || echo "  ❌ File downloads enabled!"
echo ""

echo "🔒 Allowed Users:"
wc -l allowed-emails.txt | awk '{print "  Total: " $1 " users"}'
echo ""

echo "⏱️  Audit Logs:"
du -sh logs/audit/ 2>/dev/null | awk '{print "  Size: " $0}'
ls -lh logs/audit/*.log 2>/dev/null | wc -l | awk '{print "  Files: " $0}'
echo ""

echo "════════════════════════════════════════════════════════════════"


**Make executable and run:**
```bash
chmod +x audit-status.sh
./audit-status.sh

# Schedule regular checks
# Add to crontab: 0 */4 * * * /code-server-enterprise/audit-status.sh >> audit-summary.log


---

### 4.2 Setup Alert Rules

**Create: `.github/workflows/security-audit.yml`**
```yaml
name: Security Audit Check

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  push:
    paths:
      - 'allowed-emails.txt'
      - 'docker-compose.yml'
      - 'config/'

jobs:
  audit:
    runs-on: ubuntu-lates
    steps:
      - uses: actions/checkout@v3

      - name: Check for Security Issues
        run: |
          # Verify no hardcoded credentials
          ! grep -r "password\|secret\|token" config/ --include="*.json"

          # Verify downloads are disabled
          grep "CS_DISABLE_FILE_DOWNLOADS=true" docker-compose.yml

          # Verify terminal is disabled
          grep "\"terminal.integrated.enabled\": false" config/settings.json

          # Verify allowed-emails.txt exists and is not empty
          [ -s allowed-emails.txt ]

          echo "✅ Security checks passed"


---

## PHASE 5: Testing & Validation (1 hour)

### 5.1 Test Each Security Layer

**Test 1: File Download Blocking**
```bash
# In IDE browser: Try to download a file
# Expected: No download button visible
# Expected: If user right-clicks → Save As is blocked at network level


**Test 2: Git Operations**
```bash
# (Only if terminal is enabled for testing)
# In IDE terminal:
git clone https://github.com/example/repo.gi
# Expected: ❌ Git operation blocked: git clone

git log
# Expected: ✅ Works (whitelisted operation)


**Test 3: Terminal Access**
```bash
# In IDE: Try to open terminal
# Expected: Terminal tab doesn't appear
# Expected: Can't open with Ctrl+` shortcu


**Test 4: Email Whitelist**
```bash
# Use incognito browser, try to login with email NOT in allowed-emails.tx
# Expected: OAuth error or redirect to allowlist error page


**Test 5: Role-Based Settings**
```bash
# Login as viewer role
# Expected: editor.readOnly = true
# Expected: Cannot edit files

# Verify in Developer Console:
// Code: vscode.workspace.getConfiguration().get('editor.readOnly')
// Expected output: true

# Login as developer role
# Expected: Can edit files


---

## PHASE 6: Documentation & Handoff (30 min)

### 6.1 Create User Onboarding Guide

**File: `USER_ONBOARDING.md`**
```markdown
# IDE User Onboarding Guide

## For Viewers (Read-Only Access)

1. You will receive an email invitation
2. Click the link or navigate to: https://ide.kushnir.cloud
3. Sign in with your Google account (should match the email invited)
4. You are in READ-ONLY mode:
   - ✅ Can view all code
   - ✅ Can search and navigate
   - ❌ Cannot edit files
   - ❌ Cannot download code
   - ❌ Cannot access terminal

## For Developers (Full Edit Access)

1. Receive invitation and sign in (same as viewers)
2. You have EDIT access:
   - ✅ Can edit any file
   - ✅ Can save changes (auto-format enabled)
   - ❌ Cannot download code (view only in IDE)
   - ❌ Cannot clone repo directly (must use web PR system)
   - ❌ Cannot run arbitrary commands
3. To make changes:
   - Edit file and save (Ctrl+S)
   - Use "Source Control" panel to stage changes
   - Create PR from web interface (GitHub)

## For Architects (Design-Only Access)

1. Similar to viewers, but can edit:
   - ✅ Markdown files (*.md)
   - ✅ Configuration files (*.json, *.yaml)
   - ✅ Architecture docs
   - ❌ Source code files (*.js, *.py, *.go, etc.) - read-only

## Common Issues

**Q: Can I download the code?**
A: No. Downloads are disabled for security. You can view code in the IDE.

**Q: Can I use the terminal?**
A: No terminal access for security (no ssh, scp, arbitrary command execution).

**Q: How do I make code changes?**
A: Edit in IDE → GitHub PR → Review → Merge (no direct git push).

**Q: Why are copy-paste operations logged?**
A: Security audit trail. Large code copies are logged for compliance.


---

## ROLLBACK PROCEDURES

If you need to revert any phase:

### Rollback Phase 1 (Enable Downloads)
```bash
# Edit docker-compose.yml
sed -i 's/CS_DISABLE_FILE_DOWNLOADS=true/CS_DISABLE_FILE_DOWNLOADS=false/' docker-compose.yml

docker compose up -d --build code-server
# Users can now download files again


### Rollback Phase 2 (Remove Role Restrictions)
```bash
# Revert settings.json
git checkout HEAD^ -- config/settings.json
docker compose restart code-server


### Rollback Phase 3+ (Git wrapper)
```bash
# Restore original gi
docker compose up -d --build code-server  # Rebuilds without git wrapper


---

## DEPLOYMENT CHECKLIS

- [ ] Phase 1: File downloads disabled
- [ ] Phase 1: Terminal disabled
- [ ] Phase 1: Email whitelist active
- [ ] Phase 2: Role templates created
- [ ] Phase 2: First user provisioned
- [ ] Phase 2: User can login
- [ ] Phase 3: Git wrapper deployed
- [ ] Phase 3: Copy/paste logging active
- [ ] Phase 4: Audit dashboard working
- [ ] Phase 5: All security tests pass
- [ ] Phase 6: Documentation complete
- [ ] Final: Commit all changes
- [ ] Final: Git tag release: `v1.0-security-hardened

---

## NEXT STEPS

1. **Now:** Run Phase 1 (1 hour) - Immediate wins
2. **Today:** Run Phase 2 (2 hours) - User managemen
3. **This Week:** Run Phases 3-4 (4 hours) - Advanced security
4. **Next Week:** Run Phase 5 (1 hour) - Testing & validation

---

**Questions?** See [CODE_SECURITY_HARDENING.md](./CODE_SECURITY_HARDENING.md) for full reference.
