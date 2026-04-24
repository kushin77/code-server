---
title: "Fleet SLOG and auto-remediation engine with safety rails and human override"
labels: [enhancement, P1-high, component/observability, component/platform, component/reliability, status/ready, effort/l, needs-design]
assignees: []
---

## Goal
Implement structured logs plus safe auto-remediation for workstation and portal components to reduce MTTR without introducing autonomous outage amplification.

## Why This Is Critical
The brainstorm pushes autonomous remediation. Without guardrails, auto-fixes can cause cascading failures or hide root cause.

## Scope
- Canonical JSON SLOG schema for control-plane and workstation events.
- Rule engine for remediation actions with safety gates.
- Human override and kill switch for remediation classes.

## Out Of Scope
- Unbounded autonomous patching with no approval path.
- Remediation actions that alter security baseline without audit.

## Acceptance Criteria
- [ ] SLOG schema versioned and published in docs/observability/slog-schema.md.
- [ ] Event taxonomy covers auth, policy, bootstrap, tunnel, resource health, and security signals.
- [ ] Remediation policies include severity thresholds, cooldown windows, and max retry limits.
- [ ] Every remediation action logs before, during, and after state with correlation id.
- [ ] Human override path implemented with role-based approval for high-risk actions.
- [ ] Dashboard provides fleet health, remediation success rate, and top recurring incidents.
- [ ] Post-incident export includes timeline and decision trace.

## Safety Requirements
- Remediation actions classified by risk level.
- High-risk actions require explicit policy flag and approval workflow.
- Automatic rollback required for failed remediations.

## Dependencies
- Parent: #650
- Related: #291, #655

## Closure
SLOG pipeline live, remediation engine running with guardrails, and reliability KPIs improved against baseline.
