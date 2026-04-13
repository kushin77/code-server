# ADR Template

Use this template for all Architecture Decision Records.

---

# [NNN]. [Title]

**Status**: [DRAFT | Accepted | Superseded | Deprecated]
**Date**: [YYYY-MM-DD]
**Author(s)**: [@github-username]
**Related ADRs**: [Links to related ADRs, if any]
**Supersedes**: [ADR number if replacing previous decision]

---

## Contex

What is the issue we are addressing?

Explain:
- Problem statemen
- Why it matters
- Current state/pain points
- Constraints or limitations we're working within

---

## Decision

**What did we decide to do?**

Provide a clear, actionable decision statement.

---

## Alternatives Considered

List at least 2-3 alternatives with tradeoffs:

### Alternative 1: [Name]
**Pros**:
-

**Cons**:
-

**Why not chosen**:

### Alternative 2: [Name]
**Pros**:
-

**Cons**:
-

**Why not chosen**:

---

## Consequences

### Positive Consequences
-
-

### Negative Consequences (Accepted Risks)
-
-

---

## Security Implications

How does this decision affect security posture?

- **Trust boundaries**: [How does this affect our trust model?]
- **Attack surface**: [Does this expand or reduce attack surface?]
- **Data exposure**: [Any new data exposure risks?]
- **Authentication/Authorization**: [Implications for Auth?]
- **Mitigation strategy**: [How do we mitigate identified risks?]

---

## Performance & Scalability Implications

- **Horizontal scaling**: [Can this scale horizontally? How?]
- **Bottlenecks**: [What could limit scale?]
- **Resource usage**: [CPU/memory/network implications?]
- **Latency**: [P99 latency assumptions/targets?]
- **Throughput**: [Expected throughput capacity?]

---

## Operational Impac

- **Deployment**: [How does this change deployment?]
- **Monitoring**: [What must we monitor?]
- **Alerting**: [Alert thresholds/conditions?]
- **Rollback**: [Can we rollback? How?]
- **On-call**: [What new skills/knowledge needed?]

---

## Implementation Notes

Any implementation specifics that should be documented:
- Phased rollout plan (if applicable)
- Migration strategy (if applicable)
- Dependencies on other systems

---

## Validation Criteria

How will we know this decision was the right one?

- [ ] Metric 1: [e.g., P99 latency < 100ms]
- [ ] Metric 2: [e.g., 99.9% availability achieved]
- [ ] Metric 3: [e.g., On-call volume reduced]

---

## References

- [Link 1: RFC or design doc]
- [Link 2: External precedent]
- [Link 3: Related ticket or issue]

---

## Sign-off

- [ ] Technical review: @reviewer1
- [ ] Security review: @reviewer2
- [ ] Operations review: @reviewer3
- [ ] Architecture consensus: @reviewer4
