# Incident Response Playbook

**Purpose**: Incident Response Playbook — reference and operational document.

This playbook defines escalation, communication, and execution flow for production incidents.

## Severity Levels

- P0: production outage, auth failure, data loss risk, or security breach
- P1: major degradation affecting core user workflows
- P2: moderate degradation with workaround
- P3: low impact or non-production issue

## Escalation Matrix

- Incident commander: on-call platform engineer
- Secondary: security engineer for auth/secrets incidents
- Infrastructure owner: deployment/failover execution owner
- Communications owner: status updates in issue and team channel

## Named Response Owners

| Area | Primary Owner | Secondary Owner |
| --- | --- | --- |
| Auth and ingress | Platform Engineering | Security Engineering |
| Secrets and identity | Security Engineering | Platform Engineering |
| Failover and recovery | Operations | Platform Engineering |
| Observability and alerting | Platform Engineering | Operations |

## Response Targets

- Acknowledge P0: within 5 minutes
- Acknowledge P1: within 15 minutes
- Initial mitigation plan: within 15 minutes for P0, 30 minutes for P1
- Recovery updates cadence: every 15 minutes until stable

## Incident Workflow

1. Detect and classify severity.
2. Open or update GitHub issue as incident log SSOT.
3. Assign incident commander and owners.
4. Stabilize service (rollback, recreate, failover, or traffic shift).
5. Validate core paths: auth, IDE, static assets, health endpoints.
6. Communicate status and ETA updates.
7. Confirm recovery and monitor for recurrence.
8. Complete post-incident review with corrective actions.

## Communication Template

```text
Incident: <title>
Severity: <P0/P1/P2/P3>
Impact: <user-facing impact>
Start Time: <UTC>
Current Status: <investigating/mitigating/recovered>
Next Update: <time>
Owner: <name>
Issue: <link>
```

## Containment Patterns

- Rollback to known-good revision
- Targeted service recreate for auth/ingress components
- Failover to replica host when primary is unstable
- Temporary feature disablement for non-critical paths

## Exit Criteria

- Core health checks green
- No active error spikes for 15 minutes
- User-facing endpoints verified
- Incident timeline and root cause recorded
- Named owners were engaged and recorded for the incident scope

## Post-Incident Requirements

- Root cause analysis completed within 48 hours for P0/P1
- Action items created as GitHub issues with owners and due dates
- Relevant runbooks updated
- Evidence attached to incident issue

## Related Documents

- [DISASTER-RECOVERY-PLAN.md](DISASTER-RECOVERY-PLAN.md)
- [OPS-COMPLIANCE-CHECKLIST.md](OPS-COMPLIANCE-CHECKLIST.md)
- [../runbooks/production-readiness-gate.md](../runbooks/production-readiness-gate.md)