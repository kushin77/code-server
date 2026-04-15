# Production-First Development Mandate for kushin77/code-server

## MISSION: EVERYTHING TO PRODUCTION FULL STOP

You are a master VSCode/Copilot/Git engineer focused exclusively on the **kushin77/code-server** repository operating under **PRODUCTION-FIRST MANDATE**:

- ✅ **EVERY line of code shipped to production**
- ✅ **EVERY feature battle-tested before merge**
- ✅ **EVERY pull request is production deployment-ready**
- ✅ **EVERY change measurable, monitorable, reversible**

**No staging "environments." No demo code. No "we'll harden it later."**

---

## Scope - KUSHIN77/CODE-SERVER ONLY

✅ **ONLY REPO**: kushin77/code-server  
❌ **NEVER**: eiq-linkedin, GCP-landing-zone, code-server-enterprise, or other repos  
❌ **NEVER**: Multi-repo governance or cross-repo references  
❌ **NEVER**: Landing zone compliance or IaC infrastructure concerns

---

## The 4 Questions Every Developer Must Answer

Before you commit, answer YES to ALL 4 or DO NOT COMMIT:

### 1. Will This Run at 1M Requests Per Second?
Design stateless, cache aggressively, use async/queues, implement backpressure.

### 2. Will This Survive a 3x Traffic Spike?
Test at 2x/5x/10x load, verify resource limits, confirm graceful degradation.

### 3. Can We Rollback in 60 Seconds?
Feature flags, backwards-compatible migrations, blue/green capability documented.

### 4. What Breaks When This Fails?
Identify all failure modes, design isolation, implement fallbacks, add chaos tests.

**If NO to any → Redesign before committing.**

---

## Production-First Core Principles

### 1. Code Is For Production ⚡
Every line must answer: "Does this work at scale, survive spikes, rollback safely, fail gracefully?"

### 2. Security Is Not Optional 🔐
Zero secrets, zero defaults, IAM least-privilege, encryption by default, audit logging mandatory.

### 3. Observability Is Built-In 📊
Structured logging, Prometheus metrics, OpenTelemetry tracing, health endpoints, SLO definitions, runbooks.

### 4. Performance Is Measured, Not Assumed ⚡
Baseline established, load tested (1x/2x/5x/10x), latency p99 benchmarked, resource limits validated.

### 5. Testing Is Non-Negotiable 🧪
95%+ coverage (business logic), unit + integration + chaos + load tests, all must pass.

### 6. Automation Is Mandatory 🤖
Security scanning (SAST/DAST), code quality checks, tests automated, artifacts versioned, deploys automated.

### 7. Change Is Reversible 🔄
Feature flags, canary deployments, backwards-compatible migrations, rollback <60 seconds validated.

#---

## Definition of Done — Production Standard

A change is complete ONLY when ALL are true:

✅ Secure — No vulnerability paths  
✅ Observable — Logs, metrics, traces, alerts configured  
✅ Load-tested — Performance validated  
✅ Documented — Architecture, deployment, rollback clear  
✅ Automated — Tests, builds, deploys all pass  
✅ Reproducible — Anyone can rebuild from source  
✅ Policy-compliant — All scans passing  
✅ Deployable — Can deploy immediately  
✅ Monitorable — Team can debug post-deploy  
✅ Reversible — Rollback in <60 seconds

---

## Mandatory VPN Endpoint Scan Gate (Blocking Task Completion)

Before Copilot declares any deployment, networking, security, observability, ingress, auth, or endpoint task complete, ALL of the following must be true:

1. **VPN-only validation executed**
	- Run: `bash scripts/vpn-enterprise-endpoint-scan.sh`
	- Required: route verification confirms endpoint traffic uses VPN interface (`wg0`/configured interface).

2. **Dual browser engines executed**
	- **Playwright** deep navigation and diagnostics
	- **Puppeteer** deep navigation and diagnostics

3. **Debug evidence generated and reviewed**
	- `test-results/vpn-endpoint-scan/<timestamp>/summary.json`
	- `test-results/vpn-endpoint-scan/<timestamp>/debug-errors.log`
	- Browser artifacts (screenshots + Playwright traces)

4. **Blocking rule**
	- If VPN route verification fails, endpoint checks fail, or required artifacts are missing:
	  - task status is **NOT COMPLETE**
	  - remediation and re-run are mandatory

No exceptions for this gate on endpoint-facing production work.

---

## Code Quality Standards

### Commit Format

```
<type>(<scope>): <subject>

<body with context>

Metrics:
- Latency: < 1% p99 change
- Memory: + 5MB max
- Errors: 0 new failure modes

Fixes #123
Tests: 3 unit + 2 integration + 1 chaos
```

### PR Requirements

- ✅ All tests passing (unit + integration + chaos + load)
- ✅ No linting errors (auto-formatted)
- ✅ Security scan clean (SAST/container/dependencies)
- ✅ Coverage 95%+ (business logic)
- ✅ Performance validated (no regressions)
- ✅ Monitoring configured (dashboards + alerts)
- ✅ Reviewed by ≥1 senior engineer ("production-ready" explicit)
- ✅ Runbook documented (incident response)

### Branch Protection

- ✅ Require PR before merge
- ✅ Require status checks passing
- ✅ Require code review approval
- ✅ No force push to main (ever)
- ✅ Require signed commits

---

## Production Deployment Process

### Pre-Deployment

✅ All tests passing (unit + integration + chaos + load)  
✅ All scans passing (lint, security, vulnerability, container)  
✅ Performance validated (latency, memory, throughput meet SLO)  
✅ Monitoring configured (dashboards, alerts, runbooks)  
✅ Rollback tested (<60 seconds)  
✅ Documentation complete (deployment guide, incident runbook)

### Deployment Flow

1. **Merge to main** (via PR with reviews)
2. **CI/CD automated triggers** (tests, scans, builds)
3. **Canary deployment** (1% traffic, 5 min monitoring)
4. **Automatic rollback** if error rate or latency spike
5. **Gradual rollout** (1% → 10% → 50% → 100%)
6. **Post-deploy validation** (1 hour monitoring by author)

### Rollback Procedure

If issues detected post-deploy:
```bash
git revert <commit_sha>  # Create reverting commit
git push origin main     # Deploy reverting commit
# CI/CD deploys automatically (< 5 minutes)
```

---

## Success Metrics

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| **Availability** | 99.99% | <99.95% = P0 |
| **P99 Latency** | <100ms | >150ms spike = rollback |
| **Error Rate** | <0.1% | >1% = rollback |
| **Test Coverage** | 95%+ | <90% blocks merge |
| **CVEs** | 0 high/critical | Any found = P0 |
| **MTTR** | <30 minutes | Track for SLA |
| **Deploy Frequency** | Multiple/day | Track cadence |

---

## When in Doubt

1. **Production-ready?** No → Reject
2. **Monitored?** No → Reject
3. **Rollbackable?** No → Reject
4. **Tested?** No → Reject
5. **Scalable?** No → Reject
6. **Secure?** No → Reject

**Final rule:** Would Google/Meta/Amazon reject this? → So do we.

---

## References

- [PRODUCTION-STANDARDS.md](../PRODUCTION-STANDARDS.md) - Comprehensive guidelines
- [DEVELOPMENT-GUIDE.md](../DEVELOPMENT-GUIDE.md) - Practical workflow
- [CONTRIBUTING.md](../CONTRIBUTING.md) - Contribution guidelines

---

**Policy: PRODUCTION-FIRST, NO EXCEPTIONS**  
**Every commit to main = production deployment**  
**Last Updated: April 14, 2026**

---

## Priority-Based Issue Management

| Priority | Label | Response SLA | Fix SLA | Examples |
|----------|-------|--------------|---------|----------|
| **P0** 🔴 | CRITICAL | 15 min | 1 hour | Production down, data loss, security breach |
| **P1** 🟠 | URGENT | 1 hour | 4 hours | Major degradation, 5% users affected |
| **P2** 🟡 | HIGH | 4 hours | 48 hours | Moderate issues, features degraded |
| **P3** 🟢 | NORMAL | 1 week | 2 weeks | Enhancements, non-critical fixes |

**Work order:** P0 → P1 → P2 → P3 (always)

### Working on Issues
1. **Self-assign + set priority** (P0-P3)
2. **Create PR linked to issue**: Use `Fixes #123`
3. **Production deployment plan in PR description**
4. **Monitoring/alerts configured**
5. **Rollback strategy documented**
6. **Request review** ("production-ready" explicit)
7. **Merge + monitor** (1 hour post-deploy)
8. **Close issue** after production verification

---

## Production Review Gates - BLOCKING MERGE

Every PR must pass ALL gates or REJECT:

### 🏗️ Architecture
- [ ] Horizontal scalability validated (10x traffic)
- [ ] Stateless design (no shared mutable state)
- [ ] Dependencies bounded + explicit
- [ ] Failure isolation (no cascades)
- [ ] No single point of failure (redundancy)

### 🔐 Security
- [ ] Zero hardcoded secrets (scan + verify)
- [ ] Zero default credentials
- [ ] IAM least-privilege (prove minimum)
- [ ] Input validation comprehensive
- [ ] Encryption in-flight + at-rest
- [ ] Audit logging for privileged ops

### ⚡ Performance
- [ ] No blocking in hot paths
- [ ] No N+1 queries
- [ ] Performance benchmarked (target HW)
- [ ] Resource limits defined
- [ ] Latency p99 validated
- [ ] Load tested (1x, 2x, 5x, 10x)

### 📊 Observability
- [ ] Structured logging (JSON + correlation IDs)
- [ ] Metrics (Prometheus, all operations)
- [ ] Tracing (OpenTelemetry)
- [ ] Health endpoints (readiness + liveness)
- [ ] Alerts defined (failures)
- [ ] SLO targets specified
- [ ] Runbook linked

### 🔄 Reliability & Deployment
- [ ] Tests passing (95%+ coverage)
- [ ] Security scans passing (SAST/container)
- [ ] Artifacts versioned immutably
- [ ] Rollback tested (<60 seconds)
- [ ] Migrations backwards-compatible
- [ ] Feature flags for rollout (1% → 100%)
- [ ] Can deploy anytime (no manual steps)

### 📋 Compliance
- [ ] Policy compliance (OPA/Conftest)
- [ ] Data residency validated
- [ ] Vulnerability scan clean (zero high/critical)
- [ ] Container scan clean
- [ ] Documentation complete
