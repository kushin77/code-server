# Production Readiness Gate Runbook

## Purpose

Operational runbook for the four-phase production-readiness process defined in issue #381.

## Scope

Applies to all non-trivial pull requests that modify runtime behavior, infrastructure, CI/CD, security controls, or service-facing logic.

## Phase Routing

1. Phase 1: Design Certification
- Owner: Architecture reviewer
- Required: SLA target, failure mode analysis, rollback strategy, observability plan

2. Phase 2: Code and Quality Review
- Owner: Non-author reviewer
- Required: security checklist, tests, observability instrumentation, CI pass

3. Phase 3: Performance and Load Validation
- Owner: Reliability/performance reviewer
- Required: baseline and stress profile (1x, 2x, 5x), p50/p99 latency and error-rate report

4. Phase 4: Operational Readiness
- Owner: On-call/operations reviewer
- Required: rollout strategy, rollback command, runbook updates, alert mapping

## Execution Checklist

1. Open PR using .github/pull_request_template.md.
2. Fill all required gate sections.
3. Run load test script (see scripts/loadtest/k6-baseline.js) and attach summary.
4. Verify deployment strategy and rollback command are documented.
5. Ensure readiness-gate CI check passes before merge.

## Incident Drill Procedure

1. Simulate a controlled failure in staging.
2. Validate detection through logs/metrics/traces.
3. Execute rollback command and record elapsed time.
4. Attach drill evidence to linked issue.

## Waiver Process

1. Create a waiver issue referencing the target PR and gate phase.
2. Include reason, compensating controls, and expiration date.
3. Add link to waiver issue in PR body.
4. Post-merge, close waiver issue only after corrective action is delivered.

## Evidence Requirements

- PR link and linked issue
- CI run URL for readiness-gate pass
- Load test artifact snippet
- Rollback command and observed rollback time
- On-call acknowledgement comment
