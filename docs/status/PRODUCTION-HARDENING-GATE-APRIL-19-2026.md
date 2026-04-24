# Production Hardening Gate - April 19, 2026

Status: Active
Scope: HA, DR, failover, observability, and on-call readiness for the current production topology.

## Purpose

This is the canonical readiness gate for #830. It consolidates the current SLI/SLO policy, error-budget response, DR/failover drill expectations, and on-call/runbook audit requirements into one execution artifact.

## Canonical Inputs

- Platform SLOs: [../slos/PLATFORM-SLOS.md](../slos/PLATFORM-SLOS.md)
- SLO overview: [../slos/README.md](../slos/README.md)
- Operations index: [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
- Disaster recovery plan: [../ops/DISASTER-RECOVERY-PLAN.md](../ops/DISASTER-RECOVERY-PLAN.md)
- Incident response playbook: [../ops/INCIDENT-RESPONSE-PLAYBOOK.md](../ops/INCIDENT-RESPONSE-PLAYBOOK.md)
- Operations compliance checklist: [../ops/OPS-COMPLIANCE-CHECKLIST.md](../ops/OPS-COMPLIANCE-CHECKLIST.md)
- Deployment checklist: [../ops/DEPLOYMENT-CHECKLIST.md](../ops/DEPLOYMENT-CHECKLIST.md)

## Current Readiness Baseline

- Current live failover checkpoint shows the active topology is healthy.
- Active host marker: `192.168.168.31`
- VIP owner: `192.168.168.31`
- Primary health: healthy
- Replica health: healthy
- Replica ingress: healthy
- Evidence was captured in the issue tracker and current live validation comments.

## Latest Drill Evidence

- Failover status was checked before the drill and the active topology was healthy.
- Replica promotion completed successfully and the active marker moved to `192.168.168.42`.
- Failback completed successfully and the active marker returned to `192.168.168.31`.
- Both promotion and failback wrote fresh evidence files under `/tmp/code-server-failover-evidence/`.

## Consolidated SLI/SLO Catalog

| Surface | SLI | SLO Target | Error Budget | Response Trigger |
| --- | --- | --- | --- | --- |
| Portal auth | successful login and redirect completion | 99.9% | 43.2 minutes / 30 days | burn rate or auth loop regression |
| IDE auth | successful login and redirect completion | 99.9% | 43.2 minutes / 30 days | burn rate or auth loop regression |
| Portal static delivery | static asset success rate | 99.95% | 21.6 minutes / 30 days | repeated non-200 responses |
| Core path latency | P99 request latency for portal and IDE | < 800 ms | N/A | sustained latency breach |
| Failover recovery | time to restore service after primary loss | <= 15 minutes | N/A | failover exceeds target |

## Error Budget Policy

1. If the remaining budget for a core user path falls below 50%, pause non-critical rollouts until recovery evidence is recorded.
2. If auth or static delivery burns budget faster than expected, treat the issue as a P0/P1 operational event.
3. Any SLO change must be linked to a GitHub issue and backed by measured evidence from a production validation or drill.
4. Error-budget exceptions require an explicit owner and expiry date.

## DR / Failover Evidence Checkpoints

Required for gate approval:

- Backup and restore verification recorded in the issue or drill log.
- Primary-to-replica failover drill recorded with timestamps.
- Replica ingress validation recorded after failover.
- Failback validation recorded after restoration of the primary.
- RTO and RPO measured against the values in the DR plan.

## On-Call / Runbook Audit

The current on-call and runbook surface must satisfy:

- The incident commander path is explicit.
- Escalation owners are named for auth, ingress, secrets, and failover.
- Rollback or failback commands are documented and tested.
- Health checks and user-facing smoke tests are documented.
- Evidence is attached to the issue or PR, not left in transient terminal output.

## Gate Checklist

- [x] SLI/SLO targets are published and linked from the canonical SLO docs.
- [x] Error-budget policy is acknowledged for non-critical rollouts.
- [x] DR drill evidence exists for restore, failover, and failback.
- [x] On-call ownership and escalation paths are explicit.
- [x] Runbook verification includes auth, IDE, static delivery, and failover.
- [x] Validation evidence is attached to the issue and current stack state.

## Open Follow-Up

This gate is complete. The current live failover checkpoint, DR drill evidence, runbook coverage, and named response owners are all documented and attached to the issue trail.

## Cross-References

- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
- Strategic reset: [CTO-STRATEGIC-RESET-APRIL-19-2026.md](CTO-STRATEGIC-RESET-APRIL-19-2026.md)
- Performance tuning: [../PERFORMANCE-TUNING.md](../PERFORMANCE-TUNING.md)
- Security hardening: [../SECURITY-HARDENING-GUIDE.md](../SECURITY-HARDENING-GUIDE.md)
