# Observability Gap List - April 19, 2026

Status: Active
Scope: Missing telemetry, alerting, dashboards, and signal-quality gaps for the current production topology.

## Purpose

This is the canonical observability-gap artifact for issue #830. It records the remaining blind spots, the current telemetry coverage, and the concrete follow-up items needed to make the production-hardening gate enforceable.

## Evidence Reviewed

- [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
- [../ops/DISASTER-RECOVERY-PLAN.md](../ops/DISASTER-RECOVERY-PLAN.md)
- [../ops/INCIDENT-RESPONSE-PLAYBOOK.md](../ops/INCIDENT-RESPONSE-PLAYBOOK.md)
- [../ops/DEPLOYMENT-CHECKLIST.md](../ops/DEPLOYMENT-CHECKLIST.md)
- [../ops/OPS-COMPLIANCE-CHECKLIST.md](../ops/OPS-COMPLIANCE-CHECKLIST.md)
- [../slos/PLATFORM-SLOS.md](../slos/PLATFORM-SLOS.md)
- [../PERFORMANCE-TUNING.md](../PERFORMANCE-TUNING.md)
- [../security/THREAT-MODEL-2026-04-19.md](../security/THREAT-MODEL-2026-04-19.md)

## Current Coverage

| Area | Current State | Risk |
| --- | --- | --- |
| Portal auth | Live baseline and soak evidence exist for the current stack. | Medium until the authenticated drill remains wired to a required gate. |
| IDE auth | Live baseline and soak evidence exist for the current stack. | Medium until the full auth flow is run as a required release gate. |
| Static delivery | Current live checks show stable 200 responses and low latency. | Low, but not yet tied to a formal alert threshold. |
| Failover | Promote/failback drill evidence exists and the topology returns to primary. | Medium until failover evidence is wrapped into the readiness gate and alerting policy. |
| Incident response | Playbook exists and the current runbooks are documented. | Medium until ownership, paging, and escalation are exercised with a current drill. |
| Metrics coverage | Prometheus/Grafana/Alertmanager are present in the stack. | Medium until service-by-service metric ownership is enumerated in one place. |

## Gap Matrix

| Gap | Why It Matters | Current Evidence | Follow-up |
| --- | --- | --- | --- |
| SLO ownership | Operators need a single place to know which service owns which SLI/SLO. | [PLATFORM-SLOS.md](../slos/PLATFORM-SLOS.md) | Add service owners and alert routing to the readiness gate and ops index. |
| Alert mapping | Alerts must map to the exact runbook and escalation path. | [INCIDENT-RESPONSE-PLAYBOOK.md](../ops/INCIDENT-RESPONSE-PLAYBOOK.md) | Add alert-to-runbook mapping and on-call contact ownership. |
| Dashboard coverage | Dashboards should be explicit about which user journey they cover. | Current monitoring stack is operational, but dashboard ownership is not centralized here. | Document dashboard ownership and minimum panels for auth, ingress, latency, and failover. |
| Drill cadence | DR/failover evidence should be repeatable and scheduled. | [DISASTER-RECOVERY-PLAN.md](../ops/DISASTER-RECOVERY-PLAN.md) | Attach the monthly drill schedule and evidence checklist to the readiness gate. |
| Signal quality | The system needs explicit thresholds for noise and burn rate. | [PLATFORM-SLOS.md](../slos/PLATFORM-SLOS.md) | Define alert thresholds and error-budget responses in one enforcement artifact. |
| On-call readiness | Paging and escalation need to be exercised, not just documented. | [INCIDENT-RESPONSE-PLAYBOOK.md](../ops/INCIDENT-RESPONSE-PLAYBOOK.md) | Run an on-call walkthrough and attach the evidence to the issue trail. |

## Recommended Minimum Telemetry Set

- Auth success rate for portal and IDE
- Auth latency P50/P95/P99 for login, redirect, and session restore
- Static asset response codes and latency
- Ingress health, proxy health, and upstream health
- Failover state, active host marker, and VIP ownership
- Database and Redis service health
- Error budget burn rate for core user paths
- Incident count and time-to-recover for production drills

## Closure Criteria

- Each critical user path has a named owner and alert threshold.
- The readiness gate includes a current drill schedule and evidence checklist.
- The incident playbook is tied to actual paging, escalation, and recovery evidence.
- Dashboard ownership and minimum telemetry panels are documented in one place.
- The issue trail shows the observability gaps are either closed or time-bounded.

## Cross-References

- Production hardening gate: [PRODUCTION-HARDENING-GATE-APRIL-19-2026.md](PRODUCTION-HARDENING-GATE-APRIL-19-2026.md)
- Performance offensive: [PERFORMANCE-ENGINEERING-OFFENSIVE-APRIL-19-2026.md](PERFORMANCE-ENGINEERING-OFFENSIVE-APRIL-19-2026.md)
- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
