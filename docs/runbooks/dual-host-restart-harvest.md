# Runbook: Dual-Host Restart and Log Harvest

**Purpose**: Runbook: Dual-Host Restart and Log Harvest runbook — operational procedure for dual host restart harvest response.

**Related Issues**: #892, #905

## Purpose

Run a deterministic restart pass across the primary and replica hosts while collecting the minimum evidence needed to diagnose failures quickly.

## One-Command Entry Point

```bash
bash scripts/operations/redeploy/onprem/dual-host-restart-harvest.sh
```

## What It Does

1. Captures `docker ps`, compose status, and recent compose logs for both hosts.
2. Checks the replica host for reserved-port collisions before any restart.
3. Runs the existing on-prem preflight and redeploy flow on each host.
4. Captures post-restart status snapshots for both hosts.
5. Writes a ready-to-post issue comment template and evidence bundle under `artifacts/triage/`.

## Failure Behavior

- If the replica host is already binding a reserved edge port, the run stops before restart and emits a conflict report.
- If either host fails preflight or redeploy, the script leaves the collected evidence in place and exits non-zero.

## Evidence Files

- `artifacts/triage/dual-host-restart-<timestamp>-primary-ports-before.tsv`
- `artifacts/triage/dual-host-restart-<timestamp>-replica-ports-before.tsv`
- `artifacts/triage/dual-host-restart-<timestamp>-primary-logs-since-2h.txt`
- `artifacts/triage/dual-host-restart-<timestamp>-replica-logs-since-2h.txt`
- `artifacts/triage/dual-host-restart-<timestamp>-issue-comment.md`

## Related Policy

- [Port Ownership Map](../ops/PORT-OWNERSHIP-MAP.md)
- [Container Restart Storm Runbook](container-restart-investigation.md)