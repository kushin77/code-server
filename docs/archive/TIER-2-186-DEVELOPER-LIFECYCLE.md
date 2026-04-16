# Tier 2 #186: Developer Access Lifecycle Implementation

**Status:** In Progress  
**Effort:** 4 hours  
**Dependencies:** #185 (Cloudflare Tunnel) ✅ COMPLETED  
**Owner:** Platform & Security Team  
**Target Completion:** April 15, 2026

## Overview

Implement automated developer onboarding and offboarding with time-bounded access. Provides:

- **Onboarding:** Grant time-limited access to developers (contractors, consultants, interns)
- **Automatic Expiration:** Revoke access at specified date without manual intervention
- **Audit Trail:** Log all access grants/revocations with reason and actor
- **Revocation:** Immediate access removal if needed (e.g., contract termination)
- **Database:** Persistent tracking of all developer access

### Access Lifecycle

```
Developer Lifecycle Flow
═══════════════════════════════════════════════════════════════

1. ONBOARDING (Manual - Admin)
   ┌─ Admin grants access
   │  $ developer-lifecycle.sh grant alice alice@contractor.com "2026-04-30" "Project X"
   │
   └─ System creates:
      ├─ Linux user account (locked, SSH key only)
      ├─ Cloudflare Access policy (time-bounded token)
      ├─ Database entry (tracking expiration)
      ├─ SSH key pair (stored on home server)
      └─ Audit log entry (who, when, why)

2. ACTIVE PERIOD (Automatic - No action needed)
   ┌─ Developer accesses IDE via Cloudflare
   │  URL: https://ide.dev.yourdomain.com
   │  Token verified by tunnel
   │
   ├─ Developer uses git proxy
   │  $ git push origin feature-branch
   │  (Push logged + audited)
   │
   └─ Daily expiration check runs
      * Cron: 00:00 UTC - Check for expired accounts

3. AUTO-EXPIRATION (Automatic - System)
   ┌─ Expiration date reached
   │  (e.g., 2026-04-30 becomes today)
   │
   └─ System automatically:
      ├─ Updates database status to "expired"
      ├─ Revokes Cloudflare Access token
      ├─ Locks OS user account
      ├─ Archives home directory
      └─ Logs business event

4. MANUAL REVOCATION (On-demand - Admin)
   ┌─ Contract terminates early
   │  $ developer-lifecycle.sh revoke alice "Contract ended early"
   │
   └─ System immediately:
      ├─ Revokes all access
      ├─ Locks OS user
      ├─ Archives data
      └─ Logs incident

═══════════════════════════════════════════════════════════════
```

## Implementation

### Tool 1: Developer Lifecycle Script

**File:** `scripts/developer-lifecycle.sh`  
**Status:** ✅ CREATED

Features:
- Grant time-bounded access: `grant <username> <email> <expiration-date> [reason]`
- Revoke access immediately: `revoke <username> [reason]`
- List all developers: `list`
- Auto-expire check: `expire-check` (run from cron)


Database Schema:
```sql
CREATE TABLE developers (
    id INTEGER PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    email TEXT NOT NULL,
    grant_date TEXT NOT NULL,
    expiration_date TEXT NOT NULL,
    status TEXT DEFAULT 'active',  -- active, expired, revoked
    reason TEXT,
    created_by TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE audit_log (
    id INTEGER PRIMARY KEY,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    action TEXT,  -- grant, revoke, expire, verify
    developer_username TEXT,
    actor_email TEXT,
    details TEXT,
    result TEXT  -- success, failure
);
```

### Tool 2: Cron Job for Auto-Expiration

**File:** Create `cron-daily-developer-expiration`

```bash
#!/usr/bin/env bash
# Daily expiration check - run at 00:00 UTC

# Rotate logs
logrotate /etc/logrotate.d/developer-access

# Check for expired developers
/opt/developer-access/developer-lifecycle.sh expire-check >> /var/log/developer-expiration.log 2>&1
```

**Installation:**

```bash
# Add to crontab
sudo crontab -e

# Add line:
0 0 * * * /opt/developer-access/cron-daily-developer-expiration

# Or copy to systemd timer
systemctl enable developer-expiration.timer
```

### Tool 3: Integration Points

**Code-Server Bootstrap:**

When developer starts IDE:

```bash
# Load developer metadata from database
DEVELOPER_USERNAME=$(logname)
DEVELOPER_INFO=$(sqlite3 /etc/developer-access/developers.db \
    "SELECT email, expiration_date FROM developers WHERE username='$DEVELOPER_USERNAME'")

# Set environment
export DEVELOPER_EMAIL=$(echo $DEVELOPER_INFO | cut -d'|' -f1)
export ACCESS_EXPIRATION=$(echo $DEVELOPER_INFO | cut -d'|' -f2)

# Display expiration warning if < 7 days
if [[ "$ACCESS_EXPIRATION" < "$(date -d '+7 days' +'%Y-%m-%d')" ]]; then
    cat << EOF

⚠️  WARNING: Your access will expire on $ACCESS_EXPIRATION
   Please contact admin@yourdomain.com to extend if needed

EOF
fi

# Log IDE session start
echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') | session-start | $DEVELOPER_USERNAME | IDE started" \
    >> /var/log/developer-access-audit.log
```

**Git Proxy Integration:**

When developer pushes code:

```python
# In git-proxy-server.py
@app.post("/git/push")
async def handle_git_push(...):
    # Check if developer's access has expired
    result = subprocess.run([
        "sqlite3", "/etc/developer-access/developers.db",
        f"SELECT status FROM developers WHERE username='{username}' AND expiration_date >= date('now');"
    ], capture_output=True)
    
    if not result.stdout:
        raise HTTPException(status_code=403, detail="Access expired")
    
    # Allow push to proceed
    ...
```

## Management Commands

### Grant Access

```bash
# Simple: Contractor for 15 days
sudo developer-lifecycle.sh grant alice alice@contractor.com "2026-04-30" "Contractor project X"

# Output:
# ✓ Developer Access Granted
# ═══════════════════════════════════════════════════════════════
#   Username:          alice
#   Email:             alice@contractor.com
#   Grant Date:        2026-04-15
#   Expiration Date:   2026-04-30
#   Reason:            Contractor project X
#   
#   Access Methods:
#   ┌─ Cloudflare Access via IDE
#   │  URL: https://ide.dev.yourdomain.com
#   │  Token expires: 2026-04-30
#   │
#   ├─ SSH Access NOT RECOMMENDED
#   │  (SSH keys stored on home server only)
#   │
#   └─ Git Operations via proxy
```

### Revoke Access

```bash
# Immediate revocation (e.g., contract termination)
sudo developer-lifecycle.sh revoke alice "Contract ended"

# Output:
# ! Revoking access for: alice
# ✓ Access revoked for: alice
# ! Offboarding data saved to: /tmp/developer-offboarding-alice-1713177254.tar.gz
```

### List Developers

```bash
sudo developer-lifecycle.sh list

# Output:
# ═══════════════════════════════════════════════════════════════
#   Developer Access List
# ═══════════════════════════════════════════════════════════════
#
# USERNAME    EMAIL                   STATUS   GRANT_DATE   EXPIRATION_DATE   HEALTH
# alice       alice@contractor.com    active   2026-04-15   2026-04-30        ACTIVE
# bob         bob@intern.edu          active   2026-04-10   2026-06-30        ACTIVE
# charlie     charlie@temp.com        expired  2026-04-01   2026-04-05        EXPIRED
```

### Daily Expiration Check

```bash
# Run manually for testing
sudo developer-lifecycle.sh expire-check

# Output:
# Auto-expiring: charlie
# Revoked CF access for charlie
# ✓ Access revoked for: charlie
```

## Deployment

### Step 1: Setup Database

```bash
# Create database directory
sudo mkdir -p /etc/developer-access/certs
sudo chmod 700 /etc/developer-access

# Initialize database (script does this on first run)
sudo developer-lifecycle.sh list
```

### Step 2: Install Script

```bash
# Copy to system
sudo cp scripts/developer-lifecycle.sh /usr/local/bin/developer-lifecycle
sudo chmod 755 /usr/local/bin/developer-lifecycle

# Test
sudo developer-lifecycle.sh list
```

### Step 3: Setup Cron Job

```bash
# Install daily expiration check
sudo cp scripts/cron-daily-developer-expiration /etc/cron.daily/0developer-expiration
sudo chmod 755 /etc/cron.daily/0developer-expiration

# Verify
sudo run-parts --test /etc/cron.daily/0developer-expiration
```

### Step 4: Integrate with Cloudflare Access

```bash
# In Cloudflare dashboard:
1. Create access policy for developer group
2. Set time-based restrictions via KV store
3. Reference developer database for real-time validation

# In Caddyfile:
ide.dev.yourdomain.com {
    forward_auth 127.0.0.1:23500 {
        uri /verify-developer-access
        copy_headers Cf-Access-Jwt-Assertion
    }
    reverse_proxy 127.0.0.1:8080
}

# Verify endpoint checks database:
curl -H "Cf-Access-Jwt-Assertion: $TOKEN" \
    http://localhost:23500/verify-developer-access

# Returns 200 if developer is active and not expired
```

## Testing

### Test 1: Grant Access

```bash
# Grant 30-day access
sudo developer-lifecycle.sh grant test-user test@contractor.com "2026-05-15" "Testing"

# Verify database
sudo sqlite3 /etc/developer-access/developers.db \
    "SELECT username, status, expiration_date FROM developers WHERE username='test-user';"

# Expected: test-user | active | 2026-05-15
```

### Test 2: Auto-Expiration

```bash
# Set expiration to yesterday (to test auto-expire)
sudo sqlite3 /etc/developer-access/developers.db \
    "UPDATE developers SET expiration_date='2026-04-14' WHERE username='test-user';"

# Run expiration check
sudo developer-lifecycle.sh expire-check

# Verify revocation
sudo sqlite3 /etc/developer-access/developers.db \
    "SELECT username, status FROM developers WHERE username='test-user';"

# Expected: test-user | revoked
```

### Test 3: Manual Revocation

```bash
# Grant 30-day access
sudo developer-lifecycle.sh grant test-user2 test2@example.com "2026-05-15" "Testing"

# Revoke immediately
sudo developer-lifecycle.sh revoke test-user2 "Testing complete"

# Verify database
sudo sqlite3 /etc/developer-access/developers.db \
    "SELECT username, status FROM developers WHERE username='test-user2';"

# Expected: test-user2 | revoked
```

### Test 4: Audit Logging

```bash
# Check audit log
tail -20 /var/log/developer-access-audit.log

# Expected entries:
# 2026-04-15T10:30:45Z | grant | test-user | admin@company.com | success | Expiration: 2026-05-15
# 2026-04-15T10:31:12Z | revoke | test-user2 | admin@company.com | success | Testing complete
```

## Monitoring & Alerts

### Alert Rules

```yaml
# PrometheusAlert: Developer access expiring soon (< 7 days)
alert: DeveloperAccessExpiringsoon
  expr: |
    (time_unix(developers.expiration_date) - time_unix(now())) < (7 * 86400)
  annotations:
    summary: "Developer {{ $labels.username }} access expiring in 7 days"

# PrometheusAlert: Expired access still active
alert: ExpiredAccessStillActive
  expr: |
    developers.status = 'active' AND developers.expiration_date < today()
  annotations:
    summary: "Developer {{ $labels.username }} expired but still active"

# PrometheusAlert: Revocation failure
alert: RevocationFailed
  expr: |
    audit_log.action = 'revoke' AND audit_log.result = 'failure'
  annotations:
    summary: "Failed to revoke {{ $labels.developer }}"
```

## Documentation for Admins

**Quick Start:**
```bash
# Add contractor with 30-day access
sudo developer-lifecycle.sh grant alice alice@example.com "2026-05-15" "Project X"

# Revoke if contract ends early
sudo developer-lifecycle.sh revoke alice

# Check who has access
sudo developer-lifecycle.sh list
```

**Troubleshooting:**
- Database locked? → Check `/tmp/developer-lifecycle.lock`
- Access not revoking? → Check Cloudflare dashboard for stale policies
- User still has SSH access? → Verify account locked: `sudo usermod -L username`

## Success Metrics

✅ **Completion Criteria:**
- [x] Developer lifecycle script created and working
- [x] Grant/revoke/list commands tested
- [x] Auto-expiration cron job configured
- [ ] At least 2 developers successfully onboarded with time limits
- [ ] At least 1 expiration automatically processed
- [ ] Zero access granted beyond expiration date
- [ ] Complete audit trail for all lifecycle events

## Related Issues and Docs

- [Tier 2 #184: Git Proxy Implementation](../TIER-2-184-GIT-PROXY-IMPLEMENTATION.md)
- [Tier 2 #187: Read-Only IDE Access](../TIER-2-187-READONLY-IDE-ACCESS.md)
- [DEV_ONBOARDING.md](../DEV_ONBOARDING.md)
