# 🌐 IDE Domain Configuration Guide

## Current Configuration

**Your IDE Domain**: `ide.kushnir.cloud`  
**Access Method**: HTTPS (TLS via Caddy)  
**Status**: ✅ **CONFIGURED & READY**

## Access Instructions

### Direct Access
```
https://ide.kushnir.cloud
```

### OAuth2 Authentication
The system uses Google OAuth2 for authentication:
1. Navigate to `https://ide.kushnir.cloud`
2. Click "Sign in with Google"
3. Authenticate with your Google account
4. Redirected to VS Code IDE

### API Endpoints (Internal Only)

These are accessible within the container network:
- **Code-Server**: http://code-server:8080
- **Ollama**: http://ollama:11434
- **OAuth2 Proxy**: http://oauth2-proxy:4180
- **Caddy**: https://ide.kushnir.cloud (public)

## Configuration Files

### 1. Environment Variables (.env)

The domain is configured in `.env`:

```env
# Target domain for the IDE
DOMAIN=ide.kushnir.cloud

# OAuth2 configuration (from Google Cloud Console)
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret-here
```

⚠️ **IMPORTANT:** Never commit real OAuth client secrets to the repository.
Use `gcp-fetch-secrets.sh` to load secrets from Google Secret Manager instead.

To change the domain:
```bash
# Edit .env (which should be in .gitignore)
nano .env

# Change:
# DOMAIN=ide.kushnir.cloud
# To:
# DOMAIN=your-new-domain.com

# Restart services
docker-compose down
docker-compose up -d
```

### 2. Docker Compose Configuration

The domain is automatically passed to services that need it:

```yaml
caddy:
  environment:
    DOMAIN: "${DOMAIN}"  # Read from .env

oauth2-proxy:
  environment:
    OAUTH2_PROXY_REDIRECT_URL: "https://${DOMAIN}/oauth2/callback"
```

### 3. Caddy Reverse Proxy (Caddyfile)

Caddy automatically reads the DOMAIN variable:

```caddy
{$DOMAIN} {
    # TLS via Let's Encrypt
    # HTTP/HTTPS routing configured
    # Reverse proxy to code-server
    # WebSocket upgrade for IDE features
}
```

## DNS & TLS Setup

### Current Status
- ✅ **Domain Registered**: ide.kushnir.cloud
- ✅ **DNS Configured**: GoDaddy (credentials in .env)
- ✅ **TLS Provider**: Let's Encrypt (auto-renew via Caddy)
- ✅ **HTTP Challenge**: Standard HTTP-01 (requires port 80/443 open)

### DNS Records Required

Ensure your DNS provider (GoDaddy) has these records:

```
A Record:
  Name: ide
  Type: A
  Value: <your.server.ip.address>
  TTL: 3600

CNAME (Optional, for www):
  Name: www
  Type: CNAME
  Value: ide.kushnir.cloud
  TTL: 3600
```

### Verify DNS

```bash
# Check DNS resolution
nslookup ide.kushnir.cloud
dig ide.kushnir.cloud

# Expected output:
# ide.kushnir.cloud. 3600 IN A <your.server.ip>
```

### Verify TLS Certificate

```bash
# Check certificate details
openssl s_client -connect ide.kushnir.cloud:443

# Expected:
# Subject: CN = ide.kushnir.cloud
# Issuer: C = US, O = Let's Encrypt
# Not Before: 2026-04-12
# Not After: 2026-07-11
```

## Firewall & Network Requirements

### Required Open Ports

| Port | Protocol | Purpose | Who Accesses |
|------|----------|---------|--------------|
| 80 | TCP | HTTP → HTTPS redirect | Public internet |
| 443 | TCP | HTTPS (IDE) | Public internet |
| 8080 | TCP | code-server (internal) | Caddy only |
| 11434 | TCP | Ollama (internal) | code-server only |
| 4180 | TCP | OAuth2 proxy (internal) | Caddy only |

### Network Architecture

```
┌──────────────────────────────────────────────────┐
│         Public Internet                          │
│  (ide.kushnir.cloud:443)                        │
└────────────────────┬─────────────────────────────┘
                     │ [HTTPS]
        ┌────────────▼──────────────┐
        │      Caddy (TLS)          │
        │  - Let's Encrypt renewal  │
        │  - OAuth2 integration      │
        │  - WebSocket upgrade       │
        └────────────┬──────────────┘
                     │ [HTTP Internal]
        ┌────────────▼──────────────┐
        │  Docker Network            │
        │  (enterprise, isolated)    │
        │                            │
        │  ├─ code-server:8080      │
        │  ├─ ollama:11434         │
        │  ├─ oauth2-proxy:4180    │
        │  └─ caddy:80 (redirect)  │
        └───────────────────────────┘
```

## Troubleshooting

### Issue: Certificate Errors

**Symptom**: `CERTIFICATE_VERIFY_FAILED` or untrusted certificate

**Solution**:
```bash
# 1. Check certificate validity
openssl s_client -connect ide.kushnir.cloud:443 -showcerts

# 2. Check Caddy logs
docker-compose logs caddy | grep -i certificate

# 3. Force certificate renewal
docker-compose exec caddy caddy reload  # Reload Caddyfile
```

### Issue: Cannot Access https://ide.kushnir.cloud

**Symptom**: Connection timeout or refused

**Solution**:
```bash
# 1. Check Caddy is running
docker-compose ps caddy

# 2. Check DNS resolves
nslookup ide.kushnir.cloud

# 3. Check firewall allows port 443
telnet ide.kushnir.cloud 443

# 4. Check Caddy logs
docker-compose logs caddy | tail -50
```

### Issue: OAuth2 Redirect Loop

**Symptom**: Infinite redirect between login screens

**Solution**:
```bash
# 1. Verify OAuth2 redirect URL in Caddy log
docker-compose logs oauth2-proxy | grep redirect_url

# 2. Verify DOMAIN environment variable
docker-compose exec oauth2-proxy env | grep DOMAIN

# 3. Expected: OAUTH2_PROXY_REDIRECT_URL=https://ide.kushnir.cloud/oauth2/callback

# 4. If incorrect, update .env and restart
nano .env  # Fix DOMAIN
docker-compose restart oauth2-proxy caddy
```

### Issue: Mixed Content Warning (Browser)

**Symptom**: Browser shows insecure content warning

**Solution**: This is expected during setup. After TLS is valid:
```bash
# 1. Hard refresh browser
Ctrl+Shift+R (or Cmd+Shift+R on Mac)

# 2. Clear browser cache
Settings → Privacy → Clear browsing data

# 3. Check Content-Security-Policy header
curl -I https://ide.kushnir.cloud | grep -i csp
```

## Changing the Domain

To move to a different domain:

### Step 1: Update DNS
1. Point new domain to your server IP in DNS provider
2. Wait for propagation (5-30 minutes)
3. Verify: `nslookup new-domain.com`

### Step 2: Update Configuration
```bash
# Edit .env
nano .env

# Change DOMAIN
DOMAIN=new-domain.com

# Restart services
docker-compose down
docker-compose up -d

# Caddy will automatically request new certificate for new domain
```

### Step 3: Verify Access
```bash
# Wait 30 seconds for Caddy to reload
sleep 30

# Test connectivity
curl -I https://new-domain.com

# Expected: HTTP/1.1 200 OK
# Certificate for: new-domain.com
```

## Security Best Practices

### 1. OAuth2 Configuration
- ✅ Google OAuth2 configured in .env
- ✅ Redirect URL matches domain exactly
- ✅ Cookie encryption enabled
- ⚠️ **TODO**: Update Google OAuth permissions if changing domain

### 2. TLS & HTTPS
- ✅ Let's Encrypt auto-renewal enabled
- ✅ HSTS header configured (enforces HTTPS)
- ✅ Certificate valid for 90 days
- ⚠️ Monitor: `docker-compose logs caddy | grep "renew"`

### 3. Network Isolation
- ✅ Docker network isolated (not exposed to host)
- ✅ Internal services use container names (not localhost)
- ✅ Only port 443 public (80 for ACME redirect)
- ✅ OAuth2 layer protects internal services

### 4. Firewall Rules

**UFW (Ubuntu)**:
```bash
sudo ufw allow 80/tcp   # ACME challenge
sudo ufw allow 443/tcp  # HTTPS access
sudo ufw deny 8080/tcp  # Block direct code-server access
sudo ufw deny 11434/tcp # Block direct Ollama access
```

**AWS Security Group**:
```
Inbound:
  - Port 80 (TCP): 0.0.0.0/0 (HTTP redirect)
  - Port 443 (TCP): 0.0.0.0/0 (HTTPS)
  
Outbound:
  - Allow all (for package download, cert renewal)
```

## Monitoring Certificate Health

```bash
# Check certificate expiration
docker-compose exec caddy caddy list-modules | grep tls

# Monitor renewal attempts
docker-compose logs -f caddy | grep -i "certficate\|acme\|renew"

# Set up alert (check weekly)
0 0 * * 0 docker-compose exec caddy certbot certificates

# Export to monitoring system
docker exec caddy caddy cert cat ide.kushnir.cloud | openssl x509 -text
```

## Summary

**Your Current Setup**:
- ✅ Domain: `ide.kushnir.cloud`
- ✅ TLS: Let's Encrypt (auto-renew)
- ✅ Auth: Google OAuth2
- ✅ Proxy: Caddy reverse proxy
- ✅ Internal services: Dockerized & isolated

**Next Steps**:
1. Access `https://ide.kushnir.cloud`
2. Authenticate with Google SSO
3. Verify all features working
4. Check certificate: `https://ide.kushnir.cloud` → click lock icon

**Questions?**
- Check logs: `docker-compose logs -f caddy`
- Verify configs: `cat .env | grep DOMAIN`
- Test health: `curl -I https://ide.kushnir.cloud`

---

**Last Updated**: 2026-04-13  
**Domain**: ide.kushnir.cloud  
**Status**: ✅ Production Ready
