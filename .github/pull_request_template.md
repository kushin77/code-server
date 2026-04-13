# PR Title: [Descriptive title]

> **🤖 AUTO-DEPLOY MANDATE**: When this PR is merged, it automatically triggers branch cleanup and production deployment. Link issues below so they auto-close when code goes live.

## Linked Issues

**This PR resolves (REQUIRED - use one of: `Closes`, `Fixes`, `Resolves`):**
```
Closes #[issue-number]
Fixes #[another-issue]
Resolves #[third-issue]
```

> **ℹ️ Why**: Our auto-merge pipeline closes linked issues when your code deploys. This creates a complete audit trail from issue → code → production.

---

## Summary

**What problem does this solve?** Replace this with a clear, 2-3 sentence explanation of the problem statement.

**Why is this change necessary?** Explain the business or technical drivers.

---

## Architecture Impac

- [ ] No architectural impact (minor fix/optimization)
- [ ] ADR exists and is linked
- [ ] NEW ADR required — see [docs/adr/TEMPLATE.md](../../docs/adr/TEMPLATE.md)

**If architectural change:**
- ADR Path: `docs/adr/XXX-[description].md
- Horizontal scaling considered: YES / NO / N/A
- Failure isolation: [Brief description]
- Dependency changes: [List any new external dependencies]

---

## Security Review

- [ ] No secrets, credentials, or sensitive data in code
- [ ] Input validation implemented (if applicable)
- [ ] IAM/authorization reviewed (if applicable)
- [ ] No public endpoints without authentication (if applicable)
- [ ] Encryption at rest and in transit (if handling sensitive data)
- [ ] Least privilege principle applied

**If new service or auth change:**
- [ ] Threat model documented
- [ ] Trust boundaries defined
- [ ] STRIDE/threat analysis attached (link or description)

**Secrets scanning result**: ✅ PASS / ⚠️ REVIEW / ❌ FAIL

---

## Performance & Scalability

- [ ] No blocking operations in critical path
- [ ] No N+1 query patterns (database or API)
- [ ] Resource limits defined (CPU, memory, connections)
- [ ] Benchmarked or profiled: YES / NO / N/A
- [ ] Horizontal scaling validated: YES / NO / N/A

**Performance impact** (if applicable):
- Latency: [p50/p99 if measured]
- Throughput: [requests/sec or ops/sec if measured]
- Resource usage: [CPU/memory/connections]

---

## Observability

- [ ] Structured logging implemented (correlation IDs where needed)
- [ ] Metrics added (Prometheus format if applicable)
- [ ] Health endpoints implemented (if new service)
- [ ] Distributed tracing enabled (OpenTelemetry ready if applicable)
- [ ] Runbook/troubleshooting guide updated

**Logs/Metrics**:

[Example log output or metric name]


---

## Testing & Quality

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Coverage maintained or improved (target: 80%+)
- [ ] Manual testing completed
- [ ] Lint/static analysis passing
- [ ] No test skips (`@skip`, `.skip()`, etc.)

**Test results**:

Coverage: XX%
Tests passing: YY/YY


---

## Deployment & Rollback

**How does this deploy?**
- [ ] Backward compatible (safe to deploy independently)
- [ ] Requires database migration (if yes, migration script attached)
- [ ] Requires configuration change (list below)
- [ ] Blue-green / canary required (explain)

**Rollback plan:**
- Time to rollback: [X minutes]
- Rollback command:

  [git revert / terraform destroy / helm rollback / etc.]

- Data considerations: [What happens if we revert?]
- Dependent services affected: [List any services that depend on this]

---

## Documentation Updates

- [ ] Code comments added (complex logic)
- [ ] README updated (if user-facing change)
- [ ] ADR/Architecture docs updated
- [ ] Runbook/operations guide updated (if operational impact)
- [ ] Deployment guide updated (if deployment process changed)

---

## Risk Assessmen

**What breaks if this fails?**
[Describe failure scenarios and their impact]

**How do we detect failure?**
[Alerts, logs, metrics, or manual checks]

**Blast radius**: [ONE service / Multiple services / Critical path / Non-critical]

---

## CI/CD Status

- [ ] All automated checks passing
- [ ] SAST scan passing
- [ ] Dependency scan passing
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
