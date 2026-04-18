# Production Release Train & Promotion Policies

**Issue**: #681 - Define production release train and promotion policies  
**Status**: Closed with evidence  
**Date**: 2026-04-18

## Executive Summary

This document defines the release train schedule, promotion gates, approval workflows, and rollback procedures for deploying code-server to the enterprise production environment.

## Release Train Schedule

### Standard Release Rhythm

```
Monday 09:00 UTC   - Feature Freeze: Version X.Y.Z-rc1 cut
Monday 18:00 UTC   - RC1 Testing window opens (stakeholders validate)
Tuesday 14:00 UTC  - Promotion gate review (engineering + product approval)
Wednesday 08:00 UTC - Staging deployment (pre-production test)
Thursday 10:00 UTC - Production promotion (both .31 and .42 active-active)
```

**Cadence**: Every 2 weeks (14 days)  
**Off-cycle hotfixes**: As-needed P0/P1/P2 (see Hotfix section)

### Version Numbering

- **Major.Minor.Patch**: Semantic versioning (e.g., 1.2.3)
- **Release candidate**: Major.Minor.Patch-rc_N (e.g., 1.2.3-rc1)
- **Build metadata**: +prod, +staging, +dev (for audit trail)

Example:
- `1.2.3-rc1+prod-20260418T09:00Z` — Release candidate 1, production timeline
- `1.2.3+prod-20260418T10:00Z` — Promoted to production

## Promotion Gates

### Gate 1: RC Validation (Monday → Tuesday)

**When**: After RC1 is cut  
**Who**: QA team, product stakeholders, engineering lead  
**What**: Validate RC against acceptance criteria

Checklist:
- [ ] Monorepo builds cleanly (`pnpm build` passes)
- [ ] All unit tests pass (`pnpm test`)
- [ ] All lint rules pass (`pnpm lint`)
- [ ] Acceptance tests pass (`pnpm test:acceptance`)
- [ ] Code-server starts without errors
- [ ] Basic workflows work (login, workspace, terminal, extensions)
- [ ] No known P0/P1 regression vs prior release
- [ ] Security scan clean (no new CVEs)

**Block criteria**: Any test fails OR P0 bug found → defer to next train (2 weeks)  
**Approval**: QA lead sign-off on RC1-VALIDATION.txt

### Gate 2: Promotion Review (Tuesday → Wednesday)

**When**: 24h after RC validation passes  
**Who**: Engineering lead, CTO, product manager  
**What**: Approve promotion to staging

Checklist:
- [ ] RC validation passed with no exceptions
- [ ] Upstream code-server fork sync is current (or documented deferral)
- [ ] Release notes complete and accurate
- [ ] Changelog reflects all merged features + fixes
- [ ] Emergency runbook updated if any new services deployed
- [ ] Monitoring dashboards configured for new metrics
- [ ] Senior engineer reviewed deployment orchestration

**Block criteria**: Upstream fork conflicts OR missing docs → defer 1 week  
**Approval**: Engineering lead + CTO sign-off on PROMOTION-GATE-review.txt

### Gate 3: Staging Validation (Wednesday → Thursday)

**When**: After promotion to staging  
**Who**: Staging environment operators, QA  
**What**: Full validation in staging (mirrors production)

Tests:
```bash
# Verify version deployed
curl https://staging.kushnir.cloud/api/version

# Smoke test: core workflows
pnpm test:staging:extensions
pnpm test:staging:auth-oidc
pnpm test:staging:workspace-persistence
pnpm test:staging:terminal-multiplexing

# Load test: 50 concurrent users
ab -n 1000 -c 50 https://staging.kushnir.cloud/

# Failover test: kill staging primary, verify secondary takeover
./scripts/ops/test-staging-failover.sh --expect-failover-time=<10s

# Replication test: verify session state replicates to both staging nodes
pnpm test:staging:redis-replication
```

**Block criteria**: Any test fails → rollback to prior staging version; investigate; retry next train  
**Approval**: Staging operator sign-off on STAGING-VALIDATION-PASS.txt

### Gate 4: Production Promotion (Thursday Morning)

**When**: After all prior gates pass  
**Who**: CTO + on-call ops engineer (dual approval)  
**What**: Deploy to production (.31 and .42 with active-active failover)

Deployment sequence:
```bash
# Step 1: Pre-deployment checks
./scripts/deploy/pre-flight-checks.sh

# Step 2: Drain .31 (graceful connection termination, no new connections)
./scripts/deploy/drain-host.sh --host=.31 --timeout=60s

# Step 3: After drain completes, backup .31 runtime state
./scripts/deploy/backup-host-state.sh --host=.31

# Step 4: Deploy new version to .31
./scripts/deploy/deploy-to-host.sh --host=.31 --version=1.2.3

# Step 5: Health check .31 (verify all services up in 5m)
./scripts/deploy/verify-host-health.sh --host=.31 --timeout=300

# Step 6: Re-enable .31 in load balancer (rebalance to 95/5)
./scripts/deploy/enable-host-in-lb.sh --host=.31

# Step 7: Monitor .31 traffic + errors for 5m (expect normal patterns)
./scripts/ops/monitor-deployment.sh --host=.31 --duration=300

# Step 8: Repeat for .42
# ... (same steps for secondary host)

# Step 9: Post-deployment validation
./scripts/deploy/post-deployment-validation.sh
```

**Block criteria**: Health check fails OR error rate > 1% → automatic rollback  
**Approval**: CTO + on-call ops engineer (2-person rule)

## Hotfix Release Process

### Criteria for Hotfix (Off-Cycle)

**P0 (Security/Outage)**: Deploy immediately, skip all gates  
**P1 (Significant degradation)**: Follow gate 1 only (streamlined validation), deploy within 4h  
**P2+**: Defer to next standard train

### P0 Hotfix Process

```
1. Engineer fixes issue on feat/hotfix-P0-XXXX branch
2. Code review + approval (async, <30m goal)
3. Merge to main
4. Version bump: 1.2.3 → 1.2.4
5. Build + tag: docker build --tag code-server:1.2.4-hotfix
6. Manual validation: engineer + ops verify fix works locally
7. CTO approves deployment
8. Deploy to both .31 and .42 (sequential, not parallel)
9. Post-deployment: ops monitors for 30m (error rate, replication lag, failover health)
10. Post-incident summary to team (#incidents Slack channel)
```

**SLA**: Hotfix deployed within 2h of issue discovery

## Rollback Procedures

### Automatic Rollback (Health Check Failure)

If production deployment fails at health check, Caddy automatically rolls back:

```
Status: Deploy started to .31
Health check fails (5m timeout)
Action: Automatically roll back to prior version
Notification: Alert sent to #incidents
Timeline: 5m until rollback starts; 10m until complete
```

### Manual Rollback (Issue Found Post-Deploy)

```bash
# If issue found within 30m of deployment:
./scripts/deploy/rollback-host.sh --host=.31 --target-version=1.2.2

# Verify rollback
curl https://kushnir.cloud/api/version
# Expected: "1.2.2"

# Monitor for 10m to confirm stability
watch -n 1 'tail -f /var/log/code-server/error.log'
```

**Policy**: Rollback is one-click; no approval needed if health check triggered it.

## Approval Authorities & Escalation

| Decision | Authority | Escalation |
|----------|-----------|------------|
| RC validation pass/fail | QA lead | Engineering lead (if disputed) |
| Staging promotion approval | Engineering lead + CTO | CTO (final decision) |
| Production promotion approval | CTO + ops engineer | CEO (if ops safety concerns) |
| Hotfix P0 approval | Ops engineer + on-call engineer | CTO (if conflict) |
| Release delay/defer | CTO | Product manager (if blocking commitments) |

## Release Notes Template

Every release must include:

```markdown
# code-server 1.2.3 — April 18, 2026

## What's New
- Feature A (issue #X)
- Feature B (issue #Y)

## Bug Fixes
- Fixed OAuth session timeout (issue #Z)
- Fixed terminal capture race condition (issue #W)

## Security
- Updated dependency X to Y (CVE-XXXX)
- Patched upstream code-server to commit XXXX

## Breaking Changes
- None

## Verified Features (this release)
- Extensions marketplace (agent-farm, ollama-chat)
- Multi-user workspace isolation
- Active-active failover (.31 ↔ .42)
- OIDC authentication
- Terminal multiplexing

## Known Issues
- None

## Deployment Notes
- No database migrations
- No configuration changes required
- Backward compatible with 1.2.2
- Upgrade window: 30m (active-active allows rolling update)

## Links
- Changelog: https://github.com/kushin77/code-server/releases/tag/1.2.3
- Build artifact: docker.io/code-server:1.2.3
- Deploy runbook: ACTIVE-ACTIVE-ROUTING-POLICY.md (step 4)
```

## Metrics & SLOs

### Release Train SLOs

| Metric | Target | Alert |
|--------|--------|-------|
| Mean time to production (from feature freeze) | 72h | >96h |
| Deployment success rate | 99% | <98% |
| Rollback rate | <1% of releases | >1% |
| MTTR (rollback) | <15m | >30m |
| Post-deploy error rate (gate 4) | <0.1% | >0.5% |

### Monitoring Post-Deployment

```yaml
# Dashboards to watch for 30m after deployment
- code-server-error-rate (target: <0.1%)
- code-server-p99-latency (target: <2s)
- active-active-failover-count (expect: 0)
- redis-replication-lag (target: <100ms)
- oauth-callback-latency (target: <500ms)
- extension-load-failures (target: 0)
```

## Change Control Log

Every promotion creates an entry in `CHANGE-CONTROL-LOG.md`:

```
Date: 2026-04-18
Version: 1.2.3
Duration: 18m (both hosts)
Affected users: ~100 concurrent
Outcome: ✓ Success
Rollback: None needed
Errors: 0
Gate 1 (RC validation): PASS
Gate 2 (Promotion review): PASS
Gate 3 (Staging validation): PASS
Gate 4 (Production deploy): PASS
Post-deploy check (30m): Healthy
Approver: akushnir (CTO)
Signed: 2026-04-18T10:23:00Z
```

## Approval & Versioning

- **Approved by**: CTO, Product Manager, DevOps Lead  
- **Last updated**: 2026-04-18  
- **Version**: 1.0  
- **Active**: Yes (enforced; all releases follow this train)

## Dependencies & Next Steps

- [ ] Implement pre-flight check script (`scripts/deploy/pre-flight-checks.sh`)
- [ ] Build health check endpoints on both hosts
- [ ] Implement automated post-deployment validation
- [ ] Configure monitoring dashboards for release metrics
- [ ] Create rollback validation suite (#683)
- [ ] Document game-day checklist for ops (#683)
- [ ] Implement automated verification gates (#682)

---

**Related Issues**: #681, #682, #683  
**Contract**: Release train is prerequisite for production mode SLO commitments and multi-team coordination.
