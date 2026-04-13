# Developer Access Lifecycle - Integration Guide
**Issue #186: Developer Access Lifecycle - Provisioning & Revocation**

## Overview

This guide documents the complete developer access provisioning and revocation system, including all available scripts, workflows, and operational procedures.

## Architecture

The developer access lifecycle is built on:
- **CSV-based database** for developer tracking (simple, auditable)
- **Time-bounded access** with automatic expiration
- **Multi-service coordination** (Cloudflare Access, git-proxy, audit logging)
- **Zero-knowledge credential passing** (no SSH keys exposed)

```
┌─────────────────┐
│  Administrator  │
└────────┬────────┘
         │
    ┌────▼──────────────────────────────────┐
    │  Developer Access Scripts               │
    │  ├─ developer-grant   (provision)      │
    │  ├─ developer-revoke  (immediate)      │
    │  ├─ developer-extend  (extend access)  │
    │  ├─ developer-list    (query)          │
    │  └─ developer-auto-revoke-cron (audit) │
    └────┬──────────────────────────────────┘
         │
    ┌────┴──────────────────────────────────────┐
    │  Integration Endpoints                     │
    ├─ CSV Database (~/.code-server-developers) │
    ├─ Cloudflare Access API (policies)         │
    ├─ git-proxy-server (socket notifications) │
    └─ Audit Logging (revocation.log)           │
```

## Database Format

**File**: `~/.code-server-developers/developers.csv`

```csv
email,name,grant_date,expiry_date,duration_days,status,cloudflare_access_id,invite_code,share_link,notes
john@example.com,John Contractor,2026-04-13,2026-04-20,7,active,p-abc123,INV-2026041301,https://share.example.com/...,Initial contractor assignment
jane@example.com,Jane Developer,2026-04-10,2026-05-08,28,active,p-def456,INV-2026041002,https://share.example.com/...,Extended through May
expired@example.com,Old Contractor,2026-03-01,2026-03-15,14,revoked,p-ghi789,INV-2026030101,https://share.example.com/...,Contract ended
```

**Fields**:
- `email`: Developer email address (unique identifier)
- `name`: Developer full name
- `grant_date`: When access was provisioned (YYYY-MM-DD)
- `expiry_date`: When access expires automatically (YYYY-MM-DD)
- `duration_days`: Total duration of access (for reference)
- `status`: active, revoked, or expired
- `cloudflare_access_id`: Cloudflare Access policy ID (for API updates)
- `invite_code`: Unique code for sharing (not sensitive)
- `share_link`: Public sharing link (with invite code embedded)
- `notes`: Admin notes (reason, extension history, etc.)

## Scripts Reference

### 1. developer-grant - Provision Access

**Purpose**: Create time-bounded access for a new developer

**Usage**:
```bash
# Grant access for 7 days
developer-grant john@example.com 7 "John Contractor"

# Grant access for 28 days (4 weeks)
developer-grant contractor@company.com 28 "Q2 Contract"

# Grant access for 365 days (full year, rare)
developer-grant senior@company.com 365 "Full-time employee"
```

**What it does**:
1. Validates email format
2. Calculates expiry date (today + N days)
3. Generates unique invite code
4. Creates Cloudflare Access policy for the developer
5. Updates CSV database with entry
6. Generates shareable invite link
7. Logs grant event to revocation.log
8. Sends invitation email
9. Displays access details and share link

**Output**:
```
═══════════════════════════════════════════════════════════════
✓ ACCESS GRANTED

Developer:      john@example.com (John Contractor)
Grant date:     2026-04-13
Expiry date:    2026-04-20
Duration:       7 days
Status:         active
Invite code:    INV-2026041301
Share link:     https://share.example.com/invite?code=INV-2026041301
═══════════════════════════════════════════════════════════════

Share the link above with the developer. They do not need an invite code
if you share the link - the code is embedded.

Run: developer-list    to view all developers
Run: developer-extend  to extend this access later
```

**Access control**:
- Automatically expire after N days
- No manual revocation needed for routine expirations
- Can be revoked early with developer-revoke
- Can be extended with developer-extend

### 2. developer-revoke - Immediate Revocation

**Purpose**: Immediately revoke developer access and notify all systems

**Usage**:
```bash
# Revoke with reason
developer-revoke john@example.com "Contract ended"

# Revoke for security incident
developer-revoke malicious@example.com "Security incident - unauthorized access"

# Revoke just the email
developer-revoke someone@example.com
```

**What it does**:
1. Validates developer exists in database
2. Verifies developer is active (can't revoke twice)
3. Marks status as "revoked" in CSV
4. Revokes Cloudflare Access policy immediately
5. Notifies git-proxy-server via socket (blocks all git operations)
6. Logs revocation event with timestamp and reason
7. Sends revocation notification email to developer
8. Outputs confirmation

**Revocation effects**:
- **Immediate**: Cloudflare session denied (new SSH connection blocked)
- **Quick**: git-proxy rejects all requests from revoked user
- **Eventual**: Existing SSH sessions expire on timeout (4 hour default)
- **Logged**: Full audit trail of revocation

**Output**:
```
═══════════════════════════════════════════════════════════════
✓ ACCESS REVOKED

Developer:      john@example.com (John Contractor)
Previous status: active
New status:     revoked
Revocation:     2026-04-13 14:30:00 UTC
Reason:         Contract ended
═══════════════════════════════════════════════════════════════

Revocation effects:
- Cloudflare Access policy blocked immediately
- git-proxy-server will reject all requests
- Existing SSH sessions expire on 4-hour timeout
- Full access revoked within 5 minutes

Revocation event logged to: ~/.code-server-developers/revocation.log
```

### 3. developer-extend - Extend Access

**Purpose**: Extend access for an active developer without revocation/recreation

**Usage**:
```bash
# Extend by 14 days
developer-extend john@example.com 14

# Extend by 30 days with reason
developer-extend john@example.com 30 "Extended for project deadline"

# Extend by 7 more days
developer-extend contractor@company.com 7 "Additional testing phase"
```

**What it does**:
1. Validates developer exists and is active
2. Calculates new expiry date (old_expiry + N days)
3. Updates Cloudflare Access policy with new duration
4. Updates CSV database with new expiry and notes
5. Logs extension event to audit trail
6. Sends notification email to developer
7. Displays confirmation

**Key features**:
- Non-disruptive (no need to revoke and re-grant)
- Maintains existing credentials and session
- Updates all service integrations atomically
- Tracks extension history in notes field

**Output**:
```
═══════════════════════════════════════════════════════════════
✓ ACCESS EXTENDED

Developer:       john@example.com (John Contractor)
Previous expiry: 2026-04-20
New expiry:      2026-05-04
Extension:       +14 days
New total:       21 days
Status:          active
═══════════════════════════════════════════════════════════════
```

### 4. developer-list - Query Developers

**Purpose**: View developer access status with flexible filtering

**Usage**:
```bash
# View all developers (default)
developer-list

# View only active developers
developer-list --active

# View only revoked developers
developer-list --revoked

# View developers expiring in next 7 days
developer-list --expiring-soon 7

# View in JSON format (for automation)
developer-list --json

# View in CSV format (for spreadsheets)
developer-list --csv

# View with detailed info
developer-list --verbose

# Combine filters
developer-list --active --verbose
```

**Output formats**:

**Table format** (default):
```
DEVELOPERS (Total: 15, Active: 12, Revoked: 2, Expired: 1)

Email                      Name               Days Left  Expiry      Status
john@example.com           John Contractor    7          2026-04-20  active
jane@example.com           Jane Developer     25         2026-05-08  active
bob@example.com            Bob Contractor     -15        2026-03-29  expired
malicious@example.com      Old Access         N/A        2026-03-15  revoked
```

**JSON format** (API-friendly):
```json
{
  "total": 15,
  "active": 12,
  "revoked": 2,
  "expired": 1,
  "developers": [
    {
      "email": "john@example.com",
      "name": "John Contractor",
      "grant_date": "2026-04-13",
      "expiry_date": "2026-04-20",
      "days_left": 7,
      "status": "active",
      "cloudflare_access_id": "p-abc123"
    },
    ...
  ]
}
```

**CSV format** (for spreadsheets):
```csv
email,name,grant_date,expiry_date,days_left,status,notes
john@example.com,John Contractor,2026-04-13,2026-04-20,7,active,
jane@example.com,Jane Developer,2026-04-10,2026-05-08,25,active,Extended through May
```

### 5. developer-auto-revoke-cron - Automatic Expiration

**Purpose**: Daily cron job to automatically revoke expired developers

**Installation**:
```bash
# Install script to /usr/local/bin
sudo cp scripts/developer-auto-revoke-cron /usr/local/bin/
sudo chmod +x /usr/local/bin/developer-auto-revoke-cron

# Run daily at midnight
echo "0 0 * * * /usr/local/bin/developer-auto-revoke-cron" | crontab -

# Or run every 4 hours for faster expiration
echo "0 */4 * * * /usr/local/bin/developer-auto-revoke-cron" | crontab -
```

**What it does**:
1. Reads developer database
2. Checks each active developer's expiry date
3. Automatically calls developer-revoke for expired developers
4. Logs all auto-revocations
5. Cleans up old audit entries (>90 days)
6. Reports statistics

**Cron output** (logged to file):
```
[2026-04-14 00:05:00] Starting automatic developer access revocation check...
[2026-04-14 00:05:01] EXPIRED: old-contractor@example.com (expiry: 2026-04-14)
[2026-04-14 00:05:02] Revoking access for: old-contractor@example.com
[2026-04-14 00:05:03] ACCESS REVOKED with reason: Automatic expiration (7d limit reached)
[2026-04-14 00:05:04] Auto-revoked 1 developer(s)
[2026-04-14 00:05:05] Auto-revoke cron job complete
```

**Scheduling options**:
- **Daily at midnight**: `0 0 * * *` (one check per day)
- **Every 4 hours**: `0 */4 * * *` (six checks per day)
- **Every hour**: `0 * * * *` (granular, may be overkill)

**Recommendation**: Run every 4 hours for reasonable accuracy. Daily is sufficient for most use cases.

## Workflows

### Workflow 1: Standard Contractor Onboarding (7 days)

```bash
# 1. Grant 7-day access
developer-grant contractor@company.com 7 "Q2 Contractor - Frontend"

# Output includes share link - send to contractor

# 2. Check status anytime
developer-list --active

# 3. After 7 days, developer automatically expires
# (developer-auto-revoke-cron handles it, or manually revoke)

developer-revoke contractor@company.com "Contract ended per agreement"
```

### Workflow 2: Extended Project Assignment (28 days with mid-project extension)

```bash
# 1. Grant initial 28 days
developer-grant dev@contractor.co 28 "Q2 Project Delivery"

# 2. After 14 days, project extends
developer-extend dev@contractor.co 14 "Project extended to May deadline"

# 3. Developer now has 28+14=42 days total (expires on original date + 14 days)

# 4. After 42 days, auto-revoke handles expiration
```

### Workflow 3: Full-Time Employee (360 days with yearly renewal)

```bash
# 1. Grant annual access
developer-grant employee@company.com 365 "Full-time employee - unlimited renewal"

# 2. At 11-month mark, extend for another year
developer-extend employee@company.com 365 "Annual renewal"

# 3. Can repeat endlessly as needed
```

### Workflow 4: Emergency Revocation (security incident)

```bash
# 1. Immediately revoke (blocks in <5 minutes at all layers)
developer-revoke compromised@example.com "Security incident - unauthorized access detected"

# 2. Check status
developer-list --revoked

# 3. Review audit trail
tail -20 ~/.code-server-developers/revocation.log

# 4. If needed, re-grant new access (new invite code, credentials)
developer-grant same-person@company.com 7 "Re-onboarding after incident"
```

## Integration with Other Systems

### Cloudflare Access Integration

**What happens when granting access**:
1. Script creates a Cloudflare Access policy
2. Policy allows only the specified email address
3. Policy enforces Cloudflare MFA if configured
4. Session duration is set per contract duration
5. Policy ID stored in CSV for future updates

**What happens when revoking**:
1. Script deletes/disables the Cloudflare Access policy
2. Developer's email immediately denied at Cloudflare (before SSH)
3. No new SSH connections can be established
4. Existing sessions expire on normal timeout (4 hours)

**Verification**:
```bash
# View Cloudflare Access policies
curl -X GET "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/access/policies" \
  -H "Authorization: Bearer $TOKEN"
```

### git-proxy-server Integration

**Socket communication** (when revoking):
1. developer-revoke sends revocation message to git-proxy socket
2. git-proxy immediately updates in-memory access control list
3. All future `git clone`, `git push`, `git pull` requests denied
4. Error message: "Access revoked for this user"

**Implementation**:
```bash
# Example socket notification in developer-revoke
echo "REVOKE:email@example.com:Reason" | nc -U /tmp/git-proxy.sock
```

### Audit Logging Integration

**Events logged** (in revocation.log):
- GRANT: email, duration, timestamp
- EXTEND: email, extension days, timestamp
- REVOKE: email, reason, timestamp
- CRON: auto-revoked count, timestamp

**Example**:
```
[2026-04-13 10:30:00] GRANT | john@example.com | 7d | Expiry: 2026-04-20
[2026-04-15 14:00:00] EXTEND | john@example.com | +14d | New expiry: 2026-05-04
[2026-04-20 23:59:00] CRON | Auto-revoked 1 developer(s)
[2026-04-20 23:59:01] REVOKE | john@example.com | Automatic expiration (7d limit reached)
```

## Administration

### Configuration Files

**Environment variables** (set in `.bashrc` or systemd service):
```bash
# Cloudflare API credentials
export CF_ACCOUNT_ID="your-account-id"
export CF_AUTH_TOKEN="your-api-token"

# Email notifications (optional)
export DEVELOPER_NOTIFICATION_EMAIL="noreply@company.com"
export DEVELOPER_NOTIFICATION_SMTP="smtp.company.com:587"

# Database location
export DEVELOPERS_DB_DIR="${HOME}/.code-server-developers"
```

### Backup and Recovery

**Daily backup**:
```bash
# Create automated backups
0 1 * * * cp ~/.code-server-developers/developers.csv ~/.code-server-developers/backups/developers.csv.$(date +\%Y\%m\%d)

# Keep 30-day rolling window
find ~/.code-server-developers/backups -type f -mtime +30 -delete
```

**Manual backup**:
```bash
cp ~/.code-server-developers/developers.csv ~/developers.csv.backup.$(date +%s)
```

**Recovery from backup**:
```bash
# Restore previous version
cp ~/developers.csv.backup.1234567890 ~/.code-server-developers/developers.csv

# Re-grant access if needed
developer-grant email@example.com 7 "Recovered from backup"
```

### Audit Trail Queries

**View all grants and extensions**:
```bash
grep "GRANT\|EXTEND" ~/.code-server-developers/revocation.log
```

**View all revocations**:
```bash
grep "REVOKE" ~/.code-server-developers/revocation.log
```

**View revocations in date range**:
```bash
awk '$1 >= "[2026-04-10" && $1 <= "[2026-04-15"' ~/.code-server-developers/revocation.log
```

**Export for compliance report**:
```bash
developer-list --csv > developers-export-$(date +%Y%m%d).csv
grep "REVOKE" ~/.code-server-developers/revocation.log > revocations-$(date +%Y%m%d).log
```

## Troubleshooting

### Developer Can't Access - Check Status

```bash
# 1. Check if developer is still active
developer-list --json | jq '.developers[] | select(.email == "john@example.com")'

# 2. Check Cloudflare policy is still active
cf_policy_id=$(grep "^john@example.com," ~/.code-server-developers/developers.csv | cut -d',' -f7)
curl "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/access/policies/$cf_policy_id"

# 3. Check git-proxy is running
systemctl status git-proxy-server

# 4. Check audit log for revocations
grep "john@example.com" ~/.code-server-developers/revocation.log
```

### Accidentally Revoked - How to Recover

```bash
# If revoked in error, just re-grant immediately
developer-grant john@example.com 7 "Re-granted, revocation was error"

# Access restored within 1 minute
# Developer can use new invite code or share link
```

### Database Corruption - Rebuild

```bash
# Create new clean database from backup
cp ~/.code-server-developers/developers.csv.backup ~/.code-server-developers/developers.csv

# Or rebuild header and restore manually
cat > ~/.code-server-developers/developers.csv << EOF
email,name,grant_date,expiry_date,duration_days,status,cloudflare_access_id,invite_code,share_link,notes
EOF

# Re-grant active developers
developer-grant john@example.com 7 "Rebuilt from audit log"
```

## Security Considerations

### What This System Protects Against

✅ **SSH key exposure**: No SSH keys are ever exposed to developers
✅ **Code theft**: Download tools (wget, curl, scp) blocked in shell
✅ **Unauthorized extension**: Can only extend via developer-extend script
✅ **Unauthorized access**: Time-bounded, auto-revokes after deadline
✅ **Unauthorized revocation**: Logged with timestamp, reason, and admin identity
✅ **Data loss**: Continuous backups of CSV database

### What This System Does NOT Protect Against

⚠️ **Code already downloaded**: Once downloaded, code is in developer's possession
⚠️ **Malicious insider actions**: Logs all activity but doesn't prevent it
⚠️ **Compromised Cloudflare account**: Would need separate incident response
⚠️ **Compromised git-proxy server**: Would need separate incident response

### Best Practices

1. **Always use meaningful reasons**: "Q2 Project" not "test"
2. **Regular audits**: Check revocation.log weekly
3. **Backup CSVcontents daily**: Critical for audit trail
4. **Use minimal duration**: Default to shortest needed (7-14 days)
5. **Review expired developers**: Ensure auto-revoke is working
6. **MFA enforcement**: Always enable Cloudflare MFA
7. **Monitor failed attempts**: Watch git-proxy logs for revoked user attempts

## Summary Table

| Script | Purpose | Risk | Time | Reversible? |
|--------|---------|------|------|-------------|
| developer-grant | Provision access | Low | Immediate | Yes (revoke) |
| developer-revoke | Immediate revocation | High | <1 min | Partial (re-grant) |
| developer-extend | Extend access | Low | Immediate | Yes (revoke) |
| developer-list | Query developers | None | Instant | N/A |
| developer-auto-revoke-cron | Auto-expire | Low | At schedule | N/A |

## Makefile Integration

See [Makefile targets](#makefile-targets) for automation.

## Next Steps

1. **Install scripts** to /usr/local/bin
2. **Set up cron job** for developer-auto-revoke-cron
3. **Configure Cloudflare API** credentials
4. **Create initial developer** database
5. **Begin provisioning** developers per contracts

---

**Last updated**: Issue #186 Implementation
**Status**: COMPLETE - Ready for production use
