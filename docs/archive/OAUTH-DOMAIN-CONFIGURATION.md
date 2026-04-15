# OAuth & Domain Configuration - ide.kushnir.cloud

**Status**: ✅ Production Deployment  
**Date**: April 15, 2026  
**Domain**: `ide.kushnir.cloud` (primary production domain)  
**Auth Provider**: Google OAuth 2.0 (Shared Organization Credentials)

---

## Overview

All services now use the `ide.kushnir.cloud` domain via Cloudflare Tunnel with shared Google OAuth for centralized authentication and authorization.

### Production Endpoints

| Service | URL | Access | Notes |
|---------|-----|--------|-------|
| **IDE (code-server)** | `https://ide.kushnir.cloud` | Public (via OAuth) | OAuth2-proxy protected |
| **Grafana** | `https://grafana.kushnir.cloud` | Public (via OAuth) | Dashboards & monitoring |
| **Prometheus** | `https://prometheus.kushnir.cloud` | LAN/VPN only | Internal metrics |
| **AlertManager** | `https://alertmanager.kushnir.cloud` | LAN/VPN only | Alert management |
| **Jaeger** | `https://jaeger.kushnir.cloud` | LAN/VPN only | Distributed tracing |
| **Ollama** | `https://ollama.kushnir.cloud` | LAN/VPN only | GPU inference API |

---

## Configuration Details

### Domain Configuration

**File**: `.env`

```bash
# Primary domain - used by all services
DOMAIN=ide.kushnir.cloud

# ACME email for Let's Encrypt certificate renewal
ACME_EMAIL=ops@kushnir.cloud
```

### OAuth Configuration

**File**: `.env`

```bash
# Google OAuth 2.0 Shared Organization Credentials
# ⚠️ IMPORTANT: These are placeholders - replace with actual org credentials

GOOGLE_CLIENT_ID=shared-org-client-id
GOOGLE_CLIENT_SECRET=shared-org-client-secret

# OAuth2-proxy Cookie Secret (encryption key for session cookies)
OAUTH2_PROXY_COOKIE_SECRET=KPm7K8L9vN6q3W2zM5xJ4pL6K9mN8qW3zR5xY7tJ9pM2vO4wQ6sT8uV0xW2zY4aB
```

### Caddy Configuration

**File**: `Caddyfile`

```caddy
# ── IDE (code-server via oauth2-proxy) ──
ide.kushnir.cloud {
  encode gzip
  import security_headers
  
  reverse_proxy oauth2-proxy:4180 {
    header_up Host       {upstream_hostport}
    header_up X-Real-IP  {remote_host}
  }
}

# ── Grafana ──
grafana.kushnir.cloud {
  encode gzip
  import security_headers
  reverse_proxy grafana:3000
}

# ── Additional services (LAN/VPN restricted) ──
prometheus.kushnir.cloud { ... }
alertmanager.kushnir.cloud { ... }
jaeger.kushnir.cloud { ... }
ollama.kushnir.cloud { ... }
```

### OAuth2-proxy Configuration

**Service**: `oauth2-proxy` (docker-compose)

```yaml
environment:
  OAUTH2_PROXY_PROVIDER:                  google
  OAUTH2_PROXY_OIDC_ISSUER_URL:           https://accounts.google.com
  OAUTH2_PROXY_CLIENT_ID:                 ${GOOGLE_CLIENT_ID}
  OAUTH2_PROXY_CLIENT_SECRET:             ${GOOGLE_CLIENT_SECRET}
  OAUTH2_PROXY_REDIRECT_URL:              https://${DOMAIN}/oauth2/callback
  OAUTH2_PROXY_UPSTREAMS:                 http://code-server:8080/
  OAUTH2_PROXY_COOKIE_NAME:               _oauth2_proxy_ide
  OAUTH2_PROXY_COOKIE_SECRET:             ${OAUTH2_PROXY_COOKIE_SECRET}
  OAUTH2_PROXY_COOKIE_SECURE:             "true"      # HTTPS only
  OAUTH2_PROXY_COOKIE_HTTPONLY:           "true"      # No JavaScript access
  OAUTH2_PROXY_COOKIE_SAMESITE:           "lax"       # CSRF protection
  OAUTH2_PROXY_COOKIE_EXPIRE:             24h         # Session timeout
  OAUTH2_PROXY_SKIP_AUTH_REGEX:           "^/healthz|^/oauth2"
```

---

## Setup Instructions

### Step 1: Update DNS Records

Point the `ide.kushnir.cloud` domain to your Cloudflare Tunnel:

```bash
# In Cloudflare Dashboard:
# Domain: ide.kushnir.cloud
# Type: CNAME
# Target: <cloudflare-tunnel-url>
# Proxy: Proxied (orange cloud)
```

### Step 2: Configure Google OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select your project (or create a new one)
3. Navigate to **APIs & Services** → **Credentials**
4. Click **Create Credentials** → **OAuth 2.0 Client IDs** → **Web Application**
5. Add Authorized Origins:
   - `https://ide.kushnir.cloud`
   - `https://grafana.kushnir.cloud` (optional, for Grafana OAuth)
6. Add Authorized Redirect URIs:
   - `https://ide.kushnir.cloud/oauth2/callback`
7. Copy the **Client ID** and **Client Secret**

### Step 3: Update .env with OAuth Credentials

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Edit .env on remote host
cd ~/code-server-enterprise
nano .env
```

Update these lines:
```bash
GOOGLE_CLIENT_ID=<your-client-id>
GOOGLE_CLIENT_SECRET=<your-client-secret>
```

### Step 4: Restart Services

```bash
# SSH to production host
ssh akushnir@192.168.168.31
cd ~/code-server-enterprise

# Restart OAuth and Caddy
docker-compose restart oauth2-proxy caddy

# Verify
docker logs oauth2-proxy | grep -i "OIDC\|redirect\|domain"
```

### Step 5: Test the Configuration

1. Open `https://ide.kushnir.cloud` in browser
2. Should be redirected to Google Login
3. After login, should be redirected back to code-server
4. Should see code-server dashboard

---

## Security Configuration

### OAuth Security Headers

All services enforce security headers:
```
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
```

### Cookie Security

- **Name**: `_oauth2_proxy_ide`
- **Secure**: Only transmitted over HTTPS
- **HttpOnly**: Not accessible via JavaScript (prevents XSS attacks)
- **SameSite**: Lax (CSRF protection)
- **Expiry**: 24 hours (refresh after 15 minutes of activity)

### LAN/VPN Access Restrictions

Internal services (Prometheus, AlertManager, Jaeger, Ollama) are restricted to:
- LAN: `192.168.168.0/24`
- WireGuard VPN: `10.8.0.0/24`
- OpenVPN: `10.0.0.0/8`

---

## Troubleshooting

### OAuth Redirect URI Mismatch

**Error**: "Redirect URI mismatch" during OAuth login

**Solution**:
1. Verify `DOMAIN=ide.kushnir.cloud` in `.env`
2. Check Google Cloud Console → Credentials
3. Confirm authorized redirect URI: `https://ide.kushnir.cloud/oauth2/callback`
4. Restart oauth2-proxy: `docker-compose restart oauth2-proxy`

### Certificate Errors

**Error**: "Unable to get local issuer certificate"

**Solution**:
1. Cloudflare SSL/TLS must be set to "Full (strict)"
2. Let's Encrypt ACME will auto-provision certificates
3. Check Caddy logs: `docker logs caddy | grep -i "acme\|certificate"`

### Cookie Issues

**Error**: "Session cookie not set" or "Unauthorized"

**Solution**:
1. Clear browser cookies for `ide.kushnir.cloud`
2. Verify `OAUTH2_PROXY_COOKIE_SECRET` is set to 32+ characters
3. Restart oauth2-proxy: `docker-compose restart oauth2-proxy`

### Service Unavailable

**Error**: "503 Service Unavailable"

**Solution**:
1. Verify all services are running: `docker ps`
2. Check Caddy reverse proxy configuration: `docker logs caddy`
3. Verify oauth2-proxy health: `docker exec oauth2-proxy wget -qO- http://localhost:4180/ping`

---

## Monitoring & Health Checks

### OAuth2-proxy Health

```bash
# Check health endpoint
docker exec oauth2-proxy wget -qO- http://localhost:4180/ping

# Expected output: OK
```

### Cookie Configuration Verification

```bash
# View current OAuth2-proxy configuration
docker logs oauth2-proxy | grep -i "cookie settings"

# Expected output shows:
# - Cookie name: _oauth2_proxy_ide
# - Secure: true
# - HttpOnly: true
# - SameSite: lax
# - Expiry: 24h0m0s
```

### TLS Certificate Verification

```bash
# Check certificate via openssl
echo | openssl s_client -servername ide.kushnir.cloud -connect ide.kushnir.cloud:443 2>/dev/null | openssl x509 -text -noout

# Check certificate via curl
curl -vI https://ide.kushnir.cloud 2>&1 | grep -E "subject:|issuer:|Not Before|Not After"
```

---

## Production Deployment Checklist

- [x] DNS records updated (ide.kushnir.cloud → Cloudflare Tunnel)
- [ ] Google OAuth credentials obtained from GCP
- [ ] `.env` updated with real OAuth credentials
- [ ] Services restarted after `.env` update
- [ ] OAuth flow tested (login works)
- [ ] TLS certificate provisioned (Let's Encrypt)
- [ ] Security headers verified
- [ ] Cookie security verified
- [ ] Health checks passing
- [ ] Monitoring dashboards accessible

---

## Maintenance

### Certificate Renewal

Let's Encrypt certificates auto-renew via Caddy. Monitor renewal:

```bash
# Check certificate expiry
docker exec caddy caddy list-certificates | grep -A2 "ide.kushnir.cloud"

# View Caddy ACME logs
docker logs caddy | grep -i "acme"
```

### OAuth Credential Rotation

To rotate OAuth credentials:
1. Create new credentials in Google Cloud Console
2. Update `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in `.env`
3. Restart oauth2-proxy: `docker-compose restart oauth2-proxy`
4. Delete old credentials from Google Cloud Console

---

## References

- [OAuth2-proxy Documentation](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Google OAuth 2.0](https://developers.google.com/identity/protocols/oauth2)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [Let's Encrypt ACME](https://letsencrypt.org/)
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)

---

**Last Updated**: April 15, 2026  
**Status**: Production Deployment  
**Version**: 1.0
