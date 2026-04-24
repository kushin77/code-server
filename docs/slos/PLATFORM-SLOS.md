# Platform SLOs

This document defines platform-level SLO targets for production operations.

## Scope

Applies to the core user path:

- Portal authentication
- IDE authentication and access
- Static asset delivery for portal and IDE
- Primary-to-replica failover readiness

## SLO Targets

| Metric | SLO Target | Alert Threshold | Measurement Window |
|---|---|---|---|
| Core path availability | 99.9% | < 99.7% | Rolling 30 days |
| Auth success rate | 99.9% | < 99.7% for 5 minutes | 5 minutes + 30 days |
| Portal static asset success | 99.95% | < 99.8% for 5 minutes | 5 minutes + 30 days |
| P99 request latency (portal/ide) | < 800 ms | > 1000 ms for 5 minutes | 5 minutes |
| Failover recovery time | <= 15 minutes | > 15 minutes | Per drill or incident |
| Data recovery point | <= 5 minutes | > 5 minutes | Per drill or incident |

## Error Budgets (30-Day Window)

- 99.9% availability budget: 43.2 minutes
- 99.95% availability budget: 21.6 minutes

When remaining budget is below 50%, prioritize reliability and pause non-critical rollouts.

## Operational Response

- SLO breach triggers incident classification (P0 or P1 based on impact).
- Incident commander executes mitigation and logs evidence.
- Post-incident review must include measured SLO delta and corrective actions.

## Review Cadence

- Weekly: trend review for latency and error rate
- Monthly: error budget review and target adjustments
- Quarterly: SLO target validation against business and platform changes

## References

- [README.md](README.md)
- [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
- [../ops/DISASTER-RECOVERY-PLAN.md](../ops/DISASTER-RECOVERY-PLAN.md)
- [../ops/INCIDENT-RESPONSE-PLAYBOOK.md](../ops/INCIDENT-RESPONSE-PLAYBOOK.md)
