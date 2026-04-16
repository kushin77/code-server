# Runbook: SSL Certificate Expiry Warning

**Alert**: `SSLCertExpiryWarning`  
**Severity**: MEDIUM (Warning)  
**Time to Resolution**: < 24 hours  
**Action Trigger**: Fired when cert expires in < 30 days  

---

## Symptoms

- Alert: "SSL certificate expires in X days"
- Caddy logs show ACME renewal attempts
- Certificate details show expiry date approaching

---

## Root Causes

1. **ACME renewal disabled** - Caddy misconfigured without auto-renewal
2. **DNS challenge failing** - DNS01 validation can't reach domain
3. **Rate limiting** - Let's Encrypt rate limit temporarily blocks renewal
4. **Certificate pinned** - Old certificate pinned in config
5. **Network issues** - Can't reach letsencrypt.org

---

## Immediate Actions

### 1. Check Certificate Details

```bash
# View certificate expiry date
openssl s_client -connect ide.kushnir.cloud:443 -showcerts 2>/dev/null | openssl x509 -noout -dates

# Expected output:
# notBefore=... notAfter=2026-07-18 ...

# Check days remaining
echo "$(date -d "2026-07-18" +%s) - $(date +%s)" | awk '{print int(($1-$2)/86400)}' echo "days remaining"
```

### 2. Check Caddy Renewal Status

```bash
ssh akushnir@primary.prod.internal

# Check Caddy is running
docker ps | grep caddy

# View Caddy logs
docker logs caddy --tail 100 | grep -i "acme\|renew\|certificate"

# Check certificate storage (inside container)
docker exec caddy ls -la /data/caddy/certificates/acme/acme-v02.api.letsencrypt.org/

# Expected: cert files with recent modification times
```

### 3. Verify ACME Configuration

```bash
# Check Caddy config includes auto-renewal
docker exec caddy cat /etc/caddy/Caddyfile | grep -A 2 "tls"

# Should show TLS config with ACME, no explicit cert path (means auto-renewal enabled)
```

### 4. Check DNS Resolution

```bash
# Ensure domain resolves (required for DNS01 challenge)
nslookup ide.kushnir.cloud
dig ide.kushnir.cloud +short

# Should return public IP (or CNAME to CDN)
```

### 5. Force ACME Renewal (If < 14 days left)

```bash
# Option 1: Restart Caddy (triggers renewal check)
docker-compose restart caddy

# Option 2: Force renewal via Caddy API
docker exec caddy caddy reload --config /etc/caddy/Caddyfile

# Option 3: Manual renewal with acme.sh (if Caddy renewal fails)
docker exec caddy acme.sh --renew-all --force --home /data/caddy/.acme.sh

# Monitor renewal
docker logs caddy --follow | grep -i "acme\|renew"
```

---

## Troubleshooting

### Certificate Renewal Failing with DNS Error

```bash
# Check DNS provider configuration (e.g., Cloudflare API)
docker exec caddy cat /etc/caddy/Caddyfile | grep -A 5 "dns"

# Verify DNS provider credentials are set
echo $CF_API_TOKEN  # Should be set
echo $CF_API_EMAIL  # Should be set

# If missing, add to .env and reload:
docker-compose config | grep CF_
docker-compose restart caddy
```

### Certificate Renewal Failing with Rate Limit

Let's Encrypt has rate limits:
- 50 certificates per registered domain per week
- 5 duplicate certificates per week

**If rate-limited:**

```bash
# Wait 7 days for limit to reset
# OR
# Switch to Let's Encrypt staging server for testing:
# In Caddyfile: tls {
#   ca https://acme-staging-v02.api.letsencrypt.org/directory
# }

# After testing, switch back to production
# Note: Staging certificates won't be trusted by browsers
```

### Certificate Not Renewing at All

```bash
# Check if Caddy is configured with ACME at all
docker exec caddy grep -i acme /etc/caddy/Caddyfile

# If not found, update Caddyfile:
cat >> /etc/caddy/Caddyfile << 'EOF'
ide.kushnir.cloud {
    tls {
        dns cloudflare {$CF_API_TOKEN}
    }
    reverse_proxy http://code-server:8080
}
EOF

docker-compose restart caddy
```

---

## Prevention

### 1. Enable Prometheus Alert for Critical Threshold

```yaml
# Add to prometheus alert rules:
- alert: SSLCertExpiryCritical
  expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 7
  for: 1h
  annotations:
    summary: "Certificate expires in {{ $value }} days — CRITICAL"
```

### 2. Automate Renewal Testing

```bash
# Add monthly test to ensure renewal process works
0 0 1 * * /home/akushnir/code-server-enterprise/scripts/test-acme-renewal.sh
```

### 3. Create Manual Renewal Procedure Documentation

```bash
# Create runbook for manual ACME renewal (if automation fails)
cat > /home/akushnir/code-server-enterprise/scripts/manual-acme-renewal.sh << 'EOF'
#!/bin/bash
# Manual ACME renewal for ide.kushnir.cloud
docker exec caddy acme.sh --renew \
  --domain ide.kushnir.cloud \
  --dns dns_cf \
  --home /data/caddy/.acme.sh
EOF
chmod +x /home/akushnir/code-server-enterprise/scripts/manual-acme-renewal.sh
```

---

## Escalation

If cert expires within 3 days and renewal hasn't occurred:

1. **Force manual renewal immediately** (see "Force ACME Renewal" above)
2. **Page on-call engineer** if renewal fails
3. **Temporary fix**: Use self-signed cert until production renewal succeeds
4. **Post-incident**: Review ACME automation for gaps

---

*Last Updated: April 18, 2026*  
*On-Call Contact: @infrastructure-team*
