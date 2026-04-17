# OAuth Account Chooser Implementation Playbook

**Issue**: #645 - fix(oauth): implement account chooser and resolve org_internal restriction  
**Blocked By**: #644 - diagnose(oauth): RCA org_internal restriction  
**Parent Issue**: #643 - OAuth Access Control: Fix org_internal 403 on kushnir.cloud  

---

## Overview

This playbook provides step-by-step implementation procedures for each possible root cause identified in RCA (#644). Use the root cause classification from that RCA to select the appropriate scenario below.

---

## Scenario A: Wrong OAuth App Configured

**RCA finding**: The deployed Google OAuth app is a test/staging app instead of the production app.

**Root causes that lead here**:
- Terraform/Compose config references wrong app credentials
- .env file has stale test credentials
- Environment variables point to test app in Google Cloud Console

### Step A1: Obtain Production Credentials

```bash
# Contact Google Cloud admin or check secure credentials store
# Production app should have:
# - Client ID: prod_client_id_here
# - Client Secret: prod_client_secret_here
# - Redirect URIs: https://kushnir.cloud/oauth2/callback, etc.

# Verify in Google Cloud Console:
# 1. Select correct project (production, not test)
# 2. Go to APIs & Services → Credentials
# 3. Find OAuth 2.0 Client ID for production app
# 4. Copy Client ID and Client Secret
```

### Step A2: Update Configuration Files

**Option A2a: Update terraform/variables.tf**

```bash
# SSH to production host
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Edit variables.tf
nano terraform/variables.tf

# Find and update:
variable "google_oauth_client_id" {
  default = "REPLACE_WITH_PRODUCTION_CLIENT_ID"
}

variable "google_oauth_client_secret" {
  default = "REPLACE_WITH_PRODUCTION_CLIENT_SECRET"
}

# Save (Ctrl+X, Y, Enter)
```

**Option A2b: Update .env file (faster, immediate effect)**

```bash
# SSH to production host if not already there
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Edit .env (or .env.oauth2-proxy if it exists separately)
nano .env

# Find and update:
OAUTH2_PROXY_CLIENT_ID=PRODUCTION_CLIENT_ID_HERE
OAUTH2_PROXY_CLIENT_SECRET=PRODUCTION_CLIENT_SECRET_HERE

# Save (Ctrl+X, Y, Enter)
```

### Step A3: Redeploy oauth2-proxy

```bash
# Option 1: Redeploy via docker-compose (fastest)
docker compose up -d oauth2-proxy-portal

# Option 2: Redeploy via Terraform
terraform apply -target=docker_container.oauth2_proxy_portal -auto-approve

# Verify new credentials are loaded
docker compose logs oauth2-proxy-portal 2>&1 | grep -i "client_id\|oauth" | head -5
```

### Step A4: Verify Deployment

```bash
# Check oauth2-proxy-portal is running and healthy
docker compose ps oauth2-proxy-portal

# Expected: Container should be "Up" and healthy check should pass

# Verify new client ID is active (should match PRODUCTION_CLIENT_ID)
docker compose exec oauth2-proxy-portal env | grep OAUTH2_PROXY_CLIENT_ID

# Check logs for successful startup
docker compose logs oauth2-proxy-portal | tail -20
```

### Step A5: Test Authentication Flow

**Test in browser**:
1. Open incognito/private window
2. Navigate to `https://kushnir.cloud`
3. Click "Sign in with Google"
4. Select or enter kushin77@gmail.com
5. Complete Google OAuth consent (if first time)
6. Expected: Redirected to code-server workspace (not 403 error)

**If successful**:
- ✅ Root cause fixed
- ✅ Comment in issue #645: "Scenario A fix applied: production app credentials deployed"
- ✅ Run testing checklist (Step 8)

**If still fails**:
- Verify client ID matches Google Cloud Console value
- Check oauth2-proxy logs for auth errors: `docker compose logs oauth2-proxy-portal | grep -i "error\|denied"`
- May indicate additional root cause (check Scenario B-D)

---

## Scenario B: Overly Restrictive Organization Allowlist

**RCA finding**: Google OAuth app has organization-only restrictions that are blocking valid users.

**Root causes that lead here**:
- OAuth consent screen configured for "Internal" users (org only)
- Specific allowed domains list excludes user's domain
- User allowlist configured but user not listed
- Organization membership verification failing

### Step B1: Access Google Cloud Console

```
1. Go to https://console.cloud.google.com
2. Select the PRODUCTION project (from Scenario A)
3. Navigate to APIs & Services → Credentials
4. Find the OAuth 2.0 Client ID being used
5. Click on it to view details
6. Go to "Application settings" or OAuth Consent Screen tab
```

### Step B2: Check User Type Restrictions

In Google Cloud Console:

```
OAuth Consent Screen → User Type Settings:

Current: [ ] Internal    [X] External
         [X] All users   [ ] Limited users

Risk: If set to "Internal" only, external users (like kushin77@gmail.com) 
will be blocked even if they should have access.

Action if "Internal" only:
- Change to "External" to allow Gmail accounts
- Or change to "All users" for maximum compatibility
```

### Step B3: Review Allowed Domains/Users

In Google Cloud Console:

```
OAuth Consent Screen → Allowed Domains (if configured):

Current list:
- company.com
- organization.com

Issue: If kushin77@gmail.com is required but not in allowed domains, 
they cannot authenticate.

Action:
Option 1: Add @gmail.com to allowed domains (if policy allows)
Option 2: Remove allowed domains restriction if not needed
Option 3: Add specific email addresses to user allowlist
```

### Step B4: Update Organization Restrictions (if needed)

```
Steps in Google Cloud Console:

1. OAuth Consent Screen → User Type → Change to "External" or "All users"
2. Save changes (allow 5-10 minutes for cache propagation)
3. If domain/user allowlist exists, update as needed
4. Note: Changes may require re-consent from users on next login
```

### Step B5: Test Authentication Flow

**Test in browser** (same as Step A5):
1. Incognito window → `https://kushnir.cloud`
2. Sign in with kushin77@gmail.com
3. Complete Google consent if prompted
4. Expected: Workspace access granted (not 403 org_internal)

**If successful**:
- ✅ Restrictions relaxed
- ✅ Comment in #645: "Scenario B fix applied: Organization allowlist relaxed in Google Cloud Console"
- ✅ Run testing checklist (Step 8)

**If still blocked**:
- Verify cache has propagated (can take 10+ minutes)
- Check if additional restrictions apply (e.g., device policy, IP allowlist)
- May indicate Scenario C or D

---

## Scenario C: Missing Account Chooser UI

**RCA finding**: oauth2-proxy is not showing account selection option when authentication fails.

**Root causes that lead here**:
- `skip_provider_button=true` (should be false)
- Provider button disabled in config
- Account chooser not configured in oauth2-proxy
- Login URL not properly configured

### Step C1: Update oauth2-proxy Configuration

**SSH to production host**:

```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
```

**Edit .env file (or .env.oauth2-proxy)**:

```bash
nano .env

# Find and update these settings:
# Option 1: Enable provider button (default account chooser)
OAUTH2_PROXY_SKIP_PROVIDER_BUTTON=false

# Option 2: Set login URL to show account chooser on failure
OAUTH2_PROXY_LOGIN_URL=/oauth2/sign_in

# Option 3: Configure consent prompt to always show account selector
OAUTH2_PROXY_PROMPT=consent

# Option 4: Allow offline access (enables re-authentication)
OAUTH2_PROXY_ACCESS_TYPE=offline

# Save (Ctrl+X, Y, Enter)
```

### Step C2: Redeploy oauth2-proxy

```bash
# Redeploy with updated config
docker compose up -d oauth2-proxy-portal

# Verify config is loaded
docker compose logs oauth2-proxy-portal 2>&1 | grep -i "skip_provider\|login_url"

# Check service is healthy
docker compose ps oauth2-proxy-portal
```

### Step C3: Test Account Chooser UI

**Test in browser**:

```
1. Open incognito window → https://kushnir.cloud
2. Click "Sign in with Google"
3. Expected: See "Choose an account" page or account selector
4. If auth fails (403 or permission denied):
   - Should see "Try another account" option
   - Click to return to account selector
5. If successful: Workspace access granted
```

**Expected behavior after fix**:
- ✅ Account selector appears on initial signin
- ✅ User can switch between accounts if multiple are logged in
- ✅ On auth failure, "Try another account" link appears
- ✅ Can retry with different Google identity

### Step C4: Verify Account Chooser Works

```bash
# Test multiple OAuth flow scenarios:

Scenario 1: Initial login with account selector
- Result: User can select from available Google accounts

Scenario 2: Failed auth → account chooser
- Result: User sees "Try another account" option and can retry

Scenario 3: Switch accounts
- Result: User can select different Google identity

# If all pass:
# ✅ Comment in #645: "Scenario C fix applied: Account chooser UI enabled"
# ✅ Run testing checklist (Step 8)
```

---

## Scenario D: User Not in Organization (Legitimate Restriction)

**RCA finding**: User (kushin77@gmail.com) is legitimately NOT supposed to have access; restriction is intentional.

**Root causes that lead here**:
- OAuth allowlist configured to limit specific users
- Organization membership verification is working correctly
- Access policy deliberately restricts to organization members only
- User needs to be added to allowlist or granted different auth credentials

### Step D1: Verify Restriction is Intentional

```bash
# Review current oauth2-proxy configuration
ssh akushnir@192.168.168.31
cd code-server-enterprise

docker compose exec oauth2-proxy-portal cat /etc/oauth2-proxy/allowed-emails.txt 2>/dev/null | head -20

# If file exists and doesn't contain kushin77@gmail.com:
# This is a DELIBERATE allowlist — restriction is intentional

# Check if organization verification is in place:
docker compose logs oauth2-proxy-portal 2>&1 | grep -i "org.*verify\|allowed.*group\|member"
```

### Step D2: Decide: Allow User or Keep Restricted?

**Decision Tree**:

```
Is kushin77@gmail.com supposed to have access?
├─ YES → Skip to Step D3 (Add to allowlist)
└─ NO  → Skip to Step D4 (Document policy)
```

### Step D3: Add User to Allowlist (if should be allowed)

```bash
# SSH to production host
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Option A: Add to allowed-emails.txt if using email allowlist
echo "kushin77@gmail.com" >> allowed-emails.txt

# Restart oauth2-proxy to reload allowlist
docker compose restart oauth2-proxy-portal

# Verify restart successful
docker compose ps oauth2-proxy-portal
docker compose logs oauth2-proxy-portal | tail -5

# Test authentication again
# Expected: kushin77@gmail.com should now authenticate successfully
```

### Step D4: Document Access Policy (if should stay restricted)

Create/update authentication runbook:

```bash
# Edit or create docs/OAUTH-AUTHENTICATION-POLICY.md

cat > docs/OAUTH-AUTHENTICATION-POLICY.md << 'EOF'
# OAuth Authentication Policy

## Organization-Only Access Policy

Code-server on kushnir.cloud is configured for **organization-only access**.

### Allowed Users

Only members of [YOUR_ORGANIZATION_NAME] are permitted to authenticate.

**Currently authorized**:
- users@organization.com (all @organization.com domain)
- admin@example.com (specific users)

**Explicitly denied**:
- External Gmail accounts (e.g., @gmail.com)
- Personal email addresses

### Adding New Users

To authorize a new user:

1. Verify they are an organization member
2. Contact infrastructure team to add email to allowlist
3. Allowlist: `/etc/oauth2-proxy/allowed-emails.txt`
4. Redeploy: `docker compose restart oauth2-proxy-portal`

### Account Chooser UX

If user sees "Error 403: org_internal":
1. This indicates they are NOT in the allowed organization
2. Try signing in with their organization email instead
3. If issue persists, contact infrastructure team

## Troubleshooting

**Q: Why did my personal Gmail account get blocked?**  
A: This instance restricts access to organization members only.

**Q: Can I use both org and personal accounts?**  
A: Only organization accounts are allowed per policy.

**Q: Who can add new users?**  
A: Contact [ADMIN_EMAIL] to request access.
EOF

cat docs/OAUTH-AUTHENTICATION-POLICY.md
```

### Step D5: Communicate Policy

```bash
# Update code-server welcome page or docs
# Add to: docs/README-AUTHENTICATION.md

cat >> docs/README-AUTHENTICATION.md << 'EOF'

## Authentication Requirements

This instance requires organization membership to access.

✅ If you have an @organization.com account: Use that to sign in
❌ If you only have a @gmail.com account: Request organization credentials
❌ If you're not an organization member: Access is not permitted per policy

EOF
```

---

## Step E: Universal Testing Checklist (for all scenarios)

After applying any scenario A-D fix, run these tests:

### E1: Test Primary Account

```bash
Browser: Incognito window
URL: https://kushnir.cloud
Actions:
  1. Click "Sign in with Google"
  2. Select kushin77@gmail.com
  3. Complete consent if prompted
  4. Wait for redirect
Result: 
  ✅ Redirected to code-server workspace
  ✅ Can see file explorer
  ✅ Can edit a test file
  ❌ If 403/error, note error message
```

### E2: Test Different Account (if applicable)

```bash
Browser: Same or different incognito window
Account: admin@organization.com or another test account
Actions:
  1. Click "Sign in with Google"
  2. Select different account
  3. Complete auth
Result:
  ✅ Account switching works
  ✅ Second account authenticated
  ✅ Workspace loads successfully
```

### E3: Test Error Scenarios

```bash
Scenario: Sign in with unallowed account (if allowlist in place)
Browser: Incognito
Actions:
  1. Try account that should NOT have access
  2. Complete Google consent
Result:
  ✅ Receives clear error message (not cryptic 403)
  ✅ Error message indicates access denied reason
  ✅ User can click "Try another account"

Scenario: Account chooser on failure
Result:
  ✅ If auth fails, "Try another account" button appears
  ✅ Can select different Google identity
```

### E4: Test Code-Server Functionality

```bash
After successful login:
1. Can see file explorer panel
2. Can create/edit a test file
3. Can save changes
4. Can use terminal (if enabled)
5. Can install extensions (if enabled)
Result:
  ✅ All basic functionality works
  ✅ No console errors (F12 → Console)
```

### E5: Regression Testing

```bash
Test existing users (if any were already authenticated):
1. Can existing users still access?
2. No new auth errors appearing?
3. Performance acceptable?

Actions:
  1. Ask team members to test access
  2. Monitor oauth2-proxy logs for errors:
     docker compose logs -f oauth2-proxy-portal | grep -i error
```

### E6: Post-Deployment Monitoring

```bash
Monitor for 24 hours:

docker compose logs oauth2-proxy-portal | grep -i "error\|denied\|failed" | wc -l

If error count spikes:
  - Indicate deployment issue
  - Trigger rollback (see rollback procedures)
```

---

## Rollback Procedure (if deployment fails)

```bash
# SSH to production
ssh akushnir@192.168.168.31
cd code-server-enterprise

# Identify previous working image tag
git log --oneline | head -5

# Revert to previous oauth2-proxy image
docker compose pull oauth2-proxy-portal:v7.5.1  # Specific known-good version

# Restart with previous config
docker compose down oauth2-proxy-portal
docker compose up -d oauth2-proxy-portal

# Verify services restored
docker compose ps oauth2-proxy-portal
docker compose logs oauth2-proxy-portal | tail -10

# Test authentication again
# Expected: Original behavior restored
```

---

## Summary: Which Scenario Did You Use?

After completing implementation:

**Document in issue #645**:

```markdown
## Implementation Complete ✅

**Scenario Applied**: [A / B / C / D]

**Root Cause**: [Description of what was wrong]

**Actions Taken**:
- [X] Updated [file/config]
- [X] Redeployed [service]
- [X] Verified [behavior]

**Test Results**:
- [X] Primary account (kushin77@gmail.com) authenticates
- [X] Error messages are user-friendly
- [X] Account chooser works (if applicable)
- [X] Code-server workspace loads
- [X] No regression in other users

**Evidence**:
- Screenshot: [Successful auth page]
- Logs: [oauth2-proxy successful startup]
- Test results: [All passing]

**Ready for deployment to production**
```

---

**Playbook Status**: Ready to execute once RCA (#644) completes  
**Last Updated**: April 17, 2026  
**Version**: 1.0
