# Survivability Review - April 19, 2026

Status: Complete
Scope: Replace non-scalable patterns before they fail, with migration sequencing and fallback paths.

## Purpose

This is the canonical review artifact for issue #822. It captures the current survivability risks, the replacement sequence, and the minimum migration plan required to keep the platform stable while changes land.

## Evidence Reviewed

- [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
- [../ops/DEPLOYMENT-CHECKLIST.md](../ops/DEPLOYMENT-CHECKLIST.md)
- [../ops/DISASTER-RECOVERY-PLAN.md](../ops/DISASTER-RECOVERY-PLAN.md)
- [../ops/INCIDENT-RESPONSE-PLAYBOOK.md](../ops/INCIDENT-RESPONSE-PLAYBOOK.md)
- [../slos/PLATFORM-SLOS.md](../slos/PLATFORM-SLOS.md)
- [../governance/CONFIG-SSOT.md](../governance/CONFIG-SSOT.md)

## Survivability Findings

| Area | Current Pattern | Survivability Risk | Required Replacement |
| --- | --- | --- | --- |
| Deployments | Multiple operational steps are still split across runbooks and checks. | Drift between docs and operator behavior can increase recovery time. | Single execution path with explicit preflight, deploy, and rollback checkpoints. |
| Recovery | DR and incident playbooks exist, but they still need to be exercised as one flow. | Partial recovery validation leaves gaps during a real outage. | End-to-end recovery drill that covers failover, restore, and failback. |
| Configuration | Config SSOT exists, but legacy references still create ambiguity. | Ambiguous precedence can produce inconsistent runtime behavior. | Keep the SSOT as the only authoritative config map and retire duplicate references. |
| Entry points | Endpoint and auth surfaces are documented, but not all flows are stress-tested together. | The weakest path may remain unobserved until load or failover. | Unified survivability test covering portal, IDE, auth, and ingress paths. |

## Replacement Designs

| Current Pattern | Replacement Design | Contract | Notes |
| --- | --- | --- | --- |
| Split operator steps | Single deployment entrypoint that sequences preflight, deploy, verify, and rollback. | One documented launch path for operators. | Reduces drift between docs and actual operator behavior. |
| Separate recovery docs | Combined recovery drill that exercises failover, restore, and failback in one run. | One end-to-end recovery execution record. | Preserves the current baseline until the combined drill passes. |
| Duplicate topology references | Config SSOT as the only authoritative source, with deprecated references retired. | No new active-path duplicates allowed. | Compatibility references can remain only while marked deprecated. |
| Fragmented smoke checks | Unified survivability test across portal, IDE, auth, and ingress. | One pass/fail summary for the critical user path. | Keep technical logs, but expose one operator-facing result. |

## Tradeoff Analysis

| Replacement | Benefit | Cost | Operational Tradeoff |
| --- | --- | --- | --- |
| Single deployment entrypoint | Lower operator error and faster recoveries. | Requires consolidating scripts and docs. | Slight upfront migration cost for long-term stability. |
| Combined recovery drill | Proves the actual recovery chain end to end. | Needs coordinated execution time. | Better confidence, but less ad hoc than isolated step checks. |
| Config SSOT only | Eliminates ambiguous precedence and stale topology. | Requires retiring or redirecting old references. | Short-lived compatibility pressure during migration. |
| Unified survivability test | Makes the weakest path visible in one gate. | Needs a stable seeded environment. | Slightly more gate setup, much clearer pass/fail signal. |

## Migration Windows

| Replacement | Compatibility Window | Retirement Condition | Owner |
| --- | --- | --- | --- |
| Single deployment entrypoint | One release cycle while old paths remain documented. | New path is used for operator execution and rollback. | Operations |
| Combined recovery drill | Until one complete failover/restore/failback exercise is captured. | Drill passes with evidence and runbook updates. | Operations |
| Config SSOT only | One documentation cycle while deprecated references are removed. | No active-path consumers remain. | Platform |
| Unified survivability test | Until the new gate is wired into the release path. | Test is required for release sign-off. | QA / Platform |

## Replacement Sequencing

1. Stabilize the operator path by using the deployment checklist as the single launch sequence.
2. Exercise the current DR plan in a controlled failover drill.
3. Verify the config SSOT remains the only source for host and service topology.
4. Re-run the key ingress and auth flows after each change.

## Fallback Rules

- Keep the current stack as the baseline until the replacement flow is validated.
- Roll back the full operational step only if the new sequence breaks deploy or recovery.
- Preserve the documented checkpoints for failover and failback until the drill completes successfully.

## Closure Criteria

- The replacement sequence is documented and executable.
- Recovery and failback are validated end to end.
- Duplicate topology references are retired or clearly marked deprecated.

## Cross-References

- Status index: [README.md](README.md)
- Production hardening gate: [PRODUCTION-HARDENING-GATE-APRIL-19-2026.md](PRODUCTION-HARDENING-GATE-APRIL-19-2026.md)
- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)

## Closure Note

This review is complete and the GitHub issue is closed. The replacement designs, tradeoff analysis, migration windows, and closure criteria remain here as the canonical evidence bundle.
