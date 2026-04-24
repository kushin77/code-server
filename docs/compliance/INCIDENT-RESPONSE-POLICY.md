# Incident Response Policy

**Document ID:** IRP-001  
**Version:** 1.0  
**Effective Date:** April 22, 2026  
**Classification:** Internal - Confidential

## 1. Purpose

Define procedures for detecting, responding to, and investigating security incidents.

## 2. Incident Classification

### 2.1 Severity Levels

| Level | Definition | Response Time | Examples |
|-------|-----------|---------------|----------|
| **P0 - Critical** | Service down, active breach | 15 minutes | Ransomware, database corruption, key compromise |
| **P1 - High** | Major degradation, failed access | 1 hour | Brute force attack, unauthorized admin access, data exfiltration attempt |
| **P2 - Medium** | Policy violation, minor issue | 4 hours | Failed login attempts (< 3), weak password, misconfiguration |
| **P3 - Low** | Informational, no impact | 1 business day | Security awareness reminder, patch available |

### 2.2 Incident Examples

**P0 - Immediate Escalation:**
- Service unavailable > 1 hour
- Data loss confirmed or suspected
- Ransomware / malware detected
- Private key / credential exposure
- Unauthorized code deployment to production

**P1 - Urgent Response:**
- Failed login attempts (3+ per user, 5+ per hour)
- Unauthorized access to admin panel attempted
- Policy violation with security impact
- Data integrity issue (e.g., unexpected data modification)
- Third-party reported security concern

**P2 - Standard Response:**
- Single failed login attempt from unusual location
- Misconfigured security group discovered
- Outdated dependency with non-critical CVE
- Backup failure (but previous backup successful)

**P3 - Planning:**
- Patch released for non-critical CVE
- Password expiration approaching
- Certificate expiration approaching (> 30 days out)
- Training module available

## 3. Incident Detection

### 3.1 Automated Detection
- **Security scanning:** Trivy runs on every commit (dependency CVE detection)
- **Log monitoring:** Alerts on:
  - Failed login attempts (3+ per user / hour) → P1 alert
  - Unusual data access patterns → P1 alert
  - Service errors (> 5% error rate) → P1 alert
  - Disk space critical (< 5% remaining) → P1 alert

### 3.2 Manual Detection
- User reports suspicious activity (email/phone/Slack)
- Ops team noticing anomalies during log review
- Security audit findings
- Third party (customer, security researcher) reporting issue

### 3.3 Reporting Channel
- **Slack:** #security-incidents (immediate for P0/P1)
- **Email:** security-team@kushnir.cloud
- **Phone:** Emergency number (in on-call runbook)
- **External:** security@kushnir.cloud (bug bounty, third-party reports)

## 4. Response Procedures

### 4.1 Triage (First 15 minutes)

**Assign Incident Commander:**
- Security owner or backup on-call engineer
- Responsible for coordination + decisions

**Triage Checklist:**
- [ ] Incident confirmed (not false alarm)
- [ ] Severity level assigned (P0/P1/P2/P3)
- [ ] Scope determined (what systems affected?)
- [ ] Initial impact assessment (users affected? data at risk?)

### 4.2 Containment (P0: < 1 hour, P1: < 4 hours)

**For P0 Incidents:**
1. Isolate affected system from network (if safe)
2. Revoke compromised credentials immediately
3. Kill active user sessions
4. Enable verbose logging
5. Preserve evidence (don't delete logs)
6. Notify leadership + stakeholders

**For P1 Incidents:**
1. Increase monitoring intensity
2. Block suspicious user (temporary ban)
3. Review recent activity logs
4. Prepare rollback plan
5. Notify affected users

### 4.3 Investigation (P0: 24 hours, P1: 3 days)

**Root Cause Analysis (RCA) Process:**
1. Timeline reconstruction
   - When did incident occur?
   - How long was it undetected?
   - What systems were accessed?

2. Evidence preservation
   - Backup logs and evidence
   - Secure evidence in isolated storage
   - Prevent log deletion / rotation

3. Threat analysis
   - Was breach actually successful?
   - What was attacker's objective?
   - Were credentials / data compromised?

4. Root cause identification
   - What was the initial vector? (phishing, brute force, CVE?)
   - Why was detection delayed?
   - Were existing controls bypassed?

5. Fix identification
   - What prevents recurrence?
   - Is fix urgent (patch now) or planned (next sprint)?
   - What are deployment risks?

### 4.4 Remediation (P0: < 7 days, P1: < 14 days)

**Fix Implementation:**
- Merge code fix to main branch
- Deploy to production
- Verify fix eliminates vulnerability
- Monitor for 48 hours for recurrence

**Credential Rotation:**
- Generate new OIDC signing key (if compromised)
- Rotate database passwords (if accessed)
- Revoke OAuth tokens (if leaked)
- All changes logged in audit trail

**Communication:**
- Notify affected users + customers
- Public status page update (if incident was public)
- Executive summary for board/stakeholders

## 5. Post-Incident

### 5.1 Incident Report

**Report Contents:**
- Executive summary (1-2 paragraphs)
- Timeline (detect → contain → resolve)
- Root cause
- Impact assessment (# users affected, data exposure)
- Remediation taken
- Prevention measures for future

**Report Approval:**
- Security owner sign-off
- Leadership review
- Public disclosure decision (if applicable)

### 5.2 Lessons Learned

**Within 1 week:**
- Team meeting to discuss incident
- Document what worked well
- Identify what to improve
- Assign action items (GitHub issues)

**Example Action Items:**
- Issue #1075: Improve alert sensitivity for failed logins
- Issue #1076: Add rate limiting to login endpoint
- Issue #1077: Deploy key rotation automation

### 5.3 Testing and Improvement

**Implement fixes:**
- Merge improvements to main
- Add tests to prevent recurrence
- Update runbooks based on lessons learned

**Conduct drill (6 months after incident):**
- Simulate same incident scenario
- Measure response time
- Verify fixes are working

## 6. Communications During Incident

### 6.1 Internal Communication
- **Incident Commander:** Decision maker
- **Tech Lead:** Execution (fixes, deployment)
- **Ops Lead:** Monitoring, status updates
- **Security Lead:** Forensics, investigation

### 6.2 Stakeholder Updates
- **Every 15 minutes (P0 incidents):** Status update
- **Every 30 minutes (P1 incidents):** Status update
- **At resolution:** Full incident notification
- **Within 24 hours:** Initial incident report
- **Within 7 days:** Full post-incident report

### 6.3 Public Communication
- **Status page:** Real-time updates (if customer-facing)
- **Twitter/social media:** For widespread outages only
- **Email:** Notification to affected customers post-incident
- **Tone:** Transparent, professional, accountable

## 7. Incident Tracking

All incidents documented in GitHub:
- **Issue created:** By Incident Commander
- **Title:** `[INCIDENT][P#] Brief description`
- **Labels:** `security-incident`, `P0`/`P1`/`P2`/`P3`
- **Description:**
  - Initial report (what happened)
  - Timeline updates (real-time during incident)
  - RCA findings (post-incident)
  - Linked PRs with fixes

**Example:**
```
Title: [INCIDENT][P0] Unauthorized admin access detected

Description:
## Detection
- Time: 2026-04-22 14:30 UTC
- Alert: Failed login attempts (15 attempts in 5 minutes)
- Source: IP 203.0.113.5

## Scope
- Target: admin account
- Status: Blocked (account locked)
- Data at risk: None (access denied)

## Timeline
- 14:30 - Alert triggered
- 14:35 - IP blocked via firewall
- 14:40 - User notified, password reset
- 15:00 - RCA complete, phishing email identified

## RCA
- Attacker sent phishing email with malicious link
- User clicked link, entered credentials (compromised)
- Attacker attempted login, failed due to MFA

## Fixes
- PR #1078: Add IP reputation scoring to login
- PR #1079: Implement CAPTCHA after 3 failed attempts
- PR #1080: Enhance phishing detection training
```

## 8. Incident Response Drill (Semi-Annual)

**Scenario:** Private key compromise
- **Participants:** Ops, security, developers
- **Duration:** 2 hours
- **Steps:**
  1. Simulate key disclosure (email from security researcher)
  2. Triage and assign severity (should be P0)
  3. Contain (revoke key in GSM)
  4. Remediate (generate new key, redeploy)
  5. Investigate (how did it leak?)
  6. Report findings

**Success Criteria:**
- Response time < 30 minutes
- All steps executed correctly
- All stakeholders notified
- Improvements identified

## 9. Appendix: Incident Checklist

### P0 - Critical Incident Checklist
- [ ] Incident Commander assigned
- [ ] System isolated from network (if safe)
- [ ] Leadership notified (email + phone)
- [ ] Evidence preserved (logs secured)
- [ ] Credentials revoked (if compromised)
- [ ] GitHub issue created
- [ ] Status page updated
- [ ] Users notified
- [ ] RCA completed within 24 hours
- [ ] Fix deployed within 7 days
- [ ] Post-incident report completed

---

**Document Owner:** Security Team  
**Related Issues:** #1070  
**Next Review:** July 22, 2026
