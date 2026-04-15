# Production Readiness Quality Gates

**Phase 1: Design Review** (Author + 1 Reviewer) - 🔴 MANDATORY FOR: feature, api, infra, breaking changes  
**Phase 2: Code Review** (2 Senior Engineers) - ✅ Automated via CODEOWNERS  
**Phase 3: Operational Readiness** (SRE) - 🟡 Required for: deployments, ops changes  
**Phase 4: Production Acceptance** (On-call) - 🟡 Final sign-off before merge to main  

---

## ✅ PHASE 1: DESIGN REVIEW (If Applicable)

> **Skip if**: Documentation only, tests only, trivial bug fixes, refactoring with zero behavior change

**This change is a:**
- [ ] 🟢 Bug fix (no design review needed, proceed to Phase 2)
- [ ] 🟡 Enhancement/optimization (design review recommended)
- [ ] 🔴 New feature/API/infrastructure (design review **REQUIRED**)
- [ ] 🔴 Breaking change/architecture change (design review **REQUIRED**)

### Design Phase Checklist (If applicable)

**Architecture**:
- [ ] Horizontal scalability validated (can run 10x current load)
- [ ] Stateless design (no shared mutable state)
- [ ] Dependencies bounded + explicit (no implicit coupling)
- [ ] Failure isolation (circuit breakers, bulkheads)
- [ ] No single points of failure (redundancy documented)

**Data & Persistence**:
- [ ] Data model defined (schema or document structure)
- [ ] No data loss on failure (persistence, replication strategy)
- [ ] Migration path for existing data (if schema change)
- [ ] Backup/restore procedure documented
- [ ] GDPR/compliance considerations addressed

**Deployment & Rollback**:
- [ ] Feature flag required? `__FEATURE_FLAG__`: YES / NO / N/A
- [ ] Rollback strategy (git revert time): **&lt; 60 seconds**
- [ ] Canary deployment needed: YES / NO
- [ ] Blue-green deployment procedure: YES / NO / N/A
- [ ] Database migration is backward compatible: YES / NO / N/A

**Design Documentation:**
- [ ] Design doc linked (Confluence, GitHub issue, ADR)
- [ ] Signed off by: @[architecture-reviewer]
- [ ] **ADR Created**: `docs/adr/XXX-[title].md` (if architecture change)

---

## ✅ PHASE 2: CODE REVIEW (REQUIRED - 2 Approvals)

**Linked Issues**:
```
Closes #[issue-number]
Fixes #[another-issue]
Resolves #[third-issue]
```

### Code Quality

- [ ] Security: No secrets, no hardcoded credentials, input validation
- [ ] Lint/format: Code formatted (prettier, gofmt, black, etc.)
- [ ] Test coverage: ≥80% for business logic (or explain deviation)
- [ ] No blocking I/O in critical path
- [ ] No N+1 query patterns
- [ ] Error handling implemented (no silent failures)
- [ ] Logging: Structured logs with correlation IDs (if applicable)

### Observability

- [ ] Metrics added (Prometheus, application-level)
- [ ] Health endpoints working (if new service)
- [ ] Distributed tracing enabled (OpenTelemetry propagation)
- [ ] Runbook/troubleshooting guide updated
- [ ] Alerts configured (if operational impact)

### Testing & Quality

- [ ] Unit tests: ✅ PASS (XX% coverage)
- [ ] Integration tests: ✅ PASS
- [ ] Lint/static analysis: ✅ PASS
- [ ] SAST scan: ✅ PASS
- [ ] Container scan: ✅ PASS (if Docker image change)
- [ ] Dependency scan: ✅ PASS (no high/critical CVEs)
- [ ] Manual testing: ✅ COMPLETE

### Documentation

- [ ] Code comments: Clear (complex logic explained)
- [ ] README updated: YES / NO / N/A
- [ ] API documentation: Updated (if API change)
- [ ] Deployment guide: Updated (if deployment process changed)

---

## ✅ PHASE 3: OPERATIONAL READINESS (SRE Sign-Off)

> **Required for**: Infrastructure changes, deployment procedure changes, monitoring/alerting changes

**Deployment & Monitoring**:
- [ ] Terraform plan reviewed (if IaC change)
- [ ] No hardcoded values (all config externalized)
- [ ] Immutable versions pinned (no `latest` tags in prod)
- [ ] Health checks configured (readiness + liveness)
- [ ] Monitoring/alerts configured
- [ ] Runbook for incident response attached
- [ ] MTTR SLA defined (target resolution time)

**Load Testing** (if applicable):
- [ ] Load test executed: 1x current production load
- [ ] p99 latency stable (≤ 2x baseline)
- [ ] Error rate: &lt; 0.1%
- [ ] Resource usage normal (CPU &lt; 70%, memory &lt; 80%)
- [ ] Database connection pool: No exhaustion
- [ ] Network: No packet loss

**Chaos Testing** (if applicable):
- [ ] Failure injection scenarios tested (service down, network delay)
- [ ] Graceful degradation working
- [ ] Automatic recovery validated
- [ ] User impact documented

**Rollback Validation**:
- [ ] Rollback command: `[command]`
- [ ] Rollback time: **&lt; 60 seconds** ✅
- [ ] RTO SLA: [X minutes]
- [ ] RPO SLA: [Y minutes]
- [ ] Data consistency validated after rollback

---

## ✅ PHASE 4: PRODUCTION ACCEPTANCE (Final Gate)

> **On-call engineer**: Sign off that change is production-ready

**Final Verification**:
- [ ] All phases complete (phases 1-3 checked)
- [ ] All automated checks passing
- [ ] No blocking issues or TODOs
- [ ] Team trained on rollback procedure
- [ ] On-call acknowledgment: @[oncall-engineer]

**Post-Deployment Monitoring**:
- [ ] Deploy to canary first (1% traffic) — 5 min monitoring
- [ ] Automatic rollback on error rate spike (&gt;1%)
- [ ] Manual promotion to 10% → 50% → 100%
- [ ] 1-hour post-deploy monitoring by author
- [ ] Mark issue complete only after 24-hour stability

---

## Summary

**What problem does this solve?**
[Clear, 2-3 sentence description of the problem]

**Why is this change necessary?**
[Business or technical drivers]

**Metrics after deployment:**
- Latency p99: [before] → [after] (target: &lt;2% regression)
- Throughput: [before] → [after]
- Error rate: [before] → [after]
- Resource usage: [before] → [after]

---

## Checklist Summary

```
PHASE 1 (Design):     [✅ / ⏭️ skipped]
PHASE 2 (Code):       [✅ required - 2 approvals]
PHASE 3 (Operations): [✅ required if deployment]
PHASE 4 (Production): [⏳ final sign-off before merge]
```

---

**By merging this PR, you acknowledge that this change meets production-first standards and is safe to deploy to 192.168.168.31 immediately.**

For exceptions or waivers, contact: @[engineering-lead]

---

**Related Documentation**:
- [Production Readiness Framework](../../docs/PRODUCTION-READINESS-FRAMEWORK.md)
- [Code Review Standards](../../CONTRIBUTING.md#code-review-standards)
- [Deployment Procedure](../../DEPLOYMENT-EXECUTION-PROCEDURE.md)
- [SLO & Monitoring](../../monitoring/README.md)
- [ ] Secrets scan passing
- [ ] Container scan passing (if Docker image)
- [ ] IaC policy passing (if Terraform/Helm)
- [ ] Artifact versioned and signed

🔴 **Any check failure = address before merge.**

---

## Reviewer Checklis

Reviewers verify:

- [ ] Architecture aligns with ADRs
- [ ] Security threat model reviewed
- [ ] Performance assumptions validated
- [ ] All tests present and meaningful
- [ ] Observability sufficient for production
- [ ] Documentation complete
- [ ] Rollback strategy realistic
- [ ] Risk assessment accurate

---

## Related Issues

Closes: #[ISSUE_NUMBER]
Relates to: #[ISSUE_NUMBER]

---

## Additional Contex

[Add any additional context, screenshots, links, or considerations here]
