# Production Certificate Configuration

**Status**: Caddyfile updated for automatic HTTPS (production)  
**Date**: April 14, 2026  
**Scope**: Elite Best Practices - Immutable, On-Premises Focus

---

## TLS/HTTPS Configuration Strategy

### Production (ide.kushnir.cloud)

**Deployment Mode**: Automatic HTTPS with Let's Encrypt

```yaml
Requirements:
  - Public domain: ide.kushnir.cloud
  - DNS: Must point to production host IP or Cloudflare Tunnel endpoint
  - ACME: Email ops@kushnir.cloud or admin@kushnir.cloud
  - Let's Encrypt: https://acme-v02.api.letsencrypt.org/directory
  - Auto-renewal: Caddy handles automatically
```

**Caddyfile Configuration**:
```caddy
{
    email ops@kushnir.cloud
    acme_ca https://acme-v02.api.letsencrypt.org/directory
    auto_https on   # Enable automatic certificate generation
}

ide.kushnir.cloud {
    # Your configuration here
}
```

**How It Works**:
1. Caddy listens on :443 (HTTPS) and :80 (HTTP)
2. When client connects to ide.kushnir.cloud:443
3. Caddy checks for existing cert (or generates if missing)
4. If no cert: Initiates ACME challenge via Let's Encrypt
5. Let's Encrypt validates domain ownership (HTTP-01 or DNS-01)
6. Certificate issued and stored in Caddy data directory
7. Certificate auto-renewed 30 days before expiry

**Prerequisites**:
- ✅ Domain DNS pointing to host (or Cloudflare Tunnel)
- ✅ Port 80 accessible for ACME HTTP-01 challenge
- ✅ ACME_EMAIL environment variable set
- ✅ Caddy data directory mounted as persistent volume

**Status Check**:
```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Check if certificate was issued
docker-compose logs caddy | grep -i "certificate\|acme"

# Verify certificate validity
openssl s_client -connect localhost:443 -showcerts </dev/null | grep "subject="
```

---

### On-Premises (192.168.168.31.nip.io)

**Deployment Mode**: HTTP (no TLS, no ACME)

```yaml
Configuration:
  - Domain: code-server.192.168.168.31.nip.io
  - Protocol: HTTP (no HTTPS)
  - Port: 80 (standard HTTP)
  - ACME: Disabled (nip.io is not a real registrar domain)
  - auto_https: disable_certs (in Caddyfile)
```

**Caddyfile Configuration**:
```caddy
# On-prem HTTP fallback (no HTTPS)
code-server.192.168.168.31.nip.io http://* {
    encode gzip
    header X-Content-Type-Options "nosniff"
    
    reverse_proxy code-server:8080 {
        flush_interval -1
    }
}
```

**Why HTTP?**
- nip.io is a wildcard DNS service, not a real registrable domain
- Let's Encrypt cannot issue certificates for nip.io
- On-prem deployments don't require HTTPS for internal networks
- Performance: No TLS overhead on internal LAN

**Access**:
```bash
# From any machine on the network:
http://code-server.192.168.168.31.nip.io:80

# Browser will show "Not Secure" (HTTP, not HTTPS) - this is EXPECTED
# This is intentional for on-prem; add your own certificate if needed
```

---

## Deployment Paths & Trade-offs

### Path 1: Production (Real Domain + Let's Encrypt)

**Setup**:
1. Buy or use existing domain (e.g., ide.kushnir.cloud)
2. Point DNS to production host or Cloudflare Tunnel
3. Set ACME_EMAIL in .env
4. Set ACME_CA in .env (or use default Let's Encrypt)
5. Deployment: `docker-compose up -d`

**Result**:
- ✅ Real HTTPS certificate (trusted by browsers)
- ✅ Auto-renewal (Caddy handles it)
- ✅ Production-grade security
- ✅ No manual certificate management
- ❌ Requires public DNS
- ❌ Domain must be accessible from internet

**Production .env**:
```env
DOMAIN=ide.kushnir.cloud
EXTERNAL_DOMAIN=192.168.168.31.nip.io
ACME_EMAIL=ops@kushnir.cloud
ACME_CA=https://acme-v02.api.letsencrypt.org/directory
```

---

### Path 2: On-Premises (nip.io + HTTP)

**Setup**:
1. Set DOMAIN to any on-prem hostname or IP.address
2. Set ACME_EMAIL to any value (won't be used)
3. Set ACME_CA="" (empty) to disable ACME
4. Deployment: `docker-compose up -d`

**Result**:
- ✅ Works without DNS/domain registration
- ✅ Works behind firewalls/NAT
- ✅ No Let's Encrypt setup needed
- ✅ Instant deployment (no ACME validation)
- ❌ No HTTPS (HTTP only)
- ❌ Browsers show "Not Secure" warning

**On-Prem .env**:
```env
DOMAIN=code-server.192.168.168.31.nip.io
EXTERNAL_DOMAIN=192.168.168.31.nip.io
ACME_EMAIL=none@example.com
ACME_CA=  # Empty to disable ACME
```

---

### Path 3: Hybrid (Custom Certificate + On-Prem)

**Setup**:
1. Generate self-signed certificate:
   ```bash
   openssl req -x509 -newkey rsa:4096 -nodes -days 365 \
     -out /path/to/cert.pem -keyout /path/to/key.pem
   ```
2. Mount certificate into Caddy container
3. Use Caddyfile to reference certificate
4. Deployment: `docker-compose up -d`

**Result**:
- ✅ HTTPS available on-prem
- ✅ No Let's Encrypt setup
- ✅ Works behind firewalls
- ⚠️ Self-signed: browsers show warning
- ⚠️ Manual certificate renewal

**Caddyfile for Custom Cert**:
```caddy
code-server.192.168.168.31.nip.io {
    tls /etc/caddy/certs/cert.pem /etc/caddy/certs/key.pem
    reverse_proxy code-server:8080
}
```

---

## Troubleshooting

### "Connection is not private" (Browser Warning)

**Cause**: HTTPS certificate is self-signed or not from trusted CA

**Solutions**:
1. **On-Prem (Expected)**: Use HTTP (nip.io domains)
   - Change DOMAIN to use http:// prefix in Caddy
   - This warning is expected and acceptable for on-prem

2. **Production (Problem)**: Certificate generation failed
   - Check DNS resolution: `nslookup ide.kushnir.cloud`
   - Check port 80 accessible: `curl -v http://ide.kushnir.cloud`
   - Check Caddy logs: `docker-compose logs caddy`
   - Check ACME_EMAIL configuration

### "NET::ERR_CERT_AUTHORITY_INVALID"

**Cause**: Browser doesn't trust the certificate authority

**On-Prem Solution**:
```bash
# Add certificate exception in browser (NOT recommended for production)
# Or use HTTP instead:
http://code-server.192.168.168.31.nip.io
```

**Production Solution**:
```bash
# Ensure domain is publicly resolvable
nslookup ide.kushnir.cloud
# Should resolve to Cloudflare origin or production IP

# Restart Caddy to trigger certificate generation
docker-compose restart caddy

# Check certificate logs
docker-compose logs caddy | grep -i "certificate\|acme"
```

### Certificate Not Auto-Renewing

**Check**:
```bash
# Verify Caddy certificate maintenance is running
docker-compose logs caddy | grep "certificate maintenance"

# Check certificate expiry
echo | openssl s_client -servername ide.kushnir.cloud -connect localhost:443 2>/dev/null | grep "Not After"
```

**Fix**:
1. Ensure port 80 is accessible (ACME renewal needs it)
2. Check firewall rules don't block port 80
3. Restart Caddy: `docker-compose restart caddy`

---

## Current Deployment State (April 14, 2026)

### Production Configuration

**Status**: ✅ Ready for Certificate Generation

**Current .env**:
```env
DOMAIN=ide.kushnir.cloud
EXTERNAL_DOMAIN=192.168.168.31.nip.io
ACME_EMAIL=ops@kushnir.cloud
ACME_CA=https://acme-v02.api.letsencrypt.org/directory
```

**Current Caddyfile**:
- ✅ `auto_https on` (enabled for production)
- ✅ `email ops@kushnir.cloud` (configured)
- ✅ `acme_ca https://acme-v02.api.letsencrypt.org/directory` (Let's Encrypt)
- ✅ `ide.kushnir.cloud` block (HTTPS production domain)
- ✅ `code-server.192.168.168.31.nip.io` block (HTTP on-prem)

**For Production to Work**:
1. DNS must point ide.kushnir.cloud to production host or Cloudflare Tunnel
2. Port 80 and 443 must be accessible from internet (for Let's Encrypt validation and HTTPS)
3. Restart Caddy: `docker-compose restart caddy`
4. Certificate will be auto-generated and auto-renewed

**For On-Prem to Work**:
1. Already working with HTTP
2. Access via: http://code-server.192.168.168.31.nip.io
3. Browser shows "Not Secure" (expected for HTTP)

---

## Elite Best Practices Compliance

✅ **Immutable Infrastructure**
- Certificates defined in Terraform/docker-compose
- Auto-renewal handled by Caddy (no manual renewal)
- Certificate storage in persistent Docker volume

✅ **Idempotent Deployment**
- `docker-compose up -d` reproducible (same cert every time)
- Caddy automatically manages certificate lifecycle

✅ **On-Premises Focus**
- ✅ Production path: Real domain + Let's Encrypt
- ✅ On-prem path: HTTP (no certificate needed)
- ✅ Both paths fully automated

✅ **Security Best Practices**
- HTTPS enforced in production
- Security headers configured (HSTS, CSP, etc.)
- Certificate auto-renewal prevents expiry

---

## Next Steps

1. **For Production**:
   - Configure DNS (ide.kushnir.cloud → production IP)
   - Restart Caddy container
   - Monitor certificate generation in logs
   - Verify HTTPS with browser

2. **For On-Prem**:
   - Use HTTP URLs (nip.io domains)
   - No certificate setup needed
   - All security features work via reverse proxy headers

3. **For Custom Certificates**:
   - See Path 3 above
   - Mount certificate into Caddy container
   - Reference in Caddyfile using `tls` directive

---

**Configuration Owner**: Terraform IaC (main.tf + docker-compose.tpl + Caddyfile)  
**Certificate Authority**: Let's Encrypt (automatic, auto-renewal)  
**Status**: ✅ PRODUCTION READY
