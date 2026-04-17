# Production Readiness Certification Framework

**Status**: Phase 1 Design Quality Gate (active)  
**Last Updated**: April 17, 2026  
**Owner**: Platform Engineering

## Overview

This document defines the **four-phase production-readiness certification process** that gates all non-trivial code changes to ensure elite standards for reliability, performance, security, and operability.

### Why This Matters

- **Proactive Quality**: Shift quality gates left (pre-review instead of post-deployment)
- **Risk Mitigation**: Reduce incident rate by catching systemic issues before they reach production
- **Blast Radius Control**: Ensure every change has a documented rollback plan
- **Team Accountability**: Clear ownership of reliability, performance, and operational outcomes

---

## Phase 1: Design Quality Gate

**When**: Before implementation / PR creation  
**Duration**: 1-3 days (async)  
**Approvers**: Architecture owner (or senior peer) + on-call reliability engineer  
**Blocker**: YES — no implementation review without Phase 1 approval

### Phase 1 Checklist

Every PR must include a comment with this section completed (see examples below):

```markdown
## Phase 1: Design Quality Gate

- [ ] **SLA Target**: Documented availability, latency, and throughput impact
- [ ] **Failure Mode Analysis**: What breaks if this fails? What's the blast radius?
- [ ] **Rollback Plan**: Can this be rolled back in < 60 seconds? Feature-flagged?
- [ ] **Observability**: What metrics/logs/traces prove this is working?
- [ ] **Design Approval**: ✅ @architecture-owner @on-call-engineer
```

### Phase 1 Requirements

#### SLA Target
Define what availability/latency/throughput this change improves or maintains:

**Good example**:
> SLA: Maintain P99 latency < 50ms for GET /ide route (currently 45ms).  
> Throughput: Support 10x concurrent connections (1000 → 10,000).  
> Availability: 99.99% (4x 9s, <43 seconds downtime/month).

**Bad example**:
> "Improve performance" (too vague)

#### Failure Mode Analysis
What are the failure modes? What's the blast radius?

**Good example**:
> **Failure Mode 1**: Connection pool exhaustion → all /ide requests timeout.  
> **Blast Radius**: All IDE users affected; 30 seconds to detect; 120 seconds to roll back.  
> **Failure Mode 2**: Memory leak in session cache → Caddy OOM → full outage.  
> **Blast Radius**: Entire proxy layer down; cascading failures to all routes.

**Bad example**:
> "Something might break" (not specific enough)

#### Rollback Plan
Can this be rolled back in < 60 seconds? Is there a feature flag?

**Good example**:
> **Rollback**: Revert commit + `docker-compose restart caddy` (30s).  
> **Feature Flag**: SESSION_CACHING_ENABLED (can disable in .env, no restart).  
> **Tested**: Rollback tested on staging and timed at 25s.

**Bad example**:
> "Just revert the code" (no timing, no validation)

#### Observability Plan
What metrics/logs/traces prove this is working AND failing?

**Good example**:
> **Success**: Prometheus `session_cache_hits` > 0.8 hit rate.  
> **Failure Signal**: `session_cache_miss_rate` > 0.5 (indicates cache ineffective).  
> **Alert**: Fire if `session_latency_p99` > 100ms for > 5 minutes.  
> **Trace**: Caddy access logs include `cache_hit=true/false` tag.  
> **Dashboard**: https://grafana.example.com/d/session-cache-health

**Bad example**:
> "Check logs" (no specific metrics defined)

### Phase 1 Approval Process

1. **Author** posts Phase 1 checklist in PR
2. **Architecture Owner** reviews SLA/failure modes (24h SLA)
3. **On-Call Reliability Engineer** reviews rollback/observability (24h SLA)
4. **Both approve** → Phase 2 (implementation review) can proceed
5. **Waiver**: If no architecture owner assigned, any 2 senior engineers can approve

### Phase 1 Examples

#### ✅ Good: Session Cache Refactor
```markdown
## Phase 1: Design Quality Gate ✅

- [x] **SLA Target**: 
  - P99 latency < 50ms (current 45ms, change adds max +5ms overhead)
  - Availability: 99.99% (feature-flagged, no unavailability if disabled)
  - Cache hit rate: >80% in production

- [x] **Failure Mode Analysis**:
  1. Cache memory exhaustion → evict by age → some sessions re-fetched (degraded performance, NOT outage)
  2. Cache corruption → invalid tokens → user re-login (acceptable fallback)
  3. Feature flag flip to disable caching → no latency impact (fast rollback)

- [x] **Rollback Plan**:
  - Immediate: Set `SESSION_CACHE_ENABLED=false` in .env (5s, no restart)
  - Fallback: Revert commit + `docker-compose restart caddy` (30s)
  - Tested: Verified both on staging; confirmed <35s total time

- [x] **Observability**:
  - Success: `session_cache_hits_total`, `session_cache_misses_total` (Prometheus)
  - Failure: Alert if `session_latency_p99 > 60ms` for >5min OR `cache_hit_rate < 0.7`
  - Traces: OpenTelemetry span attribute `cache.hit=true/false`
  - Logs: Structured field `cache_operation=hit|miss|evict`
  - Dashboard: `https://grafana.example.com/d/abc123`

- [x] **Design Approval**:
  ✅ @akushnir (architecture lead)
  ✅ @reliability-oncall (verified rollback timing)
```

#### ❌ Bad: Session Cache Refactor (missing details)
```markdown
## Phase 1: Design Quality Gate

- [ ] **SLA Target**: Better performance

- [ ] **Failure Mode Analysis**: It might fail

- [ ] **Rollback Plan**: Just revert the PR

- [ ] **Observability**: Check logs
```

---

## Phase 2: Implementation Quality Gate

**When**: Code review (after Phase 1 approval)  
**Duration**: 1-2 days  
**Approvers**: Peer reviewer (different domain) + architecture reviewer (if new pattern)  
**Blocker**: YES — no merge without Phase 2 approval

### Phase 2 Checklist

Code reviewers must verify:

- [ ] **Horizontal Scalability**: No N+1 queries, no shared mutable state, connection pooling validated
- [ ] **Error Handling**: All code paths handle errors (no silent failures); timeout/retry/circuit-breaker on external APIs
- [ ] **Security**: No rotation keys/auth tokens/credentials in logs; no SQL injection; proper auth checks
- [ ] **Observability**: Implements metrics/traces/logs from Phase 1 observability plan
- [ ] **Testability**: Unit tests cover >90% of code paths; integration tests validate failure modes
- [ ] **Documentation**: README/runbook updated; examples provided if public API
- [ ] **Peer Review**: At least 1 engineer NOT the author, ideally from different team domain
- [ ] **Architecture Review** (if applicable): New service/component/pattern reviewed against standards

---

## Phase 3: Operational Readiness Gate

**When**: Before merge to main (or staging for final ops validation)  
**Duration**: 2-3 days  
**Approvers**: On-call operations engineer + performance engineer  
**Blocker**: YES — no production deployment without Phase 3 sign-off

### Phase 3 Requirements

1. **Load Testing**: Validate at 1x, 2x, 5x peak load + chaos scenarios
2. **Observability Dry-Run**: Can ops find issues using Phase 1 observability plan?
3. **Runbook Validation**: Incident response follows runbook in < 5 minutes
4. **Deployment Strategy**: Feature flag or gradual rollout configured; rollback tested

---

## Phase 4: Production Acceptance Gate

**When**: After deployment to production  
**Duration**: 1 hour  
**Approvers**: Author (primary) + on-call engineer (backup)  
**Blocker**: YES — must complete before closing associated issue

### Phase 4 Checklist

- [ ] **1-Hour Post-Deploy Monitoring**: Author actively monitoring metrics/logs/dashboards
- [ ] **SLA/SLO Compliance**: Achievement vs. Phase 1 target verified; no SLA breach
- [ ] **Error Budget**: Impact quantified and approved (if any impact)
- [ ] **Incident Response**: If any issue detected, runbook executed successfully or escalated
- [ ] **Certification**: Author signs off on production acceptance

**Example**:
```markdown
## Phase 4: Production Acceptance ✅

- [x] Monitoring Period: 2026-04-17 14:30 → 15:30 UTC
- [x] SLA Status: P99 latency 48ms (target <50ms) ✅; hit rate 82% (target >80%) ✅
- [x] Error Budget: 0% impact (new feature, no existing traffic affected)
- [x] Incidents: None detected
- [x] Author Certification: @akushnir — READY FOR PRODUCTION

Issue ready to close.
```

---

## Non-Trivial vs. Trivial Changes

**Non-Trivial** (requires full 4-phase gate):
- Any backend/service code changes (API, database, cache, auth)
- Infrastructure changes (Dockerfile, docker-compose, Terraform)
- Security-related changes (auth, secrets, crypto)
- Performance-critical changes (caching, optimization)

**Trivial** (skip phases; document in PR):
- Documentation updates (README, runbooks)
- Comment clarifications (no logic change)
- Dependency updates (security patches)
- Test-only changes

**Ambiguous**: Post in PR and ask architecture owner.

---

## Waivers and Overrides

If a phase cannot be completed (e.g., load testing unavailable, architecture owner unavailable for 24h+):

1. **Document the constraint** in PR comments
2. **Request waiver** with justification: `@platform-team waiver: Phase 3 load testing — ops bandwidth constraint`
3. **Acceptance**: 2 senior engineers OR architecture owner must approve
4. **Audit trail**: Waiver logged in issue for retrospective

---

## Integration with CI/CD

### GitHub Actions Integration

CI workflow will enforce:

1. **Phase 1 Required Check**: PR cannot be merged without Phase 1 checklist comment
2. **Phase 2 Required Check**: At least 1 approval from non-author
3. **Phase 3 Required Check**: Blocking status (manual approval workflow)
4. **Phase 4 Required Check**: Issue cannot be closed without Phase 4 comment

### Manual Workflows

Pending implementation in Phase 1b:
- Design approval routing (Slack → GitHub)
- Peer review assignment (CODEOWNERS-based)
- Post-deploy monitoring checklist automation

---

## FAQ

**Q: Does this apply to every PR?**  
A: Only non-trivial changes. Documentation, tests, and minor fixes are exempt (but document in PR).

**Q: Can we skip a phase?**  
A: Only with documented waiver + 2 approvals. See "Waivers and Overrides".

**Q: What if the architecture owner is unavailable?**  
A: Any 2 senior engineers can approve Phase 1 design (but log as waiver for audit).

**Q: How long does this take?**  
A: Async + parallelizable: 3-5 days typical (depends on complexity and team availability).

**Q: What if Phase 4 finds issues?**  
A: Trigger incident response using runbook from Phase 1. Rollback if needed. Post-mortem to prevent recurrence.

---

## Rollout Timeline

**Week 1 (Apr 17)**: PR template + documentation  
**Week 2 (Apr 22)**: CI checks enabled (Phase 1 required comment)  
**Week 3 (Apr 29)**: Design approval workflow (Slack integration)  
**Week 4 (May 6)**: Peer review automation (CODEOWNERS)  

---

## Related Docs

- [docs/SCRIPT-WRITING-GUIDE.md](SCRIPT-WRITING-GUIDE.md) — Code standards
- [copilot-instructions.md](.github/copilot-instructions.md) — Governance rules
- [docs/governance/](governance/) — Full governance framework
