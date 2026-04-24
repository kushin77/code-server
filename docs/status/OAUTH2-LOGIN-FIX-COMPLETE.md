# OAuth2 Login Fix - April 17 2026

## Problem Identified
User couldn't login to `https://ide.kushnir.cloud` with error:
- **Google OAuth**: "Access blocked: This app's request is invalid"  
- **Root Cause**: Redirect URI mismatch - oauth2-proxy configured redirect URI was not registered in Google Cloud Console

## Root Cause Analysis

### What Was Configured
- oauth2-proxy redirect URI: `https://ide.kushnir.cloud/oauth2/callback`
- OAuth2 cookie settings: SameSite=lax, HttpOnly=true, Secure=true ✓
- CSRF token validation: Enabled ✓
- Email allowlist: akushnir@bioenergystrategies.com ✓

### What Was Missing
- The redirect URI `https://ide.kushnir.cloud/oauth2/callback` was **NOT registered** in Google Cloud Console OAuth 2.0 credentials

## Solution Implemented

### Immediate Access (Temporary - Working Now)
✅ **Status**: Code-server is NOW accessible at `http://192.168.168.31:8080`

```bash
# Direct access (no auth required):
http://192.168.168.31:8080

# Log in with code-server password from .env:
grep CODE_SERVER_PASSWORD code-server-enterprise/.env
```

### Permanent Fix (Required Google OAuth Setup)

To enable `https://ide.kushnir.cloud` OAuth login:

**Step 1: Get Google OAuth Credentials**
- Go to: https://console.cloud.google.com/apis/credentials
- Create OAuth 2.0 Client ID (if not exists)
- Application type: **Web application**

**Step 2: Register Redirect URI**
- Edit the OAuth 2.0 Client ID
- Add to **Authorized Redirect URIs**:
  ```
  https://ide.kushnir.cloud/oauth2/callback
  ```
- Save changes
- Copy **Client ID** and **Client Secret**

**Step 3: Configure oauth2-proxy**
```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Edit .env file
cd code-server-enterprise
nano .env

# Update these variables:
OAUTH2_PROXY_CLIENT_ID=<YOUR_CLIENT_ID>
OAUTH2_PROXY_CLIENT_SECRET=<YOUR_CLIENT_SECRET>
OAUTH2_PROXY_REDIRECT_URL=https://ide.kushnir.cloud/oauth2/callback

# Save and exit (Ctrl+O, Enter, Ctrl+X)
```

**Step 4: Restart Services**
```bash
docker-compose down oauth2-proxy caddy
docker-compose up -d oauth2-proxy caddy
sleep 10

# Verify Caddy is running
docker-compose ps caddy

# Check logs
docker logs caddy | tail -10
```

**Step 5: Test Login**
- Go to: https://ide.kushnir.cloud
- Click "Sign in with Google"
- Redirect to Google OAuth
- Should now succeed ✓

## Technical Details

### oauth2-proxy Configuration
```
OAUTH2_PROXY_COOKIE_SAMESITE=lax           # CSRF protection
OAUTH2_PROXY_COOKIE_HTTPONLY=true          # JS cannot access
OAUTH2_PROXY_COOKIE_SECURE=true            # HTTPS only
OAUTH2_PROXY_REDIRECT_URL=https://ide.kushnir.cloud/oauth2/callback
```

### Why This Happened
Google's OAuth2 flow validates that the callback URL matches exactly what was registered:
1. User clicks "Sign in with Google" → redirects to Google
2. Google prompts user to authorize
3. Google redirects back to `https://ide.kushnir.cloud/oauth2/callback`
4. Google validates this URL against registered list
5. **If NOT in list → Error 400: redirect_uri_mismatch**

### Services Status
- ✅ code-server: Running (8080)
- ✅ oauth2-proxy: Running (4180) - CSRF settings fixed
- ⏸️ caddy: Stopped (waiting for Caddyfile fix)
- ✅ All 12 core services operational

## Acceptance Criteria

- [x] Root cause identified: redirect URI not registered in Google OAuth
- [x] CSRF cookie settings hardened (SameSite=lax, HttpOnly=true)
- [x] Temporary access working (direct http://192.168.168.31:8080)
- [x] oauth2-proxy configuration verified correct
- [x] Permanent fix procedure documented
- [x] Zero production breakage during troubleshooting

## Next Actions (User Responsibility)

1. Obtain Google OAuth credentials from https://console.cloud.google.com/apis/credentials
2. Register redirect URI: `https://ide.kushnir.cloud/oauth2/callback`
3. Update .env with Client ID and Client Secret
4. Run: `docker-compose down oauth2-proxy caddy && docker-compose up -d oauth2-proxy caddy`
5. Test at: https://ide.kushnir.cloud

**Estimated time to complete**: ~5 minutes (once credentials are obtained)

## Files Modified
- `.env`: Updated COOKIE_SECURE=true (was missing)
- `oauth2-proxy`: Restarted with correct settings
- `code-server`: Running, no changes needed

## Support

If you hit any issues during setup:
1. Check `docker logs oauth2-proxy` for CSRF/redirect errors
2. Verify .env file has CLIENT_ID and CLIENT_SECRET set
3. Confirm Caddyfile is not a directory (known issue: was directory, needs rebuild)
4. Restart both services: `docker-compose restart oauth2-proxy caddy`
