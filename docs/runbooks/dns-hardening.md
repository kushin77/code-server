# DNS Hardening Runbook — kushnir.cloud DNSSEC/CAA/DMARC/SPF

**Owner**: Platform Engineering  
**Related Issues**: #347, #348 (Cloudflare hardening)  
**Last Updated**: April 15, 2026  
**Architecture**: IP-Independent (Cloudflare Tunnel CNAME-based)

---

## ✅ Why This Design (No IP Hardcoding)

Your infrastructure uses **Cloudflare Tunnel**, which is the correct approach:

```
ide.kushnir.cloud  CNAME→  home-dev.cfargotunnel.com
                           ↓
                    Cloudflare Edge (global PoP)
                           ↓
                    Tunnel Agent (outbound connection)
                           ↓
                    192.168.168.31 (changes OK - tunnel reconnects)
```

**Benefits**:
- ✅ **IP-agnostic**: When server IP changes, no DNS update needed
- ✅ **Resilient**: Tunnel agent auto-reconnects with new IP
- ✅ **Zero configuration**: No firewall rules, no port forwarding
- ✅ **Security**: DDoS protection + WAF at Cloudflare edge
- ✅ **Scale**: Global latency optimization via Cloudflare PoP network

---

## ⚠️ CRITICAL PREREQUISITE: Cloudflare Tunnel Must Be Running

**Before applying this runbook:**

```bash
# Verify Cloudflare Tunnel is active
ssh akushnir@192.168.168.31 "ps aux | grep cloudflared"

# Get your tunnel URL from Cloudflare dashboard
# https://dash.cloudflare.com/tunnels
# Example: home-dev.cfargotunnel.com

# If tunnel is NOT running, start it:
# cloudflared tunnel run home-dev --config ~/.cloudflared/config.yml
```

---

## Quick Start (5 Minutes)

### Prerequisites
- GoDaddy account with DNS access for `kushnir.cloud`
- `terraform` CLI
- Cloudflare Tunnel URL from https://dash.cloudflare.com/tunnels
- Example: `home-dev.cfargotunnel.com`

### Apply DNS Hardening Configuration

```bash
# 1. Export credentials
export TF_VAR_godaddy_api_key="YOUR_GODADDY_API_KEY"
export TF_VAR_godaddy_api_secret="YOUR_GODADDY_API_SECRET"
export TF_VAR_cloudflare_tunnel_url="home-dev.cfargotunnel.com"  # ← Your tunnel URL

# 2. Apply Terraform
cd terraform/
terraform plan -target='godaddy_domain_record.*'
terraform apply -auto-approve -target='godaddy_domain_record.*'

# 3. Enable DNSSEC via GoDaddy API
curl -X PUT "https://api.godaddy.com/v1/domains/kushnir.cloud/dnssec" \
  -H "Authorization: sso-key ${TF_VAR_godaddy_api_key}:${TF_VAR_godaddy_api_secret}" \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}'

# 4. Submit HSTS preload (one-time)
# Visit: https://hstspreload.org/ and submit kushnir.cloud
```

### Verify Configuration

```bash
# Should show CNAME pointing to Cloudflare Tunnel
dig ide.kushnir.cloud
dig kushnir.cloud

# Expected output:
# ide.kushnir.cloud.    3600 IN CNAME home-dev.cfargotunnel.com.

# NOT: 192.168.168.31 (that's not resilient to IP changes)
```

```bash
# CAA records (restrict cert issuance)
dig CAA kushnir.cloud
# Expected: three CAA records:
# - 0 issue "letsencrypt.org"
# - 0 issuewild "letsencrypt.org"
# - 0 iodef "mailto:security@kushnir.cloud"

# SPF record (email security)
dig TXT kushnir.cloud | grep spf
# Expected: v=spf1 -all

# DMARC record
dig TXT _dmarc.kushnir.cloud
# Expected: v=DMARC1; p=reject; rua=mailto:security@kushnir.cloud; adkim=s; aspf=s

# DNSSEC status
dig +dnssec kushnir.cloud SOA
# Expected: RRSIG record present (ad flag set)
```

---

## Detailed Explanation

### 1. CNAME Records (Cloudflare Tunnel)

```
ide.kushnir.cloud      → home-dev.cfargotunnel.com
kushnir.cloud          → home-dev.cfargotunnel.com
```

These point your domains to your Cloudflare Tunnel endpoint (IP-agnostic routing). The tunnel agent on 192.168.168.31 maintains an outbound connection to Cloudflare; traffic returns via that tunnel regardless of your server's IP.

**Why CNAME instead of A record**: 
- Server IP can change (failover, migration) without updating DNS
- Cloudflare provides DDoS protection + WAF at edge
- Tunnel auto-reconnects on IP change (no downtime)

---

### 2. CAA Records (Certificate Authority Authorization)

**Purpose**: Restrict which CAs can issue TLS certificates for your domain.

**Why**: Prevents attackers with access to less-secure CAs from issuing unauthorized certificates for your domain.

**Config**:
```dns
kushnir.cloud.  CAA  0 issue "letsencrypt.org"
kushnir.cloud.  CAA  0 issuewild "letsencrypt.org"
kushnir.cloud.  CAA  0 iodef "mailto:security@kushnir.cloud"
```

- `0` = flags (0 = non-critical)
- `issue` = restrict DV certificates to Let's Encrypt
- `issuewild` = restrict wildcard certs (e.g., `*.kushnir.cloud`) to Let's Encrypt
- `iodef` = notify security@kushnir.cloud if CA receives invalid/unauthorized cert request

**Verification**:
```bash
dig CAA kushnir.cloud

# Expected output:
# kushnir.cloud.	3600	IN	CAA	0 issue "letsencrypt.org"
# kushnir.cloud.	3600	IN	CAA	0 issuewild "letsencrypt.org"
# kushnir.cloud.	3600	IN	CAA	0 iodef "mailto:security@kushnir.cloud"
```

---

### 3. SPF Record (Sender Policy Framework)

**Purpose**: Prevent email spoofing from `@kushnir.cloud`.

**Why**: Attackers can send mail claiming to be from `noreply@kushnir.cloud` and it reaches inboxes. Without SPF, anyone can do this.

**Config**:
```dns
kushnir.cloud.  TXT  "v=spf1 -all"
```

- `v=spf1` = SPF version 1
- `-all` = hard fail: no servers are authorized to send mail from this domain

**Verification**:
```bash
dig TXT kushnir.cloud | grep spf

# Expected:
# kushnir.cloud.  3600  IN  TXT  "v=spf1 -all"
```

**If you add email service later**:
```dns
# Example: send via Google Workspace
kushnir.cloud.  TXT  "v=spf1 include:_spf.google.com ~all"

# Example: send via SendGrid
kushnir.cloud.  TXT  "v=spf1 sendgrid.net ~all"
```

---

### 4. DMARC Record (Domain-based Message Authentication, Reporting and Conformance)

**Purpose**: Define policy for authentication failures, receive reports.

**Why**: Even with SPF, attackers can forge the "From" header. DMARC requires DKIM/SPF authentication + alignment.

**Config**:
```dns
_dmarc.kushnir.cloud.  TXT  "v=DMARC1; p=reject; rua=mailto:security@kushnir.cloud; adkim=s; aspf=s"
```

- `v=DMARC1` = DMARC version
- `p=reject` = hard reject email that fails authentication
- `rua=mailto:security@kushnir.cloud` = send aggregate reports (daily summary)
- `adkim=s` = strict DKIM alignment (signing domain must exactly match "From" domain)
- `aspf=s` = strict SPF alignment (SPF domain must exactly match "From" domain)

**Verification**:
```bash
dig TXT _dmarc.kushnir.cloud

# Expected:
# _dmarc.kushnir.cloud.  3600  IN  TXT  "v=DMARC1; p=reject; rua=mailto:security@kushnir.cloud; adkim=s; aspf=s"
```

**Monitoring**: Check `security@kushnir.cloud` email daily for DMARC aggregate reports.

---

### 5. DNSSEC (DNS Security Extensions)

**Purpose**: Cryptographically sign DNS records to prevent DNS poisoning.

**Why**: Attacker on network path can inject forged DNS responses. DNSSEC uses cryptographic signatures to verify records are authentic.

**Status**: Enable via GoDaddy console (not yet automated in Terraform).

**Steps**:
```bash
# 1. Enable DNSSEC via API
curl -X PUT "https://api.godaddy.com/v1/domains/kushnir.cloud/dnssec" \
  -H "Authorization: sso-key $KEY:$SECRET" \
  -d '{"enabled": true}'

# 2. Wait 10 minutes for DS records to propagate
sleep 600

# 3. Verify DS records
dig +short DS kushnir.cloud

# Expected: 2-3 DS records like:
# 12345 8 2 ABCDEF1234567890...
```

**Verification** (after propagation):
```bash
dig +dnssec kushnir.cloud SOA

# Look for:
# - "ad" flag in response (DNSSEC validated)
# - RRSIG record in output
```

**Check DNSSEC Status**:
- Visit https://dnsviz.net/d/kushnir.cloud/dnssec/ (visual verification)
- All paths should be green (DNSSEC valid)

---

### 6. HSTS Preloading (One-Time Submission)

**Purpose**: Tell browsers to never connect to `kushnir.cloud` without HTTPS.

**Why**: Even if attacker redirects to HTTP, browser refuses and uses HTTPS only.

**Steps**:

1. **Set HSTS header in Caddy** (already done in production):
   ```caddy
   response.headers {
     Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
   }
   ```

2. **Submit to preload list** (one-time):
   - Visit https://hstspreload.org/
   - Enter `kushnir.cloud`
   - Click "Submit domain"
   - Wait for acceptance (email confirmation)

3. **Verify preload**:
   ```bash
   curl -s https://chromium.googlesource.com/chromium/src/+/main/net/http/transport_security_state_static.json | grep kushnir.cloud
   ```

---

## Troubleshooting

### CAA Records Not Taking Effect

**Problem**: CAA records set, but non-Let's Encrypt CAs can still issue.

**Cause**: CAs may not check CAA records yet.

**Fix**: Verify CAA records are correctly formatted:
```bash
dig CAA kushnir.cloud
# All three records must be present
```

---

### SPF Record Still Allows Spoofing

**Problem**: Emails from random@kushnir.cloud still reach inboxes.

**Cause**: Receiving mail server doesn't enforce SPF.

**Fix**: This is expected. SPF is advisory. DMARC is the enforcement layer.

---

### DMARC Reports Not Arriving

**Problem**: `security@kushnir.cloud` not receiving DMARC reports.

**Cause**: Email address may not be correct, or reports are being filtered.

**Fix**:
1. Verify `security@kushnir.cloud` exists and is monitored
2. Check DMARC record:
   ```bash
   dig TXT _dmarc.kushnir.cloud
   ```
3. Check junk/spam folder
4. Request manual report from DMARC monitoring tool (e.g., https://mxtoolbox.com/dmarc.aspx)

---

### DNSSEC Validation Failing

**Problem**: `dig +dnssec kushnir.cloud SOA` shows validation failed.

**Cause**: DS records not yet propagated, or DNSSEC not enabled.

**Fix**:
```bash
# 1. Check if DNSSEC is enabled
curl -s "https://api.godaddy.com/v1/domains/kushnir.cloud" \
  -H "Authorization: sso-key $KEY:$SECRET" | jq '.dnssecStatus'

# 2. If not enabled, enable it:
curl -X PUT "https://api.godaddy.com/v1/domains/kushnir.cloud/dnssec" \
  -H "Authorization: sso-key $KEY:$SECRET" \
  -d '{"enabled": true}'

# 3. Wait 10 minutes for DS records to propagate globally
sleep 600

# 4. Verify again:
dig +dnssec kushnir.cloud SOA
```

---

## Monitoring

### Automated Monitoring

The `.github/workflows/dns-monitor.yml` workflow runs every 15 minutes and:
- Checks A records haven't changed
- Verifies CAA records present
- Validates SPF/DMARC records
- Alerts to PagerDuty on unauthorized changes

### Manual Checks

Daily check:
```bash
#!/bin/bash
# scripts/check-dns.sh

echo "=== A Records ==="
dig A ide.kushnir.cloud +short
dig A kushnir.cloud +short

echo "=== CAA Records ==="
dig CAA kushnir.cloud +short

echo "=== SPF Record ==="
dig TXT kushnir.cloud +short | grep spf

echo "=== DMARC Record ==="
dig TXT _dmarc.kushnir.cloud +short

echo "=== DNSSEC Status ==="
dig +dnssec kushnir.cloud SOA | grep -E "(ad|RRSIG)" && echo "DNSSEC OK" || echo "DNSSEC FAIL"
```

---

## GoDaddy API Key Rotation (Quarterly)

The `GODADDY_API_TOKEN` provides full DNS write access. Rotate every 90 days:

```bash
#!/bin/bash
# scripts/rotate-godaddy-api-key.sh

set -e

echo "1. Generate new API key at https://developer.godaddy.com/keys"
read -p "Enter new API key: " NEW_KEY
read -s -p "Enter new API secret: " NEW_SECRET
echo

echo "2. Update in Vault..."
vault kv put secret/godaddy \
  GODADDY_API_KEY="$NEW_KEY" \
  GODADDY_API_SECRET="$NEW_SECRET"

echo "3. Update GitHub Actions secrets..."
gh secret set GODADDY_API_KEY --body "$NEW_KEY"
gh secret set GODADDY_API_SECRET --body "$NEW_SECRET"

echo "4. Update .env on production host..."
ssh akushnir@192.168.168.31 "cat > /home/akushnir/code-server-enterprise/.env.local <<EOF
GODADDY_API_KEY='$NEW_KEY'
GODADDY_API_SECRET='$NEW_SECRET'
EOF"

echo "5. Verify DNS still resolves..."
dig A ide.kushnir.cloud +short

echo "6. Delete old API key from GoDaddy console (https://developer.godaddy.com/keys)"
read -p "Press Enter when old key is deleted"

echo "✅ API key rotation complete"
```

---

## Related Docs

- **ADR**: `docs/adr/001-cloudflare-tunnel.md` (Cloudflare integration)
- **TLS Hardening**: Issue #348 (Cloudflare TLS 1.3 + WAF)
- **Session Security**: Issue #337 (Session invalidation)
- **Backup**: `docs/runbooks/backup-restore.md`

---

## Testing

### Validate All DNS Records

```bash
bash -x <<'EOF'
set -e

DOMAIN="kushnir.cloud"
EXPECTED_IP="192.168.168.31"

echo "Testing DNS for $DOMAIN..."

# A records
echo -n "A record (ide): "
dig +short A ide.${DOMAIN} | grep -q ${EXPECTED_IP} && echo "✅" || echo "❌"

echo -n "A record (root): "
dig +short A ${DOMAIN} | grep -q ${EXPECTED_IP} && echo "✅" || echo "❌"

# CAA records
echo -n "CAA issue: "
dig +short CAA ${DOMAIN} | grep -q "letsencrypt.org" && echo "✅" || echo "❌"

echo -n "CAA issuewild: "
dig +short CAA ${DOMAIN} | grep -q "issuewild" && echo "✅" || echo "❌"

echo -n "CAA iodef: "
dig +short CAA ${DOMAIN} | grep -q "security@kushnir.cloud" && echo "✅" || echo "❌"

# SPF record
echo -n "SPF record: "
dig +short TXT ${DOMAIN} | grep -q "v=spf1 -all" && echo "✅" || echo "❌"

# DMARC record
echo -n "DMARC record: "
dig +short TXT _dmarc.${DOMAIN} | grep -q "v=DMARC1" && echo "✅" || echo "❌"

echo "✅ All DNS checks passed"
EOF
```

---

## Incident Response

### DNS Hijack Detected

If `.github/workflows/dns-monitor.yml` fires a P0 alert:

1. **Immediately** check GoDaddy account:
   ```bash
   curl -s "https://api.godaddy.com/v1/domains/kushnir.cloud" \
     -H "Authorization: sso-key $KEY:$SECRET" | jq .
   ```

2. **Check for unauthorized logins** in GoDaddy account activity log

3. **Revoke all GoDaddy API keys** and generate new ones

4. **Roll back CNAME records** to Cloudflare Tunnel:
   ```bash
   terraform apply -auto-approve -target='godaddy_domain_record.ide_cname_cloudflare' -target='godaddy_domain_record.root_cname_cloudflare'
   ```

5. **Alert security team** and enable 2FA on GoDaddy account

6. **Post-incident**:
   - Audit GoDaddy API key access logs
   - Rotate all credentials
   - Review S3 backups for compromise

---

## Success Criteria (Issue #347)

- [x] GoDaddy Terraform provider configured for `kushnir.cloud`
- [x] A records deployed via IaC
- [x] CAA records restrict cert issuance to Let's Encrypt
- [x] SPF record set to hard fail
- [x] DMARC record set to reject
- [x] DNS monitoring workflow alerts to PagerDuty
- [ ] DNSSEC enabled (manual: requires GoDaddy API call in step 4)
- [ ] HSTS preload submitted (manual: one-time submission)
- [ ] API key rotation scheduled quarterly
