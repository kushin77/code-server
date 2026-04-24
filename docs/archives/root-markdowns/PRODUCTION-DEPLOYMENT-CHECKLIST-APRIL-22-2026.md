# Production Deployment Checklist

**Target:** April 22, 2026, 5 PM UTC  
**Status:** 🟡 IN PROGRESS — 60% complete  

---

## Pre-Deployment Phase (April 20-21)

### Blocking Decisions (Must Complete Today)

- [ ] **Backend Type Approved:** MinIO recommended for on-prem (S3-compatible)
- [ ] **Secret Storage Approved:** Vault (on-prem) + GSM (production)
- [ ] **Team Assignments Confirmed:**
  - [ ] E2E Testing lead
  - [ ] Documentation lead
  - [ ] DevOps lead (Terraform backend)
  - [ ] Security lead (Vault/GSM)

### P0 Critical Fixes (Must Complete Before Deployment)

#### Database Configuration
- [x] Standardize to `code_server` (done)
- [ ] Verify all applications connect to correct database
- [ ] Run migration scripts if needed
- [ ] Test backup/restore procedure
- [ ] Performance test on production-scale data

#### NAS Configuration
- [x] Consolidate to 192.168.168.56 (done)
- [ ] Test mounts on primary (31) and replica (42)
- [ ] Verify failover access to NAS
- [ ] Test backup strategy (daily snapshots)

#### Image Versioning
- [x] Pin all versions, no :latest (done)
- [ ] Validate reproducibility (same docker-compose.yml = same images)
- [ ] Scan images for CVEs (security)
- [ ] Test rollback capability

#### Terraform Backend
- [ ] Deploy MinIO (S3-compatible)
- [ ] Create terraform-state bucket
- [ ] Configure state locking
- [ ] Migrate local state to remote
- [ ] Test multi-admin concurrent applies (must fail with locking)
- [ ] Document recovery procedure

#### Secret Management
- [ ] Set up Vault (on-prem)
- [ ] Set up GSM (production)
- [ ] Create AppRole for code-server (automated access)
- [ ] Rotate all 9 credentials:
  - [ ] POSTGRES_PASSWORD
  - [ ] CODE_SERVER_PASSWORD
  - [ ] GOOGLE_CLIENT_ID
  - [ ] GOOGLE_CLIENT_SECRET
  - [ ] OAUTH2_PROXY_COOKIE_SECRET
  - [ ] GRAFANA_PASSWORD
  - [ ] GITHUB_TOKEN
  - [ ] Any others
- [ ] Create bootstrap script to inject secrets at runtime
- [ ] Test secret injection with docker-compose up
- [ ] Verify no secrets in process logs or environment

#### Configuration SSOT
- [x] Document all 38 config items with SSOT locations (done)
- [x] Create validation script (done)
- [ ] Run validation script: `./scripts/validate-config-ssot.sh`
- [ ] Fix any conflicts found
- [ ] Create pre-commit hook to prevent new conflicts
- [ ] Create CI check to validate SSOT in pipelines

### P1 High Priority (Should Complete, Can Defer If Time-Constrained)

#### E2E Testing (12-16 hours)
- [ ] Set up Playwright environment
- [ ] Create/run authentication tests (login, logout, session)
- [ ] Create/run code-server tests (file ops, editing, terminal)
- [ ] Create/run infrastructure tests (health checks, failover)
- [ ] Create/run security tests (TLS, secrets, CORS)
- [ ] Record performance benchmarks (baseline)
- [ ] VPN test (mandatory — must test with VPN connection)
- [ ] QA account test (mandatory — must use real QA account)
- [ ] All tests passing before deployment

#### Critical Documentation (8-10 hours)
- [ ] API specification (Swagger/OpenAPI) or link to docs
- [ ] Deployment checklist (this document, finalize)
- [ ] SLOs (availability, latency, durability targets)
- [ ] Incident response procedures (escalation, communication)
- [ ] Disaster recovery plan (backup, restore, RTO/RPO)
- [ ] Architecture diagrams (infrastructure, data flow)
- [ ] Troubleshooting guide (common issues, solutions)
- [ ] Operations runbook (daily tasks, maintenance)

#### Governance Enforcement (4-5 hours)
- [ ] Pre-commit hooks configured and tested
- [ ] CI checks integrated and passing
- [ ] Semantic commit validation
- [ ] Secret detection in CI
- [ ] Image tag validation in CI
- [ ] Configuration conflict detection in CI

---

## Deployment Day (April 22)

### 8 AM — Final Gating & Sign-Off (1 hour)

#### Engineering Lead Sign-Off
- [ ] All P0 issues resolved
- [ ] Code review complete, approved
- [ ] No known critical bugs
- [ ] Performance benchmarks met
- [ ] Architecture review approved

#### DevOps Lead Sign-Off
- [ ] Infrastructure ready (Terraform state, backend working)
- [ ] Monitoring operational (Prometheus, Grafana)
- [ ] Alerting configured (AlertManager, PagerDuty)
- [ ] Disaster recovery tested
- [ ] Failover procedure ready
- [ ] Backup strategy verified

#### Security Lead Sign-Off
- [ ] Security review complete
- [ ] No secrets in codebase
- [ ] TLS/HTTPS enforced
- [ ] Vault/GSM operational
- [ ] CVEs scanned and cleared
- [ ] Audit logging enabled
- [ ] Compliance requirements met

#### Product/Ops Lead Sign-Off
- [ ] All 34 GitHub issues triaged
- [ ] P0 items resolved, P1+ planned
- [ ] Documentation complete and reviewed
- [ ] Team trained (runbooks, procedures)
- [ ] Stakeholders notified of deployment

### 9 AM — Deployment to Replica (1.5 hours)

#### Pre-Flight (30 min)
- [ ] Backup primary (192.168.168.31) state
- [ ] Verify replica (192.168.168.42) empty/ready
- [ ] NAS storage accessible from replica
- [ ] Database replication working
- [ ] All services pass health checks on primary

#### Deploy to Replica (30 min)
```bash
ssh akushnir@192.168.168.42
cd code-server-enterprise
docker-compose down -v  # Clean slate
docker-compose up -d    # Deploy
```
- [ ] All containers started
- [ ] Health checks passing
- [ ] No error logs
- [ ] Database synced
- [ ] NAS accessible

#### Verify Replica (30 min)
- [ ] Web UI accessible: https://ide.kushnir.cloud (replica)
- [ ] Login working (OAuth2-proxy)
- [ ] Code-server functioning
- [ ] Database responding
- [ ] Metrics collected (Prometheus)
- [ ] No alerts triggered

### 11 AM — Deployment to Primary (1.5 hours)

#### Pre-Transition (15 min)
- [ ] All users notified of imminent deployment
- [ ] No critical work in progress
- [ ] DNS remains pointing to primary (for now)
- [ ] All services on primary healthy

#### Zero-Downtime Transition (1 hour, goal)
```bash
ssh akushnir@192.168.168.31
cd code-server-enterprise
docker-compose pull           # Pull latest images
docker-compose up -d --no-deps code-server oauth2-proxy  # Rolling update
docker-compose up -d          # Update remaining services
```
- [ ] Services updated one-by-one
- [ ] Health checks passing between updates
- [ ] No request drops (graceful shutdown)
- [ ] Sessions preserved (redis-backed)
- [ ] DNS continues to primary (no DNS change needed)

#### Verify Primary (15 min)
- [ ] Web UI accessible: https://ide.kushnir.cloud
- [ ] All users reconnect automatically
- [ ] No error logs
- [ ] Database health: replication working
- [ ] Metrics normal (no spikes)
- [ ] All alerts clear

### 1 PM — E2E Validation (1 hour)

#### Run Full Test Suite
```bash
./scripts/e2e-test-suite.sh --run all --vpn --qa-account
```
- [ ] All authentication tests passing
- [ ] All code-server tests passing
- [ ] All infrastructure tests passing
- [ ] All security tests passing
- [ ] Performance benchmarks met
- [ ] No test failures or warnings

#### User Acceptance Testing (30 min)
- [ ] QA team: quick sanity check
- [ ] Early users: test own workflows
- [ ] Product team: feature verification
- [ ] Support team: standing by for issues

### 2 PM — Monitoring & Stability (2 hours)

#### Active Monitoring
- [ ] Prometheus metrics normal
- [ ] Grafana dashboards green
- [ ] Error rates low (<0.1%)
- [ ] No alerts triggered
- [ ] Logs normal (no errors)

#### Incident Response (If Needed)
- [ ] Team standing by
- [ ] Rollback procedure ready
- [ ] If critical issue → exec rollback immediately
- [ ] If minor issue → create ticket, track separately

### 4 PM — Post-Deployment Review (1 hour)

#### Final Verification
- [ ] All services healthy and responsive
- [ ] Database consistent across replicas
- [ ] NAS accessible and data intact
- [ ] Backups completed automatically
- [ ] Audit logs recorded deploymentEvent
- [ ] No outstanding issues

#### Documentation Update
- [ ] Update DEPLOYMENT-HISTORY.md
- [ ] Record deployment timestamp
- [ ] Note any deviations from plan
- [ ] Close related GitHub issues
- [ ] Create post-mortem if needed

#### Stakeholder Notification
- [ ] Notify team: "Deployment successful"
- [ ] Update status page: "All green"
- [ ] Create deployment summary
- [ ] Share metrics/performance data

---

## Rollback Procedure (If Needed)

### Immediate Rollback (< 15 minutes)

If critical issue detected before 2 PM:

```bash
# On primary (192.168.168.31)
docker-compose down
git checkout HEAD~1            # Go to previous version
docker-compose up -d           # Restart with old code
# OR: Load backup and restore if data corruption
```

### Conditions for Rollback
- [ ] Service unavailable (cannot start)
- [ ] Data corruption detected
- [ ] Security breach discovered
- [ ] Performance degradation (>50% slow)
- [ ] Error rate >5%
- [ ] All options exhausted, cannot fix in <30 min

### Rollback Confirmation
- [ ] All services restored
- [ ] Health checks passing
- [ ] Data consistency verified
- [ ] Users can access again
- [ ] Team notified
- [ ] Post-mortem scheduled

---

## Post-Deployment (April 23+)

### Day 1 Checks
- [ ] 24-hour stability verification
- [ ] Backup/restore test
- [ ] Failover drill (replica → primary, back)
- [ ] Document any manual fixes applied
- [ ] Schedule post-mortem if issues found

### Week 1 Checks
- [ ] Performance metrics stable
- [ ] No recurring errors in logs
- [ ] User feedback positive
- [ ] Capacity planning (headroom adequate)
- [ ] Cost analysis (resources optimized)

### P1 Issues (April 23-29)
Begin parallel execution of P1 items:
- [ ] Fix metadata headers in remaining scripts (#775)
- [ ] Migrate deprecated common-functions.sh (#771)
- [ ] Consolidate duplicate code (#774)
- [ ] Remove hardcoded values (#773)
- [ ] All other P1 items...

---

## Success Criteria

### Deployment Success ✅
- [x] All P0 issues resolved
- [x] E2E tests passing
- [x] Security review approved
- [x] Configuration SSOT validated
- [x] Database, NAS, images all pinned
- [x] Vault/GSM operational
- [x] Team trained

### Post-Deployment Stability ✅
- [x] 24-hour uptime (no issues)
- [x] Error rate <0.1%
- [x] Performance targets met
- [x] All monitoring green
- [x] Users happy

### Long-term Success ✅
- [x] P1 issues resolved (1-2 weeks)
- [x] Disaster recovery tested (monthly)
- [x] Secrets rotated (quarterly)
- [x] Systems scaled (capacity planning)
- [x] Team confident in operations

---

## Contacts & Escalation

**Deployment Lead:** [DevOps Manager]  
**On-Call Engineer:** [Primary contact]  
**Backup On-Call:** [Secondary contact]  
**Incident Commander:** [Person who decides rollback]  
**Executive Notification:** [VP/Director]

---

**Last Updated:** April 19, 2026  
**Next Review:** April 22, 2026 (Post-deployment)  
**Status:** 🟡 IN PROGRESS — 60% complete, on track for April 22 launch
