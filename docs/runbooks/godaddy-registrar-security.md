# GoDaddy Registrar Security Hardening — kushin.cloud

**Owner**: Platform Engineering  
**Related Issues**: #347, #348 (Cloudflare DNS hardening)  
**Last Updated**: April 15, 2026  
**Architecture**: GoDaddy (registrar only) + Cloudflare (authoritative DNS)

---

## Architecture Clarification

Your DNS setup uses two providers:

```
kushin.cloud (domain)
  ├─ GoDaddy (registrar): Domain ownership + nameserver delegation
  └─ Cloudflare (authoritative DNS): Actual DNS records + edge + WAF + tunnel
```

**GoDaddy's role**: Only manages the domain registration and delegates nameservers to Cloudflare  
**Cloudflare's role**: Manages all DNS records (A, CNAME, MX, TXT, CAA, etc.)

This document focuses on securing the **registrar** side (GoDaddy). For DNS records, see issue #348.

---

## 1. Domain Registrar Lock

**Risk**: An attacker who gains access to GoDaddy account can:
- Initiate unauthorized domain transfer to another registrar
- Point domain to attacker-controlled infrastructure within 5 days
- Complete transfer, hijacking all services relying on kushin.cloud

**Current Status**: ❓ UNKNOWN (needs verification)

**Fix**: Enable domain lock in GoDaddy (1-click, no code needed)

### Manual Steps:
1. Log into GoDaddy.com (with MFA — see below)
2. Navigate: **My Products** → **My Domains** → **kushin.cloud** → **Settings**
3. Find **Domain Lock** section → **ENABLE**
4. GoDaddy will send confirmation email
5. Verify in terminal:
   ```bash
   whois kushin.cloud | grep -i "Status"
   # Expected output includes: clientTransferProhibited
   ```

### Automated Verification:
```bash
#!/bin/bash
# Verify domain lock is enabled
STATUS=$(whois kushin.cloud | grep -i "Status" | grep -i "Transfer")
if [[ "$STATUS" == *"Prohibited"* ]]; then
  echo "✓ Domain lock ENABLED"
  exit 0
else
  echo "✗ Domain lock NOT ENABLED (status: $STATUS)"
  exit 1
fi
```

### Rollout:
- **Manual activation**: Now (1 click in GoDaddy UI)
- **Automated verification**: Add to `.github/workflows/dns-monitor.yml` (run quarterly)
- **Alert**: PagerDuty P1 if lock becomes disabled

---

## 2. GoDaddy Account MFA (TOTP)

**Risk**: If GoDaddy account password is compromised, attacker gains full domain control

**Current Status**: ❓ UNKNOWN (needs verification)

**Fix**: Enable TOTP-based 2FA (NOT SMS — SIM-swap vulnerable)

### Manual Steps:
1. Log into GoDaddy.com
2. Navigate: **Account** → **Account Settings** → **Login & PIN**
3. Find **2-Step Verification** → **Enable**
4. Choose method: **Authenticator App** (Google Authenticator, Authy, 1Password, etc.)
5. Scan QR code with authenticator app
6. Save backup codes in secure location (HashiCorp Vault or password manager)
7. Verify: Log out and back in using TOTP code

### Why NOT SMS:
- ❌ SMS is vulnerable to SIM-swap attacks
- ❌ Telecom employees can transfer phone number to attacker
- ❌ No real protection against sophisticated attackers
- ✅ TOTP (time-based one-time password) is cryptographic, not interceptable

### Backup Codes:
- GoDaddy generates 10 one-time backup codes
- Store in: HashiCorp Vault, 1Password, or encrypted file
- **Location**: `/root/.secrets/godaddy-backup-codes.txt` (on 192.168.168.31, encrypted at rest)
- **Access**: Only via sudo, logged to audit trail

### Verification:
```bash
# This is manual - verify user can log into GoDaddy with TOTP
# No automated check available
echo "GoDaddy MFA setup requires manual verification"
echo "Test: Log into GoDaddy.com using TOTP from authenticator app"
```

---

## 3. GoDaddy API Key Scoping + Rotation

**Risk**: The `GODADDY_API_TOKEN` in `.env` currently has broad scope. If leaked:
- Attacker can create/modify DNS records at GoDaddy level (not authorized by Cloudflare)
- Attacker can query registrar API, revealing domain registration details
- No way to revoke leaked key without updating all deployments

**Current Status**: Needs scoping (check `.env` for current key scope)

**Fix**: Create scoped API key and implement quarterly rotation

### Step 1: Create Scoped API Key

1. Log into **developer.godaddy.com** (GoDaddy Developer account)
2. Navigate: **API Keys** → **Create Key**
3. **Name**: `code-server-enterprise-domain-lock` (descriptive)
4. **Scope**: Select only `domains` permission
5. **Specific domain**: `kushin.cloud` (NOT all domains)
6. **Rate limit**: 100 requests/minute (sufficient for registration checks)
7. Copy the new key and secret

### Step 2: Store in Vault

```bash
# Store new key in HashiCorp Vault (or .env file)
vault kv put secret/godaddy \
  api_key="YOUR_SCOPED_KEY" \
  api_secret="YOUR_SCOPED_SECRET" \
  rotation_date="2026-04-15" \
  next_rotation="2026-07-15"
```

### Step 3: Update Deployment

Update `.env` file on 192.168.168.31:
```bash
# Old (broad scope)
GODADDY_API_TOKEN=<old_broad_token>

# New (scoped to kushin.cloud domains only)
GODADDY_API_TOKEN=<new_scoped_token>
GODADDY_API_SECRET=<new_scoped_secret>
GODADDY_API_ROTATION_DATE="2026-04-15"
```

### Step 4: Delete Old Key

1. Log into developer.godaddy.com
2. Navigate: **API Keys**
3. Find the old broad-scope key
4. Click **Delete**
5. Confirm deletion

### Quarterly Rotation Schedule:

Add to runbook: `scripts/rotate-godaddy-api-key.sh`

```bash
#!/bin/bash
# Rotate GoDaddy API key quarterly

set -e

# Configuration
ROTATION_INTERVAL_DAYS=90
VAULT_PATH="secret/godaddy"
BACKUP_FILE="/root/.backup/godaddy-api-key-$(date +%s).txt"

# 1. Check if rotation is needed
LAST_ROTATION=$(vault kv get -field=rotation_date "$VAULT_PATH")
DAYS_SINCE_ROTATION=$(( ($(date +%s) - $(date -d "$LAST_ROTATION" +%s)) / 86400 ))

if [ $DAYS_SINCE_ROTATION -lt $ROTATION_INTERVAL_DAYS ]; then
  echo "API key rotation not yet due ($DAYS_SINCE_ROTATION / $ROTATION_INTERVAL_DAYS days)"
  exit 0
fi

echo "Rotating GoDaddy API key (last rotated: $LAST_ROTATION)..."

# 2. Backup current key
OLD_KEY=$(vault kv get -field=api_key "$VAULT_PATH")
mkdir -p /root/.backup
echo "$OLD_KEY" > "$BACKUP_FILE"
chmod 600 "$BACKUP_FILE"

# 3. Generate new key at GoDaddy (manual or via API if GoDaddy supports it)
echo "⚠️  Manual Step: Generate new API key at developer.godaddy.com"
echo "   Scope: domains:kushin.cloud"
echo "   Name: code-server-enterprise-rotation-$(date +%Y%m%d)"
read -p "Enter new API key: " NEW_API_KEY
read -p "Enter new API secret: " NEW_API_SECRET

# 4. Test new key (make read-only API call)
if ! curl -s -H "Authorization: sso-key $NEW_API_KEY:$NEW_API_SECRET" \
    https://api.godaddy.com/v1/domains/kushin.cloud > /dev/null 2>&1; then
  echo "✗ New API key test failed"
  exit 1
fi

# 5. Update Vault
vault kv put "$VAULT_PATH" \
  api_key="$NEW_API_KEY" \
  api_secret="$NEW_API_SECRET" \
  rotation_date="$(date -u +%Y-%m-%d)" \
  previous_key_backup="$BACKUP_FILE"

# 6. Update .env file on deployments
# (This would typically be done via configuration management or manual update)
echo "✓ API key rotated successfully"
echo "  Next rotation due: $(date -d "+90 days" +%Y-%m-%d)"
echo "  Old key backed up to: $BACKUP_FILE"

# 7. Schedule next rotation
echo "$(date -d '+90 days' '+%Y-%m-%d 09:00') - GoDaddy API Key Rotation" | \
  crontab -e  # Interactive - user confirms
```

### Monitoring / Alerting:

Add to Prometheus rules:

```yaml
# prometheus/rules/godaddy.yml
groups:
  - name: godaddy_compliance
    rules:
      - alert: GoDaddyAPIKeyRotationDue
        expr: |
          (time() - godaddy_api_key_last_rotated_timestamp) / 86400 > 90
        for: 1h
        labels:
          severity: warning
          component: registrar
        annotations:
          summary: "GoDaddy API key rotation due ({{ $value | humanize }}d overdue)"
          runbook: "docs/runbooks/godaddy-registrar-security.md#quarterly-rotation-schedule"
```

---

## 4. Nameserver Pinning Verification

**Risk**: If GoDaddy nameservers are accidentally changed away from Cloudflare:
- DNS stops resolving (all services break)
- Attacker can hijack DNS by changing GoDaddy NS records
- No one notices until customer reports downtime

**Current Status**: Should be correct (delegating to Cloudflare)

**Fix**: Automated verification in GitHub Actions

### Manual Verification:

```bash
# Check current nameservers
dig NS kushin.cloud @8.8.8.8

# Expected output:
# kushin.cloud.  86400  IN  NS  tara.ns.cloudflare.com.
# kushin.cloud.  86400  IN  NS  vince.ns.cloudflare.com.
#
# NOT expected: godaddy.com, route53, etc.
```

### Automated Check (add to `.github/workflows/dns-monitor.yml`):

```yaml
- name: Verify Nameserver Delegation
  id: ns_check
  run: |
    NS_RECORDS=$(dig +short NS kushin.cloud @8.8.8.8)
    
    if echo "$NS_RECORDS" | grep -q "cloudflare.com"; then
      echo "ns_valid=true" >> $GITHUB_OUTPUT
      echo "✓ Nameservers correctly delegated to Cloudflare"
    else
      echo "ns_valid=false" >> $GITHUB_OUTPUT
      echo "✗ Nameservers NOT pointing to Cloudflare!"
      echo "   Current NS: $NS_RECORDS"
      exit 1
    fi

- name: Alert on NS Delegation Change
  if: failure()
  run: |
    # Send P0 alert to PagerDuty
    curl -X POST https://events.pagerduty.com/v2/enqueue \
      -H "Authorization: Token token=${{ secrets.PAGERDUTY_TOKEN }}" \
      -H "Content-Type: application/json" \
      -d '{
        "routing_key": "'${{ secrets.PAGERDUTY_ROUTING_KEY }}'",
        "event_action": "trigger",
        "payload": {
          "summary": "CRITICAL: kushin.cloud nameservers changed (not pointing to Cloudflare)",
          "severity": "critical",
          "source": "GitHub Actions - DNS Monitor"
        }
      }'
```

---

## Implementation Checklist

- [ ] **Registrar Lock**: Enabled in GoDaddy UI, verified with `whois` command
- [ ] **GoDaddy Account MFA**: TOTP enabled (NOT SMS), backup codes stored securely
- [ ] **API Key Scoped**: New key created with `domains:kushin.cloud` scope only
- [ ] **API Key Rotation**: Quarterly rotation script (`scripts/rotate-godaddy-api-key.sh`) committed
- [ ] **Nameserver Verification**: Added to `.github/workflows/dns-monitor.yml`
- [ ] **Monitoring**: Prometheus alert rule for key rotation compliance
- [ ] **Documentation**: This runbook in `/docs/runbooks/`

---

## Security Checklist (Production Readiness)

| Control | Status | Verification |
|---------|--------|--------------|
| Domain lock enabled | ☐ | `whois kushin.cloud \| grep clientTransferProhibited` |
| GoDaddy account MFA (TOTP) | ☐ | Manual: Login with authenticator app |
| API key scoped to domain | ☐ | GoDaddy Developer dashboard |
| API key rotated <90 days ago | ☐ | Vault: `vault kv get secret/godaddy rotation_date` |
| NS delegation verified | ☐ | `dig NS kushin.cloud` returns Cloudflare NS |
| Alerting configured | ☐ | Prometheus + PagerDuty rule exists |

---

## Incident Response

### If Domain Transfer is Initiated:

1. **Immediately**:
   - Log into GoDaddy with MFA
   - Navigate: **My Domains** → **kushin.cloud** → **Lock Domain**
   - Reject any transfer authorization emails from GoDaddy

2. **Within 1 hour**:
   - Change GoDaddy account password (strong random)
   - Review GoDaddy account activity log for suspicious access
   - Rotate GoDaddy API key immediately
   - Alert team on Slack #security

3. **Follow-up**:
   - Investigate how attacker gained GoDaddy access (password reuse? phishing?)
   - Force password reset for all team members with GoDaddy access
   - Enable additional authentication (hardware security key if available)

### If Nameservers Accidentally Changed:

1. **Immediately**:
   - Log into GoDaddy
   - Go to **My Domains** → **kushin.cloud** → **DNS Settings**
   - Change nameservers back to Cloudflare:
     ```
     tara.ns.cloudflare.com
     vince.ns.cloudflare.com
     ```

2. **Wait 15-30 minutes** for DNS propagation

3. **Verify**:
   ```bash
   dig NS kushin.cloud @8.8.8.8
   ```

4. **Alert team**: Post incident to #ops and create GitHub issue

---

## Related Issues

- **#348**: Cloudflare DNS hardening (CAA, SPF, DMARC, DNSSEC)
- **#349**: Cloudflare WAF rules and DDoS mitigation
- **#350**: SSL/TLS certificate management and renewal

---

## References

- [GoDaddy Domain Lock Documentation](https://www.godaddy.com/help/lock-or-unlock-your-domain-1951)
- [GoDaddy 2-Step Verification](https://www.godaddy.com/help/set-up-2-step-verification-5024)
- [GoDaddy API Documentation](https://developer.godaddy.com/docs/endpoint/domains)
- [TOTP Security Best Practices (NIST SP 800-63B)](https://pages.nist.gov/800-63-3/sp800-63b.html)
