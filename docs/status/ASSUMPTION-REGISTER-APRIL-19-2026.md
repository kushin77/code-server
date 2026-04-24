# Assumption Register - April 19, 2026

Status: Active
Scope: Hidden risks, edge cases, and long-tail failure assumptions for the current platform.

## Purpose

This is the canonical assumption register for issue #825. It records the assumptions that still matter, what could invalidate them, and who should review them.

## Proof Status Legend

| Status | Meaning |
| --- | --- |
| Validated | The assumption has current evidence in the live or replayed stack. |
| Unproven | The assumption still lacks direct evidence and needs validation work. |
| Invalid | The assumption was tested and does not hold for the current platform. |

## Assumptions

| Assumption | Proof Status | Why It Exists | Failure Mode | Owner | Due Date | Review Cadence |
| --- | --- | --- | --- | --- | --- | --- |
| Current ingress and auth topology remains stable under the documented load. | Validated | The live stack currently routes through the present portal/auth chain. | Redirect loops, auth regressions, or TLS/host-header drift. | Platform | N/A | Weekly until the next major topology change. |
| DR procedures remain valid for the current host pair and service topology. | Validated | The failover plan and host mapping are already documented. | Restore or failback commands no longer match reality. | Operations | N/A | After every failover-related change. |
| The config SSOT remains the single authoritative topology source. | Validated | The repo already centralizes config precedence and host mapping. | Divergent environment values or stale references produce inconsistent runtime behavior. | Governance | N/A | On every config change. |
| Policy and secret validators continue to reflect the deployed posture. | Validated | Governance and secret rotation checks are already in place. | Silent drift between repo policy and runtime policy. | Security | N/A | Quarterly, and after each hardening change. |

## Long-Tail Risks

- Authenticated flows may fail only under specific browser state or session setup.
- Performance regressions may show up only after longer soak or higher concurrency.
- Operational steps may drift if the docs are not exercised during real deploys.
- Any future unproven critical assumption must be added here with an owner, due date, and explicit validation task.

## Retirement Rules

- Remove an assumption only after it is validated in a live or replayed exercise.
- Convert an invalid assumption into a tracked remediation item with an owner and due date.
- Keep the register small; do not add generic risk statements that are already covered elsewhere.

## Closure Criteria

- Every active assumption has an owner and a review cadence.
- Invalid assumptions are promoted to tracked remediations.
- The register is updated after major platform or topology changes.

## Cross-References

- Status index: [README.md](README.md)
- Production hardening gate: [PRODUCTION-HARDENING-GATE-APRIL-19-2026.md](PRODUCTION-HARDENING-GATE-APRIL-19-2026.md)
- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
