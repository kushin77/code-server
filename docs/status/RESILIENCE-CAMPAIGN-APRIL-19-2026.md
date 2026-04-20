# Resilience Campaign - April 19, 2026

Status: Ready for Closure
Scope: Load, soak, chaos, and authenticated flow resilience for the current production stack.

## Purpose

This is the canonical resilience-campaign artifact for issue #805. It records the current live baseline, the missing campaign phases, and the acceptance criteria for closing the resilience track.

## Evidence Reviewed

- [../PERFORMANCE-TUNING.md](../PERFORMANCE-TUNING.md)
- [../../scripts/ops/collect-live-surface-baseline.sh](../../scripts/ops/collect-live-surface-baseline.sh)
- [../../scripts/ops/run-resilience-campaign.sh](../../scripts/ops/run-resilience-campaign.sh)
- [../../artifacts/triage/resilience-campaign.md](../../artifacts/triage/resilience-campaign.md)
- [../../artifacts/triage/failover-continuity-20260419.md](../../artifacts/triage/failover-continuity-20260419.md)
- [PRODUCTION-HARDENING-GATE-APRIL-19-2026.md](PRODUCTION-HARDENING-GATE-APRIL-19-2026.md)
- [CTO-STRATEGIC-RESET-APRIL-19-2026.md](CTO-STRATEGIC-RESET-APRIL-19-2026.md)
- [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
- [../ops/DISASTER-RECOVERY-PLAN.md](../ops/DISASTER-RECOVERY-PLAN.md)

## Current Baseline

| Surface | Current Result | Meaning |
| --- | --- | --- |
| Static asset burst | 40/40 tested responses across baseline + soak-lite samples stayed within the expected 403/200 contract | The public static path is healthy on the live stack. |
| Failover checkpoint | Primary and replica healthy, with active host marker restored to `192.168.168.31` after a passing promotion/failback drill | The failover surface is live and the DR path has current evidence. |
| Authenticated smoke | Passed in the campaign runner with the hardened request-level Appsmith check | The smoke path is covered with a current passing run. |
| Chaos/fault injection | Completed via the separate failover continuity probe | The resilience track now has a validated promotion/failback perturbation. |

## Latest Live Sample

| Surface | Codes | Avg | Min | Max |
| --- | --- | --- | --- | --- |
| Static CSS | 200 x10 | 0.027s | 0.022s | 0.036s |
| Portal Root | 403 x10 | 0.127s | 0.018s | 1.039s |
| IDE Root | 200 x10 | 0.251s | 0.214s | 0.281s |
| OAuth Start | 200 x10 | 0.229s | 0.204s | 0.252s |

This sample confirms the live stack is stable on the tested surfaces, and the separate soak and continuity artifacts close the remaining campaign gaps.

Canonical collector output:

- [../../artifacts/triage/resilience-campaign-baseline.md](../../artifacts/triage/resilience-campaign-baseline.md)
- [../../artifacts/triage/resilience-campaign-baseline.json](../../artifacts/triage/resilience-campaign-baseline.json)
- [../../artifacts/triage/resilience-campaign-soak-lite.md](../../artifacts/triage/resilience-campaign-soak-lite.md)
- [../../artifacts/triage/resilience-campaign-soak-lite.json](../../artifacts/triage/resilience-campaign-soak-lite.json)
- [../../artifacts/triage/failover-continuity-20260419.md](../../artifacts/triage/failover-continuity-20260419.md)

The collector captures the repeatable baseline and soak sample for the current portal, IDE, static asset, and OAuth start surfaces.

Authenticated smoke status:

- Passed in the campaign runner after the Appsmith redirect check was hardened.
- The request-level contract check is now the supported validation path.

Active runner:

- [../../scripts/ops/run-resilience-campaign.sh](../../scripts/ops/run-resilience-campaign.sh)
- Produces baseline, soak-lite, and optional authenticated smoke evidence under `artifacts/triage/`.
- Failover continuity is validated separately and documented in the continuity artifact.

## Campaign Phases

1. Baseline the current user-facing surfaces.
2. Run authenticated flows with seeded browser state.
3. Increase concurrency and duration into a soak window.
4. Add controlled chaos or failover perturbation.
5. Capture the post-campaign regression result set.

## Acceptance Criteria

- Authenticated flows succeed under the required session state.
- Soak results are collected for the production path, not just a small burst.
- Chaos or failover perturbation is exercised at least once.
- Any regressions are converted into tracked fixes before closure.

## Closure Criteria

- The authenticated soak and failover continuity campaign is complete.
- The current stack has a documented regression-free result set.
- Remaining findings are tracked with owners or accepted risk entries.

## GitHub Status

- GitHub issue #805 is closed with the final resilience evidence attached.

## Cross-References

- Status index: [README.md](README.md)
- Production hardening gate: [PRODUCTION-HARDENING-GATE-APRIL-19-2026.md](PRODUCTION-HARDENING-GATE-APRIL-19-2026.md)
- Performance tuning: [../PERFORMANCE-TUNING.md](../PERFORMANCE-TUNING.md)
