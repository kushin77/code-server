# Audit Logging Policy

**Document ID:** ALP-001  
**Version:** 1.0  
**Effective Date:** April 22, 2026  
**Classification:** Internal - Confidential

## 1. Purpose

Document what audit events are logged, how they're stored, and how they're reviewed.

## 2. Audit Event Classification

### 2.1 Events to Log

**Authentication Events (Must Log):**
- [ ] Successful login (user, IP, timestamp)
- [ ] Failed login (user, IP, reason, timestamp)
- [ ] Password reset request (user, timestamp)
- [ ] MFA enabled/disabled (user, timestamp)
- [ ] Session timeout / logout (user, duration)
- [ ] API token created (service account, purpose, expiry)
- [ ] API token revoked (service account, reason)

**Authorization Events (Must Log):**
- [ ] Permission granted (user, role, timestamp)
- [ ] Permission denied (user, action, resource, timestamp)
- [ ] Privilege escalation (user, from role, to role)
- [ ] RBAC role assignment (who assigned, to whom, role)
- [ ] RBAC role revocation (who revoked, from whom, role)

**Data Access Events (Conditional - Sensitive Data Only):**
- [ ] Access to user passwords (read attempt)
- [ ] Access to OAuth tokens (read attempt)
- [ ] Access to OIDC keys (read attempt)
- [ ] Database administrative access (database, operation, timestamp)

**Administrative Events (Must Log):**
- [ ] System configuration change (what changed, who, when)
- [ ] Firewall rule change (rule, action, who)
- [ ] User account creation (user, who created)
- [ ] User account deletion (user, who deleted)
- [ ] Service deployment (version, timestamp, who)
- [ ] Disaster recovery execution (type, timestamp, outcome)

**Security Events (Must Log):**
- [ ] Security alert triggered (alert name, severity, timestamp)
- [ ] Security patch applied (patch, version, timestamp)
- [ ] Security key rotation (key type, timestamp)
- [ ] Access list updated (what list, changes, who)
- [ ] Incident opened (incident #, severity, timestamp)

### 2.2 Audit Event Schema

All audit events recorded in PostgreSQL `audit_logs` table:

```sql
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  user_id TEXT NOT NULL,                    -- User who triggered action
  action TEXT NOT NULL,                     -- LOGIN, LOGOUT, PERMISSION_GRANT, etc.
  resource TEXT NOT NULL,                   -- What was accessed (users.password_hash, etc.)
  status TEXT NOT NULL,                     -- success, failure, denied
  details JSONB,                            -- Additional context (IP, result, etc.)
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Integrity controls
  hash TEXT NOT NULL,                       -- SHA256(prev_hash || this_record)
  signature TEXT,                           -- For digital signature (future)
  
  -- Immutability
  CONSTRAINT audit_logs_readonly AS (status = status)
) WITH (fillfactor=90);

-- Prevent modification of existing records
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_logs_immutable ON audit_logs
  FOR UPDATE USING (false);  -- No updates allowed
CREATE POLICY audit_logs_no_delete ON audit_logs
  FOR DELETE USING (false);  -- No deletes allowed
```

**Example entries:**

```json
{
  "id": 1001,
  "user_id": "akushnir",
  "action": "LOGIN",
  "resource": "oauth2-proxy",
  "status": "success",
  "details": {
    "ip": "203.0.113.45",
    "mfa_used": true,
    "session_id": "sess_xyz789"
  },
  "timestamp": "2026-04-22T14:30:00Z",
  "hash": "5e8f2a3c...(sha256)"
}
```

```json
{
  "id": 1002,
  "user_id": "akushnir",
  "action": "PERMISSION_DENIED",
  "resource": "admin-panel",
  "status": "denied",
  "details": {
    "required_role": "admin",
    "user_role": "editor",
    "ip": "203.0.113.45"
  },
  "timestamp": "2026-04-22T14:35:00Z",
  "hash": "7f3b9e1d...(sha256)"
}
```

## 3. Log Retention and Archival

### 3.1 Retention Schedule

| Log Type | Duration | Storage | Purpose |
|----------|----------|---------|---------|
| Hot logs (PostgreSQL) | 90 days | production DB | Active investigation, compliance audit |
| Archive logs (NAS) | 2 years | NAS cold storage | Long-term compliance, forensics |
| Compliance archive (S3) | 7 years | AWS S3 Glacier | SOC2/ISO27001 evidence |

### 3.2 Archival Process

**Monthly archival (automated):**
1. Export logs older than 90 days from PostgreSQL
2. Compress and encrypt (AES-256)
3. Copy to NAS /nas/cold/audit-logs/
4. Copy to S3 Glacier
5. Delete from production PostgreSQL
6. Log archival action in new audit record

## 4. Log Integrity

### 4.1 Hash Chain

Every audit record includes SHA256 hash of previous record:

```
hash(record_0) = SHA256(header || "")
hash(record_1) = SHA256(header || hash(record_0))
hash(record_2) = SHA256(header || hash(record_1))
...
hash(record_n) = SHA256(header || hash(record_n-1))
```

**Tampering Detection:**
- If any historical record modified, its hash changes
- Next record's hash (which depends on previous) becomes invalid
- Chain breaks, tamper attempt is obvious

**Quarterly verification:**
```sql
-- Verify hash chain is unbroken
WITH RECURSIVE chain AS (
  SELECT id, hash, LAG(hash) OVER (ORDER BY id) as prev_hash
  FROM audit_logs
)
SELECT COUNT(*) as broken_links
FROM chain
WHERE hash != SHA256(...);  -- All hashes should verify

-- Alert if broken_links > 0
```

### 4.2 Log Integrity Monitoring

- Automated check: Every 24 hours
- Manual review: Quarterly
- Alert threshold: Any tampering attempt triggers P0 incident

## 5. Audit Log Review

### 5.1 Daily Review

**Time:** 9:00 AM UTC (after night logging completes)  
**Reviewer:** Ops team (rotating)  
**Duration:** 15-30 minutes  
**Scope:** Last 24 hours of logs

**Checklist:**
- [ ] Count of login successes (expected ~20-50/day?)
- [ ] Count of login failures (expected < 5/day)
- [ ] Any unusual access patterns (same user multiple IPs?)
- [ ] Any failed permission attempts (possible lateral movement?)
- [ ] Any administrative changes (any unauthorized changes?)

**If anomaly detected:**
- Escalate to security owner immediately (P1 incident)
- Preserve evidence (don't delete logs)
- Initiate investigation

### 5.2 Monthly Compliance Audit

**Time:** First Friday of month, 10:00 AM UTC  
**Reviewer:** Security owner + external auditor (if SOC2 audit period)  
**Duration:** 2-4 hours  
**Scope:** All logs from previous month

**Process:**
1. Export logs for month
2. Run compliance checks:
   - [ ] All logins have MFA indicator?
   - [ ] No failed logins from unusual IPs exceeding threshold?
   - [ ] All admin changes approved in change request?
   - [ ] All permission changes match RBAC assignments?
   - [ ] No unauthorized data access?
3. Generate compliance report
4. Sign off: "All reviewed logs compliant with policy"

**Compliance Report Template:**
```
# Monthly Audit Compliance Report - March 2026

**Period:** 2026-03-01 to 2026-03-31
**Reviewer:** Security Team
**Date Reviewed:** 2026-04-05

## Summary
✅ All 2,847 audit logs reviewed
✅ Zero anomalies detected
✅ Zero compliance violations

## Findings
- Login successes: 2,104 (avg 68/day)
- Login failures: 12 (all from known IP ranges)
- Failed permission attempts: 8 (all expected, users testing access)
- Admin changes: 3 (all approved via change requests #1020, #1021, #1022)

## Signature
Security Owner: _________________ Date: _________
```

### 5.3 Quarterly Forensics Review

**Time:** Quarterly (Mar 31, Jun 30, Sep 30, Dec 31)  
**Scope:** All logs from previous quarter (90 days)
**Depth:** Deep forensic analysis

**Questions to answer:**
1. Are there any accounts with unusual activity?
2. Are there any IP ranges we don't recognize?
3. Are there any services accessing data they shouldn't?
4. Are there any failed attempts to escalate privilege?
5. Are there any after-hours access patterns?

**Output:** Forensic report documenting findings

## 6. Audit Log Queries (Examples)

### 6.1 Suspicious Activity Queries

**Find users with excessive failed logins:**
```sql
SELECT user_id, COUNT(*) as failed_count
FROM audit_logs
WHERE action = 'LOGIN' AND status = 'failure'
  AND timestamp > NOW() - INTERVAL '24 hours'
GROUP BY user_id
HAVING COUNT(*) > 3  -- Alert if > 3 failures/day
ORDER BY failed_count DESC;
```

**Find all admin actions in past 24 hours:**
```sql
SELECT user_id, action, resource, timestamp
FROM audit_logs
WHERE action IN ('PERMISSION_GRANT', 'USER_DELETE', 'CONFIG_CHANGE')
  AND timestamp > NOW() - INTERVAL '24 hours'
ORDER BY timestamp DESC;
```

**Find data access from unexpected IPs:**
```sql
SELECT user_id, details->'ip' as ip, COUNT(*) as count
FROM audit_logs
WHERE resource IN ('user_passwords', 'oauth_tokens', 'signing_keys')
  AND timestamp > NOW() - INTERVAL '30 days'
GROUP BY user_id, details->'ip'
HAVING COUNT(*) > 10  -- Alert on unusual patterns
ORDER BY count DESC;
```

## 7. Audit Log Retention and Legal Holds

### 7.1 Legal Hold

If incident or litigation occurs:
- Notify legal team
- Place audit logs on legal hold (don't delete)
- Preserve for court discovery
- Maintain chain of custody

### 7.2 GDPR Right to be Forgotten

If user requests data deletion (GDPR):
- Redact user's personal data (name, email)
- Keep pseudonymized audit records for security
- Document redaction in compliance log

## 8. Audit Report Templates

### 8.1 Daily Standup Report

```
# Audit Log Standup - April 22, 2026

**Period:** 2026-04-21 22:00 UTC to 2026-04-22 22:00 UTC
**Reviewed By:** [Name]
**Status:** ✅ CLEAR

**Metrics:**
- Total events: 1,247
- Logins: 312 success, 2 failure
- Permission changes: 8
- Admin actions: 2
- Anomalies: 0

**Next Action:** Continue monitoring
```

### 8.2 Monthly Compliance Report

(See section 5.2 above)

### 8.3 Quarterly Forensic Report

```
# Quarterly Forensic Audit - Q1 2026

**Period:** 2026-01-01 to 2026-03-31
**Reviewed By:** Security Team
**Date:** 2026-04-05

**Findings:**
- 86,400 events reviewed
- 4 anomalies detected and investigated
- 0 security violations confirmed
- Recommendations for 3 process improvements

**Anomalies:**
1. IP 198.51.100.5 - 20 failed logins (2026-02-15)
   - Investigation: User travel, using VPN, multiple attempts
   - Outcome: Expected, user notified of MFA requirement

2. Service account API_BACKEND exceeded quota (2026-03-10)
   - Investigation: New feature deployment used more API calls
   - Outcome: Quota increased, monitoring added

(... etc ...)
```

## 9. Appendix: Audit Logging Checklist

### Monthly
- [ ] Daily reviews completed (all 30+ days)
- [ ] No audit anomalies missed
- [ ] Compliance report signed off
- [ ] Hash chain verified unbroken

### Quarterly
- [ ] Forensic review completed
- [ ] All anomalies investigated
- [ ] Retention policy enforced (old logs archived)
- [ ] Audit log system health verified

### Annually
- [ ] Full year review
- [ ] Audit policy effectiveness assessed
- [ ] Improvements implemented
- [ ] Compliance certification prep

---

**Document Owner:** Security Team  
**Related Issues:** #1070, #1276 (immutable audit log epic)  
**Next Review:** July 22, 2026
