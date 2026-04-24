# Architecture Stress Review - April 19, 2026

Status: Complete
Scope: Scale, fault domains, resilience, and maintainability review for the current platform architecture.

## Purpose

This is the canonical stress-review artifact for issue #826. It summarizes the present architectural pressure points and the decisions that need to be made if the platform grows or degrades further.

## Evidence Reviewed

- [../ops/NAS-ARCHITECTURE.md](../ops/NAS-ARCHITECTURE.md)
- [../ops/ENDPOINT-CONTRACT-INDEX.md](../ops/ENDPOINT-CONTRACT-INDEX.md)
- [../ops/DISASTER-RECOVERY-PLAN.md](../ops/DISASTER-RECOVERY-PLAN.md)
- [../slos/PLATFORM-SLOS.md](../slos/PLATFORM-SLOS.md)
- [../governance/CONFIG-SSOT.md](../governance/CONFIG-SSOT.md)
- [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)

## Stress Findings

| Component | Pressure Point | Stress Risk | Decision Needed |
| --- | --- | --- | --- |
| Ingress/auth | Shared ingress and auth behavior can hide failure boundaries. | Recovery may be slower if the first failure is only visible at the edge. | Keep the auth/ingress contract explicit and verify it under failover. |
| Storage topology | NAS and shared storage are central to persistence and recovery. | Storage-level issues can cascade into deploy and backup workflows. | Validate storage recovery assumptions and document the blast radius. |
| Operational runbooks | Multiple runbooks exist across deployment, DR, and incident response. | Operators may follow a different path under stress. | Consolidate the critical path into one execution order. |
| Config topology | Topology is documented, but drift can still accumulate across references. | Small drift becomes a maintainability problem over time. | Keep config SSOT authoritative and prune duplicate references. |

## Failure Map

Top 20 breakpoints for the current architecture under growth, dependency loss, and recovery pressure.

| Rank | Breakpoint | Failure Mode | Why It Matters |
| --- | --- | --- | --- |
| 1 | Shared ingress/auth boundary | Redirect or header drift causes auth regressions. | User entry fails before app logic is reached. |
| 2 | Portal static delivery path | Static assets stop loading or return the wrong contract. | Portal usability collapses even when the app is up. |
| 3 | IDE auth session restore | Session state is lost after login or failover. | The primary user workflow becomes unstable. |
| 4 | NAS mount contract | Shared storage becomes unavailable or inconsistent. | Profile, backup, and workspace persistence break. |
| 5 | Primary host saturation | CPU or memory saturation delays or denies requests. | The active node becomes the bottleneck. |
| 6 | Replica promotion lag | Replica cannot take over within the expected window. | Failover no longer protects availability. |
| 7 | Failback drift | Primary returns with stale or divergent state. | Operators risk split-brain or rollback confusion. |
| 8 | Config SSOT drift | Documents, env vars, and runtime settings diverge. | Operators make decisions on outdated contracts. |
| 9 | Secrets source mismatch | GSM/Vault/env fallbacks conflict. | Deploy-time behavior becomes non-deterministic. |
| 10 | Observability gaps | Health and error signals are incomplete. | Failures stay hidden until users report them. |
| 11 | Runbook fragmentation | Operators follow different procedures under stress. | Recovery slows and mistakes multiply. |
| 12 | CI artifact drift | Validation and runtime artifacts differ. | A green build no longer predicts runtime safety. |
| 13 | Unpinned dependencies | Floating versions introduce unreviewed change. | Reproducibility and rollback fidelity degrade. |
| 14 | Browser-state dependency | Auth succeeds only under narrow local state. | E2E confidence becomes fragile. |
| 15 | Request burst collapse | Tail latency or error rate explodes under concurrency. | The service fails before capacity assumptions hold. |
| 16 | Memory leak accumulation | Soak windows reveal unbounded growth. | Long-lived sessions become unstable. |
| 17 | Disk I/O contention | Storage latency stalls the stack. | Backups, persistence, and logs slow down together. |
| 18 | Operator access sprawl | SSH/VPN/admin access is broader than needed. | The blast radius of a compromise expands. |
| 19 | Policy/ADR divergence | Decisions are recorded in one place but implemented elsewhere. | Architecture intent and runtime drift apart. |
| 20 | Audit trail gaps | Validation happens without durable evidence. | Issues cannot be closed with confidence. |

## Target-State Reference Architecture

The target state is a layered, explicit control/data-plane design that keeps the current on-prem footprint but removes accidental coupling.

| Layer | Target Shape | Tradeoff |
| --- | --- | --- |
| Edge / ingress | Single canonical ingress path with explicit auth headers and redirect contracts. | Less flexibility at the edge, more predictability. |
| Auth control plane | oauth2-proxy remains the auth gateway, but contract checks are required in CI and preflight. | Slightly higher validation overhead, much lower auth drift risk. |
| Application plane | code-server and the portal remain separate surfaces with documented boundaries. | Extra coordination between surfaces, cleaner failure isolation. |
| Shared state plane | NAS-backed persistence with explicit mount contracts and backup evidence. | Shared storage remains a dependency, but it is bounded and observable. |
| Failover plane | Primary/replica with measured promotion/failback windows and explicit active-marker validation. | More operational ceremony, clearer recovery guarantees. |
| Observability plane | Prometheus/Grafana/AlertManager with endpoint contracts and SLO-based alerts. | More alert tuning, much better failure detection. |
| Delivery plane | Pinned images, deterministic scripts, and validated policy bundles. | Slower change velocity, higher release confidence. |

Design goals for the target state:

- Auth and ingress failures must be visible as contract violations, not just user complaints.
- Stateful dependencies must have one documented owner and one documented recovery path.
- Deployments must be reproducible from pinned inputs and validated in CI before production.
- Failover must preserve the user-facing contract and produce evidence on every drill.

## Phased Migration Plan

| Phase | Goal | Exit Criteria | Rollback |
| --- | --- | --- | --- |
| 1 | Freeze the current contracts and document the failure map. | Failure map, SLO baseline, and active-marker drill evidence all current. | Revert docs and keep the live topology unchanged. |
| 2 | Tighten auth/ingress and storage contracts. | Auth redirects, static delivery, and NAS behavior all validated under current load. | Restore previous ingress/auth config and re-run contract checks. |
| 3 | Reduce operational coupling. | Runbooks consolidated, config SSOT authoritative, and drift checks enforced. | Re-enable the prior runbook path if a regression appears. |
| 4 | Strengthen scale and recovery evidence. | Higher-concurrency burst, soak, and failover evidence attached to the tracker. | Fall back to the current validated stack and pause expansion. |
| 5 | Evaluate structural change only after the contracts hold. | Reference architecture approved and ADRed. | Keep current on-prem topology until the new shape is exercised. |

Migration sequence:

1. Lock the current contract boundaries and treat deviations as blockers.
2. Remove ambiguous fallbacks in ingress, auth, and secrets handling.
3. Keep the current primary/replica topology but enforce drill evidence as a release gate.
4. Promote additional structural changes only after the contract surface is stable.

## ADR Updates

The current ADR set already provides the architectural direction needed to absorb this stress review.

- [ADR-004-MULTI-REPO-INTERACTION-MODEL.md](../architecture/ADR-004-MULTI-REPO-INTERACTION-MODEL.md) defines the user-facing multi-repo model and should remain in draft until pilot validation lands.
- [ADR-005-DEVELOPER-CONTEXT-HUB.md](../architecture/ADR-005-DEVELOPER-CONTEXT-HUB.md) defines the portal control-plane boundary and should remain draft until the workspace-set contract is implemented.
- A follow-on ADR should capture the explicit ingress/auth/storage failure boundaries from this stress review once the next migration slice is approved.

Required ADR follow-through:

1. Mark the finalized failure map as the architectural baseline for scale and resilience reviews.
2. Reuse the current target-state shape instead of creating a new parallel architecture.
3. Update the parent epic references when the next migration slice is scheduled.

## Heavier Burst Evidence

The current live stack was exercised with a larger burst profile to probe the next failure boundary.

| Concurrent users | Requests | Success rate | Throughput | p99 latency |
| --- | ---: | ---: | ---: | ---: |
| 10 | 120 | 100.0% | 21.08 req/s | 1501.30 ms |
| 20 | 239 | 99.6% | 17.07 req/s | 4196.13 ms |
| 40 | 417 | 86.9% | 14.53 req/s | 4799.55 ms |

Observations:

- The current stack stays healthy at 10-way burst levels and begins to degrade materially at 20-way concurrency.
- At 40-way concurrency, request success falls below the acceptable threshold and tail latency climbs sharply.
- The failure boundary is now explicit enough to drive the next architecture decisions instead of relying on anecdote.

## Replacement / Retirement Decisions

1. Retire any architecture path that cannot be exercised in a recovery drill.
2. Replace ambiguous cross-runbook steps with a single operational sequence.
3. Keep the host, storage, and endpoint contracts explicit until stress evidence is current.

## Migration Sequencing

- First, validate the current topology under current load and failover.
- Next, isolate the highest-friction components and decide whether they need replacement or tighter contracts.
- Finally, only then change the architecture shape.

## Closure Criteria

- The current architecture has a current stress snapshot.
- Fragile patterns have explicit replacement or retirement decisions.
- Migration sequencing is recorded with compatibility windows.

## Closure Note

The full deliverable set for #826 is now present in this SSOT: failure map, target-state reference architecture, phased migration plan, and ADR follow-through.

## Cross-References

- Status index: [README.md](README.md)
- Production hardening gate: [PRODUCTION-HARDENING-GATE-APRIL-19-2026.md](PRODUCTION-HARDENING-GATE-APRIL-19-2026.md)
- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
