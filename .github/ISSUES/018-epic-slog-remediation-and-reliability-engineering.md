---
title: "EPIC: SLOG remediation and reliability engineering"
labels: [epic, P1-high, component/observability, component/reliability, component/platform, status/ready, effort/l]
assignees: []
---

## Goal
Deliver fleet-grade observability and bounded auto-remediation that reduces incident impact without causing cascading failures.

## Scope
- SLOG schema, taxonomy, and ingestion pipeline.
- Rule-based remediation with risk classes and human override.
- Reliability KPIs and incident traceability.

## Detailed Work Items
- [ ] Publish canonical SLOG schema and required fields.
- [ ] Implement correlation-id end-to-end across portal and runtime.
- [ ] Build remediation policy engine with cooldown and retry ceilings.
- [ ] Add manual override and emergency disable controls.
- [ ] Add dashboards for incident frequency, MTTR, and remediation success.

## Acceptance Criteria
- [ ] High-value events are captured with deterministic schema validation.
- [ ] Remediation actions are fully auditable with before and after state.
- [ ] High-risk remediations require explicit approval path.
- [ ] MTTR and repeat-incident metrics improve against baseline.

## Dependencies
- Parent: #014
- Related: #011, #291

## Definition Of Done
- [ ] Schema and ingestion tests green.
- [ ] Reliability dashboards and alert routes operational.
- [ ] Incident review template and runbook published.
