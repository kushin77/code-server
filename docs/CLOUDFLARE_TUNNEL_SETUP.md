# Cloudflare Tunnel & Access Setup Guide

**Issue**: #185 - IMPL: Cloudflare Tunnel Setup for Home Server IDE Access
**Status**: Implementation guide + scripts
**Date**: April 13, 2026

## Overview

This guide implements secure, globally-accessible code-server IDE access via Cloudflare Tunnel and Access, with zero IP exposure and enterprise-grade zero-trust authentication.

## Architecture

```
Developer Browser
    ↓ (HTTPS, encrypted)
Cloudflare Global Edge (DDoS protection, ~50ms latency)
    ↓ (Zero IP exposure)
Cloudflare Access (Zero-trust auth, MFA, time-limits)
    ↓ (Authenticated session)
Cloudflare Tunnel (encrypted backhaul)
    ↓ (localhost:8080)
Code-Server IDE (on-premises, never exposed)
```

## Prerequisites

- **Cloudflare Account**: Free tier eligible
- **code-server**: Already running on home network (localhost:8080)
- **Domain**: yourdomain.com (preferably already on Cloudflare)
- **Linux/macOS**: For cloudflared installation
- **API Access**: Cloudflare API token with Access permissions

## Quick Start

### 1. Install Cloudflare Tunnel

```bash
# Linux
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb

# macOS
brew install cloudflare/cloudflare/cloudflared

# Authenticate (opens browser)
cloudflared login
```

### 2. Create Tunnel

```bash
# Create tunnel named "home-dev"
cloudflared tunnel create home-dev

# Verify tunnel created
cloudflared tunnel list
```

### 3. Configure Tunnel Routing

Create `~/.cloudflared/config.yml`:

```yaml
tunnel: home-dev
credentials-file: ~/.cloudflared/<tunnel-id>.json

ingress:
  # Main IDE access
  - hostname: dev.yourdomain.com
    service: http://localhost:8080

  # Terminal proxy (future)
  - hostname: terminal.yourdomain.com
    service: http://localhost:3000

  # Default 404
  - service: http_status:404

logger:
  level: info

originRequest:
  http2Origin: true
  connectTimeout: 30s
  tlsTimeout: 10s
```

### 4. Add DNS CNAME Record

In Cloudflare Dashboard:

1. Go to DNS → Records
2. Add CNAME: `dev` → `<tunnel-id>.cfargotunnel.com`
3. Add CNAME: `terminal` → `<tunnel-id>.cfargotunnel.com`
4. Orange cloud enabled (proxied through Cloudflare)

### 5. Start Tunnel

```bash
# Manual (for testing)
cloudflared tunnel run home-dev --config ~/.cloudflared/config.yml

# Systemd (production)
# Setup by script or manually:
sudo systemctl start cloudflared
```

### 6. Verify Access

```bash
# Check tunnel status
cloudflared tunnel status home-dev

# Test connectivity
curl -I https://dev.yourdomain.com

# Verify NO IP exposure
curl -I https://dev.yourdomain.com | grep -i x-real-ip
# Should NOT show home IP
```

## Automation Scripts

### setup-cloudflare-tunnel.sh

Fully automated tunnel setup:

```bash
#!/bin/bash
DOMAIN=dev.yourdomain.com \
CODE_SERVER_PORT=8080 \
  bash scripts/setup-cloudflare-tunnel.sh
```

**Does:**
- Installs cloudflared
- Authenticates with Cloudflare
- Creates tunnel
- Generates config.yml
- Sets up systemd service
- Tests connectivity

### setup-cloudflare-access.sh

Configures zero-trust authentication:

```bash
#!/bin/bash
export CLOUDFLARE_API_TOKEN='your-api-token'
export CLOUDFLARE_ACCOUNT_ID='your-account-id'
export APP_DOMAIN='dev.yourdomain.com'
  bash scripts/setup-cloudflare-access.sh
```

**Does:**
- Creates Access application
- Sets up access policies:
  - Allow specific email domains
  - Require MFA (TOTP/U2F)
  - Deny all others by default
- Configures session timeouts (72h session, 4h idle)
- Enables audit logging

## Cloudflare Access: Zero-Trust Authentication

### Setup in Dashboard

1. **Access → Applications → Create Application**
   - Name: Code-Server IDE
   - Domain: dev.yourdomain.com
   - Type: Self-hosted

2. **Policies Tab** (or use script)
   - Policy 1: Allow developers@example.com (Precedence: 1)
   - Policy 2: Require MFA (Precedence: 2)
   - Policy 3: Deny All (Precedence: 999)

3. **Session Configuration**
   - Session duration: 72 hours
   - Idle timeout: 4 hours
   - Secure cookies: enabled
   - SameSite: lax

4. **Authentication Methods**
   - Enable: Email OTP (default)
   - Enable: TOTP (Google Authenticator, Authy)
   - Enable: U2F (hardware keys)

### Developer Experience

1. Developer opens: `https://dev.yourdomain.com`
2. Cloudflare Access prompt: "Login with your email"
3. Developer enters: `john@example.com`
4. Receives MFA code via email or authenticator
5. Code-Server IDE loads
6. Session lasts up to 72 hours (or 4 hours idle)

### Automatic Revocation

When developer's email is removed from policy:
- Active sessions terminated
- New logins denied
- Access logged in audit trail

## Security Features

### Network Layer
- ✅ **Zero IP Exposure**: Home IP never visible
- ✅ **DDoS Protection**: Free Cloudflare DDoS mitigation
- ✅ **Encryption**: TLS 1.3 end-to-end
- ✅ **Global Edge**: ~50ms latency from anywhere

### Access Layer
- ✅ **Zero-Trust**: No implicit trust, MFA required
- ✅ **Email Verification**: OTP via email
- ✅ **MFA**: TOTP/U2F support
- ✅ **Session Timeout**: 4-hour idle + 72-hour max
- ✅ **Audit Logs**: Every access attempt logged

### Monitoring & Alerts
- ✅ **Real-time Dashboard**: Session status
- ✅ **Access Logs**: 180 days (Enterprise) or 3 days (Free)
- ✅ **Failed Logins**: Visible in logs
- ✅ **Session Analytics**: Usage patterns

## Cost Analysis

| Component | Free Tier | Cost |
|-----------|-----------|------|
| Tunnel | Unlimited connections | FREE ✅ |
| Access (basic) | Up to 50 users | FREE ✅ |
| Access (advanced) | Enterprise features | $$ |
| Custom domain | yourdomain.com | Usually included (already yours) |
| **Total** | | **FREE** ($0/month) |

## Troubleshooting

### Tunnel Won't Start
```bash
# Check config
cloudflared config validate

# Check credentials
ls -la ~/.cloudflared/cert.pem

# Full verbose mode
cloudflared tunnel run home-dev --config ~/.cloudflared/config.yml --loglevel debug
```

### Access Denied After Setup
```bash
# Check policies in dashboard
# Verify email domain matches policy
# Check session duration not expired
# Verify MFA methods enabled
```

### Slow Performance
```bash
# Check tunnel health
cloudflared tunnel status home-dev

# Verify code-server responding
curl http://localhost:8080

# Check Cloudflare edge latency (should be ~50ms)
curl -I https://dev.yourdomain.com | grep server-timing
```

### DNS Not Resolving
```bash
# Verify CNAME record exists
dig dev.yourdomain.com

# Check Cloudflare dashboard DNS tab

# Flush local DNS if needed
# macOS: sudo dscacheutil -flushcache
# Linux: sudo systemctl restart systemd-resolved
```

## Advanced: Custom Headers & Security

Add to `config.yml`:

```yaml
originRequest:
  # Security headers
  headers:
    X-Custom-Auth: "code-server"
    X-Real-IP: "tunnel"

  # Disable specific features
  disableChunkedEncoding: false

  # Keep-alive
  http2Origin: true
  connectTimeout: 30s
  tlsTimeout: 10s
  tcpKeepAlive: 30s
```

## Integration with Issue #188 (Makefile)

The Makefile `make grant-access` target can be enhanced to:

```bash
# When running: make grant-access EMAIL=john@example.com DAYS=14
# Also update Cloudflare Access policy to:
# - Add john@example.com to policy
# - Set expiry reminder
# - Log to audit trail
```

## Next Steps (Roadmap)

- [ ] **Issue #187**: Read-only IDE access control (prevent code downloads)
- [ ] **Issue #184**: Git commit proxy (safe commit operations)
- [ ] **Issue #183**: Audit & compliance reporting
- [ ] **Issue #182**: Latency optimization (edge proximity routing)

## References

- **Cloudflare Tunnel Docs**: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/
- **Cloudflare Access Docs**: https://developers.cloudflare.com/cloudflare-one/identity/
- **API Reference**: https://api.cloudflare.com/
- **Tunnelsmith (YAML builder)**: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/

---

**Implementation Status**: Scripts + documentation complete
**Automation**: 2 setup scripts provided
**Manual Setup**: Dashboard configuration required for policies
**Testing**: Connectivity verification included
**Next Issue**: #187 (Read-only IDE access control)
