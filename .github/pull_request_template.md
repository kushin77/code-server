# [TYPE] PR Title: [Descriptive title]

> **🎯 PRODUCTION READINESS FRAMEWORK**: All PRs follow a 4-phase quality gate system (Design → Code → Performance → Operations). Complete each phase before merging to main.

## Linked Issues

**This PR resolves (REQUIRED - use one of: `Closes`, `Fixes`, `Resolves`):**
```
Closes #[issue-number]
Fixes #[another-issue]
Resolves #[third-issue]
```

**Linked ADR** (if architectural change):
```
See ADR #XXX in docs/adr/
```

> **ℹ️ Why**: Our auto-merge pipeline closes linked issues when your code deploys. This creates a complete audit trail from issue → code → production.

---

## Phase 1: Design Certification ✓

> **Gate Owner**: @architecture-team  
> **Must complete before Phase 2 begins**

**Primary decision**:
- [ ] No architectural impact (skip Phase 1 detailed items, proceed to Phase 2)
- [ ] Architectural change (complete all Phase 1 items below)

**If architectural change, complete these:**
- [ ] ADR written and peer-reviewed (see [ADR Template](../../docs/adr/TEMPLATE.md))
- [ ] Horizontal scaling considered and documented
- [ ] Failure isolation strategy defined
- [ ] Dependency changes listed and approved
- [ ] Security threat model documented (STRIDE analysis or equivalent)
- [ ] Trust boundaries identified
- [ ] Data flow diagram included (if handling PII/secrets)

**Design Review Certification** (by @architecture-team):
- [ ] Reviewer: `@[github-user]`
- [ ] Comments: `[Link to design review thread or approval comment]`

---

## Phase 2: Code & Quality Review ✓

> **Gate Owner**: @code-review-team  
> **Automatically checked by CI; manual review required**

### Security
- [ ] No secrets, credentials, or sensitive data in code  
- [ ] Input validation implemented (if applicable)
- [ ] IAM/authorization reviewed (if applicable)
- [ ] No public endpoints without authentication (if applicable)
- [ ] Encryption at rest and in transit (if handling sensitive data)
- [ ] Least privilege principle applied
- [ ] Secret scan result: ✅ PASS / ⚠️ REVIEW / ❌ FAIL

### Code Quality
- [ ] Lint checks passing (GitHub Actions)
- [ ] SAST scan passing (semgrep, trivy, etc.)
- [ ] No test skips (`@skip`, `.skip()`, etc.)
- [ ] Complexity metrics acceptable (cyclomatic complexity < 10)
- [ ] Code review approved by >= 1 senior engineer

### Testing
- [ ] Unit tests added/updated (target: 80%+ coverage on modified code)
- [ ] Integration tests added/updated (if cross-service changes)
- [ ] Coverage maintained or improved
- [ ] Manual testing completed and documented
- [ ] E2E tests passing (if UI-facing)

### Observability
- [ ] Structured logging implemented (correlation IDs included)
- [ ] Metrics added (Prometheus format if applicable)
- [ ] Health endpoints updated (if new service)
- [ ] Distributed tracing enabled (OpenTelemetry headers if applicable)

---

## Phase 3: Performance & Load Testing ✓

> **Gate Owner**: @performance-team  
> **Required for core services and high-impact changes**

**Exemption** (check if applicable):
- [ ] Change is documentation-only (skip Phase 3)
- [ ] Change is test code only (skip Phase 3)
- [ ] Change is non-critical or internal utility (skip Phase 3)
- [ ] **Performance testing required** (complete all items below)

**Performance Testing**:
- [ ] Benchmarked against baseline (before/after comparison)
- [ ] Load test scenarios defined (1x, 2x, 5x, 10x current traffic)
- [ ] Latency p50/p99 measured and acceptable
- [ ] Resource limits defined (CPU, memory, connections)
- [ ] No N+1 query patterns (database or API)
- [ ] Horizontal scaling validated (if applicable)

**Load Test Results**:
```
Baseline (before): [X ms p99 latency, Y requests/sec]
After this PR:     [X ms p99 latency, Y requests/sec]
Change:            [+/- Z%]
Test scenario:     [Description of test (1x, 2x, 5x, etc.)]
Test duration:     [Minutes]
```

---

## Phase 4: Operational Readiness ✓

> **Gate Owner**: @operations-team  
> **Required before production deployment**

**Deployment Planning**:
- [ ] Backward compatible (safe to deploy independently)
- [ ] Requires database migration: YES / NO (if yes, migration script attached)
- [ ] Requires configuration change: YES / NO (list below)
- [ ] Deployment strategy: `rolling` / `blue-green` / `canary` / `feature-flag`

**If feature-flagged deployment:**
- [ ] Feature flag defined in feature store (LaunchDarkly / internal system)
- [ ] Rollout strategy documented (1% → 10% → 50% → 100%)
- [ ] Kill switch procedure documented (how to disable if issues found)

**Rollback Plan**:
- [ ] Time to rollback: [X minutes]
- [ ] Rollback command: `[git revert / terraform destroy / helm rollback / etc.]`
- [ ] Data consistency on rollback: [What happens to in-flight data?]
- [ ] Dependent services affected: [List services that depend on this]

**Runbook & Troubleshooting**:
- [ ] Runbook updated: [Link to runbooks.md section]
- [ ] Common failure scenarios documented
- [ ] How to detect failure (logs, metrics, alerts)
- [ ] Escalation path defined

**Monitoring & Alerts**:
- [ ] Prometheus metrics defined (new or updated)
- [ ] Grafana dashboard updated (if applicable)
- [ ] Alerting rules added (SLO violations trigger alerts)
- [ ] Alert runbook linked
- [ ] On-call team trained

**Documentation**:
- [ ] README updated (if user-facing change)
- [ ] API docs updated (if API change)
- [ ] Architecture docs updated
- [ ] Deployment guide updated (if process changed)



---

## Risk Assessment

**What breaks if this fails?**

[Describe failure scenarios and their impact]

**How do we detect failure?**

[Alerts, logs, metrics, or manual checks]

**Blast radius**: `ONE service` / `Multiple services` / `Critical path` / `Non-critical`

---

## CI/CD & Merge Requirements

- [x] All 4 phases of quality gates completed
- [ ] All automated checks passing (lint, SAST, dependency scan)
- [ ] Code review approved (GitHub CODEOWNERS)
- [ ] Architecture review approved (for architectural changes)

**Do NOT merge if:**
- Any Phase gate is incomplete
- Any required check is failing
- Any blocker comment from reviewers

---

**Checklist**: Once all 4 phases are complete, this PR is eligible for merge. The main branch is protected—merge is automatic when all checks pass and reviewers approve.
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
