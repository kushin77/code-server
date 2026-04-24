# Pre-Deployment Readiness Checklist

**Objective**: Ensure all prerequisites are met before production deployment  
**Owner**: DevOps/Infrastructure Team  
**Timing**: Execute before E2E testing (Issues #983-#984)  
**Time Estimate**: 30-45 minutes total  
**Status**: Ready for use immediately

---

## Infrastructure Prerequisites (Verify with your team)

### Cloud Infrastructure
- [ ] GCP Project configured and accessible
- [ ] Service account created with appropriate permissions
- [ ] Google Secret Manager (GSM) accessible from deployment host
- [ ] Firewall rules configured (allow inbound 80/443, restrict others)
- [ ] VPN/bastion host configured (if on-prem behind firewall)

### On-Premises Hardware
- [ ] Primary host (192.168.168.31) online and accessible
- [ ] Replica host (192.168.168.42) configured for failover
- [ ] Network connectivity between hosts (10 Gbps minimum for prod)
- [ ] Storage capacity > 500GB available (database + media)
- [ ] CPU: 4+ cores (8+ recommended for full stack)
- [ ] Memory: 16GB+ available (24GB+ recommended)
- [ ] Network: Latency between hosts < 5ms

### Docker Environment
- [ ] Docker daemon running on primary host
- [ ] Docker Compose v2.0+ installed
- [ ] Docker volumes pre-created (or auto-created by compose)
- [ ] Container image registry accessible (Docker Hub or internal)
- [ ] Sufficient disk space for images (~50GB)

### DNS & Network
- [ ] DNS configured for your domain
- [ ] Internal DNS (if air-gapped): /etc/hosts configured
- [ ] TLS certificates valid and non-expired
- [ ] Reverse proxy (Caddy/Nginx) configured
- [ ] Firewall rules configured (allow 80/443, block unnecessary ports)

---

## Application Prerequisites

### Code & Dependencies
- [ ] Repository cloned to deployment host
- [ ] Git on latest stable branch (main)
- [ ] No uncommitted changes: `git status` shows clean
- [ ] Dependencies installed: `npm ci` or `pnpm install`
- [ ] Build successful: `npm run build` completes without errors

### Database
- [ ] PostgreSQL 15+ installed
- [ ] Database initialized: `createdb synapse_db`
- [ ] User created with appropriate permissions
- [ ] Database backup procedure tested
- [ ] Backup storage location configured (internal/NAS/S3)
- [ ] Retention policy documented (e.g., 30 days)

### Redis
- [ ] Redis 7+ installed
- [ ] Cluster mode configured (if HA required)
- [ ] Persistence enabled (RDB or AOF)
- [ ] Memory limits configured
- [ ] Password set and stored in GSM
- [ ] Replication configured (if multi-host)

### Credentials & Secrets
- [ ] All secrets in Google Secret Manager (not in code)
- [ ] GSM access configured with service account
- [ ] `scripts/fetch-gsm-secrets.sh` working on deployment host
- [ ] Sensitive environment variables loading correctly
- [ ] No plaintext passwords in .env files or Docker Compose

---

## User & Access Management

### Service Accounts
- [ ] Google Cloud service account created
- [ ] Service account has appropriate roles (min required)
- [ ] Service account key downloaded and stored securely
- [ ] Service account authorized in Workspace Admin Console
- [ ] Domain-wide delegation enabled (if Workspace integration needed)

### QA User Account
- [ ] Google Workspace domain verified
- [ ] Workspace admin with delegated authority identified
- [ ] Process documented for creating qa@kushnir.cloud user
- [ ] QA user password generation procedure documented
- [ ] Password stored in Google Secret Manager (not in code)

### SSH Access
- [ ] SSH keys configured for deployment host access
- [ ] Key-based authentication working (no password-only access)
- [ ] SSH port 22 accessible from your network
- [ ] Bastion host configured (if needed for security)
- [ ] SSH known_hosts updated with server keys

---

## Monitoring & Observability Setup

### Prometheus
- [ ] Prometheus image pulled and available
- [ ] Prometheus storage directory created (>100GB recommended)
- [ ] Scrape config created (`prometheus.yml`)
- [ ] Alert rules defined (`prometheus-rules-*.yml`)
- [ ] Retention policy configured (>30 days recommended)

### Grafana
- [ ] Grafana image pulled and available
- [ ] Admin password set (non-default)
- [ ] Datasource (Prometheus) configured
- [ ] Dashboards imported or created
- [ ] Dashboard provisioning configured
- [ ] Alerting integration tested

### AlertManager
- [ ] AlertManager image available
- [ ] Alert routing configured
- [ ] Notification channels tested (email, Slack, etc.)
- [ ] Alert grouping rules defined
- [ ] Inhibition rules configured (to avoid alert storms)

---

## Testing & Validation

### Unit Tests
- [ ] All unit tests passing locally: `npm test`
- [ ] Test coverage > 80% (or team standard)
- [ ] No flaky tests or timeouts
- [ ] Test suite runs in < 5 minutes

### Integration Tests
- [ ] Docker Compose stack starts without errors
- [ ] Services reach healthy state within 2 minutes
- [ ] All services pass health checks
- [ ] Services communicate correctly (no network issues)

### E2E Tests (Pending #983/#984)
- [ ] E2E test framework configured (Playwright)
- [ ] Test data seeded correctly
- [ ] OAuth login test configured
- [ ] Test environment variables set
- [ ] All 150+ tests passing

### Security Tests
- [ ] No secrets in Git history: `git log -S "password"` returns nothing
- [ ] No hardcoded credentials in code
- [ ] Dependency vulnerabilities scanned: `npm audit` clean or acceptable risks documented
- [ ] Static code analysis passed (linting, type checking)

---

## Documentation & Runbooks

### Deployment Documentation
- [ ] Deployment runbook written and tested
- [ ] Pre-deployment checklist (this file) completed
- [ ] Post-deployment verification guide (see separate document) reviewed
- [ ] Rollback procedure documented and tested in staging
- [ ] Team members briefed on deployment plan

### Operational Runbooks
- [ ] Service health check procedure documented
- [ ] Common troubleshooting scenarios documented
- [ ] Log locations and rotation policy documented
- [ ] Backup/restore procedures documented and tested
- [ ] Incident response playbook prepared

### Knowledge Transfer
- [ ] Team trained on deployment procedure
- [ ] On-call support briefed on system architecture
- [ ] Escalation path clearly defined
- [ ] Contact information for all support team members documented
- [ ] Knowledge base updated with relevant information

---

## Staging & Dry-Run

### Staging Environment
- [ ] Staging environment mirrors production configuration
- [ ] All services deployed to staging
- [ ] Full E2E test suite running against staging
- [ ] Monitoring stack operational in staging
- [ ] Data refresh procedure tested (if using production data subset)

### Deployment Dry-Run
- [ ] Complete deployment procedure executed in staging
- [ ] Deployment time measured and documented
- [ ] Rollback procedure tested in staging
- [ ] Team familiar with deployment interface/commands
- [ ] Potential issues identified and mitigated

### Failure Scenarios
- [ ] Service failure simulation tested (kill a container, verify recovery)
- [ ] Network partition tested (if applicable)
- [ ] Disk space exhaustion scenario tested
- [ ] Database corruption recovery tested
- [ ] Backup/restore tested with actual backup files

---

## Security & Compliance

### Security Review
- [ ] Code reviewed by security team (or automated scanning passed)
- [ ] Dependency vulnerabilities addressed
- [ ] Authentication/authorization logic reviewed
- [ ] Encryption at rest and in transit verified
- [ ] Access control policies documented

### Compliance Checks
- [ ] GDPR readiness verified (if applicable)
- [ ] Data residency requirements met
- [ ] Audit logging enabled
- [ ] Data retention policies configured
- [ ] PII handling procedures documented

### Secrets Management
- [ ] All secrets in external vault (Google Secret Manager)
- [ ] Secrets rotation procedure documented
- [ ] Secret access audit trail enabled
- [ ] Emergency secret revocation procedure documented
- [ ] No secrets in Git history or Docker images

---

## Team Readiness

### Team Composition
- [ ] Deployment lead identified (1 person)
- [ ] Infrastructure engineer assigned (1-2 people)
- [ ] QA lead assigned (1 person)
- [ ] On-call support scheduled (24/7 minimum)
- [ ] Escalation contacts identified

### Team Training
- [ ] All team members reviewed deployment plan
- [ ] All team members reviewed runbooks
- [ ] Team members practiced deployment in staging
- [ ] Team members understand rollback procedure
- [ ] Team members know how to monitor system health

### Communication
- [ ] Deployment schedule announced to stakeholders
- [ ] Maintenance window approved by business
- [ ] Incident communication plan prepared
- [ ] Status page / notification channel configured
- [ ] Stakeholders briefed on what to expect

---

## Final Sign-Off

### Approval Gates
- [ ] Infrastructure Lead: `_________` (Signature/Date)
- [ ] Security Lead: `_________` (Signature/Date)
- [ ] QA Lead: `_________` (Signature/Date)
- [ ] Business Owner: `_________` (Signature/Date)

### Go/No-Go Decision
- [ ] All items above checked and approved
- [ ] Outstanding issues documented and risk-accepted
- [ ] Team confident in deployment plan
- [ ] Decision: **[ ] PROCEED / [ ] HOLD / [ ] INVESTIGATE**

### Issue Resolution
If any items are not ready, document the risk and mitigation:

| Item | Status | Risk | Mitigation |
|------|--------|------|-----------|
| Example | Not Ready | Critical | We will proceed with close monitoring |
| | | | |
| | | | |

---

## Pre-Deployment Day Activities

### 24 Hours Before
- [ ] All team members available and on-call
- [ ] External stakeholders notified
- [ ] Monitoring dashboards prepared
- [ ] Communication channels tested
- [ ] Final backup created and verified

### 1 Hour Before
- [ ] Team assembled in communication channel
- [ ] Last-minute health check of staging
- [ ] Verification that deployment tools are ready
- [ ] Final confirmation from all sign-off parties
- [ ] Begin deployment

### During Deployment
- [ ] Real-time status updates to stakeholders
- [ ] Monitor all services closely
- [ ] Watch logs for errors
- [ ] Have rollback plan ready
- [ ] Document any unexpected behavior

### Post-Deployment (First Hour)
- [ ] Run post-deployment verification checklist
- [ ] Confirm all services healthy
- [ ] Verify user access working
- [ ] Check for any errors in logs
- [ ] Get stakeholder confirmation

---

## Success Criteria

### Successful Pre-Deployment Readiness
✅ All items checked  
✅ All team members trained  
✅ All sign-offs collected  
✅ Staging environment fully tested  
✅ Runbooks documented and reviewed  
✅ Monitoring ready  
✅ Backup/restore tested  

### Red Flags (Do Not Proceed)
🔴 Secrets found in code  
🔴 Tests failing in staging  
🔴 Deployment procedure untested  
🔴 Team member unavailable  
🔴 Security concerns unresolved  
🔴 Stakeholder approval not obtained  

---

## Revision History

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2026-04-20 | 1.0 | Initial checklist | DevOps Team |
| | | | |

---

**Document Version**: 1.0  
**Last Updated**: April 20, 2026  
**Next Review**: May 20, 2026  
**Status**: Ready for pre-deployment use
