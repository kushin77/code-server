# Disaster Recovery Strategy

**Status**: Active draft for production operations
**Cluster**: `192.168.168.31`, `192.168.168.42`
**Shared Storage**: `192.168.168.56` NAS

This document defines the recovery strategy for the active-active production cluster. It is the canonical reference for backup, restore, failover, and sequential reboot operations.

## Objectives

- **RTO**: <= 5 minutes for all P0 services.
- **RPO**: <= 15 minutes from the last durable backup point.
- **Failover time**: < 30 seconds end-to-end.
- **Recovery verification**: every recovery action must end with health checks and evidence capture.

## Architecture Summary

- Both hosts are active replicas and must run the same image set and configuration.
- Session state is shared through the approved HA state layer.
- Persistent data is protected through scheduled NAS-backed backups.
- Load balancing must remove unhealthy hosts from rotation automatically.

## Backup Policy

### PostgreSQL

- Daily hot snapshot to NAS.
- Weekly cold archive to NAS cold storage.
- Restore tests must verify checksum / row-count integrity.

### Docker Volumes

- Persistent volumes are backed up before cleanup.
- Ephemeral volumes are pruned when the parent container is removed.

### Terraform / Config

- Terraform state must be backed up continuously to the approved backend.
- Git-tracked configuration is authoritative; local drift must not become the restore source.

## Restore Validation

1. Restore to a staging target or isolated host.
2. Verify database integrity after restore.
3. Verify application health endpoints and login flow.
4. Capture the restore log as evidence in `artifacts/triage/`.

## Failover Procedure

1. Confirm both replicas are healthy before taking action.
2. Remove the unhealthy host from the load balancer.
3. Promote the replica or shift traffic to the remaining healthy host.
4. Verify `health`, `healthz`, and application smoke checks.
5. Document the failover window and the recovered host in the issue or PR.

Failback is manual and requires operator confirmation.

## Sequential Reboot Procedure

The sequential reboot flow is validated through the resilience campaign tooling.

### Phase 1: Reboot `192.168.168.31`

- Verify `192.168.168.42` is healthy and serving traffic.
- Drain traffic from `192.168.168.31`.
- Reboot the host.
- Wait for health checks to recover.
- Collect logs and record evidence.

### Phase 2: Reboot `192.168.168.42`

- Repeat the same process after the first host is fully recovered.
- Ensure total downtime remains below the target window.

Reference automation:

- [scripts/ops/run-resilience-campaign.sh](../../scripts/ops/run-resilience-campaign.sh)
- [scripts/ci/run-playwright-failover-continuity.sh](../../scripts/ci/run-playwright-failover-continuity.sh)

## Chaos Engineering Suite

Required scenarios:

1. Kill a single container and verify auto-recovery.
2. Kill the primary host and verify failover in under 30 seconds.
3. Kill the replica host and verify the remaining host serves traffic.
4. Remove the NAS mount and confirm graceful degradation.
5. Simulate a network partition between hosts and prevent split brain.
6. Simulate disk-full conditions and verify alerting and recovery.
7. Simulate memory pressure / OOM and confirm only the target container restarts.

## Stress Testing

- CPU stress: run `stress-ng` against both hosts.
- GPU stress: exercise Ollama inference while the cluster is under load.
- Memory stress: validate the cluster stays stable near high-water usage.
- Disk I/O stress: validate NAS-backed services under write pressure.

## Monitoring and Alerts

- Backup freshness alert if backups are older than 2 hours beyond schedule.
- Host health alert if a replica is removed from rotation.
- NAS capacity alert if utilization exceeds the documented threshold.
- Recovery audit log must be attached to the issue or PR after each test.

## Verification Commands

```bash
bash scripts/ops/run-resilience-campaign.sh
bash scripts/ci/run-playwright-failover-continuity.sh
```

## Review Cadence

- Quarterly DR tests.
- Monthly restore validation.
- After any major change to storage, networking, or service topology.
