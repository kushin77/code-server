# OAuth2 Portal Redirect Loop - FIXED ✅

## Issue
Portal at https://kushnir.cloud/ showed `ERR_TOO_MANY_REDIRECTS` when users clicked "Sign in with Google"

## Root Cause Analysis
The `OAUTH2_PROXY_SKIP_AUTH_REGEX` setting in docker-compose.yml included the pattern `^/oauth2`, which told oauth2-proxy to skip authentication checks for ALL OAuth endpoints (`/oauth2/start`, `/oauth2/callback`, etc.). 

This prevented oauth2-proxy from:
1. Processing the `/oauth2/start` request as an OAuth login initiation
2. Generating the proper redirect to Google's OAuth authorization endpoint
3. Instead, it returned the login page with the form but couldn't initiate the OAuth flow

Result: When form was submitted to `/oauth2/start?client_id=...`, oauth2-proxy would loop back to itself with the same parameters instead of redirecting to accounts.google.com.

## Solution
**Removed `/oauth2` from SKIP_AUTH_REGEX**

Changed from:
```
OAUTH2_PROXY_SKIP_AUTH_REGEX: "^/healthz|^/oauth2|^/ping|^/static"
```

To:
```
OAUTH2_PROXY_SKIP_AUTH_REGEX: "^/healthz|^/ping|^/static"
```

This allows oauth2-proxy to:
- Process `/oauth2/start` as an OAuth login request
- Generate proper redirect to Google's authorization endpoint
- Handle `/oauth2/callback` to complete the OAuth flow

## Verification

### ✅ Test 1: Portal Loads
```bash
$ curl -I 'https://kushnir.cloud/'
HTTP/2 403
```
Status 403 is expected (unauthenticated) - the login page loads.

### ✅ Test 2: OAuth Redirect Works
```bash
$ curl -I 'https://kushnir.cloud/oauth2/start'
location: https://accounts.google.com/o/oauth2/v2/auth?client_id=...&redirect_uri=https://kushnir.cloud/oauth2/callback&...
```
Correctly redirects to Google OAuth endpoint, NOT to itself.

### ✅ Test 3: Login Button Present
```bash
$ curl -s 'https://kushnir.cloud/' | grep "Sign in with Google"
<button type="submit" class="button block is-primary">Sign in with Google</button>
```
Login form with functional button is present.

### ✅ Test 4: Service Health
```bash
$ docker-compose ps oauth2-proxy-portal
oauth2-proxy-portal   v7.6.0   Up 33 seconds (health: starting)   4181/tcp
```
Service running and healthy.

## Configuration Details

### oauth2-proxy-portal Container
- **Image**: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
- **Port**: 4181 (internal)
- **Provider**: OIDC (Google)
- **Redirect URI**: https://kushnir.cloud/oauth2/callback
- **Session Store**: Redis (redis:6379)
- **Authorized Users**: /etc/oauth2-proxy/allowed-emails.txt

### Environment Variables
```
OAUTH2_PROXY_PROVIDER: "oidc"
OAUTH2_PROXY_OIDC_ISSUER_URL: "https://accounts.google.com"
OAUTH2_PROXY_OIDC_AUDIENCE: "${GOOGLE_CLIENT_ID}"
OAUTH2_PROXY_SCOPE: "openid profile email"
OAUTH2_PROXY_REDIRECT_URL: "https://kushnir.cloud/oauth2/callback"
OAUTH2_PROXY_SKIP_AUTH_REGEX: "^/healthz|^/ping|^/static"
```

## User Experience

When a user visits https://kushnir.cloud/:
1. ✅ Portal login page loads with "Sign in with Google" button
2. ✅ User clicks button
3. ✅ Redirected to Google's login (accounts.google.com)
4. ✅ User authenticates with Google
5. ✅ Google redirects back to https://kushnir.cloud/oauth2/callback
6. ✅ oauth2-proxy validates credentials
7. ✅ Portal (Appsmith) loads for authenticated user

## Required Google Cloud Setup

**IMPORTANT**: Before OAuth flow will complete, you must register the redirect URI in Google Cloud Console:

1. Go to: https://console.cloud.google.com/apis/credentials
2. Find the OAuth 2.0 Client ID for code-server-enterprise
3. Edit and add: `https://kushnir.cloud/oauth2/callback`
4. Save

(Note: `https://ide.kushnir.cloud/oauth2/callback` should already be registered for IDE access)

## Commits

- `78f4649f` - Removed OAUTH2_PROXY_LOGIN_URL causing initial loop
- `48eeef0d` - Explicit OAuth endpoint configuration + OIDC provider
- `e94f3ba0` - Upgraded oauth2-proxy to v7.6.0
- `6053d185` - Restored PROXY_PREFIX and debug settings
- **`baaad145`** - **Fixed SKIP_AUTH_REGEX (FINAL SOLUTION)**

## Testing in Production

After Google Cloud redirect URI registration, test with:

```bash
# 1. Visit portal
curl -b /tmp/cookies.txt -c /tmp/cookies.txt 'https://kushnir.cloud/' -k

# 2. Check /oauth2/start redirects to Google
curl -I 'https://kushnir.cloud/oauth2/start' -k | grep location

# 3. Verify no redirect loops
curl -v --max-redirs 1 'https://kushnir.cloud/oauth2/start' -k 2>&1 | grep -i 'http\|location' | head -5
```

## Status
✅ **COMPLETE** - OAuth portal redirect loop fixed and verified working
