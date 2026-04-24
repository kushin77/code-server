# Storage Lifecycle Strategy

**Status**: Active draft for production operations
**Primary Host Storage**: NAS `192.168.168.56`

This document defines the storage retention and cleanup strategy for containers, volumes, artifacts, backups, and stale branches.

## Goals

- Prevent disk exhaustion and backup sprawl.
- Keep immutable backups available for the required retention windows.
- Remove stale, orphaned, and idle resources without disturbing active services.
- Keep cleanup operations idempotent and auditable.

## Retention Policy

| Resource | Hot / Active Retention | Cold / Archive Retention | Cleanup Cadence |
|---|---:|---:|---|
| Docker images | 30 days for non-pinned tags | 90 days for registry cleanup | Weekly |
| Docker volumes (orphaned) | 0 days | N/A | On container stop / weekly audit |
| NAS hot backups | 30 days | 90 days cold archive | Daily / weekly |
| Terraform state | Continuous | Backed up with NAS policy | Continuous |
| CI artifacts | 14 days | 30 days when archived | GitHub Actions + monthly archive |
| Triage artifacts | 30 days | Archive to NAS cold storage | Monthly |
| Prometheus metrics | 15 days local | Long-term if required | Automated rotation |
| Stale branches | 7 days post-merge | N/A | Weekly |

## Planned Cleanup Automation

- `scripts/ops/cleanup-docker-resources.sh` — prune old images, stopped containers, and orphaned volumes.
- `scripts/ops/cleanup-nas-storage.sh` — archive or delete stale NAS data according to the retention table.
- `scripts/ops/cleanup-stale-branches.sh` — remove merged branches that are older than the retention window.
- `scripts/ops/audit-idle-resources.sh` — report idle resources and cost hot spots without deleting anything.

## Safe Operating Rules

1. Never delete pinned images or active volumes.
2. Never remove a backup until the archive copy is validated.
3. Never clean a resource without logging the action and its reason.
4. Prefer dry-run output before the first destructive action.
5. Make every cleanup safe to re-run.

## Validation Steps

1. Run `docker system df` and compare against the expected threshold.
2. Review `docker stats --no-stream` output for long-lived low-usage containers.
3. Confirm `gh api rate_limit` remains above the documented safety threshold.
4. Confirm `docker volume ls -f dangling=true` returns no orphaned volumes after cleanup.
5. Confirm NAS utilization stays below the documented alert threshold.
6. Confirm stale branches are removed only after merge and age checks pass.

## Related Automation

- [scripts/ops/cleanup-stale-branches.sh](../../scripts/ops/cleanup-stale-branches.sh)
- [scripts/lib/nas.sh](../../scripts/lib/nas.sh)
- [docs/operations/DISASTER-RECOVERY.md](DISASTER-RECOVERY.md)
