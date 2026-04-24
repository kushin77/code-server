# Data Protection Policy

**Document ID:** DPP-001  
**Version:** 1.0  
**Effective Date:** April 22, 2026  
**Classification:** Internal - Confidential

## 1. Purpose

Protect sensitive data through classification, encryption, and retention controls.

## 2. Data Classification Scheme

### 2.1 Classification Levels

| Level | Examples | Handling | Retention |
|-------|----------|----------|-----------|
| **Public** | Documentation, roadmap | No restrictions | Permanent |
| **Internal** | Configuration, design docs | KC employees only | 7 years (org records) |
| **Confidential** | Customer data, API keys | Admin + ops team | 90 days (audit) |
| **Restricted** | OIDC signing keys, DB passwords | GSM + encryption | 1 year (compliance) |

### 2.2 Data Inventory

| Data Type | Classification | Storage | Encryption |
|-----------|----------------|---------|-----------|
| User credentials | Restricted | IdP database | Bcrypt hashed |
| OAuth tokens | Confidential | Redis | At-rest + in-transit |
| OIDC signing key | Restricted | GSM | AES-256 |
| Database passwords | Restricted | GSM | AES-256 |
| Session data | Internal | PostgreSQL | Optional (customer choice) |
| Audit logs | Confidential | PostgreSQL | Signed (tamper detection) |
| Backups | Confidential | NAS + S3 | AES-256 |

## 3. Encryption Requirements

### 3.1 Encryption In-Transit

**Mandatory:**
- HTTP → HTTPS (Caddy enforces redirect)
- All backend services: mTLS
- Database connections: Encrypted
- SSH: MFA + key-based auth

**Cipher Suites (TLS 1.2+):**
```
TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
```

### 3.2 Encryption At-Rest

**Implementation:**
- PostgreSQL: pgcrypto for sensitive columns (passwords, tokens)
- Redis: Encryption via GSM-managed keys
- Backups: S3 server-side encryption (SSE-S3)
- NAS: CIFS/SMB encryption (if supported by storage)

**Example (PostgreSQL):**
```sql
-- Sensitive columns encrypted via pgcrypto
ALTER TABLE users ADD COLUMN password_hash TEXT;
CREATE TRIGGER password_encrypt BEFORE INSERT ON users
  FOR EACH ROW EXECUTE FUNCTION pgcrypto.crypt_password();
```

## 4. Data Retention and Disposal

### 4.1 Retention Periods

| Data Type | Retention | Reason | Reference |
|-----------|-----------|--------|-----------|
| Audit logs | 90 days minimum, 2 years archive | Compliance, investigation | SOC2 CC7.2 |
| Database backups | 30 days daily, 1 year weekly | Disaster recovery | ISO27001 A.12.3.1 |
| Session logs | 14 days | Session forensics | Policy |
| Error logs | 7 days | Incident investigation | Policy |
| Access logs | 90 days | Compliance audit | Policy |

### 4.2 Data Disposal

**When data reaches end of retention:**
1. Export final snapshot (if legally required)
2. Permanently delete from primary storage
3. Overwrite with random data (3 passes)
4. Verify deletion in audit log
5. Document destruction date

**For Restricted data (keys, passwords):**
- Immediate destruction upon revocation
- Invalidate any tokens issued with old keys
- Log destruction action in audit_compliance_log

**Equipment end-of-life:**
- Sanitize all storage devices (DBAN or cryptographic erase)
- Verify saturation with forensic tools
- Certificate of destruction maintained

## 5. Backup and Recovery Procedures

### 5.1 Backup Strategy

**Daily Automated Backups:**
- PostgreSQL: WAL archiving + daily snapshots
- Redis: Append-only file (AOF)
- NAS: Incremental snapshots
- Schedule: 2:00 AM UTC (off-peak)
- Retention: 30 days rolling

**Weekly Backups:**
- Full database export
- Code repository snapshot
- Configuration export
- Retention: 1 year

**Monthly Backups:**
- Off-site archive (S3)
- Long-term retention for compliance
- Retention: 7 years

### 5.2 Recovery Procedures

**Recovery Objectives:**
- **RTO** (Recovery Time Objective): 2 hours
- **RPO** (Recovery Point Objective): 1 hour
- Test quarterly

**Recovery Steps:**
1. Validate backup integrity (checksum verification)
2. Restore to staging environment first
3. Verify data consistency
4. Promote to production (if validation passes)
5. Notify stakeholders
6. Document recovery in incident log

**For Production Data Loss:**
- If < 1 GB: Restore from daily backup (< 30 minutes)
- If >= 1 GB: Restore from weekly backup (1-2 hours)
- If > 30 days ago: Restore from archival S3 (2-4 hours)

## 6. Access to Sensitive Data

### 6.1 Principle of Least Privilege
- Database: Connect as limited service account (not admin)
- By role: Developers connect with read-only, admins with read-write
- By time: Access temporary (auto-revoke after 1 hour)
- By approval: Each access logged with approval ticket

### 6.2 Sensitive Data Access Audit

All access to restricted data logged:
```sql
-- Example audit entry for accessing password_hash
INSERT INTO audit_logs (
  user_id, action, resource, timestamp
) VALUES (
  'akushnir', 'SELECT', 'users.password_hash', NOW()
);
```

## 7. Data Breach Response

### 7.1 Detection
- Automated alerts for unusual data access patterns
- Weekly manual audit log review
- Quarterly data integrity validation

### 7.2 Incident Response
1. **Containment** (< 15 minutes):
   - Revoke affected user access
   - Review access logs for extent of breach
   - Preserve evidence (don't delete logs)

2. **Assessment** (< 1 hour):
   - What data was exposed?
   - How long was access unauthorized?
   - Were credentials compromised?

3. **Notification** (per regulatory timeline):
   - Affected users (email + phone)
   - Management + board
   - Regulatory authorities (if required)
   - Credit bureaus (if PII exposed)

4. **Remediation** (< 7 days):
   - Reset all affected credentials
   - Rotate encryption keys
   - Patch underlying vulnerability
   - File incident report

## 8. Third-Party Data

### 8.1 Third-Party Integrations
- Google OAuth2: Customer identity
  - Data Handling: SSO login only, no data storage
  - DPA: Google Standard Processor Agreement
- LiveKit: Video sessions
  - Data Handling: Encrypted end-to-end
  - DPA: Signed contract with LiveKit
- AWS S3: Backup storage
  - Data Handling: Encrypted at rest
  - DPA: AWS Data Processing Agreement

### 8.2 Contractor / Vendor Access
- Must sign DPA (Data Processing Agreement)
- Audit access to sensitive data
- Remove access immediately upon contract end

## 9. Data Minimization

**Only collect and store:**
- Minimum necessary for service operation
- No marketing data, no profiling
- No personal data beyond what's necessary

**Example:**
- ✅ Store: User session activity (for availability features)
- ❌ Store: User geographic location (not needed)

## 10. Privacy and GDPR Compliance

**If handling EU personal data:**
- Implement privacy by design
- Data subject rights: Access, rectification, deletion ("right to be forgotten")
- Data retention: Minimum necessary only
- Consent management: Opt-in for marketing communications

---

**Document Owner:** Security Team  
**Related Issues:** #1070, #793  
**Next Review:** July 22, 2026
