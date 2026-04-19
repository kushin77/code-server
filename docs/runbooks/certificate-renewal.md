# Runbook: TLS Certificate Expiration (CertificateExpiration)

**Alert**: `CertificateExpirationWarning` (< 30 days) | `CertificateExpirationCritical` (< 7 days)  
**Severity**: WARNING / CRITICAL  
**Component**: TLS certificate management  
**Related Issue**: #569

## Overview

This alert fires when TLS certificates are approaching expiration. Expired certificates cause HTTPS connections to fail with security warnings.

## Quick Response

```bash
# 1. Check current certificate status
docker-compose exec caddy caddy list-certs

# 2. Check certificate expiration dates
openssl s_client -connect kushnir.cloud:443 </dev/null 2>/dev/null | openssl x509 -noout -dates

# 3. View Caddy logs for cert renewal attempts
docker-compose logs --tail 50 caddy | grep -i cert
```

## Detailed Investigation

### Step 1: Verify Certificate Details

```bash
# List all certificates managed by Caddy
docker-compose exec caddy caddy list-certs --format json | jq .

# Extract expiration dates
docker-compose exec caddy caddy list-certs | grep -E "^[[:space:]]*Expiration:|^[[:space:]]*Subject:"
```

### Step 2: Renewal Status

```bash
# Check if Caddy is trying to renew
docker-compose logs caddy | grep -i "renew\|acme" | tail -20

# Check certificate cache directory
docker-compose exec caddy ls -la /data/caddy/certificates/acme/*/
```

### Step 3: Common Issues

| Issue | Detection | Resolution |
|-------|-----------|------------|
| ACME renewal failing | Caddy logs show "ACME error" | Check internet connectivity and rate limits |
| Certificate not trusted | `openssl verify` fails | Regenerate via ACME: `docker-compose restart caddy` |
| DNS not resolving | `nslookup kushnir.cloud` fails | Update DNS records, wait for propagation |
| Firewall blocking ACME | Port 80/443 unreachable from internet | Update firewall rules for Let's Encrypt validation |
| Old cert still in use | `openssl s_client` shows old dates | Clear cache: `docker-compose exec caddy rm -rf /data/caddy/certificates/` && restart |

### Step 4: Force Renewal

```bash
# Option 1: Full Caddy restart (automatic renewal)
docker-compose down caddy
docker-compose up -d caddy

# Wait for renewal
sleep 60

# Verify new certificate
openssl s_client -connect kushnir.cloud:443 </dev/null 2>/dev/null | openssl x509 -noout -dates

# Option 2: Manual ACME renewal (if configured)
docker-compose exec caddy caddy reload  # soft reload may trigger renewal
```

### Step 5: Verify Fix

```bash
# Check certificate is valid and not expired
docker-compose exec caddy caddy list-certs | grep -E "Subject|Expiration"

# Test HTTPS connection
curl -vI https://kushnir.cloud 2>&1 | grep -E "subject|issuer|notBefore|notAfter"

# Monitor renewal in logs
docker-compose logs -f caddy | grep -i cert
```

## Prevention

- **Alert configured**: Warning at 30 days, Critical at 7 days
- **Automatic renewal**: Caddy handles Let's Encrypt renewal automatically
- **DNS validation**: Ensure DNS records point to production host
- **Internet connectivity**: Verify outbound HTTPS on port 443 to ACME servers

## Configuration

```yaml
# Caddyfile - automatic HTTPS
kushnir.cloud {
    reverse_proxy http://code-server:8080
    # Caddy automatically handles Let's Encrypt renewal
}
```

## Escalation

If certificate renewal fails repeatedly:
1. Check ACME rate limits: Let's Encrypt allows 5 failures per account per hour
2. Verify email for ACME notifications: admin@kushnir.cloud
3. Consider switching to production Let's Encrypt (vs staging) if in testing
4. Manual certificate upload if ACME cannot be used

## Related Documentation

- [Caddy HTTPS Documentation](https://caddyserver.com/docs/quick-start)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
