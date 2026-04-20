# Disaster Recovery Plan

This plan defines backup, restore, failover, and testing requirements for production services.

## Objectives

- Recovery Time Objective (RTO): 15 minutes for core IDE/auth path
- Recovery Point Objective (RPO): 5 minutes for stateful data
- Availability target: maintain service continuity via primary/replica topology

## Protected Assets

- PostgreSQL data and schema
- Redis state (where durable recovery is required)
- Compose and infrastructure configuration
- Operational runbooks and deployment scripts
- code-server user profile backups

## Backup Strategy

### Databases

- PostgreSQL full backup: daily
- PostgreSQL WAL/incremental: every 5 minutes
- Retention: 30 days online, 90 days archive

### User and Workspace Data

- code-server profile backup: every 6 hours
- Retention: 30 days

### Config and IaC

- Git repository is source of truth for configuration
- Terraform state and critical env references are backed up daily

## Restore Procedure

1. Confirm incident severity and scope.
2. Freeze non-essential deployments.
3. Validate latest healthy backups.
4. Restore PostgreSQL to staging target for verification.
5. Run integrity checks and smoke tests.
6. Promote restore to production target.
7. Recreate impacted services via Docker Compose.
8. Validate auth, IDE, and static endpoint paths.
9. Document restoration timeline and data-loss window.

## Failover Procedure (Primary to Replica)

1. Verify primary health degradation.
2. Confirm replica readiness and data currency.
3. Promote replica services using failover orchestration scripts.
4. Route traffic to replica path.
5. Validate portal login, IDE login, and static assets.
6. Monitor error rate and latency for 15 minutes.
7. Announce incident status and recovery state.

## Failback Procedure (Replica to Primary)

1. Repair and validate primary host.
2. Re-synchronize data from active node.
3. Execute controlled failback during low-risk window.
4. Validate full service health and session behavior.
5. Close incident with post-incident summary.

## Monthly DR Test Schedule

- Week 1: backup restore verification drill
- Week 2: failover simulation drill
- Week 3: failback simulation drill
- Week 4: evidence review and corrective actions

Each drill must produce:

- Start and end timestamps
- RTO and RPO measured values
- Pass/fail status
- Follow-up actions and owners

## Commands

```bash
# Preflight
bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode ssh --fix-stale-logs

# Failover status
bash scripts/operations/redeploy/onprem/failover-orchestrate.sh --action status

# Promote replica
bash scripts/operations/redeploy/onprem/failover-orchestrate.sh --action promote

# Failback primary
bash scripts/operations/redeploy/onprem/failover-orchestrate.sh --action failback
```

## Evidence Requirements

- Docker service health snapshots
- Endpoint checks for portal and IDE
- Incident timeline
- Drill artifacts attached to related issue

## Related Documents

- [INCIDENT-RESPONSE-PLAYBOOK.md](INCIDENT-RESPONSE-PLAYBOOK.md)
- [OPS-COMPLIANCE-CHECKLIST.md](OPS-COMPLIANCE-CHECKLIST.md)
- [../runbooks/backup-recovery.md](../runbooks/backup-recovery.md)
