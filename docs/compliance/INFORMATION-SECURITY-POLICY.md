# Information Security Policy

**Document ID:** ISP-001  
**Version:** 1.0  
**Effective Date:** April 22, 2026  
**Last Reviewed:** April 22, 2026  
**Classification:** Internal - Confidential  
**Approval:** Kushnir Architecture Team

## 1. Purpose and Scope

This Information Security Policy establishes the framework for protecting the confidentiality, integrity, and availability of Kushnir.cloud (KC) information systems and data.

### 1.1 Scope
- All KC infrastructure and services (192.168.168.31, .42 on-premises)
- All employees, contractors, and third parties with system access
- All systems: code-server IDE, session-broker, backend API, databases, cloud integrations

### 1.2 Policy Objectives
- Protect information assets from unauthorized access, modification, or destruction
- Ensure business continuity and disaster recovery
- Comply with SOC2 Type II and ISO 27001 standards
- Maintain security posture against evolving threats
- Support audit and evidence collection for compliance

## 2. Roles and Responsibilities

### 2.1 Security Owner
- **Responsibility:** Overall information security governance
- **Assigned to:** Platform Engineering Lead
- **Duties:**
  - Quarterly security risk assessment
  - Annual policy review and updates
  - Security incident escalation and decision-making
  - Compliance audit coordination

### 2.2 System Administrators
- **Responsibility:** Day-to-day security controls implementation
- **Assigned to:** Ops Team (akushnir@192.168.168.31)
- **Duties:**
  - Patch management (weekly automated + monthly manual review)
  - Access control enforcement (IAM policies)
  - Backup verification (daily automated + weekly manual)
  - Log monitoring and anomaly detection
  - Incident response execution

### 2.3 Application Developers
- **Responsibility:** Secure coding and deployment practices
- **Duties:**
  - Code review for security issues (every PR)
  - Dependency vulnerability scanning (pre-deploy)
  - Secrets management via GSM (no hardcoded credentials)
  - Security testing before production deployment

### 2.4 All Users
- **Responsibility:** Following security policies and procedures
- **Duties:**
  - Maintain strong passwords (≥16 characters, mix case/numbers/symbols)
  - Enable MFA on all accounts
  - Report suspicious activity immediately
  - Participate in security training (annual)

## 3. Security Principles

### 3.1 Defense in Depth
- Multiple security layers: network, application, data, audit
- No single point of failure
- Zero-trust architecture (assume compromise, verify always)

### 3.2 Least Privilege
- Users granted minimum permissions needed for role
- Regular access reviews (quarterly)
- Immediate access revocation upon role change

### 3.3 Immutability
- Audit logs append-only, no deletion or modification
- Version control for all infrastructure code
- Cryptographic hash chain for audit trail integrity

### 3.4 Idempotency
- All operations safe to repeat
- No side effects from multiple executions
- Safe rollback procedures for all changes

## 4. Risk Management Process

### 4.1 Risk Assessment
Conducted quarterly; identifies, evaluates, and prioritizes threats.

**Process:**
1. Identify assets (code, data, infrastructure, credentials)
2. Identify threats (unauthorized access, data loss, service disruption)
3. Evaluate probability (rare, low, medium, high)
4. Evaluate impact (negligible, low, medium, critical)
5. Calculate risk score (probability × impact)
6. Prioritize by risk score (P0 critical, P1 high, P2 medium, P3 low)

**Example:**
- **Asset:** OIDC signing key
- **Threat:** Key compromise
- **Probability:** Low (no incidents to date, key in GSM)
- **Impact:** Critical (all JWT tokens compromised)
- **Risk Score:** High (low prob × critical impact)
- **Controls:** GSM encryption, RBAC, audit logging, key rotation

### 4.2 Control Implementation
Every P1/P2 risk receives mitigating controls:

| Risk | Threat | Mitigation | Evidence |
|------|--------|-----------|----------|
| OIDC key compromise | Private key leak | GSM encryption + audit logging | ADR-002 architecture |
| Database compromise | SQL injection | Parameterized queries + schema validation | Code review + tests |
| Unauthorized access | Brute force | MFA + rate limiting | IAM config |
| Service failure | DDoS | Load balancing + failover | K8s manifests |
| Data loss | Hardware failure | Daily backups + replication | NAS + PostgreSQL HA |

### 4.3 Risk Monitoring
- Continuous: Security scanning (trivy, snyk), error logs
- Daily: Audit log review (first 50 entries)
- Weekly: Alert review (failed logins, unusual access patterns)
- Monthly: Compliance checklist validation
- Quarterly: Full risk assessment refresh

## 5. Security Requirements

### 5.1 Authentication
- **MFA Requirement:** All users must enable MFA (Time-based One-Time Password)
- **Password Policy:** Minimum 16 characters, must include uppercase, lowercase, numbers, symbols
- **Session Timeout:** 30 minutes for web, 24 hours for SSH with MFA
- **Service Accounts:** Use OIDC or key-based auth, no passwords

### 5.2 Authorization
- **RBAC:** Role-based access control via PostgreSQL rbac_roles
- **Roles:** admin (full), editor (read/write), viewer (read-only), system (service-to-service)
- **Principle of Least Privilege:** Default deny, explicitly grant permissions
- **Role Review:** Quarterly access reviews, immediate removal of unused permissions

### 5.3 Encryption
- **In-Transit:** TLS 1.2+ (mandatory)
  - All HTTP → HTTPS via Caddy
  - All internal service communication via mTLS
  - TLS cipher suites: TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384, TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
- **At-Rest:** AES-256
  - PostgreSQL: pgcrypto for sensitive columns
  - Redis: Encryption via GSM-managed keys
  - Backups: S3 server-side encryption (SSE-S3)

### 5.4 Audit and Logging
- **Events Logged:**
  - All authentication attempts (success and failure)
  - All authorization failures (permission denied)
  - All admin actions (role changes, configuration updates)
  - All data access (selective, for sensitive tables)
- **Log Retention:** Minimum 90 days, audit_logs table with ROW LEVEL SECURITY
- **Log Integrity:** Immutable append-only table, hash chain for tampering detection
- **Log Review:** First 100 entries reviewed daily by ops team

### 5.5 Secrets Management
- **Storage:** Google Secret Manager exclusively (no .env in git)
- **Access:** OIDC role-based, logged in audit trail
- **Rotation:** 
  - OIDC signing key: Annually or upon suspected compromise
  - Database passwords: Annually or when employee leaves
  - OAuth credentials: Upon rotation request
- **Disposal:** Revoke immediately in GSM, invalidate any issued tokens

## 6. Compliance Standards

### 6.1 SOC2 Type II
- **Scope:** Code-server IDE, session-broker, backend API, databases
- **Audit Period:** 6 months continuous testing
- **Controls Tested:** CC6.1 (auth), CC7.1 (logging), A1.1 (access), A1.2 (monitoring)
- **Target Completion:** Q3 2026

### 6.2 ISO 27001
- **Scope:** All information systems
- **14 Control Areas:**
  1. Information Security Policies (Section 5 of this document)
  2. Organization of Information Security (Section 2)
  3. Human Resource Security (Roles section)
  4. Asset Management (Inventory maintained in #1070)
  5. Access Control (Section 5.2, RBAC)
  6. Cryptography (Section 5.3)
  7. Physical and Environmental Security (Data center on-premises, locked)
  8. Operations Security (Incident response, Section 7)
  9. Communications Security (TLS, mTLS, Section 5.3)
  10. System Acquisition, Development, and Maintenance (Code review, testing)
  11. Supplier Relationships (Third parties: Google, LiveKit)
  12. Information Security Incident Management (Section 7)
  13. Business Continuity (Backups, failover, Section 8)
  14. Compliance (This policy, audits, evidence)
- **Target Certification:** Q4 2026

## 7. Incident Response

### 7.1 Incident Classification
- **P0/Critical:** Active compromise, data loss, service down > 1 hour
- **P1/High:** Failed login attempts (3+ per user), unauthorized access attempt
- **P2/Medium:** Policy violation, weak password detected, minor misconfiguration
- **P3/Low:** Security awareness reminder, non-urgent patch available

### 7.2 Response Escalation
1. **Detection:** Alert triggered (automated or manual report)
2. **Acknowledgment:** Ops lead confirms receipt within 15 minutes
3. **Triage:** Classify severity (P0/P1/P2/P3)
4. **Containment:** 
   - P0: Isolate system, revoke credentials, notify stakeholders (< 1 hour)
   - P1: Increase monitoring, block suspicious user (< 4 hours)
   - P2/P3: Log and monitor (< 1 business day)
5. **Root Cause Analysis:** Within 3 days of detection
6. **Remediation:** Fix identified vulnerability (target: < 7 days)
7. **Notification:** Affected users and stakeholders (within timeline per regulation)

### 7.3 Investigation and RCA
All incidents documented in GitHub issues with tags:
- `security-incident`: For tracking
- `P0`/`P1`/`P2`/`P3`: Priority level
- Root cause documented in issue body
- Corrective action tracked in related PR

## 8. Training and Awareness

### 8.1 Security Training (Annual)
- **Target Audience:** All employees and contractors
- **Topics:**
  - Password security and MFA setup
  - Phishing and social engineering recognition
  - Data classification and handling
  - Incident reporting procedures
  - Compliance requirements (SOC2, ISO 27001)
- **Completion:** 100% attestation required

### 8.2 Incident Response Drill (Semi-Annual)
- **Scenario:** Simulated security incident (e.g., key compromise)
- **Participants:** Ops team, developers, security lead
- **Evaluation:** Response time, procedures followed, gaps identified
- **Documentation:** Drill report and corrective actions

## 9. Policy Review and Updates

### 9.1 Review Schedule
- **Quarterly:** Risk assessment update (Section 4.1)
- **Semi-Annual:** Policy effectiveness review (this document)
- **Annual:** Full policy revision and board approval
- **Ad-hoc:** Upon security incident or regulatory change

### 9.2 Version Control
- **Document History:** Maintained in git (docs/compliance/INFORMATION-SECURITY-POLICY.md)
- **Change Tracking:** All updates include version bump and effective date
- **Approval:** Security owner sign-off before publishing

## 10. Appendix: Security Control Checklist

### Daily (automated + manual verification)
- [ ] Backup completed successfully
- [ ] Audit logs flowing (> 0 entries in last 24 hours)
- [ ] No failed logins exceeding threshold (3+ per user triggers alert)
- [ ] Database replication lag < 1 second
- [ ] Disk usage < 80%

### Weekly
- [ ] Patch availability check (OS, dependencies, Docker images)
- [ ] Anomaly review (unusual access patterns, error spikes)
- [ ] Secrets rotation check (GSM version dates)
- [ ] Firewall/security group configuration unchanged

### Monthly
- [ ] Access control audit (role assignments match org chart)
- [ ] Disaster recovery test (restore from backup)
- [ ] Certificate expiry check (all certs expire > 30 days out)
- [ ] Compliance checklist update

### Quarterly
- [ ] Full risk assessment
- [ ] Penetration testing (if budget allows)
- [ ] Policy review
- [ ] Security training effectiveness survey

### Annually
- [ ] Policy revision and board approval
- [ ] Compliance audit (SOC2/ISO27001 prep)
- [ ] Security tool updates (trivy, snyk, etc.)
- [ ] Disaster recovery drill (full restore and validation)

---

**Document Owner:** Security Team  
**Last Updated:** April 22, 2026  
**Next Review:** July 22, 2026 (Quarterly)  
**Related Issues:** #1070 (Compliance), #793 (Security Hardening), #412 (P0 Security)
