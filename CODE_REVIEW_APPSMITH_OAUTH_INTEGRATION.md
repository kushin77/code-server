# Code Review: Appsmith OAuth Integration & VPN Test RCA
**Date:** April 30, 2026  
**Status:** 🔴 CRITICAL - OAuth Credentials Missing  
**Impact:** Appsmith cannot authenticate users; kushnir.cloud connection error  

---

## Executive Summary

The Appsmith OAuth integration is **architecturally sound but functionally incomplete**:
- ✅ Caddyfile routing configured correctly
- ✅ docker-compose.enterprise.yml has OAuth environment variables defined
- ✅ Documentation is comprehensive
- ❌ **CRITICAL:** OAuth credentials are not deployed (empty values)
- ❌ **CRITICAL:** .env file with credentials is missing
- ❌ **RESULT:** Users cannot log in; kushnir.cloud shows `ERR_CONNECTION_CLOSED`

---

## Root Cause Analysis (RCA)

### Symptom
```
kushnir.cloud - unexpectedly closed the connection
ERR_CONNECTION_CLOSED
```

### Root Causes

#### 1. Missing OAuth Credentials (PRIMARY)
**File:** `docker-compose.enterprise.yml` (Lines 224-227)

```yaml
# PROBLEMATIC CODE:
- OAUTH_GOOGLE_CLIENT_ID=${OAUTH_GOOGLE_CLIENT_ID:-}      # ❌ Empty!
- OAUTH_GOOGLE_CLIENT_SECRET=${OAUTH_GOOGLE_CLIENT_SECRET:-}  # ❌ Empty!
- OAUTH_GITHUB_CLIENT_ID=${OAUTH_GITHUB_CLIENT_ID:-}      # ❌ Empty!
- OAUTH_GITHUB_CLIENT_SECRET=${OAUTH_GITHUB_CLIENT_SECRET:-}  # ❌ Empty!
```

**Issue:** The `-` default is empty string, so Appsmith starts without OAuth providers configured.

**Impact:**
- Appsmith starts but has no authentication backend
- User navigates to https://kushnir.cloud
- Appsmith returns error (no OAuth provider configured)
- Browser shows connection closed error

#### 2. Missing .env File (SECONDARY)
**Expected:** `/home/akushnir/code-server/.env`  
**Actual:** File does not exist  

**Issue:** Documentation says to create `.env` with OAuth credentials, but the file was never created or deployed.

**Impact:**
- docker-compose falls back to empty defaults
- Service starts without credentials
- VPN test fails because infrastructure is inaccessible

#### 3. Unverified VPN Connectivity (TERTIARY)
**After VPN test:**
- DNS resolution may have changed
- OAuth redirect URLs may point to unreachable endpoints
- Appsmith health check may fail

---

## Code Issues & Fixes

### Issue #1: Empty OAuth Variables in docker-compose
**Location:** [docker-compose.enterprise.yml](docker-compose.enterprise.yml#L224-L227)  
**Severity:** 🔴 CRITICAL

**Current Code:**
```yaml
environment:
  - APPSMITH_DISABLE_TELEMETRY=true
  - APPSMITH_GOOGLE_MAPS_API_KEY=${GOOGLE_MAPS_API_KEY:-}
  - APPSMITH_MAIL_ENABLED=${APPSMITH_MAIL_ENABLED:-false}
  - APPSMITH_INSTANCE_NAME=${APPSMITH_INSTANCE_NAME:-kushnir-cloud-ide}
  - OAUTH_GOOGLE_CLIENT_ID=${OAUTH_GOOGLE_CLIENT_ID:-}           # ❌
  - OAUTH_GOOGLE_CLIENT_SECRET=${OAUTH_GOOGLE_CLIENT_SECRET:-}   # ❌
  - OAUTH_GITHUB_CLIENT_ID=${OAUTH_GITHUB_CLIENT_ID:-}           # ❌
  - OAUTH_GITHUB_CLIENT_SECRET=${OAUTH_GITHUB_CLIENT_SECRET:-}   # ❌
```

**Problem:** OAuth variables have empty defaults, so Appsmith starts without authentication.

**Fix:**
```yaml
environment:
  - APPSMITH_DISABLE_TELEMETRY=true
  - APPSMITH_GOOGLE_MAPS_API_KEY=${GOOGLE_MAPS_API_KEY:-}
  - APPSMITH_MAIL_ENABLED=${APPSMITH_MAIL_ENABLED:-false}
  - APPSMITH_INSTANCE_NAME=${APPSMITH_INSTANCE_NAME:-kushnir-cloud-ide}
  - OAUTH_GOOGLE_CLIENT_ID=${OAUTH_GOOGLE_CLIENT_ID}           # ✅ Required
  - OAUTH_GOOGLE_CLIENT_SECRET=${OAUTH_GOOGLE_CLIENT_SECRET}   # ✅ Required
  - OAUTH_GITHUB_CLIENT_ID=${OAUTH_GITHUB_CLIENT_ID:-}         # GitHub optional
  - OAUTH_GITHUB_CLIENT_SECRET=${OAUTH_GITHUB_CLIENT_SECRET:-} # GitHub optional
```

**Reason:** Google OAuth is required for production. GitHub is optional. Missing required vars will cause docker-compose to fail early (better than silent failure).

---

### Issue #2: Missing .env File
**Location:** Root directory  
**Severity:** 🔴 CRITICAL

**Problem:** Documentation references `.env` file but it doesn't exist.

**Solution:** Create `.env` file with required credentials.

---

### Issue #3: No Verification Script for OAuth
**Location:** Documentation references `./verify-appsmith-integration.sh`  
**Severity:** 🟡 WARNING

**Problem:** Verification script doesn't exist or doesn't check OAuth credentials.

**Solution:** Create verification script that checks OAuth credentials are present.

---

## Security Concerns

### 1. .env File Should Not Be in Git ✅
**Status:** OK - `.env` is git-ignored

### 2. OAuth Credentials Exposure Risk ⚠️
**Concern:** Production OAuth credentials must not be committed to git
**Status:** OK - credentials in .env (not committed)

### 3. TLS Configuration ✅
**Status:** Good - Caddyfile enforces TLS 1.2+, disables weak ciphers

### 4. OAuth Token Forwarding ✅
**Status:** Good - Caddyfile forwards OAuth tokens to backend services

---

## VPN Test Verification

### Pre-VPN Test Checklist
```bash
# 1. Verify .env file exists with OAuth credentials
[ -f .env ] && echo "✓ .env exists" || echo "✗ .env missing"

# 2. Verify OAuth variables are set
source .env 2>/dev/null && \
  [[ -n "${OAUTH_GOOGLE_CLIENT_ID}" ]] && echo "✓ Google OAuth configured" || \
  echo "✗ Google OAuth not configured"

# 3. Verify DNS resolves after VPN
nslookup kushnir.cloud

# 4. Verify Appsmith health
curl -s http://localhost:8084/health || echo "Appsmith not responding"

# 5. Verify Caddyfile is valid
caddy validate --config Caddyfile

# 6. Test OAuth redirect URLs
curl -I https://kushnir.cloud 2>&1 | head -5
```

### Post-VPN Test Actions
```bash
# 1. Restart Appsmith to pick up new network configuration
docker compose -f docker-compose.enterprise.yml restart code-server-appsmith

# 2. Wait for health check
sleep 30

# 3. Verify services are running
docker compose -f docker-compose.enterprise.yml ps

# 4. Check for OAuth errors
docker logs code-server-appsmith 2>&1 | grep -i "oauth\|error\|auth" | tail -10
```

---

## Recommended Actions

### Immediate (Critical)
1. ✅ **Create `.env` file** with Google OAuth credentials
   ```bash
   cat > .env << 'EOF'
   OAUTH_GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
   OAUTH_GOOGLE_CLIENT_SECRET=your-client-secret
   APPSMITH_INSTANCE_NAME=kushnir-cloud-ide
   EOF
   chmod 600 .env
   ```

2. ✅ **Update docker-compose.enterprise.yml** to fail if OAuth not set (see Issue #1 fix)

3. ✅ **Restart Appsmith**
   ```bash
   docker compose -f docker-compose.enterprise.yml restart code-server-appsmith
   ```

### Short-term (This Week)
1. Create verification script: `verify-appsmith-oauth.sh`
2. Add pre-deployment OAuth credential check
3. Document OAuth setup process clearly

### Long-term (Infrastructure)
1. Add GitHub Actions to validate OAuth configuration
2. Add CICD check for missing .env variables
3. Implement secure credential rotation for OAuth tokens

---

## Deployment Instructions for Google OAuth

### Step 1: Create Google OAuth Application
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create new project: "kushnir-cloud"
3. Enable Google+ API
4. Create OAuth 2.0 credentials (OAuth consent screen):
   - App name: "Hermes Agent Portal"
   - Authorized domains: kushnir.cloud
5. Create OAuth client ID (Web application):
   - Name: "Hermes Portal Web Client"
   - Authorized redirect URIs:
     - `https://kushnir.cloud/oauth/callback`
     - `https://kushnir.cloud/` 
     - `http://localhost:8084/` (for local testing)
   - Click "Create"
6. Copy Client ID and Client Secret

### Step 2: Create .env File
```bash
cd /home/akushnir/code-server

cat > .env << 'EOF'
# OAuth Configuration (Google)
OAUTH_GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
OAUTH_GOOGLE_CLIENT_SECRET=your-client-secret

# Appsmith Configuration
APPSMITH_INSTANCE_NAME=kushnir-cloud-ide
APPSMITH_DISABLE_TELEMETRY=true

# Optional: GitHub OAuth (if needed)
# OAUTH_GITHUB_CLIENT_ID=your-github-client-id
# OAUTH_GITHUB_CLIENT_SECRET=your-github-client-secret
EOF

chmod 600 .env
```

### Step 3: Verify Configuration
```bash
# Source the .env file
source .env

# Verify variables
echo "Google OAuth Client ID: ${OAUTH_GOOGLE_CLIENT_ID}"
echo "Configuration status: $([ -n "$OAUTH_GOOGLE_CLIENT_ID" ] && echo "✓ Ready" || echo "✗ Not set")"
```

### Step 4: Deploy
```bash
# Start Appsmith with OAuth credentials
cd /home/akushnir/code-server
docker compose -f docker-compose.enterprise.yml up -d code-server-appsmith

# Wait for startup (60 seconds)
sleep 60

# Verify health
curl -s http://localhost:8084/health
```

### Step 5: Test OAuth Flow
```bash
# 1. Test HTTP to HTTPS redirect (via Caddyfile)
curl -I https://kushnir.cloud/

# 2. Check Appsmith logs for OAuth initialization
docker logs code-server-appsmith | grep -i "oauth\|auth"

# 3. Access Appsmith dashboard
# Browser: https://kushnir.cloud
# Expected: Google OAuth login button appears
```

---

## Files to Create/Modify

| File | Action | Reason |
|------|--------|--------|
| `.env` | **CREATE** | Store OAuth credentials |
| `docker-compose.enterprise.yml` | **MODIFY** | Make OAuth credentials required |
| `verify-appsmith-oauth.sh` | **CREATE** | Validate OAuth setup before deployment |
| `OAUTH_SETUP_GUIDE.md` | **CREATE** | Step-by-step OAuth configuration |

---

## Verification Checklist

- [ ] .env file created with Google OAuth credentials
- [ ] docker-compose.enterprise.yml has required OAuth variables
- [ ] Appsmith container is running and healthy
- [ ] Caddyfile is valid and routes to Appsmith
- [ ] DNS resolves kushnir.cloud to correct IP
- [ ] HTTPS/TLS works (curl -I https://kushnir.cloud/)
- [ ] Google OAuth redirect URLs are configured in Google Cloud Console
- [ ] User can access https://kushnir.cloud and see OAuth login
- [ ] User can authenticate with Google account
- [ ] Appsmith dashboard loads after OAuth login
- [ ] VPN connectivity verified post-test

---

## References

- [APPSMITH_DEPLOYMENT_GUIDE.md](APPSMITH_DEPLOYMENT_GUIDE.md) - Full deployment instructions
- [APPSMITH_KUSHNIR_CLOUD_SECURE_INTEGRATION.md](APPSMITH_KUSHNIR_CLOUD_SECURE_INTEGRATION.md) - Security & OAuth details
- [docker-compose.enterprise.yml](docker-compose.enterprise.yml#L214-L245) - Appsmith service config
- [Caddyfile](Caddyfile) - Reverse proxy & TLS config

---

## Next Steps

1. ✅ User provides Google OAuth credentials
2. ✅ Create `.env` file with credentials
3. ✅ Update docker-compose to require OAuth variables
4. ✅ Restart Appsmith service
5. ✅ Verify OAuth login works
6. ✅ Test VPN connectivity post-deployment
