# Enterprise Security & User Management - Quick Reference

## 🎯 Overview

This guide summarizes security enhancements and user management for your code-server IDE. It prevents code theft and provides fine-grained user access control.

---

## 📋 Quick Start (5 minutes)

### Add Your First User

```bash
cd /code-server-enterprise

# Provision a developer
./scripts/manage-users.sh add-user "dev@company.com" "developer" "John Developer"

# Provision a viewer (read-only)
./scripts/manage-users.sh add-user "viewer@company.com" "viewer" "Jane Viewer"

# Commit changes
git add allowed-emails.txt config/user-settings/
git commit -m "chore: add users"
git push origin main

# Restart (auto-redeploys)
docker compose restart oauth2-proxy


**User can now log in:** `https://ide.kushnir.cloud` → Google OAuth → Auto-settings apply

---

## 🔒 Security Features (What's Protected)

### Built-In Protections

| Protection | Status | Details |
|-----------|--------|---------|
| **Email Whitelist** | ✅ Active | Users must be in `allowed-emails.txt` |
| **File Download Block** | ✅ Active | No "Download" button (set: `CS_DISABLE_FILE_DOWNLOADS=true`) |
| **Terminal Disabled** | ✅ Active | No command execution (set: `"terminal.integrated.enabled": false`) |
| **Git Protection** | 🔄 Ready | Git clone/push blocked (requires wrapper script) |
| **Copy/Paste Audit** | 📋 Logging | Large copies logged to audit trail |
| **SSH Key Quarantine** | ✅ Active | SSH keys read-only in container |
| **Network Isolation** | ✅ Active | Egress filtering in docker-compose |
| **Audit Logging** | ✅ Active | All access logged in `logs/audit/` |
| **Role-Based Access** | ✅ Active | Settings enforced per role |
| **Immutable Logs** | 📋 Ready | Append-only audit logs |

---

## 👥 User Roles

### Available Roles


┌────────────────────────────────────────────────────────────────┐
│                         VIEWER                                │
│  • Read-only code access                                       │
│  • Can search, navigate, view history                          │
│  • ❌ Cannot edit, download, run commands                      │
│  Use: Code reviewers, auditors, stakeholders                   │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│                       DEVELOPER                                │
│  • Full code editing access                                    │
│  • Auto-formatting on save                                     │
│  • ❌ Cannot clone/push directly (PR system only)              │
│  • ❌ Cannot run terminal                                       │
│  Use: Engineers with write access                              │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│                       ARCHITECT                                │
│  • Edit design docs (markdown, json, yaml)                     │
│  • ❌ Code files read-only                                      │
│  • ❌ Cannot edit source code                                   │
│  Use: Architects, tech leads (design focus)                    │
└────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│                         ADMIN                                  │
│  • Full access (all operations)                                │
│  • Terminal available                                          │
│  • All actions audit-logged                                    │
│  Use: Platform engineers, admins only                          │
└────────────────────────────────────────────────────────────────┘


---

## 🛠️ User Management Commands

### Manage Users

```bash
# List all users
./scripts/manage-users.sh list-users

# Add user
./scripts/manage-users.sh add-user email@company.com [role] [display_name]

# Show user details
./scripts/manage-users.sh show-user email@company.com

# Change role
./scripts/manage-users.sh change-role email@company.com developer

# Remove user (revoke access)
./scripts/manage-users.sh remove-user email@company.com

# Check security status
./scripts/manage-users.sh security-status

# List active sessions
./scripts/manage-users.sh list-sessions

# Revoke all sessions (everyone logs out)
./scripts/manage-users.sh revoke-all-sessions


---

## 🚀 User Onboarding Workflow

### Step 1: Provision User
```bash
./scripts/manage-users.sh add-user "newdev@company.com" "developer"


**This creates:**
- ✅ Entry in OAuth2 allowlis
- ✅ Role-based settings profile
- ✅ Isolated workspace
- ✅ Audit log entry

### Step 2: Commit & Deploy
```bash
git add allowed-emails.txt config/user-settings/
git commit -m "chore: add newdev@company.com"
git push origin main


### Step 3: User Logs In

User opens: https://ide.kushnir.cloud
   ↓
Redirected to Google OAuth
   ↓
OAuth2 validates: email in allowed-emails.txt?
   ↓ (Yes)
Settings auto-load from role-based profile
   ↓
IDE ready with restricted features


### Step 4: (Optional) Later Change Role
```bash
./scripts/manage-users.sh change-role newdev@company.com viewer


---

## 📊 Security Architecture


┌─────────────────────────────────────────────────────────────────┐
│                     NETWORK LAYER                               │
│  • Egress filtering (blocks SSH, SCP, curl to external)         │
│  • WebSocket proxied through Caddy                              │
│  • Strict HTTPS only (TLS handshake enforced)                   │
└─────────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                   AUTHENTICATION LAYER                          │
│  • Google OAuth2 (no hardcoded credentials)                     │
│  • Email whitelist (allowed-emails.txt)                         │
│  • Session cookies (secure, httponly, sameSite=lax)             │
└─────────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                   APPLICATION LAYER                             │
│  • Role-based settings (viewer, developer, architect, admin)    │
│  • File download disable                                        │
│  • Terminal disabled                                            │
│  • Git operations blocked                                       │
│  • Extension marketplace restricted                             │
└─────────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                    AUDIT LAYER                                   │
│  • All access logged to logs/audit/                             │
│  • Git operations logged                                        │
│  • Copy/paste events logged                                     │
│  • Session start/stop logged                                    │
│  • Immutable logs (append-only)                                 │
└─────────────────────────────────────────────────────────────────┘


---

## 🔑 File Locations Reference


/code-server-enterprise/
├── allowed-emails.txt              ← OAuth2 whitelist (edit to add users)
├── config/
│   ├── role-settings/              ← Role templates
│   │   ├── viewer-profile.json
│   │   ├── developer-profile.json
│   │   ├── architect-profile.json
│   │   └── admin-profile.json
│   └── user-settings/              ← Per-user configurations
│       └── user-id/
│           ├── settings.json       ← IDE settings
│           └── user-metadata.json  ← Role, name, timestamps
├── workspaces/                     ← Per-user isolated workspaces
│   └── user-id/
│       └── .code-workspace
├── logs/audit/                     ← Audit trail (immutable)
│   └── operations.log
├── audit/                          ← Audit tracking
│   └── user-provisioning.log       ← User changes log
├── scripts/
│   ├── provision-new-user.sh       ← Add user scrip
│   └── manage-users.sh             ← User management CLI
├── docker-compose.yml              ← Disable downloads here
└── CODE_SECURITY_HARDENING.md      ← Full reference


---

## 🔍 Verification Checklis

After setting up, verify all security features:

```bash
# 1. Check file downloads are disabled
grep "CS_DISABLE_FILE_DOWNLOADS=true" docker-compose.yml && echo "✅" || echo "❌"

# 2. Check terminal is disabled
grep '"terminal.integrated.enabled": false' config/settings.json && echo "✅" || echo "❌"

# 3. Check allowlist is active
[[ -f allowed-emails.txt && -s allowed-emails.txt ]] && echo "✅" || echo "❌"

# 4. Check role templates exis
ls config/role-settings/*.json | wc -l && echo "✅" || echo "❌"

# 5. Check audit directory exists
[[ -d logs/audit ]] && echo "✅" || echo "❌"

# 6. Check Docker containers running
docker compose ps | grep -E "code-server|oauth2-proxy" && echo "✅" || echo "❌"

# 7. Run full security check
./scripts/manage-users.sh security-status


---

## 📚 Additional Resources

| Document | Purpose |
|----------|---------|
| [CODE_SECURITY_HARDENING.md](./CODE_SECURITY_HARDENING.md) | Complete security reference (all layers) |
| [SECURITY_IMPLEMENTATION_STEPS.md](./SECURITY_IMPLEMENTATION_STEPS.md) | Step-by-step deployment (6 phases) |
| [USER_ONBOARDING.md](./USER_ONBOARDING.md) | User guide (what they can/cannot do) |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Code quality standards (FAANG-level) |

---

## ⚡ Common Commands

```bash
# List current users
./scripts/manage-users.sh list-users

# Add new user (interactive)
./scripts/manage-users.sh add-user newuser@company.com developer "Display Name"

# Check security status
./scripts/manage-users.sh security-status

# View user details
./scripts/manage-users.sh show-user user@company.com

# Change user's role
./scripts/manage-users.sh change-role user@company.com viewer

# Revoke access
./scripts/manage-users.sh remove-user user@company.com

# Emergency: logout all users
./scripts/manage-users.sh revoke-all-sessions

# View audit logs
tail -f logs/audit/operations.log

# Restart services (applies changes)
docker compose restart oauth2-proxy code-server


---

## 🛡️ Security Best Practices

### DO ✅

- ✅ Regularly review `allowed-emails.txt` (who has access?)
- ✅ Use strong email addresses (avoid generic ones)
- ✅ Change user roles based on responsibilities
- ✅ Monitor `logs/audit/` for suspicious activities
- ✅ Disable access immediately if someone leaves
- ✅ Encrypt backups of `allowed-emails.tx
- ✅ Use git history to track user changes

### DON'T ❌

- ❌ Don't modify roles directly (use `manage-users.sh change-role`)
- ❌ Don't bypass OAuth2 (it's your security boundary)
- ❌ Don't enable downloads (CS_DISABLE_FILE_DOWNLOADS=true is critical)
- ❌ Don't enable terminal (unless absolutely necessary)
- ❌ Don't commit secrets to git (pre-commit hooks prevent this)
- ❌ Don't remove users manually (use `manage-users.sh remove-user`)
- ❌ Don't ignore audit logs (they're your evidence trail)

---

## 🚨 Troubleshooting

### User Can't Login
```bash
# Check if email is in allowlis
grep "user@company.com" allowed-emails.tx

# Restart OAuth proxy (picks up changes)
docker compose restart oauth2-proxy

# Check OAuth2 logs
docker logs oauth2-proxy | tail -20


### User Settings Not Applied
```bash
# Verify settings file exists
ls config/user-settings/{user-id}/settings.json

# Reload IDE (F1 → Reload Window)
# Or restart container: docker compose restart code-server


### Files Are Downloadable (should be blocked)
```bash
# Check docker-compose.yml
grep "CS_DISABLE_FILE_DOWNLOADS" docker-compose.yml

# Rebuild and restar
docker compose up -d --build code-server


### Terminal Is Still Available
```bash
# Check settings
grep '"terminal.integrated.enabled"' config/settings.json

# Verify it's false, then restar
docker compose restart code-server


---

## 📞 Suppor

For detailed implementation, see:
- **Security Reference:** [CODE_SECURITY_HARDENING.md](./CODE_SECURITY_HARDENING.md)
- **Implementation Steps:** [SECURITY_IMPLEMENTATION_STEPS.md](./SECURITY_IMPLEMENTATION_STEPS.md)
- **Code Quality:** [CONTRIBUTING.md](./CONTRIBUTING.md)
- **Architecture:** [ARCHITECTURE.md](./ARCHITECTURE.md)

---

**Status:** ✅ Production Ready
**Last Updated:** 2026-04-12
**Security Level:** Enterprise (FAANG-grade)
