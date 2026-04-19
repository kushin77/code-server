# Portal OAuth Configuration - Final Steps

## Current Status ✅ Code Complete

The portal oauth2-proxy is fully deployed and configured on production (192.168.168.31):
- ✅ Using same Google OAuth credentials as IDE
- ✅ Redirect URI set to: `https://kushnir.cloud/oauth2/callback`
- ✅ Portal login page loads and displays correctly
- ✅ All environment variables properly configured

## What's Needed ⚠️ Manual Configuration

The Google OAuth application needs to have the portal redirect URI registered.

### Current State
- **OAuth App ID**: `1025559705580-2oi5316d95j6ajoki7o51v9tq4eb9cd1.apps.googleusercontent.com`
- **Registered URIs** (current):
  - ✅ `https://ide.kushnir.cloud/oauth2/callback` (IDE - should already exist)
  - ❌ `https://kushnir.cloud/oauth2/callback` (Portal - NEEDS TO BE ADDED)

### Steps to Complete (Manual - requires Google Cloud access)

1. Go to: https://console.cloud.google.com/apis/credentials?project=gcp-eiq
2. Find OAuth 2.0 Client ID: `1025559705580-2oi5316d95j6ajoki7o51v9tq4eb9cd1.apps.googleusercontent.com`
3. Click the **Edit** button (pencil icon)
4. Scroll to "Authorized redirect URIs"
5. Add: `https://kushnir.cloud/oauth2/callback`
6. Click **Save**

That's it! Once saved, the portal OAuth login will work correctly.

### Verification After Setup

Once you've registered the URI:

```bash
# Test the portal OAuth flow
curl -v "https://kushnir.cloud/oauth2/start?rd=https://kushnir.cloud/" \
  -H "Host: kushnir.cloud" \
  -k 2>&1 | grep -E 'Location:|accounts.google.com'
```

You should see a redirect to Google's OAuth login page without errors.

## Code Changes Made

### Commits
- `863a9f5a` - fix: consolidate OAuth credentials for portal, document required Google Cloud config

### Files Modified
- `docker-compose.yml` - Portal oauth2-proxy now uses GOOGLE_CLIENT_ID/SECRET consistently

### Files Created (documentation/helpers)
- `scripts/configure-google-oauth-uris.sh` - Automation script (requires gcloud + credentials)
- `REGISTER-OAUTH-URIS.sh` - Quick reference for manual/automated setup

## Architecture

```
User Request to https://kushnir.cloud/
    ↓
Caddy (reverse proxy on VIP 192.168.168.30)
    ↓
oauth2-proxy-portal:4181 (with TRUST_PROXY enabled)
    ↓
Google OAuth Server (accounts.google.com)
    ├─ Redirects to: https://accounts.google.com/o/oauth2/auth?...&redirect_uri=https://kushnir.cloud/oauth2/callback
    └─ [ERROR] Redirect URI not registered ← FIX NEEDED
    ↓
Browser receives error: "The redirect_uri MUST match one of the registered URLs"
```

Once the URI is registered in Google Cloud Console, the flow completes successfully.

## Testing Commands

```bash
# Check portal oauth2-proxy is running
ssh akushnir@192.168.168.31 "docker-compose ps | grep oauth2-proxy-portal"

# View portal oauth2-proxy configuration
ssh akushnir@192.168.168.31 \
  "docker-compose exec -T oauth2-proxy-portal env | grep OAUTH2"

# Test portal accessibility
curl -s "https://kushnir.cloud/" -k | grep -i oauth2-proxy
```

## Next Steps

1. **You**: Register the redirect URI in Google Cloud Console (5 minutes)
2. **System**: oauth2-proxy will automatically accept the URI
3. **Test**: Click "Sign in with Google" on portal page
4. **Success**: You'll be redirected to Google login, then back to portal
