# OAuth2 and Dex Integration — Step-by-Step Setup Guide

## Overview

You have existing oauth2-proxy v7.5.1 infrastructure that manages authentication for `ide.kushnir.cloud`. This guide walks through:

1. **Getting OAuth2 credentials from Google Cloud Console**
2. **Configuring environment variables**
3. **Enabling oauth2-proxy in production**
4. **Testing the OAuth flow**

---

## Current Status

✅ **Already Completed:**
- oauth2-proxy v7.5.1 configured in `docker-compose.yml`
- Caddyfile updated for authentication routing (HTTP reverse proxy to oauth2-proxy:4180)
- `allowed-emails.txt` whitelist configured (akushnir@bioenergystrategies.com)
- terraform variables prepared (`terraform/variables.tf`)
- Production host: 192.168.168.31

⏳ **Pending Steps:**
1. Create/obtain Google OAuth2 credentials
2. Populate `.env` file with credentials
3. Restart containers with OAuth enabled
4. Configure DNS (CNAME: ide.kushnir.cloud → home-dev.cfargotunnel.com via Cloudflare Tunnel)
5. Test OAuth flow

---

## Step 1: Get Google OAuth2 Credentials

### Option A: Create New Credentials (If Dex setup doesn't have them yet)

1. **Go to Google Cloud Console:**
   ```
   https://console.cloud.google.com/
   ```

2. **Create or select a project:**
   - Click "Select a Project" → "New Project"
   - Name: `code-server-production`
   - Click "Create"

3. **Enable Google+ API:**
   - Search for "Google+ API" in the search bar
   - Click "Google+ API" → "Enable"

4. **Create OAuth 2.0 Consent Screen (if not done already):**
   - Go to `APIs & Services` → `OAuth consent screen`
   - Choose "External" (unless you're in a Google Workspace)
   - Fill in:
     - App name: `code-server-ide`
     - User support email: Your email
     - Developer contact: Your email
   - Click "Save & Continue"
   - Add scopes: `openid`, `email`, `profile` (click "Add or Remove Scopes")
   - Click "Save & Continue" → "Done"

5. **Create OAuth 2.0 Credentials:**
   - Go to `APIs & Services` → `Credentials`
   - Click "+ Create Credentials" → "OAuth client ID"
   - Application type: "Web application"
   - Name: `code-server-ide`
   - Authorized JavaScript origins: `https://ide.kushnir.cloud`
   - Authorized redirect URIs: `https://ide.kushnir.cloud/oauth2/callback`
   - Click "Create"

6. **Copy your credentials:**
   - You'll see a dialog with "Client ID" and "Client Secret"
   - **Copy both values** — you'll need them in the next step

### Option B: Use Existing Dex Credentials

If you set up Dex previously "the other day", the credentials should be:
- Stored in Dex configuration or Kubernetes secrets
- Used by your existing identity provider setup
- Documented in your deployment notes or ADR-002

Check:
```bash
ssh akushnir@192.168.168.31
# Look for existing configuration:
env | grep -i GOOGLE
env | grep -i OIDC
grep -r "client.id" ~/.config/
cat ~/.docker-volumes/*/config.json 2>/dev/null | grep -i client
```

---

## Step 2: Populate Environment Variables

### Create `.env` File (Local Development)

1. **Copy the example file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your credentials:**
   ```bash
   DOMAIN=ide.kushnir.cloud
   GOOGLE_CLIENT_ID=YOUR_CLIENT_ID.apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=YOUR_CLIENT_SECRET
   OAUTH2_PROXY_COOKIE_SECRET=KPm7K8L9vN6q3W2zM5xJ4pL6K9mN8qW3zR5xY7tJ9pM2vO4wQ6sT8uV0xW2zY4aB
   CODE_SERVER_PASSWORD=your-secure-password
   ```

3. **Set file permissions (never commit `.env`):**
   ```bash
   chmod 600 .env
   echo ".env" >> .gitignore
   ```

### Set Environment on Production Host (Remote Deployment)

1. **SSH to production:**
   ```bash
   ssh akushnir@192.168.168.31
   cd code-server-enterprise
   ```

2. **Create `.env` file on production:**
   ```bash
   cat > .env << 'EOF'
   DOMAIN=ide.kushnir.cloud
   GOOGLE_CLIENT_ID=YOUR_CLIENT_ID.apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=YOUR_CLIENT_SECRET
   OAUTH2_PROXY_COOKIE_SECRET=KPm7K8L9vN6q3W2zM5xJ4pL6K9mN8qW3zR5xY7tJ9pM2vO4wQ6sT8uV0xW2zY4aB
   CODE_SERVER_PASSWORD=your-secure-password
   EOF
   chmod 600 .env
   ```

3. **Verify environment variables are set:**
   ```bash
   source .env
   echo "DOMAIN: $DOMAIN"
   echo "GOOGLE_CLIENT_ID: $GOOGLE_CLIENT_ID"
   echo "GOOGLE_CLIENT_SECRET: $GOOGLE_CLIENT_SECRET"
   ```

---

## Step 3: Enable and Restart oauth2-proxy

### On Production Host (192.168.168.31)

1. **Stop current containers:**
   ```bash
   docker-compose down
   ```

2. **Load environment and restart:**
   ```bash
   source .env
   docker-compose up -d
   ```

3. **Verify oauth2-proxy is healthy:**
   ```bash
   docker-compose logs oauth2-proxy
   # Should show: "oauth2-proxy v7.5.1 is running"
   # And: "listening on 0.0.0.0:4180"
   ```

4. **Check all services:**
   ```bash
   docker-compose ps
   ```

   Expected output:
   ```
   NAME              STATUS           PORTS
   code-server       Up (healthy)     8080/tcp
   oauth2-proxy      Up (healthy)     4180/tcp
   caddy             Up (healthy)     0.0.0.0:80->80/tcp
   ollama            Up (healthy)     11434/tcp
   redis             Up (healthy)     6379/tcp
   ```

---

## Step 4: Configure DNS

The domain `ide.kushnir.cloud` needs to point to your production host IP.

### Using Cloudflare (Recommended)

1. **Log in to Cloudflare:**
   ```
   https://dash.cloudflare.com
   ```

2. **Select your domain (`kushnir.cloud`)**

3. **Go to DNS Records → Add Record:**
   - Type: `A`
   - Name: `ide`
   - IPv4 address: `192.168.168.31`
   - TTL: Auto
   - Proxy status: DNS only (orange cloud)
   - Click "Save"

4. **Verify DNS resolution:**
   ```bash
   nslookup ide.kushnir.cloud
   # Should reply: 192.168.168.31
   ```

### Using Terraform (Automatic)

If you have Cloudflare credentials set up:
```bash
terraform apply -var="domain=ide.kushnir.cloud"
```

---

## Step 5: Test OAuth Flow

### Test 1: Access via Browser

1. **Open browser:**
   ```
   https://ide.kushnir.cloud
   ```

2. **Expected flow:**
   - Browser redirects to Google login
   - You sign in with Google (or Dex OIDC provider)
   - Upon success, you're redirected to code-server IDE
   - Session cookie `_oauth2_proxy_ide` is set

3. **Verify session cookie:**
   ```
   Developer Tools → Application → Cookies
   # Should see: _oauth2_proxy_ide (secure, HttpOnly, SameSite=Lax)
   ```

### Test 2: Verify oauth2-proxy Logs

```bash
ssh akushnir@192.168.168.31
docker-compose logs oauth2-proxy | tail -50
# Should show: [INFO] successful authentication and redirect
```

### Test 3: Verify Email Whitelist

Only emails in `allowed-emails.txt` can authenticate:
```bash
cat allowed-emails.txt
# akushnir@bioenergystrategies.com
```

To add more users, edit and restart:
```bash
echo "user@example.com" >> allowed-emails.txt
docker-compose restart oauth2-proxy
```

---

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│ Browser                                                    │
│ https://ide.kushnir.cloud                                  │
└─────────────────────────────┬──────────────────────────────┘
                              │ (initial request)
                              ▼
         ┌────────────────────────────────────────┐
         │ Caddy (HTTP reverse proxy)             │
         │ :80 →[forward]→ oauth2-proxy:4180      │
         └─────────────────┬──────────────────────┘
                           │
         ┌─────────────────▼──────────────────────┐
         │ oauth2-proxy v7.5.1                    │
         │ - Checks for auth cookie               │
         │ - If missing: redirect to Google       │
         │ - If present: forward to upstream      │
         └─────────────────┬──────────────────────┘
                           │
         ┌─────────────────▼──────────────────────┐
         │ code-server:8080                       │
         │ IDE running (after authentication)     │
         └────────────────────────────────────────┘

Authentication Flow:
1. Browser → https://ide.kushnir.cloud
2. Caddy → oauth2-proxy:4180 (reverse proxy)
3. oauth2-proxy checks session cookie
   - If missing: redirect to Google login
   - If valid: forward to code-server
4. Google/Dex → authenticate user
5. oauth2-proxy sets session cookie
6. Redirect to code-server IDE
7. Code-server serves IDE (fully authenticated)
```

---

## Troubleshooting

### Issue 1: oauth2-proxy Stuck in Restart Loop

**Symptom:** `docker-compose logs oauth2-proxy` shows restart errors

**Cause:** Environment variables not set

**Solution:**
```bash
# Check if .env exists and is sourced
ls -la .env
source .env
env | grep GOOGLE_CLIENT_ID  # Should show your client ID

# Restart containers with environment
docker-compose down
docker-compose up -d
```

### Issue 2: "Invalid Redirect URI" from Google

**Symptom:** Google login page says "Redirect URI mismatch"

**Cause:** Mismatch between Google console and deployed domain

**Solution:**
1. Go to Google Cloud Console → Credentials
2. Edit OAuth application
3. Verify "Authorized Redirect URIs" includes: `https://ide.kushnir.cloud/oauth2/callback`
4. Save changes
5. Restart oauth2-proxy: `docker-compose restart oauth2-proxy`

### Issue 3: DNS Not Resolving

**Symptom:** `nslookup ide.kushnir.cloud` fails or returns wrong IP

**Solution:**
```bash
# Force DNS refresh
nslookup -debug ide.kushnir.cloud 8.8.8.8  # Use Google DNS
# Should return: 192.168.168.31

# If still wrong, check Cloudflare DNS records
# https://dash.cloudflare.com → Select domain → DNS Records
```

### Issue 4: User Not Authorized (Email Whitelist)

**Symptom:** Login succeeds, but redirects back to Google login

**Cause:** Your email not in `allowed-emails.txt`

**Solution:**
```bash
# Add your email to whitelist
echo "your-email@example.com" >> allowed-emails.txt
docker-compose restart oauth2-proxy
```

---

## File Locations

| File | Location | Purpose |
|------|----------|---------|
| Caddyfile | `./Caddyfile` | Reverse proxy configuration (updated for oauth2-proxy) |
| docker-compose.yml | `./docker-compose.yml` | oauth2-proxy service definition |
| .env | `./` (not in repo) | Environment variables with credentials |
| allowed-emails.txt | `./allowed-emails.txt` | Email whitelist for authentication |
| OAuth setup | `scripts/automated-oauth-configuration.sh` | Automated setup script |
| Architecture | `docs/adr/002-oauth2-authentication.md` | Full ADR documentation |

---

## Next Steps

1. ✅ **Obtain Google OAuth2 credentials** (Step 1)
2. ✅ **Create `.env` file** with credentials (Step 2)
3. ✅ **Restart containers** on production (Step 3)
4. ✅ **Configure DNS** for ide.kushnir.cloud (Step 4)
5. ✅ **Test OAuth flow** in browser (Step 5)

Once credentials are ready, test the flow:
```bash
# From production host
ssh akushnir@192.168.168.31
cd code-server-enterprise
source .env
docker-compose restart oauth2-proxy caddy
docker-compose ps  # Verify all services healthy
```

Then in browser:
```
https://ide.kushnir.cloud
# Should redirect to Google/Dex login
```

---

## References

- **Docker Compose:** `docker-compose.yml` (lines 122-165)
- **Caddyfile:** `./Caddyfile` (updated for oauth2-proxy)
- **Terraform:** `terraform/variables.tf` (OAuth configuration)
- **Architecture:** `docs/adr/002-oauth2-authentication.md`
- **DNS Guide:** `DNS-IMPLEMENTATION-GUIDE.md`
- **oauth2-proxy Docs:** https://oauth2-proxy.github.io/oauth2-proxy/

---

**Last Updated:** April 2026 - OAuth2 Dex Integration Setup
