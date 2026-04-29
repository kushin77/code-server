# Governance & Compliance Remediation Tracking
**Created:** April 29, 2026  
**Last Updated:** April 29, 2026  
**Status:** IN PROGRESS

---

## P0 - Critical (Do This Week)

### P0-1: Rotate Expired Secrets
- **Status:** ⏳ PENDING
- **Severity:** CRITICAL (104-149 days overdue)
- **Affected Secrets:** DB_PASSWORD_PROD, REDIS_AUTH_TOKEN
- **Action:**
  ```bash
  bash scripts/security/secret-rotation-manager.sh --rotate --vault-path secrets/production
  ```
- **Verification:**
  ```bash
  psql -h postgres -U postgres -d app_db -c "SELECT 1;"
  redis-cli -h redis -a $(vault kv get -field=password secret/prod/redis) ping
  ```
- **Target Completion:** TODAY
- **Owner:** Platform Engineer
- **Evidence:** Rotation log in `/var/log/compliance-audit.log`

### P0-2: Vault Dev Mode → HA+Raft
- **Status:** ⏳ PLANNED
- **Severity:** CRITICAL (production blocker)
- **Current:** DEV mode with hardcoded token (devtoken)
- **Target:** HA deployment with Raft backend
- **Actions:**
  1. Plan Vault HA infrastructure (Week 1)
  2. Deploy Vault primary + replica (Week 1-2)
  3. Migrate secrets (Week 2)
  4. Seal Vault and initialize (Week 2)
  5. Rotate root token (Week 2)
- **Target Completion:** 2 weeks (by May 13)
- **Owner:** DevOps
- **Evidence:** Terraform state shows Vault HA deployed + sealed

---

## P1 - High Priority (Within 30 Days)

### P1-1: Implement Log Retention Tiers
- **Status:** ⏳ PLANNED
- **Severity:** HIGH (HIPAA/PCI-DSS/SOC2 compliance)
- **Current:** 31 days (Loki) + 30 days (Prometheus)
- **Target:** Hot (31d) → Warm (90d) → Cold (2160d/7yr)
- **Actions:**
  1. Plan retention strategy (Week 1)
  2. Set up S3/Glacier (Week 2)
  3. Configure Loki tiering (Week 2-3)
  4. Configure Prometheus tiering (Week 3)
  5. Verify archive → restore (Week 3)
- **Target Completion:** 3 weeks (by May 20)
- **Owner:** Platform Engineer
- **Evidence:** S3 buckets with tiering policies, Loki config updated

### P1-2: Add Device Trust Policy (OPA)
- **Status:** ⏳ PLANNED
- **Severity:** HIGH (zero-trust enforcement)
- **Current:** Missing `identity/device_trust.rego`
- **Actions:**
  1. Define device compliance attributes (Week 1)
  2. Implement Rego policy (Week 1-2)
  3. Test policy decisions (Week 2)
  4. Deploy to production (Week 2)
- **Target Completion:** 2 weeks (by May 13)
- **Owner:** Security
- **Evidence:** Rego policy deployed, test results pass

### P1-3: Centralize OPA Decision Logs
- **Status:** ⏳ PLANNED
- **Severity:** HIGH (audit trail gaps)
- **Current:** Decision logs console-only
- **Target:** Stream to Loki for audit trail
- **Actions:**
  1. Configure OPA decision log streaming (Week 1)
  2. Set up Loki consumer (Week 1)
  3. Add alerting on policy denials (Week 1-2)
  4. Verify logs flowing (Week 2)
- **Target Completion:** 1 week (by May 6)
- **Owner:** Platform Engineer
- **Evidence:** Loki query returns OPA decisions, alerts firing

### P1-4: Verify Backup Retention
- **Status:** ⏳ REVIEW NEEDED
- **Severity:** HIGH (compliance requirement)
- **Current:** 30 days default
- **Target:** Document retention by compliance standard
- **Actions:**
  1. Audit current backup configurations (Week 1)
  2. Update Terraform retention variables (Week 1-2)
  3. Set retention per database (Week 2)
  4. Test restore from old backups (Week 2-3)
- **Target Completion:** 2-3 weeks (by May 13-20)
- **Owner:** Platform Engineer
- **Evidence:** Terraform shows compliance-aligned retention, DR test passes

---

## P2 - Medium Priority (30-60 Days)

### P2-1: Consolidate Secrets to Vault
- **Status:** ⏳ PLANNED
- **Severity:** MEDIUM (GSM/AWS/Vault fragmentation)
- **Current:** DB creds in Vault, API keys in AWS SM, GitHub PAT in GSM
- **Actions:**
  1. Plan secret consolidation (Week 1)
  2. Migrate AWS Secrets Manager → Vault (Week 2-3)
  3. Migrate GSM → Vault (Week 3)
  4. Verify all apps use Vault (Week 4)
- **Target Completion:** 4 weeks (by May 27)
- **Owner:** DevOps
- **Evidence:** All active secrets in Vault, AWS/GSM empty or archived

### P2-2: Enable Certificate Pinning
- **Status:** ⏳ PLANNED
- **Severity:** MEDIUM (MITM risk mitigation)
- **Current:** HPKP mentioned but not deployed
- **Actions:**
  1. Extract public key hash from certificate (Week 1)
  2. Add HPKP header to Caddy (Week 1)
  3. Test pinning with curl (Week 1)
  4. Deploy and monitor (Week 1-2)
- **Target Completion:** 1 week (by May 6)
- **Owner:** Platform Engineer
- **Evidence:** curl -i shows HPKP header, cert hash matches

### P2-3: Implement Secrets Masking Validator
- **Status:** ⏳ PLANNED
- **Severity:** MEDIUM (secrets leak prevention)
- **Current:** Masking done in Promtail, not verified end-to-end
- **Actions:**
  1. Create secrets pattern detection script (Week 1-2)
  2. Add to CI/CD pipeline (Week 2)
  3. Add to log aggregation checks (Week 2)
  4. Generate weekly reports (Week 2-3)
- **Target Completion:** 2-3 weeks (by May 13-20)
- **Owner:** Platform Engineer
- **Evidence:** CI/CD checks logs for secrets, weekly report shows 0 leaks

---

## P3 - Low Priority (60+ Days)

### P3-1: Document Incident Response Procedures
- **Status:** ⏳ PLANNED
- **Severity:** LOW-MEDIUM (operational readiness)
- **Actions:**
  1. Create IR runbook template (Week 1)
  2. Document discovery/containment/recovery phases (Week 1-2)
  3. Create IR playbooks per scenario (Week 2-3)
  4. Schedule quarterly IR drills (Week 3)
- **Target Completion:** 3-4 weeks (by May 20-27)
- **Owner:** Security + Platform Engineer
- **Evidence:** Runbooks in docs/, quarterly drill scheduled

### P3-2: Implement GDPR Consent Management
- **Status:** ⏳ FUTURE
- **Severity:** LOW (only if processing EU personal data)
- **Actions:** (Deferred until compliance requirements clarified)

### P3-3: Network Policy for Kubernetes (if applicable)
- **Status:** ⏳ FUTURE
- **Severity:** LOW (not applicable for Docker Compose)
- **Note:** Create K8s NetworkPolicy resources if migrating to Kubernetes

---

## Compliance Verification Checklist

### Monthly (1st of month, 09:00 UTC)
- [ ] Run compliance validator: `bash scripts/security/compliance-as-code-validator.sh`
- [ ] Check secret rotation: `bash scripts/security/secret-rotation-manager.sh --status`
- [ ] Audit RBAC: `bash scripts/security/identity-governance-verifier.sh --audit`
- [ ] Verify certificates: `docker exec code-server-caddy caddy list-certificates`
- [ ] Count audit events: `curl 'http://localhost:3100/loki/api/v1/query?query={job="audit"}'`

### Quarterly (1st week of quarter)
- [ ] Run compliance audit for HIPAA/PCI-DSS/SOC2
- [ ] Execute incident response drill (IR playbook simulation)
- [ ] Review and update security policies
- [ ] Backup integrity test (restore from backup)

### Ad-Hoc
- [ ] After secret rotation: Verify apps restarted without errors
- [ ] After policy change: Verify OPA decisions reflected
- [ ] After deployment: Run compliance validator to detect drift

---

## Success Criteria

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| Expired Secrets | 2 | 0 | ⏳ THIS WEEK |
| Vault HA Deployed | No | Yes | ⏳ 2 WEEKS |
| Log Retention | 31d | 2160d (HIPAA) | ⏳ 3 WEEKS |
| OPA Decision Logs | Console | Loki | ⏳ 1 WEEK |
| Device Trust Policy | No | Yes | ⏳ 2 WEEKS |
| Certificate Pinning | No | Yes | ⏳ 1 WEEK |
| Governance Score | 82/100 | 92/100 | ⏳ 30 DAYS |
| HIPAA Readiness | 65% | 90% | ⏳ 30 DAYS |
| PCI-DSS Readiness | 70% | 90% | ⏳ 30 DAYS |
| SOC2 Readiness | 75% | 90% | ⏳ 30 DAYS |

---

## Links & References

- **Full Report:** [GOVERNANCE_COMPLIANCE_POSTURE_REVIEW.md](GOVERNANCE_COMPLIANCE_POSTURE_REVIEW.md)
- **OPA Policies:** [policies/](policies/)
- **Security Docs:** [docs/security/](docs/security/)
- **Security Scripts:** [scripts/security/](scripts/security/)
- **Terraform Modules:** [terraform/modules/](terraform/modules/)

---

**Last Updated:** 2026-04-29T00:00:00Z  
**Next Review:** 2026-05-29T09:00:00Z (Monthly)  
**Status:** TRACKING ACTIVE REMEDIATION
