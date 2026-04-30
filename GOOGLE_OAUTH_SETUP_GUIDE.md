# Google OAuth Setup for Appsmith - Step-by-Step Guide

**Date:** April 30, 2026  
**Purpose:** Configure Google OAuth 2.0 authentication for Appsmith on kushnir.cloud  
**Time Required:** 15-20 minutes  
**Difficulty:** ⭐⭐ Intermediate

---

## Overview

This guide walks you through setting up Google OAuth 2.0 authentication for the Appsmith dashboard at `https://kushnir.cloud`.

### What You'll Get
- ✅ Google OAuth login button on Appsmith dashboard
- ✅ Single sign-on (SSO) with Google accounts
- ✅ Secure OAuth token forwarding to backend APIs
- ✅ TLS encrypted authentication flow

---

## Prerequisites

Before starting, ensure you have:
1. A Google account (personal or Google Workspace)
2. Access to [Google Cloud Console](https://console.cloud.google.com)
3. Project owner or editor role
4. SSH access to code-server primary host (192.168.168.31)
5. The `kushnir.cloud` domain configured (already done)

---

## Step 1: Create a Google Cloud Project

### 1.1 Sign in to Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Sign in with your Google account
3. Click **"Select a Project"** → **"NEW PROJECT"**

### 1.2 Create New Project

**Project Details:**
```
Project Name:       kushnir-cloud
Organization:       (leave blank if personal account)
Location:          (use default)
```

1. Enter `kushnir-cloud` as the project name
2. Click **"CREATE"**
3. Wait for project to be created (1-2 minutes)
4. Click on the new project to open it

---

## Step 2: Enable Required APIs

### 2.1 Enable Google+ API

1. In the left sidebar, go to **"APIs & Services"** → **"Library"**
2. Search for **"Google+ API"**
3. Click on "Google+ API" (first result)
4. Click **"ENABLE"**
5. Wait for the API to be enabled (30 seconds)

### 2.2 Verify OAuth Consent Screen

1. Go to **"APIs & Services"** → **"OAuth consent screen"**
2. Click **"Configure Consent Screen"**
3. Select **"External"** (for testing) or **"Internal"** (if using Google Workspace)
4. Click **"CREATE"**

### 2.3 Configure OAuth Consent Screen

**Required Fields:**
```
App name:                  Hermes Agent Portal
User support email:        your-email@gmail.com
Developer contact info:    your-email@gmail.com
```

1. Fill in the required fields above
2. Under "Authorized domains", add: `kushnir.cloud`
3. Click **"SAVE AND CONTINUE"**

**Scopes (Keep defaults):**
1. You'll see "Scopes" page - no changes needed
2. Click **"SAVE AND CONTINUE"**

**Summary:**
1. Review the summary
2. Click **"BACK TO DASHBOARD"**

---

## Step 3: Create OAuth 2.0 Credentials

### 3.1 Create OAuth Client

1. Go to **"APIs & Services"** → **"Credentials"**
2. Click **"+ CREATE CREDENTIALS"** → **"OAuth client ID"**
3. Select **"Web application"**
4. Enter name: `Hermes Portal Web Client`

### 3.2 Configure Authorized Redirect URIs

This is critical - these URLs must match your Appsmith deployment:

**Authorized redirect URIs:**
```
https://kushnir.cloud/
https://kushnir.cloud/auth/oauth2/google/callback
https://kushnir.cloud/oauth/callback
http://localhost:8084/
http://localhost:8084/auth/oauth2/google/callback
```

**To add:**
1. Click **"+ ADD URI"** for each URL above
2. Copy-paste each URL exactly
3. Include all variations above for maximum compatibility

### 3.3 Create and Copy Credentials

1. Click **"CREATE"**
2. A dialog box appears with your credentials
3. **IMPORTANT:** Copy both values:
   - **Client ID:** `your-client-id.apps.googleusercontent.com`
   - **Client Secret:** `your-client-secret` (don't share this!)
4. Click **"OK"** to close the dialog

### 3.4 Download or Note Credentials

1. In the "OAuth 2.0 Client IDs" section, find your "Hermes Portal Web Client"
2. Click the **download icon** (or write down the values)
3. You'll need these in the next step

**Keep these safe:**
```
CLIENT_ID:     your-client-id.apps.googleusercontent.com
CLIENT_SECRET: your-client-secret
```

---

## Step 4: Create .env File with Credentials

### 4.1 SSH to Code-Server Host

```bash
# From your local machine
ssh akushnir@192.168.168.31

# Or if using bastion
ssh -i your-key.pem akushnir@192.168.168.31
```

### 4.2 Navigate to Code-Server Directory

```bash
cd ~/code-server

# Verify you're in the right directory
pwd
# Should output: /home/akushnir/code-server

ls docker-compose.enterprise.yml
# Should show the file exists
```

### 4.3 Create .env File

```bash
# Create the .env file
cat > .env << 'EOF'
# ============================================
# Google OAuth Configuration
# ============================================
# From Google Cloud Console - Credentials
OAUTH_GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
OAUTH_GOOGLE_CLIENT_SECRET=your-client-secret

# ============================================
# Appsmith Configuration
# ============================================
APPSMITH_INSTANCE_NAME=kushnir-cloud-ide
APPSMITH_DISABLE_TELEMETRY=true
APPSMITH_MAIL_ENABLED=false

# ============================================
# Optional: GitHub OAuth (if needed)
# Uncomment and fill in if you want GitHub login too
# ============================================
# OAUTH_GITHUB_CLIENT_ID=your-github-client-id
# OAUTH_GITHUB_CLIENT_SECRET=your-github-client-secret

EOF

# Secure the file (important!)
chmod 600 .env

# Verify it was created
ls -la .env
# Should show: -rw------- (600 permissions)
```

### 4.4 Verify Configuration

```bash
# Source the .env file
source .env

# Verify Google OAuth is configured
if [[ -n "${OAUTH_GOOGLE_CLIENT_ID}" ]]; then
    echo "✓ Google OAuth configured"
    echo "  Client ID: ${OAUTH_GOOGLE_CLIENT_ID:0:40}..."
else
    echo "✗ Google OAuth not configured"
fi

# Verify it's readable only by owner
stat .env | grep Access
# Should show: (0600/-rw-------)
```

---

## Step 5: Deploy Appsmith with OAuth

### 5.1 Verify docker-compose Configuration

```bash
# Check docker-compose has OAuth environment variables
grep "OAUTH_GOOGLE_CLIENT" docker-compose.enterprise.yml

# Should see:
# - OAUTH_GOOGLE_CLIENT_ID=${OAUTH_GOOGLE_CLIENT_ID}
# - OAUTH_GOOGLE_CLIENT_SECRET=${OAUTH_GOOGLE_CLIENT_SECRET}
```

### 5.2 Stop Running Appsmith Container (if any)

```bash
# Stop the current Appsmith container
docker compose -f docker-compose.enterprise.yml stop code-server-appsmith

# Wait for it to stop
sleep 5
```

### 5.3 Start Appsmith with OAuth Credentials

```bash
# Start Appsmith with the .env file loaded
cd /home/akushnir/code-server

# Source .env to load credentials into environment
source .env

# Start Appsmith
docker compose -f docker-compose.enterprise.yml up -d code-server-appsmith

# Wait for startup (Appsmith takes 30-60 seconds)
echo "Waiting for Appsmith to start..."
sleep 60

# Check container status
docker compose -f docker-compose.enterprise.yml ps code-server-appsmith
# Should show: Running (and healthy after a minute)
```

### 5.4 Verify Appsmith Started Successfully

```bash
# Check if Appsmith is responding
curl -s http://localhost:8084/health

# Should return: 200 OK or similar

# Check logs for OAuth initialization
docker logs code-server-appsmith | tail -30

# Should NOT show any OAuth errors
```

---

## Step 6: Test OAuth Login

### 6.1 Access Appsmith Dashboard

1. Open your browser
2. Go to: **https://kushnir.cloud/**
3. Or alternative URL: **https://kushnir.cloud/paperclip**

### 6.2 Verify OAuth Button Appears

You should see:
- ✅ Appsmith login page
- ✅ "Sign in with Google" button (or similar)
- ✅ No errors about authentication

### 6.3 Test OAuth Flow

1. Click **"Sign in with Google"** button
2. You'll be redirected to Google login
3. Enter your Google credentials
4. Approve permissions (if asked)
5. You'll be redirected back to Appsmith dashboard
6. Should see: Appsmith dashboard with your data

### 6.4 Troubleshooting

**If you see errors:**

#### Error: "Invalid redirect URI"
- Go back to Google Cloud Console
- Check "Authorized redirect URIs" - ensure all URLs are listed
- Restart Appsmith: `docker compose restart code-server-appsmith`

#### Error: "OAuth credentials not configured"
- Verify .env file exists: `ls -la .env`
- Check credentials are correct: `source .env && echo $OAUTH_GOOGLE_CLIENT_ID`
- Restart Appsmith container

#### Error: "Connection refused" on https://kushnir.cloud
- Check DNS: `nslookup kushnir.cloud`
- Check Caddyfile: `cat Caddyfile | grep -A5 "kushnir.cloud"`
- Verify Caddyfile is running

---

## Step 7: VPN Test Verification

After VPN test, verify OAuth still works:

### 7.1 Post-VPN Verification Script

```bash
#!/bin/bash
# Save as: verify-oauth-vpn.sh

cd /home/akushnir/code-server

echo "Post-VPN OAuth Verification..."
echo ""

# 1. Check DNS
echo "1. Verifying DNS resolution..."
if nslookup kushnir.cloud 2>/dev/null | grep -q "Address"; then
    echo "✓ DNS resolves kushnir.cloud"
else
    echo "✗ DNS resolution failed"
    exit 1
fi

# 2. Check Appsmith is running
echo "2. Checking Appsmith container..."
if docker compose ps code-server-appsmith | grep -q "Up"; then
    echo "✓ Appsmith container is running"
else
    echo "✗ Appsmith container is not running"
    docker compose up -d code-server-appsmith
    sleep 60
fi

# 3. Check OAuth credentials
echo "3. Verifying OAuth credentials..."
source .env 2>/dev/null || true
if [[ -n "${OAUTH_GOOGLE_CLIENT_ID}" ]]; then
    echo "✓ Google OAuth credentials are set"
else
    echo "✗ Google OAuth credentials missing"
    exit 1
fi

# 4. Check Appsmith health
echo "4. Checking Appsmith health..."
if curl -s http://localhost:8084/health | grep -q "OK\|success"; then
    echo "✓ Appsmith is healthy"
else
    echo "✗ Appsmith health check failed"
    exit 1
fi

# 5. Check HTTPS
echo "5. Verifying HTTPS connectivity..."
if curl -s -I https://kushnir.cloud/ 2>&1 | head -1 | grep -q "200\|301\|302"; then
    echo "✓ HTTPS connection successful"
else
    echo "✗ HTTPS connection failed"
fi

echo ""
echo "✓ Post-VPN verification complete - OAuth is ready"
```

### 7.2 Run Post-VPN Verification

```bash
# Save the script
cat > verify-oauth-vpn.sh << 'EOF'
[paste the script above]
EOF

chmod +x verify-oauth-vpn.sh

# Run it
./verify-oauth-vpn.sh

# Expected output:
# ✓ DNS resolves kushnir.cloud
# ✓ Appsmith container is running
# ✓ Google OAuth credentials are set
# ✓ Appsmith is healthy
# ✓ HTTPS connection successful
# ✓ Post-VPN verification complete
```

---

## Troubleshooting

### OAuth Login Not Working

**Symptom:** Click "Sign in with Google" but nothing happens

**Solutions:**
1. Check browser console for errors (F12)
2. Verify Appsmith container is running: `docker ps | grep appsmith`
3. Check Appsmith logs: `docker logs -f code-server-appsmith | grep -i oauth`
4. Verify .env file is loaded: `docker exec code-server-appsmith env | grep OAUTH`

### "Invalid Redirect URI" Error

**Symptom:** Google shows error about redirect URI mismatch

**Solutions:**
1. Go to Google Cloud Console → Credentials
2. Edit "Hermes Portal Web Client" OAuth client
3. Update "Authorized redirect URIs" - ensure these exact URLs are listed:
   - `https://kushnir.cloud/`
   - `https://kushnir.cloud/auth/oauth2/google/callback`
   - `https://kushnir.cloud/oauth/callback`
4. Save changes
5. Restart Appsmith: `docker compose restart code-server-appsmith`
6. Wait 2-3 minutes for changes to propagate

### DNS Resolution Issues

**Symptom:** Can't reach kushnir.cloud

**Solutions:**
```bash
# Check DNS
nslookup kushnir.cloud

# Should resolve to: 192.168.168.31

# If not, check /etc/hosts
cat /etc/hosts | grep kushnir

# If hosts file is missing, add:
echo "192.168.168.31 kushnir.cloud" >> /etc/hosts
```

### VPN Connection Issues

**Symptom:** After VPN test, Appsmith is unreachable

**Solutions:**
1. Verify VPN is properly configured
2. Check DNS: `nslookup kushnir.cloud`
3. Verify Appsmith: `curl http://localhost:8084/health`
4. Check Caddyfile: `docker logs caddy | tail -20`
5. Restart services: `docker compose restart`

---

## Security Best Practices

### 1. Protect Your Credentials
```bash
# ✓ Do this
chmod 600 .env
cat .env > /dev/null  # private reading

# ✗ Don't do this
chmod 644 .env        # world readable!
cat .env | mail ...   # emailing credentials
```

### 2. Never Commit .env to Git
```bash
# .env should be in .gitignore
echo ".env" >> .gitignore

# Verify it's ignored
git status | grep .env
# Should NOT appear
```

### 3. Rotate Credentials Regularly
- Every 90 days, create new OAuth credentials in Google Cloud
- Update .env file
- Delete old credentials

### 4. Monitor OAuth Usage
- Check Appsmith logs for authentication errors
- Monitor Google Cloud Console for usage
- Review authorized apps periodically

---

## Next Steps

1. ✅ Verify OAuth login works
2. ✅ Test VPN connectivity post-deployment
3. ✅ Document any custom OAuth settings
4. ✅ Set up OAuth credential rotation schedule
5. ✅ Consider adding GitHub OAuth as backup (optional)

---

## Support & References

- [Appsmith OAuth Documentation](https://docs.appsmith.com/core-concepts/connecting-to-data-sources/authentication/oauth2)
- [Google OAuth 2.0 Documentation](https://developers.google.com/identity/protocols/oauth2)
- [Caddyfile Configuration](Caddyfile)
- [Docker Compose Configuration](docker-compose.enterprise.yml)
- [Code Review & RCA](CODE_REVIEW_APPSMITH_OAUTH_INTEGRATION.md)

---

**Setup Complete!** 🎉

Your Appsmith instance now has Google OAuth authentication enabled and is ready for production use on `https://kushnir.cloud`.
