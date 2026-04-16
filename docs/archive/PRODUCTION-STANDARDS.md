# Production-First Development Standards

## Core Mandate

**EVERY LINE OF CODE IS FOR PRODUCTION.**

- ✅ Code ships to production on merge
- ✅ No staging environments  
- ✅ No demo code paths
- ✅ No "we'll harden it later"
- ✅ No manual pre-deployment steps
- ✅ No single-use debugging code
- ✅ No accepted technical debt

---

## Four Questions Every Developer Must Ask

Before every commit, answer these 4 questions or DO NOT COMMIT:

### 1. Will This Run at 1M Requests Per Second?

- Design stateless where possible
- Use horizontal scaling, not vertical
- Cache aggressively
- Batch operations
- Use async/queues for blocking operations
- Implement rate limiting + backpressure

**If NO:** Redesign before committing.

### 2. Will This Survive a 3x Traffic Spike?

- Test at 2x, 5x, 10x normal load
- Verify resource limits don't get exceeded
- Confirm no unbounded memory growth
- Validate connection pools don't exhaust
- Ensure graceful degradation

**If NO:** Add circuit breakers, bulkheads, scale testing before committing.

### 3. Can We Rollback in 60 Seconds?

- Feature flags for new features (revert = disable flag)
- Database migrations backwards-compatible
- Config changes support revert
- Blue/green deployment capability
- Documented rollback procedure

**If NO:** Change approach to support rollback before committing.

### 4. What Breaks When This Fails?

- Identify all failure modes
- Map cascade scenarios
- Design isolation (bulkheads)
- Implement fallbacks
- Add chaos tests
- Document incident response

**If UNKNOWN:** Add chaos tests before committing.

---

## Production Checklist: Pre-Deployment Verification

### Security ✅

```bash
# Secrets scanning (automated enforcement)
pre-commit run detect-private-key --all-files

# SAST (static analysis for vulns)
bandit -r src/  # Python
eslint src/  # JavaScript

# Container scanning
trivy image --severity HIGH,CRITICAL myapp:latest

# Dependency scanning
pip-audit  # Python
npm audit  # JavaScript
```

Result: **Zero high/critical findings or DO NOT DEPLOY**

### Testing ✅

```bash
# Unit tests (95%+ coverage)
pytest tests/unit/ -v --cov=src/ --cov-fail-under=85

# Integration tests
pytest tests/integration/ -v --tb=short

# Chaos tests
pytest tests/chaos/ -v --timeout=30

# Load tests
locust -f tests/load/locustfile.py --headless -u 1000 -r 100 -t 5m
```

Result: **All tests passing or DO NOT DEPLOY**

### Performance ✅

```bash
# Baseline metrics established
# P99 latency: < 100ms (or service-specific SLO)
# Memory: < 500MB per instance
# CPU: < 70% under normal load
# Throughput: > 1000 req/sec per instance

# Verified via:
# 1. Load test baseline (see above)
# 2. Production metrics (Prometheus)
# 3. Canary deployment (1% traffic, 5 min)
```

Result: **Baseline established + canary healthy or DO NOT DEPLOY**

### Observability ✅

```bash
# Logging: Structured (JSON) with correlation IDs
# Metrics: Prometheus format, all operations
# Tracing: OpenTelemetry enabled
# Health: /health + /health/ready endpoints
# Alerts: Defined for failure scenarios
# SLO: Specified (availability, latency, error rate)
# Runbook: Linked for incident response
```

Result: **Complete observability stack or DO NOT DEPLOY**

### Compliance ✅

```bash
# Policy compliance: conftest pass  
# Data residency: validated
# Encryption: TLS 1.3+, AES-256
# Access logging: immutable
# Secret rotation: scheduled
# Backup validation: restore tested
```

Result: **All compliance checks pass or DO NOT DEPLOY**

---

## Development Standards by Language

### Python

**Linting & Formatting**
```bash
black src/  # Format
pylint src/ --fail-under=8.0  # Lint
mypy src/ --strict  # Type checking
```

**Testing**
```bash
pytest tests/ -v --cov=src/ --cov-fail-under=85 --tb=short
```

**Security**
```bash
bandit -r src/  # Security scan
pip-audit  # Dependency audit
```

**.pre-commit hooks**
- black (auto-format)
- pylint (lint check)
- bandit (security scan)
- detect-private-key (secrets check)

### JavaScript/TypeScript

**Linting & Formatting**
```bash
prettier --write "src/**/*.{js,ts}"  # Format
eslint src/ --fix  # Lint with fixes
tsc --noEmit  # Type check
```

**Testing**
```bash
jest tests/ --coverage --collectCoverageFrom='src/**'
```

**Security**
```bash
npm audit  # Dependency audit
eslint --config .eslintrc.security.js  # Security rules
```

**.pre-commit hooks**
- prettier (auto-format)
- eslint (lint + security checks)
- npm audit (dependency scan)

### Bash/Shell

**Standards**
```bash
shellcheck scripts/*.sh  # No warnings/errors
shfmt -i 2 -l 120 scripts/*.sh  # Format
```

**Requirements**
- Error handling: `set -e`, `set -o pipefail`
- Logging: Structured, with timestamps
- Timeouts: All external calls have timeout
- Retries: Failed calls retry 3x with backoff

**.pre-commit hooks**
- shellcheck (linting)
- shfmt (formatting)

### Terraform/IaC

**Standards**
```bash
terraform fmt -recursive  # Format
terraform validate  # Validate syntax
checkov -d .  # Policy compliance
```

**Requirements**
- All resources tagged
- No hardcoded values
- Data sources for sensitive lookups
- Encryption by default
- State file encrypted + backed up

**.pre-commit hooks**
- terraform fmt (formatting)
- terraform validate (validation)
- checkov (policy compliance)

### SQL & Migrations

**Standards**
- Backwards-compatible always
- Test forward + backward migration
- No data loss scenarios
- Rollback procedure documented
- Performance impact validated

---

## Deployment Process

### Pre-Deployment (Local)

1. **All tests passing** (unit, integration, chaos, load)
2. **All scans passing** (lint, security, dependency, container)
3. **Performance validated** (latency, memory, throughput)
4. **Runbook documented** (incident response)
5. **Rollback tested** (can revert in <60 seconds)

### Merge to Main

1. **PR review approval** (>=1 senior engineer)
2. **All CI/CD checks passing**
3. **Code marked "production-ready"** (explicit statement)
4. **Fast-forward merge** (linear history)

### Automated Deployment

1. **Canary deployment** (1% traffic, 5 minutes)
   - Monitor error rate (should be 0)
   - Monitor latency (should be baseline)
   - Monitor resource usage (should be normal)

2. **Automatic rollback if:**
   - Error rate > 1% above baseline
   - Latency p99 > 200% baseline
   - OOM or crash events
   - Alert firing above thresholds

3. **Full rollout** (100% traffic)
   - Gradual: 1% → 10% → 50% → 100%
   - 5 minute soak between each step
   - Monitor continuously

4. **Post-deployment validation** (1 hour)
   - Author monitors dashboards
   - Verify feature works end-to-end
   - Confirm no new alerts
   - Document observed metrics

### If Issues Found

**Automatic rollback trigger:**
```bash
if error_rate > baseline * 1.01:
    deploy_previous_version()
    alert_team()
    create_incident()
```

**Manual rollback:**
```bash
git revert <commit_sha>  # Create reverting commit
git push origin main  # Deploy reverting commit
# CI/CD deploys automatically
```

---

## Incident Response Standard

### P0 (Production Down)

- **Response SLA:** 15 minutes
- **Initial assessment:** What's broken? What's affected? Is user data at risk?
- **Rollback decision:** Is previous version working? If YES → rollback immediately
- **Fix preparation:** Parallel track to rollback assessment
- **Timeline:** < 1 hour to resolve or escalate

### P1 (Major Degradation)

- **Response SLA:** 1 hour
- **Assessment:** Impact scope, affected users, workarounds
- **Fix preparation:** Immediate coding + testing
- **Timeline:** < 4 hours to deploy fix or rollback

### P2 (Moderate Issues)

- **Response SLA:** 4 hours
- **Assessment:** Reproducible? Can we confirm root cause?
- **Fix:** Plan fix, code, test, deploy within 48 hours

### P3 (Minor/Enhancement)

- **Response SLA:** 1 week
- **Scheduled:** Include in next deployment cycle

---

## Performance Standards by Component

### API Handlers

- P50: < 50ms
- P99: < 100ms
- P99.9: < 500ms
- Error rate: < 0.1%
- Throughput: > 1000 req/sec per instance

### Database Queries

- P50: < 10ms
- P99: < 50ms
- Connection pool: Max 100, Min 10
- Connection timeout: 5 seconds
- Query timeout: 30 seconds

### Cache (Redis)

- Get latency p99: < 5ms
- Set latency p99: < 5ms
- Miss rate: < 5%
- Eviction policy: allkeys-lru

### Message Queues

- Publish latency p99: < 100ms
- Message processing: < 1 second
- Dead letter queue monitored
- Replay capability validated

### Background Jobs

- Job execution timeout: 5 minutes default
- Retry: 3x with exponential backoff
- Dead letter queue for failures
- Daily summary in logs

---

## Monitoring & Alerting

### Required Metrics (Every Service)

- **Throughput:** Requests/second
- **Latency:** P50, P95, P99
- **Errors:** Count + rate + types
- **Resources:** CPU, memory, disk, connections
- **Saturation:** Queue depth, pool usage, cache hit rate

### Alert Rules (Must Have)

| Alert | Threshold | Action | Duration |
|-------|-----------|--------|----------|
| High Error Rate | > 1% | Page on-call | 5 min |
| High Latency | P99 > 200ms | Page on-call | 10 min |
| Out of Memory | > 80% | Auto-restart + page | 2 min |
| Database Down | Connection lost | Page on-call | 1 min |
| Disk Full | > 90% | Alert | Immediate |

### Dashboard Requirements

Every service needs:
- Error rate graph + trend
- Latency graph (p50, p95, p99)
- Throughput graph
- Resource usage (CPU, memory, disk)
- Query performance (if DB service)
- Cache hit rate (if cache service)
- Alert threshold lines visible

---

## Security Standards

### Secrets Management

❌ **NEVER:**
- Commit passwords to git
- Hardcode API keys
- Default credentials in containers
- Secrets in logs

✅ **ALWAYS:**
- Use secrets management (Vault, AWS Secrets Manager, etc.)
- Rotate secrets regularly
- Audit secret access
- Encrypt secrets in transit + at rest

### Network Security

❌ **NEVER:**
- Public databases
- Unencrypted internal communication
- World-accessible admin endpoints

✅ **ALWAYS:**
- Private subnets for databases
- TLS 1.3+ for all communication
- Network policies (K8s) isolate services
- Admin endpoints behind authentication

### Dependency Management

❌ **NEVER:**
- Use unvetted dependencies
- Use unmaintained packages
- Ignore security advisories

✅ **ALWAYS:**
- Scan dependencies before use
- Update security patches within 48 hours
- Use pinned versions (reproducibility)
- Test updates before deployment

### Audit Logging

✅ **LOG:**
- All authentication attempts (success + failures)
- All authorization changes
- All data access (PII, financial, etc.)
- All configuration changes
- All deployments

---

## Code Review Standards for Reviewers

### Security Review

- [ ] **Secrets check:** No hardcoded credentials, API keys, tokens
- [ ] **Authentication:** Properly validated, no bypasses
- [ ] **Authorization:** Least-privilege enforced
- [ ] **Input validation:** All external inputs validated
- [ ] **Dependencies:** Known vulnerabilities checked
- [ ] **Cryptography:** Strong algorithms, proper usage

### Performance Review

- [ ] **Complexity:** O() complexity acceptable?
- [ ] **Scaling:** Will this work at 1M RPS?
- [ ] **Memory:** No leaks, proper cleanup?
- [ ] **Queries:** No N+1, batching used?
- [ ] **Concurrency:** Thread-safe? Proper locking?
- [ ] **Load testing:** Performance validated?

### Reliability Review

- [ ] **Error handling:** All failure paths handled?
- [ ] **Timeouts:** External calls have timeout?
- [ ] **Retries:** Failed operations retry with backoff?
- [ ] **Cascades:** What fails when this fails?
- [ ] **Monitoring:** Observable enough to debug?
- [ ] **Alerting:** Alerts defined for failures?

### Code Quality Review

- [ ] **Clarity:** Understandable without explanation?
- [ ] **Testability:** Can unit tests cover this?
- [ ] **Reusability:** Extract common patterns?
- [ ] **Duplication:** DRY principle followed?
- [ ] **Coupling:** Loose coupling, high cohesion?
- [ ] **Comments:** Why, not what - documented?

### Final Gate

**Ask yourself:** "Would I ship this code at Google/Meta/Amazon?"

If NO → Reject. Request changes.

---

## Success Metrics

| KPI | Target | Measurement | Cadence |
|-----|--------|-------------|---------|
| **Availability** | 99.99% | Uptime monitoring | Daily |
| **P99 Latency** | <100ms | APM system | Real-time |
| **Error Rate** | <0.1% | Application metrics | Real-time |
| **Test Coverage** | 95%+ | Code coverage scan | Per commit |
| **CVEs** | 0 high/critical | Dependency scan | Weekly |
| **MTTR** | <30 minutes | Incident tracking | Monthly |
| **Deploy Frequency** | Multiple/day | Git commits | Daily |
| **Lead Time** | <4 hours | Commit to production | Hourly |

---

**Last Updated: April 14, 2026**  
**Policy: PRODUCTION-FIRST, NO EXCEPTIONS**
