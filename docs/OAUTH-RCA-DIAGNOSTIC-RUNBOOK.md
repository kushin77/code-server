# OAuth org_internal Error RCA — Diagnostic Runbook

**Issue**: #644 - diagnose(oauth): RCA org_internal restriction and OAuth app configuration  
**Parent Issue**: #643 - OAuth Access Control: Fix org_internal 403 on kushnir.cloud  
**Related Fix**: #645 - Account chooser implementation  

---

## Problem Statement

Users attempting to authenticate via kushnir.cloud receive:

```
Access blocked: ElevatedIQ Portal can only be used within its organization
Error 403: org_internal
Account: kushin77@gmail.com
```

This diagnostic runbook traces the OAuth flow and identifies root cause.

---

## Prerequisites

- SSH access to production host: `ssh akushnir@192.168.168.31`
- Docker Compose running on remote host
- Browser with developer tools (Network tab)
- Google Cloud Console access to OAuth app settings

---

## Step 1: Verify OAuth Proxy Instance & Routing

### 1a. Check which oauth2-proxy containers are running

```bash
ssh akushnir@192.168.168.31
docker compose ps | grep oauth2-proxy
```

**Expected output** (2 containers):
- `oauth2-proxy` (main IDE proxy, port 4180)
- `oauth2-proxy-portal` (portal proxy, port 4181)

**Diagnostic questions**:
- Are both containers running?
- What versions are they (should be v7.5.1)?
- Are they healthy or restarting?

### 1b. Check Caddyfile routing for kushnir.cloud

```bash
cat Caddyfile | grep -A 5 "kushnir.cloud"
```

**Expected routing**:
```
kushnir.cloud {
    # Portal traffic
    reverse_proxy oauth2-proxy-portal:4181
}
```

**Key verification**:
- ✅ kushnir.cloud should route to `oauth2-proxy-portal:4181`, NOT `oauth2-proxy:4180`
- If pointing to wrong port, root cause is **routing misconfiguration**

---

## Step 2: Extract oauth2-proxy Configuration

### 2a. Check portal proxy environment variables

```bash
docker compose exec oauth2-proxy-portal env | grep -E "OAUTH|CLIENT|DOMAIN|RESTRICT|ORG" | sort
```

**Critical env vars to verify**:
- `OAUTH2_PROXY_CLIENT_ID` — Google OAuth app ID (should be production app)
- `OAUTH2_PROXY_OIDC_ISSUER_URL` — Google OAuth issuer (should be `https://accounts.google.com`)
- `OAUTH2_PROXY_ALLOWED_GROUPS` — Organization/group restrictions (if any)
- `OAUTH2_PROXY_ALLOWED_EMAILS` — Email allowlist (if any)
- `OAUTH2_PROXY_SCOPE` — OAuth scopes requested from Google
- `OAUTH2_PROXY_SKIP_PROVIDER_BUTTON` — Should be `false` (show account chooser)

### 2b. Capture full oauth2-proxy configuration

```bash
docker compose exec oauth2-proxy-portal cat /etc/oauth2-proxy/oauth2-proxy.cfg 2>/dev/null || echo "Config mounted from .env"
```

**If using .env file**:
```bash
docker compose config | grep -A 30 "oauth2-proxy-portal"
```

### 2c. Extract the OAuth2 app credentials

```bash
docker compose exec oauth2-proxy-portal env | grep -E "CLIENT_ID|CLIENT_SECRET|REDIRECT"
```

**Security note**: CLIENT_SECRET will be visible — keep this safe during diagnostics.

---

## Step 3: Identify Google OAuth App Configuration

### 3a. Determine which Google OAuth app is deployed

```bash
# From the CLIENT_ID extracted above
CLIENT_ID=$(docker compose exec oauth2-proxy-portal env | grep OAUTH2_PROXY_CLIENT_ID | cut -d= -f2)
echo "Deployed Client ID: $CLIENT_ID"

# Compare with expected production/test apps
echo "Expected Production App: [PROD_CLIENT_ID_FROM_TERRAFORM]"
echo "Expected Test App: [TEST_CLIENT_ID_FROM_TERRAFORM]"
```

**Classification**:
- If CLIENT_ID matches **test/staging app**: Root cause is **wrong app deployed**
- If CLIENT_ID matches **production app**: Root cause is **org restrictions** or **allowlist issues**

### 3b. Check Google Cloud Console for organization restrictions

1. Navigate to [Google Cloud Console](https://console.cloud.google.com)
2. Select the OAuth app project
3. Go to **APIs & Services** → **Credentials**
4. Find the OAuth 2.0 Client ID matching the deployed `CLIENT_ID`
5. Check **Authorized redirect URIs**: Should include `https://kushnir.cloud/oauth2/callback`
6. Check for **OAuth consent screen** settings:
   - User type: Internal or External?
   - Organization restrictions enabled?
   - Allowed domains/email domains?
   - Organization members allowlist?

**Document findings**:
- [ ] App name (test vs. production)
- [ ] Authorized redirect URIs (includes kushnir.cloud?)
- [ ] User type (Internal/External)
- [ ] Organization restrictions (enabled/disabled)
- [ ] Allowed domains (if restricted)
- [ ] Allowed email domains (if restricted)
- [ ] Specific user allowlist (includes kushin77@gmail.com?)

---

## Step 4: Examine OAuth Request/Response Flow

### 4a. Capture oauth2-proxy logs during failed auth attempt

In terminal 1 (keep logs running):
```bash
docker compose logs -f oauth2-proxy-portal 2>&1 | grep -E "ERROR|WARN|org_internal|consent|403"
```

In terminal 2 (trigger auth flow):
```bash
# In browser: Navigate to https://kushnir.cloud
# Wait for 403 error
# In terminal 1, look for error messages
```

**Key log patterns to look for**:
- `"org_internal"` — Error coming from Google OAuth directly
- `"invalid_scope"` — oauth2-proxy requesting invalid scopes
- `"redirect_uri_mismatch"` — Redirect URI not in Google Console allowlist
- `"OIDC validation failed"` — OIDC configuration issue
- `"access_denied"` — Google explicitly blocking user/org
- `"no permission"` — Organization membership verification failed

### 4b. Capture browser Network tab

1. Open browser developer tools (F12)
2. Go to **Network** tab
3. Clear network log
4. Navigate to `https://kushnir.cloud`
5. Click "Sign in with Google"
6. Complete auth flow until 403 error
7. **Export HAR file**: Right-click → Save all as HAR with content

**Analyze requests**:
- Initial request: `https://kushnir.cloud/`
- Redirect to: `https://kushnir.cloud/oauth2/start?rd=...`
- Redirect to: `https://accounts.google.com/o/oauth2/v2/auth?...`
- Final response: Look for `error=...&error_description=...` in redirect

---

## Step 5: Check Allowed Emails / Organization Allowlist

### 5a. Review allowed-emails.txt (if used)

```bash
cat allowed-emails.txt | head -20
echo "..."
wc -l allowed-emails.txt
```

**Questions**:
- Does it contain `kushin77@gmail.com`?
- Are other test accounts listed?
- Is this file being mounted in oauth2-proxy?

### 5b. Check oauth2-proxy-portal logs for email validation

```bash
docker compose logs oauth2-proxy-portal 2>&1 | grep -E "allowed_emails|kushin77|email.*denied"
```

---

## Step 6: Root Cause Classification

Based on evidence collected, classify the error:

| Classification | Evidence | Remediation |
|---|---|---|
| **Wrong OAuth app** | Deployed app ID is test/staging, not production | Update oauth2-proxy env vars to use production app credentials |
| **Overly restrictive org config** | App has organization restrictions + user not in allowed list | Add user to organization or relax restrictions in Google Cloud Console |
| **Missing account chooser UX** | Logs show access denied, but no account selection prompt | Enable `--skip-provider-button=false` in oauth2-proxy config |
| **Redirect URI mismatch** | Logs show `redirect_uri_mismatch` error | Add `https://kushnir.cloud/oauth2/callback` to Google Cloud Console authorized URIs |
| **Invalid OIDC scope** | Logs show scope validation failure | Update OIDC scopes in oauth2-proxy config to match Google app settings |
| **Legitimate restriction** | User not in allowed email list + email allowlist is intentional | Either add user to allowed list or remove allowlist policy if not needed |

---

## Step 7: Evidence Collection Checklist

- [ ] Screenshot of 403 error page (browser)
- [ ] HAR export from Network tab (browser dev tools)
- [ ] oauth2-proxy-portal container logs (5+ minutes around failure)
- [ ] Caddyfile routing config (verify kushnir.cloud block)
- [ ] oauth2-proxy-portal env vars (CLIENT_ID, OIDC_ISSUER, scope, allowlist settings)
- [ ] Google Cloud Console OAuth app settings (verified by human)
- [ ] Docker Compose config for oauth2-proxy-portal service definition
- [ ] Output of `docker compose ps` (container health check)

---

## Step 8: Documentation Template

Create GitHub issue comment with findings:

```markdown
### OAuth RCA Findings

**Root Cause**: [Classification from Step 6]

**Evidence**:
- Container status: [Running/Restarting/Unhealthy]
- Deployed OAuth app: [App name + ID]
- Expected app: [Production/Test]
- Caddyfile routing: [✅ Correct / ❌ Wrong]
- Organization restrictions: [Enabled/Disabled]
- User [kushin77@gmail.com] in allowlist: [Yes/No/N/A]

**Logs**:
```
[Key error messages from oauth2-proxy logs]
```

**Browser Network Flow**:
```
1. POST https://kushnir.cloud/ → 302 redirect
2. GET https://kushnir.cloud/oauth2/start?rd=... → 302 redirect
3. GET https://accounts.google.com/o/oauth2/v2/auth?... → 200 (Google consent)
4. POST https://accounts.google.com/o/oauth2/token → 200 (token received)
5. [Final request that returned 403]
```

**Remediation Path**: [Based on classification]
```

---

## Quick Reference: Common Solutions

### Solution A: Fix wrong OAuth app
```bash
# Update .env.oauth2-proxy with production app credentials
OAUTH2_PROXY_CLIENT_ID=<production_client_id>
OAUTH2_PROXY_CLIENT_SECRET=<production_client_secret>

# Redeploy
docker compose up -d oauth2-proxy-portal
```

### Solution B: Add user to allowed list
```bash
# Edit allowed-emails.txt
echo "kushin77@gmail.com" >> allowed-emails.txt

# Restart oauth2-proxy to reload allowlist
docker compose restart oauth2-proxy-portal
```

### Solution C: Enable account chooser
```bash
# Add to .env.oauth2-proxy
OAUTH2_PROXY_SKIP_PROVIDER_BUTTON=false

# Redeploy
docker compose up -d oauth2-proxy-portal
```

### Solution D: Relax or remove organization restrictions
1. Go to Google Cloud Console → OAuth app
2. Disable organization restrictions in OAuth consent screen
3. Save and restart oauth2-proxy-portal

---

## Next Steps

1. **Run all diagnostic steps** (1-7) and collect evidence
2. **Classify root cause** using Step 6 classification table
3. **Apply corresponding solution** from Quick Reference
4. **Test auth flow** after remediation
5. **Document findings** in issue #644 as comment
6. **Unblock #645** (account chooser implementation) once root cause is known

---

**Runbook Version**: 1.0  
**Last Updated**: April 17, 2026  
**Status**: Ready for diagnostics execution
