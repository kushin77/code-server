# IDE OAuth2 Configuration Checklist

**Date:** April 2026  
**Status:** 🔄 Ready for credential population  
**Target Domain:** https://ide.kushnir.cloud  

---

## Pre-Deployment Setup (IN PROGRESS)

- [x] oauth2-proxy v7.5.1 service configured in docker-compose.yml
- [x] Caddyfile updated: HTTP reverse proxy routing through oauth2-proxy:4180
- [x] allowed-emails.txt configured with akushnir@bioenergystrategies.com
- [x] terraform/variables.tf prepared with domain and OAuth placeholders
- [x] docker-compose service health checks configured
- [ ] **Google OAuth2 credentials obtained** ← **BLOCKING**
- [ ] .env file created with credentials
- [ ] DNS record configured: ide.kushnir.cloud → CNAME → home-dev.cfargotunnel.com (Cloudflare Tunnel)

---

## OAuth Credential Setup

### Get Credentials

- [ ] Option A: Create new credentials in Google Cloud Console
  - [ ] Project created: code-server-production
  - [ ] Google+ API enabled
  - [ ] OAuth consent screen configured
  - [ ] OAuth app created (Web application)
  - [ ] Authorized redirect URI: https://ide.kushnir.cloud/oauth2/callback
  - [ ] **Client ID obtained:** `_____________________`
  - [ ] **Client Secret obtained:** `_____________________`
  
- [ ] Option B: Retrieve existing Dex credentials
  - [ ] Location verified: _____________________
  - [ ] **Client ID:** `_____________________`
  - [ ] **Client Secret:** `_____________________`

### Populate Environment

- [ ] .env file created locally (copy from .env.example)
- [ ] GOOGLE_CLIENT_ID populated
- [ ] GOOGLE_CLIENT_SECRET populated
- [ ] OAUTH2_PROXY_COOKIE_SECRET set (or use default)
- [ ] .env added to .gitignore
- [ ] .env file transferred to production (192.168.168.31)
- [ ] Production .env verified with: `source .env && env | grep GOOGLE`

---

## Service Deployment

### Local Development (Optional)

- [ ] Run `docker-compose down` (clean state)
- [ ] Run `source .env && docker-compose up -d` (with OAuth credentials)
- [ ] Verify oauth2-proxy: `docker-compose logs oauth2-proxy`
- [ ] Verify all services healthy: `docker-compose ps`

### Production Host (192.168.168.31)

- [ ] SSH to production: `ssh akushnir@192.168.168.31`
- [ ] Run `docker-compose down`
- [ ] Verify .env file present: `cat .env | grep GOOGLE`
- [ ] Run `source .env && docker-compose up -d`
- [ ] Verify oauth2-proxy healthy: `docker-compose logs oauth2-proxy`
- [ ] Check service startup: `docker-compose ps`

---

## DNS Configuration

### Cloudflare DNS

- [ ] Log in to https://dash.cloudflare.com
- [ ] Select domain: kushnir.cloud
- [ ] DNS Records → Add Record:
  - [ ] Type: A
  - [ ] Name: ide
  - [ ] IPv4: 192.168.168.31
  - [ ] Save
- [ ] Verify: `dig ide.kushnir.cloud` → Returns CNAME to cfargotunnel.com (Cloudflare Tunnel)
- [ ] Wait for DNS propagation (up to 5 minutes)

### Alternative: Terraform

- [ ] Cloudflare credentials configured
- [ ] Run: `terraform apply -var="domain=ide.kushnir.cloud"`

---

## Testing & Validation

### oauth2-proxy Service Health

- [ ] Service running: `docker-compose ps oauth2-proxy` shows "Up"
- [ ] Health check passing: `docker exec oauth2-proxy curl -f http://localhost:4180/ping`
- [ ] Listening on port 4180: `docker exec oauth2-proxy netstat -tlnp | grep 4180`
- [ ] Logs clean: No errors in `docker-compose logs oauth2-proxy`

### OAuth Flow

- [ ] Browser access: `https://ide.kushnir.cloud`
- [ ] Auto-redirect to Google/Dex login received
- [ ] Google OAuth consent shown
- [ ] Successfully authenticated (authorize)
- [ ] Redirected to code-server IDE
- [ ] Session cookie set: `_oauth2_proxy_ide` in DevTools → Application → Cookies
- [ ] IDE functional (code editing, terminal working)

### Email Whitelist

- [ ] Authenticated user email matches `allowed-emails.txt`
- [ ] Test non-whitelisted email rejected (if possible)
- [ ] Add additional emails to whitelist: `echo "user@example.com" >> allowed-emails.txt && docker-compose restart oauth2-proxy`

### Service Integration

- [ ] Caddy forwarding to oauth2-proxy (check logs)
- [ ] oauth2-proxy forwarding authenticated requests to code-server
- [ ] code-server receiving X-Auth-Request headers from oauth2-proxy
- [ ] Ollama models accessible within authenticated session
- [ ] Model inference working (e.g., `/api/v1/completions`)

---

## Production Verification

### Container Status

```bash
# On production host
docker-compose ps

# Should show all HEALTHY/Up for:
# - oauth2-proxy (4180)
# - caddy (80, 443)
# - code-server (8080)
# - ollama (11434)
# - redis (6379)
```

- [ ] All services show "Up" status
- [ ] No services in "Restarting" state
- [ ] Health checks passing

### Network Verification

```bash
# Test oauth2-proxy listening port
docker exec caddy curl -vvv http://oauth2-proxy:4180/ping

# Test code-server upstream
docker exec oauth2-proxy curl -vvv http://code-server:8080/

# Test inter-service communication
docker network inspect code-server-enterprise_enterprise
```

- [ ] oauth2-proxy listening on 0.0.0.0:4180
- [ ] code-server accessible from oauth2-proxy
- [ ] Caddy can reach oauth2-proxy

### Log Verification

```bash
# oauth2-proxy logs should show:
docker-compose logs oauth2-proxy | grep -E "running|listening|successful|allowed|denied"

# caddy logs should show reverse proxy traffic
docker-compose logs caddy | tail -20

# code-server logs should show authenticated sessions
docker-compose logs code-server | tail -20
```

- [ ] oauth2-proxy: "v7.5.1 is running" + "listening on 0.0.0.0:4180"
- [ ] oauth2-proxy: Successful authentications logged
- [ ] caddy: Reverse proxy requests forwarded
- [ ] code-server: IDE sessions established

---

## Issue Resolution

### If oauth2-proxy Won't Start

**Symptom:** Stuck in restart loop

**Checklist:**
- [ ] .env file exists and is readable
- [ ] GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET populated
- [ ] Run: `source .env && docker-compose restart oauth2-proxy`
- [ ] Check logs: `docker-compose logs oauth2-proxy`

### If DNS Not Resolving

**Symptom:** Browser can't reach ide.kushnir.cloud

**Checklist:**
- [ ] Cloudflare DNS record created (CNAME ide.kushnir.cloud → home-dev.cfargotunnel.com)
- [ ] Wait for propagation (5-10 minutes)
- [ ] Flush DNS cache: `ipconfig /flushdns` (Windows) or `sudo dscacheutil -flushcache` (Mac)
- [ ] Test: `nslookup ide.kushnir.cloud 8.8.8.8`

### If OAuth Redirect Fails

**Symptom:** "Redirect URI mismatch" from Google

**Checklist:**
- [ ] Google Cloud Console OAuth app edited
- [ ] Authorized Redirect URI: https://ide.kushnir.cloud/oauth2/callback
- [ ] Saved in Google Console
- [ ] oauth2-proxy restarted: `docker-compose restart oauth2-proxy`

### If User Not Authorized

**Symptom:** Loops back to Google login after auth

**Checklist:**
- [ ] User email in `allowed-emails.txt`
- [ ] File readable by oauth2-proxy container
- [ ] oauth2-proxy restarted: `docker-compose restart oauth2-proxy`
- [ ] Check: `docker exec oauth2-proxy cat /etc/oauth2-proxy/allowed-emails.txt`

---

## File Modifications Summary

| File | Changes | Status |
|------|---------|--------|
| Caddyfile | Updated: HTTP → oauth2-proxy:4180 reverse proxy | ✅ Complete |
| docker-compose.yml | No changes (oauth2-proxy already configured) | ✅ Ready |
| .env.example | Created: credential template | ✅ Complete |
| .env | To be created with actual credentials | ⏳ Pending |
| allowed-emails.txt | Already populated (akushnir@bioenergystrategies.com) | ✅ Ready |
| terraform/variables.tf | No changes (domain already set) | ✅ Ready |
| OAUTH2-DEX-SETUP-GUIDE.md | Created: comprehensive setup documentation | ✅ Complete |
| IDE-OAUTH-CONFIGURATION-CHECKLIST.md | This file | ✅ Complete |

---

## Deployment Timeline

1. **Phase 1: Preparation** (✅ Complete)
   - oauth2-proxy infrastructure discovered and validated
   - Caddyfile updated for authentication routing
   - Documentation and templates created

2. **Phase 2: Credential Setup** (⏳ Awaiting User Input)
   - Obtain Google OAuth2 credentials
   - Create .env file
   - Populate production .env on 192.168.168.31

3. **Phase 3: Service Deployment** (Ready to Execute)
   - Restart containers with OAuth enabled
   - Verify health checks
   - Test service communication

4. **Phase 4: DNS Configuration** (Ready to Execute)
   - Configure Cloudflare DNS (CNAME: ide.kushnir.cloud → home-dev.cfargotunnel.com)
   - Wait for propagation

5. **Phase 5: End-to-End Testing** (Ready to Execute)
   - Test browser access to https://ide.kushnir.cloud
   - Verify OAuth login flow
   - Validate IDE functionality

---

## Contact & Support

- **Production Host:** akushnir@192.168.168.31
- **Domain:** ide.kushnir.cloud
- **Architecture Reference:** docs/adr/002-oauth2-authentication.md
- **Setup Guide:** OAUTH2-DEX-SETUP-GUIDE.md

---

**Status:** 🟡 **BLOCKED - Awaiting OAuth Credentials**

To proceed:
1. Provide GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET
2. These will be populated in .env file
3. Services will be restarted on production
4. oauth2-proxy will become operational for ide.kushnir.cloud

---

**Last Updated:** April 2026 - OAuth Configuration Phase
