# Service Level Objectives (SLOs)

Purpose: canonical entry point for platform SLO policy, service targets, and operational response thresholds.

## Canonical Documents

- [../SLO.md](../SLO.md) - service-level objective matrix and burn-rate policy
- [PLATFORM-SLOS.md](PLATFORM-SLOS.md) - platform-level core path targets and alert thresholds
- [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md) - operations SSOT and incident/runbook index
- [../ops/DISASTER-RECOVERY-PLAN.md](../ops/DISASTER-RECOVERY-PLAN.md) - restore, failover, and drill procedures
- [../ops/INCIDENT-RESPONSE-PLAYBOOK.md](../ops/INCIDENT-RESPONSE-PLAYBOOK.md) - incident workflow and escalation

## SLO Policy

- Every production-facing service must have an SLO target or an explicit documented exemption.
- SLOs must be based on user-visible behavior, not internal-only metrics.
- Alerts should trigger on SLO burn or customer impact, not on isolated resource noise.
- Error budget consumption must influence rollout and release decisions.

## SLO Definitions

- SLI: the measured indicator, such as availability, success rate, or P99 latency.
- SLO: the target threshold for the SLI over a defined window.
- Error budget: the acceptable amount of failure for the same window.
- SLA: the promise to users or stakeholders, usually slightly below the SLO.

## Platform Targets

See [PLATFORM-SLOS.md](PLATFORM-SLOS.md) for the canonical platform targets, review cadence, and recovery expectations.

## Change Control

- Update the SLO document before changing alert thresholds or recovery objectives.
- Attach evidence from production validation or drill execution when updating targets.
- Keep SLO changes linked to a GitHub issue or PR for auditability.
