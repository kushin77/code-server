# Production Pull Request Workflow Guide

**kushin77/code-server** uses a **4-Phase Production-First** pull request process ensuring every merge to `main` is production-ready.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [The 4 Phases](#the-4-phases)
3. [Creating a PR](#creating-a-pr)
4. [Phase 1: Design Review](#phase-1-design-review)
5. [Phase 2: Code Quality](#phase-2-code-quality)
6. [Phase 3: Operational Readiness](#phase-3-operational-readiness)
7. [Phase 4: Production Acceptance](#phase-4-production-acceptance)
8. [Merging to Production](#merging-to-production)
9. [Post-Deploy](#post-deploy)
10. [Troubleshooting](#troubleshooting)

---

## Quick Start

### For small fixes (not feature/API/infra changes)

```bash
# 1. Create branch
git checkout -b fix/issue-123

# 2. Make changes + tests
# 3. Push
git push origin fix/issue-123

# 4. Create PR (use template, fill out Phase 2 + Phase 4 sections)
# 5. Wait for automated Phase 1-2 checks
# 6. Request 2 code reviews
# 7. After approval: Merge with "Squash and merge" strategy
```

### For features/APIs/infrastructure (requires design review)

Follow full 4-phase process below ↓

---

## The 4 Phases

| Phase | Responsibility | Timeline | Gate |
|-------|----------------|----------|------|
| **1: Design** | Author + Design Reviewer | 24-48h | ADR doc, architecture approved |
| **2: Code Quality** | Automated CI/CD | 10-30min | Tests (95%+), lint, security scans |
| **3: Operations** | SRE/On-call | 4-24h | Observability, monitoring, runbook |
| **4: Production** | On-call Engineer | 1-4h | Deployment plan, rollback tested |

---

## Creating a PR

### Step 1: Use the PR Template

When creating a PR, GitHub will show `.github/PULL_REQUEST_TEMPLATE.md`. Fill it out completely:

```markdown
# Title: [Type] Brief description

## Type of Change
- [ ] Bug fix
- [x] Feature / API change
- [ ] Infrastructure change
- [ ] Security hardening

## Phase Applicability
- [x] Phase 1: Design Review (required for: feature, API, infra, breaking change)
- [x] Phase 2: Code Quality (always required)
- [ ] Phase 3: Ops Review (required for: deployments, backend changes)
- [ ] Phase 4: Production Acceptance (required for: all main branch merges)

## Phase 1: Design (if applicable)

### Architecture
- Horizontal scalability: ✅ Tested at 10x load
- Stateless design: ✅ No shared mutable state
- Failure isolation: ✅ Circuit breakers implemented
- Single point of failure: ✅ Redundancy via load balancer

### Deployment & Rollback
- Feature flag required: NO
- Rollback time: < 60 seconds (git revert)
- Canary deployment: YES (1% traffic 5min)
- DB migration backwards compatible: N/A

### Design Review
- [ ] ADR linked: `docs/adr/XXX-[title].md`
- [ ] Design doc: [link to confluence]
- [ ] Signed off by: @[architecture-lead]

---

## Phase 2: Code Quality

### Tests
- [x] Unit tests (95%+ coverage)
- [x] Integration tests
- [x] Chaos/failure tests
- [ ] Load tests (TBD)
- Test coverage: 96% ✅

### Code Quality
- [x] Linting passed (eslint, shellcheck, terraform fmt)
- [x] Type checking passed (TypeScript, mypy)
- [x] No code duplication
- [x] Security scanning passed

### Security
- [x] No hardcoded secrets
- [x] No default credentials
- [x] Input validation comprehensive
- [x] Dependencies scanned (npm audit, pip audit)

---

## Phase 3: Operational Readiness (if applicable)

### Observability
- [x] Structured logging (JSON + correlation IDs)
- [x] Metrics instrumented (Prometheus counters, histograms)
- [x] Distributed tracing (OpenTelemetry spans)
- [x] Health checks configured (readiness + liveness)

### Monitoring & Alerting
- [x] Alert rules defined (Prometheus)
- [x] SLO targets specified (availability, latency)
- [x] Grafana dashboard created
- [x] PagerDuty/Slack integration tested

### Documentation
- [x] Runbook documented: `docs/runbooks/[service].md`
- [x] Deployment guide: README or DEPLOYMENT.md
- [x] Incident response steps
- [ ] Architecture diagram

---

## Phase 4: Production Acceptance

### Deployment Plan
- [ ] Pre-deploy checklist prepared
- [ ] Rollback procedure tested (< 60 seconds)
- [ ] On-call team notified
- [ ] Maintenance window scheduled (if needed)

### Monitoring Plan
- [ ] Post-deploy validation (1 hour)
- [ ] Key metrics pinned in Grafana
- [ ] Alert thresholds confirmed
- [ ] Slack #alerts channel configured

### Risks & Mitigation
- Key risks identified: [list]
- Mitigation strategies: [list]
- Fallback options: [list]
```

---

## Phase 1: Design Review

**Required for**: Feature, API, infrastructure, breaking change  
**Timeline**: 24-48 hours  
**Gate**: Architecture approval + ADR

### When to Skip Phase 1

✅ **Skip Phase 1 for**:
- Bug fixes with zero behavior change
- Documentation updates
- Test additions
- Refactoring with identical behavior
- Dependency upgrades (patch only)

❌ **ALWAYS do Phase 1 for**:
- New feature or API
- Infrastructure changes (Terraform, Kubernetes, networking)
- Database schema changes
- Breaking changes
- Security features
- Performance-critical changes

### How to do Phase 1

1. **Write ADR** (Architecture Decision Record)
   ```bash
   # Create docs/adr/XXX-[title].md
   # Template: .github/ADR-TEMPLATE.md
   ```

   Example: `docs/adr/024-oauth2-proxy-integration.md`
   ```markdown
   # ADR 024: OAuth2-Proxy Integration for API Authentication

   **Status**: PROPOSED (awaiting review)  
   **Date**: 2026-04-17  
   **Authors**: @[your-username]

   ## Context
   - Current auth: API keys (insecure, non-rotatable)
   - Requirement: OAuth2 OIDC for enterprise
   - Scale: 1M req/sec, 3-second rollback SLA

   ## Decision
   - Use oauth2-proxy (proven, widely deployed)
   - Port: 4180 (redirect from 8080)
   - Feature flag: ENABLE_OAUTH2_AUTH
   - Rollback: Simple nginx redirect change

   ## Consequences
   - New external dependency (oauth2-proxy binary)
   - All requests filtered through auth gateway
   - Latency: +20ms p50 (measured)
   - Redundancy: Multi-instance load balanced
   ```

2. **Request Design Review**
   ```
   @[architecture-lead] Please review ADR 024 in docs/adr/
   
   Key questions:
   - Does oauth2-proxy architecture fit our scale?
   - Rollback procedure adequate?
   - Any security concerns?
   ```

3. **Iterate Until Approved**
   - Update ADR based on feedback
   - Mark as `APPROVED` in header
   - Design review posts ✅ approval comment

---

## Phase 2: Code Quality

**Required for**: All PRs  
**Timeline**: 10-30 minutes (automated)  
**Gate**: Tests (95%+), linting, security scans

### Automated Checks

When you push code, GitHub Actions automatically runs:

#### `.github/workflows/phase-2-code-quality.yml`
- ✅ Unit tests (Jest, pytest)
- ✅ Type checking (TypeScript, mypy)
- ✅ Linting (ESLint, Shellcheck, yamllint)
- ✅ Security scanning (hardcoded secrets, defaults)
- ✅ Dependency scanning (npm audit, pip audit)
- ✅ Docker build validation

### What to Do If Checks Fail

**Tests failing?**
```bash
# Run locally
npm test
pytest

# Fix and push
git add .
git commit -m "fix: adjust test expectations"
git push
```

**Linting errors?**
```bash
# Auto-fix
npm run lint -- --fix
terraform fmt -recursive
black .

git add .
git commit -m "style: auto-format code"
git push
```

**Type errors?**
```bash
# Review errors
npm run type-check
# Fix manually
git add .
git commit -m "fix: resolve type errors"
git push
```

**Security scan failed?**
```bash
# If hardcoded secret detected:
# 1. Remove from code
# 2. Rotate secret immediately
# 3. Push fix
# 4. Notify @security team

git rm --cached [sensitive-file]
git add .
git commit -m "sec: remove hardcoded secret"
git push
```

---

## Phase 3: Operational Readiness

**Required for**: Backend changes, deployments, infra changes  
**Timeline**: 4-24 hours  
**Gate**: Observability, monitoring, runbook

### Automated Checks

When PR is reviewed, automated Phase 3 checks run:

#### `.github/workflows/phase-3-operational-ready.yml`
- ✅ Observability verification (logs, metrics, traces)
- ✅ Monitoring config check (alerts, SLO)
- ✅ Configuration validation (hardcoded IPs/secrets)
- ✅ Database migration review

### What to Add

#### 1. Logging
```python
# Before: No visibility
result = process_payment(order_id)

# After: Structured logging
logger.info("payment_processing_started", extra={
    "order_id": order_id,
    "amount": order.total,
    "correlation_id": request.headers.get("X-Correlation-ID")
})
result = process_payment(order_id)
logger.info("payment_processing_completed", extra={
    "order_id": order_id,
    "result": result.status,
    "duration_ms": result.duration
})
```

#### 2. Metrics (Prometheus)
```python
from prometheus_client import Counter, Histogram

payment_counter = Counter('payments_total', 'Total payments', ['status'])
payment_duration = Histogram('payment_duration_seconds', 'Payment duration')

with payment_duration.time():
    result = process_payment(order_id)
    
payment_counter.labels(status=result.status).inc()
```

#### 3. Tracing (OpenTelemetry)
```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("process_payment") as span:
    span.set_attribute("order_id", order_id)
    result = process_payment(order_id)
    span.set_attribute("status", result.status)
```

#### 4. Health Checks
```python
@app.get("/health/ready")
def readiness():
    return {
        "status": "ready",
        "checks": {
            "database": check_db_connection(),
            "cache": check_redis_connection(),
            "dependencies": check_external_apis()
        }
    }
```

#### 5. Monitoring (Prometheus + Grafana)
```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'code-server'
    static_configs:
      - targets: ['localhost:8080']
```

#### 6. Alerting
```yaml
# alert-rules.yml
groups:
  - name: payment_service
    rules:
      - alert: HighErrorRate
        expr: rate(payments_total{status="error"}[5m]) > 0.01
        for: 5m
        annotations:
          summary: "Payment service error rate > 1%"
          
      - alert: HighLatency
        expr: histogram_quantile(0.99, payment_duration_seconds) > 1.0
        for: 5m
        annotations:
          summary: "Payment P99 latency > 1 second"
```

#### 7. Runbook
```markdown
# docs/runbooks/payment-service.md

## Payment Service Incidents

### Symptom: High Error Rate (>1%)
1. Check logs: `kubectl logs -l app=payment-service --tail=100`
2. Query: Error rate in Grafana
3. Possible causes:
   - Database overload → Check DB connection pool
   - Payment gateway timeout → Check upstream API
   - Invalid request data → Validate incoming data
4. Mitigation: Enable circuit breaker, scale replicas
5. Rollback: `git revert [commit_sha]`
```

### How to Request SRE Review

```
@[sre-team] Phase 3 operational readiness review

Changes:
- Added Prometheus metrics for payment processing
- Configured alerting for error rate > 1%
- Documented incident response runbook
- Load tested at 2x expected traffic

Please review:
- [ ] Observability adequate
- [ ] Alerts appropriately configured
- [ ] Runbook complete
- [ ] Capacity planning acceptable
```

---

## Phase 4: Production Acceptance

**Required for**: All merges to main  
**Timeline**: 1-4 hours  
**Gate**: Deployment plan, rollback tested

### On-Call Acceptance

Before merge, on-call engineer must approve by:

1. **Review deployment plan**
   ```
   @[on-call] Requesting production acceptance
   
   Deployment plan:
   - Canary: 1% traffic, 5 min monitoring
   - Rollout: 1% → 10% → 50% → 100% (15 min each)
   - Rollback: `git revert [sha]` (60 sec)
   - Post-deploy: 1 hour monitoring by author
   ```

2. **Verify rollback tested**
   ```bash
   # Confirm in PR:
   "Tested rollback: git revert [sha] deployed, verified in 45 seconds"
   ```

3. **Confirm on-call coverage**
   ```
   On-call during deployment: ✅
   Pager team notified: ✅
   Post-deploy support: @[author] for 1 hour
   ```

4. **Approve merge**
   GitHub approves PR → "✅ Production-ready for merge"

---

## Merging to Production

### Merge Procedure

```bash
# 1. Ensure all reviews approved
# 2. Ensure all phase gates passed
# 3. Click "Merge pull request" button
# 4. Select "Squash and merge"
# 5. Confirm commit message includes PR number:
#    "fix: payment error handling (fixes #123)"
```

### Merge Strategy

Use **squash and merge** for all merges:
- ✅ Keeps main history clean
- ✅ Atomic commits (one feature = one commit)
- ✅ Easy to revert entire feature

### Post-Merge Triggers

When you merge, GitHub Actions automatically:

1. **Tests** → Run full test suite (unit + integration + chaos + load)
2. **Security** → Run SAST scan, container scan, dependency audit
3. **Build** → Create Docker image, push to registry
4. **Deploy** → Trigger deployment to production
5. **Monitor** → Watch error rate, latency, resource usage

---

## Post-Deploy

### Author Monitoring (1 hour)

After merge to main:

1. **Monitor key metrics** (next 60 minutes)
   - Error rate (should stay < 0.1%)
   - P99 latency (should stay within 20% of baseline)
   - Resource usage (CPU, memory, disk)
   - Pod restarts/crashes

2. **Watch for alerts**
   - Slack #alerts
   - PagerDuty notifications
   - Grafana dashboards

3. **If issues detected**
   - Initiate rollback: Contact on-call
   - Execute: `git revert [commit_sha]` on production host
   - Notify team in #incidents
   - Create incident post-mortem ticket

4. **If all good after 1 hour**
   - Post in #deployments: "✅ Deployment [PR#123] successful"
   - Close any related issues
   - Update runbook if needed

### Post-Deploy Verification Checklist

```markdown
## Deployment Verification (Post-Deploy)

✅ **Immediate (0-5 min)**
- [ ] Service health check passing
- [ ] Error rate normal (< 0.1%)
- [ ] No new 5xx errors in logs
- [ ] Database migrations applied

✅ **5-30 minutes**
- [ ] P99 latency within baseline ±20%
- [ ] CPU/memory usage reasonable
- [ ] No alert storms
- [ ] Canary metrics look good

✅ **30-60 minutes**
- [ ] Gradual rollout proceeding as planned
- [ ] No error spikes after each rollout stage
- [ ] Customer-facing metrics stable
- [ ] Post-deploy business metrics normal

✅ **1+ hour**
- [ ] All rollout stages complete (100% traffic)
- [ ] Sustained stability (no degradation)
- [ ] Ready to hand off from author to ops
```

---

## Troubleshooting

### "Phase 1: Design Review is Mandatory"

**Problem**: CI rejects PR without design review for feature change.

**Solution**:
```bash
# 1. Create ADR
cat > docs/adr/XXX-[title].md << 'EOF'
# ADR XXX: [Title]
Status: PROPOSED
[fill out template]
EOF

# 2. Update PR description
# 3. Request review
# 4. CI will pass after design approval
```

### "Tests Failing in Phase 2"

**Problem**: Unit tests fail.

**Solution**:
```bash
# Run locally
npm test  # or pytest

# Fix + push
git add .
git commit -m "fix: test failures"
git push origin [branch]
```

### "Phase 3: SRE Review Blocking Merge"

**Problem**: SRE hasn't reviewed operational readiness.

**Solution**:
```
@[sre-team] Operational readiness review needed for PR #123

Added observability:
- Prometheus metrics for [service]
- Alert rules for [scenarios]
- Runbook at docs/runbooks/[service].md
- Load tested at 5x traffic

Please approve or request changes.
```

### "Merge Conflict with Main"

**Problem**: Main branch has changed since you branched.

**Solution**:
```bash
# 1. Update local main
git fetch origin
git checkout main
git pull origin main

# 2. Rebase your branch
git checkout [your-branch]
git rebase main

# 3. Resolve conflicts in editor
git add .
git rebase --continue

# 4. Force push (safe since only you're on this branch)
git push origin [your-branch] --force-with-lease
```

### "Phase 4: On-Call Rejected Deployment"

**Problem**: On-call says rollback strategy is insufficient.

**Solution**:
```
In PR comment:

@[on-call] Addressing rollback concerns:

1. Rollback procedure verified:
   - Command: git revert [commit]
   - Tested locally: Confirms deployment success in < 60 sec
   - Database rollback: No schema changes, safe

2. Post-deploy monitoring:
   - Grafana dashboard: [link]
   - Alert thresholds: [specify]
   - On-call support: [duration]

3. Risk mitigation:
   - Canary: 1% traffic 5 minutes before expanding
   - Feature flag: Can disable [feature] without rollback
   - Scaling: Set resource limits, auto-scaling enabled

Ready for approval when you're confident.
```

---

## Summary

### The 4 Phases at a Glance

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Design Review (if feature/API/infra)                      │
│    Author writes ADR, architecture lead approves             │
│    Timeline: 24-48h │ Gate: ADR approved                     │
├─────────────────────────────────────────────────────────────┤
│ 2. Code Quality (automated)                                  │
│    Tests (95%+), lint, security, dependencies                │
│    Timeline: 10-30min │ Gate: All CI checks pass             │
├─────────────────────────────────────────────────────────────┤
│ 3. Operational Readiness (SRE review)                        │
│    Observability, monitoring, runbook, capacity              │
│    Timeline: 4-24h │ Gate: SRE approval                      │
├─────────────────────────────────────────────────────────────┤
│ 4. Production Acceptance (on-call)                           │
│    Deployment plan, rollback tested, on-call approval        │
│    Timeline: 1-4h │ Gate: On-call sign-off                   │
├─────────────────────────────────────────────────────────────┤
│ 5. Merge & Deploy                                            │
│    Automatic CI/CD deployment on merge to main               │
│    Timeline: 5-15min │ Gate: All tests passing               │
├─────────────────────────────────────────────────────────────┤
│ 6. Post-Deploy Monitoring (1 hour)                           │
│    Author monitors metrics, on-call on standby               │
│    Timeline: 60min │ Gate: Metrics stable, no alerts         │
└─────────────────────────────────────────────────────────────┘
```

### Quick Checklist for Every PR

- [ ] PR title: `[Type] Brief description` (bug fix, feature, infra)
- [ ] PR description: Filled from `.github/PULL_REQUEST_TEMPLATE.md`
- [ ] Phase 1: Design ADR (if feature/API/infra)
- [ ] Phase 2: All tests pass, linting passes, security clean
- [ ] Phase 3: Observability added (if backend change)
- [ ] Phase 4: Rollback procedure documented
- [ ] ≥2 code reviews with ✅ APPROVED
- [ ] ≥1 SRE review (if deployments/ops)
- [ ] On-call approval before merge
- [ ] Merge with "Squash and merge" strategy
- [ ] Monitor 1 hour post-deploy

---

## Questions?

Contact #engineering-standards or post in GitHub Issues with `[QUESTION]` prefix.

---

**Last Updated**: April 17, 2026  
**Policy**: Production-First, No Exceptions
