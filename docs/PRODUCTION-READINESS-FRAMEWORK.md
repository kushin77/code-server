# Production Readiness Certification Framework (Issue #381)

**Status**: DESIGN PHASE - Week 3-4  
**Effort**: 2-3 weeks implementation + operations  
**Priority**: P0 (gates all production code)  
**Owner**: QA/Architecture/SRE Team  

---

## 1. OVERVIEW

Production readiness certification is a 4-phase quality gate that shifts quality decisions **left** (before code review) and ensures all non-trivial changes meet elite standards for reliability, performance, security, and operability.

**Design Principle**: Not a blocker, but a **responsibility clarification**. Author owns proving readiness; gates highlight what needs proof.

---

## 2. FOUR-PHASE GATE FRAMEWORK

### Phase 1: Design Certification (Before Implementation)

**Gate Owner**: Architecture Lead + On-Call Reliability Engineer  
**Duration**: 1-2 hours  
**Required For**: Any change > 100 LOC, new service, new pattern, config change affecting 10+ containers

#### What Author Must Define

1. **SLA Target** (1 line)
   ```
   Current:  P99 latency = 500ms, Availability = 99%
   Target:   P99 latency = 200ms, Availability = 99.9%
   Impact:   -60% latency improvement, +0.9% availability
   ```

2. **Failure Mode Analysis** (2-3 scenarios)
   ```
   Failure Mode 1: Cache backend goes down
   - Blast Radius: Code-server features degrade (2-3 sec slower)
   - RPO: 0 (stateless, auto-recovers)
   - RTO: < 30 seconds
   - Mitigation: Fallback to primary DB
   
   Failure Mode 2: Configuration reload fails
   - Blast Radius: Service uses stale config (max 5 min)
   - RPO: 0
   - RTO: Manual restart < 2 min
   - Mitigation: Config validation in CI, health check for config mismatch
   
   Failure Mode 3: Replication lag > 2 min
   - Blast Radius: Read replicas see stale data
   - RPO: 2 min
   - RTO: N/A (manual promotion required)
   - Mitigation: Alert at lag > 30s, runbook for replica recovery
   ```

3. **Rollback Plan** (1-2 paragraphs)
   ```
   This change is:
   - Backwards-compatible: YES - old clients will still work
   - Feature-flagged: YES - flag=feature-name, default=off, enable 1%→10%→100%
   - Database migrated: NO (no schema changes)
   - Rollback time: < 60 seconds (revert flag in config, redeploy)
   - Rollback validation: Metrics return to baseline within 2 min
   
   If needed: git revert SHA && deploy
   Time estimate: 5 minutes
   ```

4. **Observability Plan** (metrics, logs, dashboards)
   ```
   Metrics (from Prometheus):
   - feature_flag_enabled{feature="new-cache"} = 1
   - cache_hit_rate{backend="redis"} (target: >90%)
   - cache_latency_p99{backend="redis"} (target: <10ms)
   - cache_errors_total{backend="redis"} (target: 0)
   
   Logs (structured, in Jaeger):
   - cache_operation{operation="get", hit=true/false}
   - cache_error{operation="set", error="timeout"}
   
   Dashboard:
   - "Cache Performance" dashboard in Grafana
   - Panels: hit rate, latency, error rate, backend availability
   
   Alerts:
   - CacheHitRateDropped (< 85%)
   - CacheLatencySpiked (p99 > 50ms)
   - CacheBackendDown (error rate > 10%)
   ```

**Design Template**:
```markdown
## Design Certification for PR #XXX

### SLA Target
Current: [current metrics]
Target: [target metrics]
Impact: [delta analysis]

### Failure Modes (FMEA)
| Mode | Blast Radius | Mitigation | RTO |
|------|---|---|---|
| ... | ... | ... | ... |

### Rollback Plan
- Backwards-compatible: YES/NO
- Feature-flagged: YES/NO
- Rollback time: < X seconds
- Validation: [how to confirm rollback successful]

### Observability
- Metrics: [list]
- Logs: [schema]
- Dashboards: [Grafana links]
- Alerts: [alert names and thresholds]
```

**Approval Requirement**:
- ✅ Architecture lead reviews design (no implementation yet)
- ✅ On-call reliability engineer validates observability plan
- ✅ Both approve in PR comment: "Design certified ✓"

**Waiver Path**:
- Doc updates, non-prod scripts, bug fixes to existing code: **EXEMPT** (low risk)
- All other changes: **REQUIRED**

---

### Phase 2: Implementation Quality Gate (During Code Review)

**Gate Owner**: Peer Reviewer (not author) + Architecture  
**Duration**: Code review normal time + checklist  
**When**: Every PR with code changes

#### Code Review Checklist

```markdown
## Production Readiness Code Review Checklist

### Horizontal Scalability
- [ ] No N+1 queries (explain any loops querying DB)
- [ ] No shared mutable state (e.g., static variables, global cache)
- [ ] Stateless service (if replicated, each instance independent)
- [ ] Connection pooling configured (max connections defined)
- [ ] Request context not leaked (no goroutine escapes)

### Error Handling
- [ ] All code paths have error handling (no silent failures)
- [ ] Timeouts on all external API calls (min 5s, max 30s)
- [ ] Retry logic for transient failures (exponential backoff)
- [ ] Circuit breaker for cascading failures
- [ ] Observability: all errors logged with trace_id + error_fingerprint

### Security & Data
- [ ] No secrets in code, config, or logs
- [ ] User IDs hashed if logged (SHA256)
- [ ] No credentials in git history (checked with gitleaks)
- [ ] Sensitive data not persisted longer than needed
- [ ] OWASP Top 10: input validation, SQLi prevention, XSS prevention

### External Dependencies
- [ ] All external APIs have timeout/retry/circuit-breaker
- [ ] Fallback behavior defined if dependency fails
- [ ] Version pinned (no floating versions in prod)
- [ ] License compatible (no AGPL/GPL in proprietary code)

### Operability
- [ ] Configuration externalizable (env vars or config file)
- [ ] Health check endpoint defined
- [ ] Graceful shutdown (drain connections, finish requests)
- [ ] Resource limits defined (CPU, memory)
- [ ] Deployment reversible (feature flag or versioning)

### Code Quality
- [ ] Tests: unit tests for business logic, integration tests for dependencies
- [ ] Coverage: >80% for critical paths
- [ ] No linting errors (eslint, pylint, etc.)
- [ ] No security scan violations (SAST)
- [ ] Performance: no regressions vs. baseline
```

**Checklist Application**:
1. Author fills in checklist before requesting review
2. Reviewer explicitly approves each section (or requests explanation/changes)
3. If unchecked items, reviewer explains why it's not applicable or requests author fix

**Approval Requirement**:
- ✅ Peer review complete (checklist all items addressed)
- ✅ If architecture impact: architecture review approval
- ✅ If test coverage < 80%: explicit exception or tests added
- ✅ If new dependency: license and CVE check

**Who Can Review**:
- Peer: Any engineer from different domain (backend reviews frontend, etc.)
- Architecture: Person listed in CODEOWNERS for that path
- Security: On-call security engineer if secrets/crypto involved

---

### Phase 3: Operational Readiness Gate (Before Merging to Main)

**Gate Owner**: QA/SRE  
**Duration**: 2-4 hours (for high-risk changes)  
**When**: For changes marked "risky" or "new feature"

#### Load Testing Requirements

```bash
# Baseline: current production profile
load_baseline.sh --duration 5m --rps 100  # Current production RPS

# Phase 1: 1x load (current production)
load_test.sh --duration 10m --rps 100
# Verify: P99 latency stable, error rate < 0.1%

# Phase 2: 2x load spike
load_test.sh --duration 10m --rps 200
# Verify: P99 latency < 2x worse, no errors, recovery < 2m

# Phase 3: 5x load sustained
load_test.sh --duration 5m --rps 500
# Verify: P99 latency < 5x worse, error rate < 1%, auto-scaling works

# Phase 4: Chaos (random failures)
chaos_test.sh --duration 5m --failure-rate 0.01 --rps 100
# Verify: Graceful degradation, recovery < 1m, no cascading failures
```

#### Observability Dry-Run

```
Scenario: Simulate p99 latency spike (customer perspective)
- Production load equivalent to Phase 3 (5x)
- Introduce network delay/failure
- Can ops find root cause using logs/traces/metrics in < 5 minutes?

Checklist:
- [ ] Trace ID visible in all logs (can correlate across services)
- [ ] Error message tells operator what to do (not "unknown error")
- [ ] Dashboard shows affected service immediately (color change on status board)
- [ ] Alert fires with runbook link
- [ ] Runbook steps get to root cause in < 5 min
- [ ] Runbook fix tested and works
```

#### Runbook Validation

```
Operator (not author) tests runbook for Phase 1 failure modes:
1. Service down - can operator recover in < 2 min?
2. Config error - can operator fix and rollback in < 5 min?
3. Database connection failing - can operator failover/scale in < 3 min?

Each runbook must:
- Have exact commands (not "check logs")
- Be testable (author runs it on staging)
- Reference observability (where to find evidence)
- Include escalation path
- Be under 500 words
```

#### Deployment Safety

```
Feature flag configuration (before merge):
- [ ] Feature flag is OFF by default
- [ ] Flag can be toggled at runtime (no restart needed)
- [ ] Gradual rollout defined: 1% → 5% → 25% → 100%
- [ ] Rollback tested: toggle off, verify metrics revert

OR if no feature flag possible:
- [ ] Canary deployment defined (1 instance, 5 min)
- [ ] Automatic rollback if error rate > 1%
- [ ] Manual promotion to production after 1 hour

Rollback test checklist:
- [ ] Rollback command runs in < 60 seconds
- [ ] Metrics return to baseline within 2 minutes
- [ ] No data loss on rollback
```

**Approval Requirement**:
- ✅ Load testing passed (all phases green)
- ✅ Observability dry-run successful
- ✅ Runbook validated by ops
- ✅ Feature flag or rollback plan tested

**Waiver Path**:
- Bug fix to existing code: **EXEMPTIBLE** if metrics show low risk
- Config change: **EXEMPTIBLE** if backwards-compatible
- Documentation: **EXEMPT**

---

### Phase 4: Production Acceptance Gate (After Deployment)

**Gate Owner**: Author + On-Call SRE  
**Duration**: 1-2 hours (first hour critical)  
**When**: After code merged and deployed to production

#### Hour 0-1: Author Monitoring

```
Author is responsible for:
1. Monitoring metrics dashboard for regression
   - Latency p99, error rate, throughput
   - Feature-specific metrics (hit rate, etc.)
   
2. Checking logs for errors
   - docker logs app | grep -i error
   - Jaeger UI: filter by trace_id of errors
   
3. Running smoke tests
   - curl health checks
   - User-facing feature verification
   
4. Alert validation
   - New alerts firing (if expected)
   - No spurious alerts
   
5. Prepared for rollback
   - Have revert command ready
   - Know SLA impact if leaving code 30+ min
```

#### Hour 1-4: Passive Monitoring

```
On-call SRE monitors:
- Error rate stays < baseline + 0.5%
- P99 latency stays < baseline + 100ms
- No new alerts firing
- Database replication lag normal
- No customer reports in Slack #incidents
```

#### SLA/SLO Compliance

```
Before closing issue, verify:
1. SLA target from Phase 1 achieved or exceeded
   - Target: P99 < 200ms
   - Actual: P99 = 180ms ✓
   
2. No error budget impact
   - Error budget for month: 0.1% (99.9% SLA)
   - This change impact: -0.02% (good)
   
3. Availability maintained
   - Target: 99.9%
   - Actual: 99.91% ✓
```

#### Production Acceptance Checklist

```markdown
## Production Acceptance Certification for PR #XXX

### Hour 0-1 (Author Monitoring)
- [ ] Metrics dashboard: P99 latency baseline ± 50ms
- [ ] Error rate: < 0.5% above baseline
- [ ] No errors in logs (docker logs | grep error = 0 lines)
- [ ] Feature-specific metrics healthy
- [ ] Smoke tests passing
- [ ] Rollback command tested and ready

### Hour 1-4 (SRE Passive Monitoring)
- [ ] No new incidents reported
- [ ] All alerts expected or cleared
- [ ] No customer complaints in Slack

### SLA/SLO Compliance
- [ ] SLA target achieved: [specific numbers]
- [ ] Error budget impact: [% of monthly budget]
- [ ] Availability maintained: [99.9% or higher]

### Sign-Off
Author: [name] Date: [date]
On-Call SRE: [name] Date: [date]
```

**Sign-Off Required**:
- ✅ Author certifies Hour 0-1 monitoring complete, no issues
- ✅ On-call SRE certifies Hour 1-4 stability verified
- ✅ SLA compliance documented

**If Issues Detected**:
- Minor (< 20% latency increase): Monitor extra hour, then close
- Major (> 20% latency, error rate spike): **ROLLBACK IMMEDIATELY**

---

## 3. IMPLEMENTATION ROADMAP

### Week 3 (Design Phase - Current):
- [ ] Design template approved
- [ ] Routing rules defined (who approves what)
- [ ] Phase 1-4 criteria documented

### Week 3-4 (PR & Automation):
- [ ] PR template updated with Phase 2 checklist
- [ ] CODEOWNERS file updated
- [ ] Peer reviewer assignment automation (GitHub Actions)

### Week 4-5 (Infrastructure):
- [ ] Load testing harness deployed (JMeter/K6)
- [ ] Chaos testing framework (Gremlin/Pumba)
- [ ] Feature flag system (LaunchDarkly or internal)

### Week 5-6 (Operations):
- [ ] Team trained on gate process
- [ ] Runbook template created
- [ ] Post-deploy monitoring dashboard created

### Week 6+ (Continuous):
- [ ] Metrics on gate effectiveness (% of changes certified, incident correlation)
- [ ] Monthly review + refinement

---

## 4. WAIVER & EXCEPTION SYSTEM

**Waiver Request Process**:

```markdown
## Waiver Request: [Issue/PR #XXX]

### Gate Being Waived
- [ ] Phase 1: Design Certification
- [ ] Phase 2: Code Review Checklist
- [ ] Phase 3: Load Testing
- [ ] Phase 4: Production Monitoring

### Justification
Explain why this gate is not applicable or its cost exceeds its benefit:
- Bug fix: existing code paths unchanged
- Config: backwards-compatible, rollback < 10 sec
- Doc: non-code change

### Risk Assessment
- Risk Level: LOW / MEDIUM / HIGH
- Estimated blast radius if wrong: [describe]
- Confidence in fix: [%]

### Approval
- Requester: [engineer name]
- Approver: [engineering lead name]
- Waiver valid for: This change only
```

**Waiver Audit Trail** (tracked in GitHub):
- Waivers logged in excel/database with approval chain
- Monthly audit: correlation between waivers and production incidents
- If > 10% of incidents have waiver, tighten waiver criteria

**Automatic Waivers** (no approval needed):
- Documentation changes
- Non-production scripts (tools, dev aids)
- Test code additions
- Config updates that are backwards-compatible

---

## 5. RESPONSIBILITIES MATRIX

| Phase | Owner | Approver | Escalation |
|-------|-------|----------|---|
| Design | Author | Arch Lead + SRE | VP Engineering |
| Code Review | Peer | Arch Lead | VP Engineering |
| Load Testing | QA/SRE | Tech Lead | VP Eng + Incident Commander |
| Production Acceptance | Author | On-Call SRE | VP Engineering |

---

## 6. SUCCESS METRICS

**Gate Adoption**:
- % of PRs with complete Phase 1 design: target 90% by week 6
- % of issues with runbook links: target 100% by week 6
- Mean time from review start to approval: target < 2 hours

**Production Stability**:
- Incidents with root cause in "gate bypass": target 0
- MTTR improvement: target < 30 min by month 2
- SLA compliance: target 99.9%+ by month 2

---

## 7. ROLLOUT STRATEGY

**Week 1-2**: Voluntary (team learning, optional)
**Week 3+**: Mandatory for high-risk changes (>500 LOC, new services)
**Week 6+**: Mandatory for all non-trivial changes

**Gradual Enforcement**:
- Start with Phase 1 & 2 (design + code review)
- Add Phase 3 & 4 after load testing infrastructure ready
- Measure adoption and adjust criteria

---

**Document Owner**: Architecture + QA Team  
**Last Updated**: April 15, 2026  
**Next Review**: April 29, 2026 (after Phase 1-2 piloting)  
**Status**: DESIGN COMPLETE - READY FOR IMPLEMENTATION
