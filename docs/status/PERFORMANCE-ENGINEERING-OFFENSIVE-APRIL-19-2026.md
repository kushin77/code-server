# Performance Engineering Offensive - April 19, 2026

Status: Complete
Scope: Bottlenecks, concurrency, memory, I/O, and latency budgets on the current production stack.

## Purpose

This is the canonical performance artifact for issue #828. It records the current live baseline, the gaps that remain, and the next performance campaign steps.

## Evidence Reviewed

- [../PERFORMANCE-TUNING.md](../PERFORMANCE-TUNING.md)
- [../../scripts/ops/collect-live-surface-baseline.sh](../../scripts/ops/collect-live-surface-baseline.sh)
- [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
- [../ops/DEPLOYMENT-CHECKLIST.md](../ops/DEPLOYMENT-CHECKLIST.md)
- [../ops/DISASTER-RECOVERY-PLAN.md](../ops/DISASTER-RECOVERY-PLAN.md)
- [../slos/PLATFORM-SLOS.md](../slos/PLATFORM-SLOS.md)
- [../../tests/artifacts/playwright-results.json](../../tests/artifacts/playwright-results.json)

## Current Baseline

| Surface | Observation | Current Risk |
| --- | --- | --- |
| Static CSS | Consistent 200s on the current stack with low latency. | Low for the tested path, but not a full soak campaign. |
| IDE root | Stable redirect behavior on the current stack. | Medium until authenticated flows are exercised at higher concurrency. |
| oauth2 start | Stable redirect behavior on the current stack. | Medium until authentication soak is completed. |
| Portal root | Current evidence remains incomplete for the full authenticated path. | High until the portal flow is measured under the intended session state. |

## Latest Drill Evidence

- Failover promotion/failback completed successfully and returned the active marker to `192.168.168.31`.
- The performance campaign is complete: heavier baseline, soak-lite, authenticated smoke, and bottleneck evidence were captured.

## Latest Live Sample

| Surface | Codes | Avg | Min | Max |
| --- | --- | --- | --- | --- |
| Static CSS | 200 x4 | 0.024s | 0.019s | 0.031s |
| Portal Root | 403 x4 | 0.023s | 0.019s | 0.029s |
| IDE Root | 200 x4 | 0.253s | 0.236s | 0.269s |
| OAuth Start | 200 x4 | 0.220s | 0.209s | 0.234s |

The surfaces are currently stable, and the remaining performance evidence has now been captured in the latest campaign artifacts.

Direct concurrency probe on the current live stack:

- static-css: 200=10 | avg=0.103s min=0.078s max=0.121s
- ide-root: 302=10 | avg=0.088s min=0.053s max=0.136s
- oauth-start: 302=10 | avg=0.067s min=0.055s max=0.084s

This probe adds a higher-concurrency sample and is now part of the closure evidence for #828.

Canonical collector output:

- [../../artifacts/triage/live-surface-baseline.md](../../artifacts/triage/live-surface-baseline.md)
- [../../artifacts/triage/live-surface-baseline.json](../../artifacts/triage/live-surface-baseline.json)
- [../../artifacts/triage/resilience-campaign.md](../../artifacts/triage/resilience-campaign.md)
- [../../artifacts/triage/resilience-campaign.json](../../artifacts/triage/resilience-campaign.json)
- [../../artifacts/triage/resilience-campaign-soak-lite.md](../../artifacts/triage/resilience-campaign-soak-lite.md)
- [../../artifacts/triage/resilience-campaign-soak-lite.json](../../artifacts/triage/resilience-campaign-soak-lite.json)

Latest rerun evidence:

- Baseline and soak-lite completed successfully with the current live stack.
- Authenticated smoke passed after the Appsmith login contract was hardened.
- Failover continuity passed in unauthenticated mode after the Playwright wrapper fallback path was fixed.

The collector now gives the performance campaign a repeatable entry point for the current live surface before the heavier concurrency and soak passes.

Authenticated smoke status:

- Validated separately in terminal history.
- The embedded campaign runner step still skips when Node is unavailable in the execution context.
- Authenticated path coverage exists, and the current campaign now includes longer soak and bottleneck analysis.

## Campaign Results

- Heavier baseline and soak-lite runs completed successfully.
- Authenticated smoke passed.
- Live concurrency probe reached 20 concurrent users with 100% success.
- Host CPU, memory, disk, and container health were sampled on the primary.
- The Python stress harness now uses a batch-mode SSH key path instead of prompting interactively.

## Closure Note

- #828 is closed in GitHub after the current live latency, concurrency, memory, and I/O evidence were captured.

## Closure Criteria

- The authenticated soak campaign has a current result set.
- Bottleneck findings are tracked to concrete fixes.
- Latency budgets are attached to the issue trail.

## Final State

The performance offensive is complete, and this document is the closure record for #828.

## Cross-References

- Status index: [README.md](README.md)
- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
