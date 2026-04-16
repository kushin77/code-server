# Alert Runbook: SSL Certificate Expiry

**Alert**: `SSLCertExpiry{Warning,Critical}`  
**Severity**: WARNING (>30 days), CRITICAL (<7 days)  
**SLA**: Resolve within 1 week (for warning), 24 hours (for critical)  
**Owner**: DevOps/Security Team  

---

## Problem

SSL/TLS certificate for production domain is expiring soon. If not renewed before expiry:
- Users see "Certificate Expired" browser errors
- TLS handshake fails, blocking all HTTPS traffic
- API clients fail with SSL certificate verification errors
- SLA violation if users cannot access service

---

## Immediate Investigation (< 5 minutes)

### 1. Check Certificate Status

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Check certificate expiry date
openssl x509 -enddate -noout -in /path/to/certificate.crt

# Check via Caddy (using curl)
curl -vI https://ide.kushnir.cloud 2>&1 | grep -i "expire\|date"

# Check via system
date +%s  # Current time in seconds since epoch
openssl x509 -in /path/to/certificate.crt -noout -dates | grep notAfter
```

### 2. Check Caddy Renewal Status

```bash
# View Caddy logs
docker logs caddy --tail 100 | grep -i "renew\|cert\|error"

# Check Caddy certificate store
ls -lh /mnt/caddy-data/certificates/

# Check for renewal errors
docker logs caddy | grep -i "rate limit\|challenge failed\|dns"
```

### 3. Check Let's Encrypt Quota

```bash
# If using Let's Encrypt public CA:
# - Rate limit: 50 certs per domain per week
# - Can only re-issue same cert 5 times per week

# Check how many certs issued this week
dig +short txt _acme-challenge.ide.kushnir.cloud
```

---

## Common Root Causes & Fixes

### Cause 1: Caddy DNS Challenge Failing

**Symptoms**:
- Caddy logs: "DNS challenge failed" or "TXT record not found"
- Certificate is not being renewed
- Date shows ">30 days until expiry"

**Fix (Let's Encrypt)**:
```bash
# Verify DNS is resolving correctly
nslookup ide.kushnir.cloud
nslookup _acme-challenge.ide.kushnir.cloud

# If using Cloudflare:
curl -X GET "https://api.cloudflare.com/client/v4/zones?name=kushnir.cloud" \
  -H "Authorization: Bearer $CF_TOKEN" | jq .

# Verify Caddy has DNS credentials (if DNS provider plugin used)
docker inspect caddy | grep -i "env\|dns"

# Restart Caddy to retry renewal
docker-compose down caddy
docker-compose up -d caddy
docker logs caddy --follow
```

### Cause 2: Insufficient Permissions or Space

**Symptoms**:
- Caddy logs: "Permission denied" or "No space left"
- Certificate store directory `/mnt/caddy-data/` is full or read-only

**Fix**:
```bash
# Check space
df -h /mnt/caddy-data/

# Check permissions
ls -ld /mnt/caddy-data/
sudo chown caddy:caddy /mnt/caddy-data/
sudo chmod 750 /mnt/caddy-data/

# Clean old certificates (if > 90 days old)
find /mnt/caddy-data/certificates/ -mtime +90 -delete

# Restart Caddy
docker-compose restart caddy
docker logs caddy --follow
```

### Cause 3: Rate Limited by ACME Provider

**Symptoms**:
- Caddy logs: "Rate limit exceeded" or "Too many requests"
- Recently renewed certificate multiple times (testing, failed attempts)

**Fix**:
```bash
# Wait for rate limit window to reset (typically 7 days)
# Check provider documentation for specifics

# Use Let's Encrypt staging server for testing (lower rate limits)
# Modify Caddy email/ACME endpoint in docker-compose.yml

# Once staging works, switch back to production
# Then rate limit window will be available

# Manually request certificate if near expiry
# Using staging first, then production
```

### Cause 4: Incorrect Domain Configuration

**Symptoms**:
- Certificate is for different domain (e.g., old.example.com)
- Caddy config has wrong email or domain
- Hostname mismatch between cert and actual domain

**Fix**:
```bash
# Check Caddy configuration
cat /mnt/caddy-data/Caddyfile | grep -A5 "ide.kushnir.cloud"

# Verify domain in certificate
openssl x509 -in /path/to/cert.crt -noout -subject -text | grep "DNS:"

# If domain is wrong, update Caddyfile:
docker-compose down caddy

# Edit docker-compose.yml or Caddyfile.tpl to correct domain
vi Caddyfile

# Restart
docker-compose up -d caddy
docker logs caddy --follow
```

### Cause 5: On-Premises (No Public DNS)

**Symptoms**:
- Environment: on-prem deployment
- Cannot use Let's Encrypt (requires public DNS and validation)
- Using self-signed certificates

**Fix**:
```bash
# Generate new self-signed certificate with longer validity
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 \
  -subj "/CN=ide.kushnir.cloud"

# Copy to Caddy store
sudo cp cert.pem /mnt/caddy-data/certificates/ide.kushnir.cloud.crt
sudo cp key.pem /mnt/caddy-data/certificates/ide.kushnir.cloud.key
sudo chown caddy:caddy /mnt/caddy-data/certificates/ide.kushnir.cloud.*

# Restart Caddy
docker-compose restart caddy

# Verify new certificate
openssl x509 -enddate -noout -in /mnt/caddy-data/certificates/ide.kushnir.cloud.crt
```

---

## Verification

After fixing, verify renewal succeeded:

```bash
# 1. Check certificate not-after date
openssl x509 -enddate -noout -in /path/to/cert.crt
# Should show date > 30 days from now

# 2. Check Caddy logs
docker logs caddy | tail -20
# Should show "Renewed certificate" or "Certificate already exists"

# 3. Test HTTPS connectivity
curl -vI https://ide.kushnir.cloud 2>&1 | head -20
# Should show HTTP/2 200 and certificate details

# 4. Check Prometheus alert
curl -s http://localhost:9093/api/v1/alerts | \
  jq '.data[] | select(.labels.alertname | test("SSLCert"))'
# Alert should clear within 5 minutes
```

---

## Critical Action Timeline

| Days to Expiry | Action | SLA |
|---|---|---|
| **> 30 days** | Monitor (warning alert) | No action required |
| **7-30 days** | Investigate renewal, verify DNS | 1 week |
| **< 7 days** | CRITICAL - immediate manual renewal | 24 hours |
| **< 1 day** | Page oncall - potential outage imminent | NOW |
| **Expired** | EMERGENCY - restore from backup cert or manual renewal | NOW |

---

## Escalation (If Renewal Failing)

If certificate still not renewed after 1 hour of troubleshooting:

1. **Manual cert request** (using Let's Encrypt CLI):
   ```bash
   # Install certbot
   sudo apt-get install certbot certbot-dns-<provider>

   # Request certificate
   certbot certonly --dns-<provider> -d ide.kushnir.cloud

   # Copy to Caddy
   sudo cp /etc/letsencrypt/live/ide.kushnir.cloud/fullchain.pem \
           /mnt/caddy-data/certificates/ide.kushnir.cloud.crt
   sudo cp /etc/letsencrypt/live/ide.kushnir.cloud/privkey.pem \
           /mnt/caddy-data/certificates/ide.kushnir.cloud.key

   # Restart Caddy
   docker-compose restart caddy
   ```

2. **Request manual cert from CA**:
   - Contact Let's Encrypt support (if applicable)
   - Request temporary rate limit exception
   - Or purchase commercial certificate from alternative CA

3. **Escalate to Infrastructure team**:
   - Slack: @infra-oncall
   - Page: pagerduty incident
   - Info: Certificate expiry date, renewal attempts, error messages

---

## Prevention

**Automatic reminders** (built into monitoring):
- 30-day warning alert + email
- 7-day critical alert + page oncall
- 1-day pre-expiry emergency page

**Annual review**:
- Audit all certificates in use
- Check renewal automation is working
- Test renewal process in staging

---

**Document**: docs/runbooks/ssl-cert-expiry.md  
**Last Updated**: 2026-04-15  
**Approved By**: DevOps Lead  
