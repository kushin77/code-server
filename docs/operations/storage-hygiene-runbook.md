# Storage Hygiene Runbook

**Issue:** #3160 - Storage & Resource Hygiene: Orphan Cleanup, Lifecycle Policies, Cost-Safe Housekeeping
**Status:** Active reference runbook

## Purpose

This runbook defines the safe inventory and cleanup process for stale containers, unused volumes, dangling images, and other removable artifacts.

The default posture is dry-run first. Cleanup requires explicit approval.

## Scope

- Stopped or orphaned containers
- Dangling or unused Docker images
- Unused Docker volumes
- Hygiene reports and monthly cost tracking evidence

## Primary Entry Points

- [scripts/ops/storage-hygiene-audit.sh](../../scripts/ops/storage-hygiene-audit.sh)
- [.github/workflows/storage-hygiene.yml](../../.github/workflows/storage-hygiene.yml)
- [scripts/ops/rollback-safe.sh](../../scripts/ops/rollback-safe.sh)
- [scripts/ops/verify-docker-compose-idempotency.sh](../../scripts/ops/verify-docker-compose-idempotency.sh)

## Inventory Flow

1. Run the hygiene audit in inventory mode.
2. Review the generated counts and resource lists.
3. Confirm whether any candidate cleanup is actually safe.
4. Archive the inventory report with the month’s operational evidence.

## Cleanup Flow

1. Run a dry-run cleanup first.
2. Review the proposed removals.
3. Obtain approval before any destructive action.
4. Run the approval-gated cleanup mode.
5. Re-run inventory to confirm the cleanup result.

## Rollback Path

If cleanup removes something unexpectedly:

1. Stop further cleanup work.
2. Restore the last known-good deployment from backup using [scripts/ops/rollback-safe.sh](../../scripts/ops/rollback-safe.sh).
3. Recreate or reattach the affected volume or image from source control or artifact backup.
4. Re-run the hygiene inventory to verify the restored state.

## Lifecycle Policy

The repository should treat the following as candidates for pruning only after validation:

- Images not referenced by active deployment manifests
- Containers that are stopped and not referenced by current compose state
- Volumes no longer referenced by any active service

Any cleanup script must document its target set and must support dry-run output.

## Monthly Tracking

Track these metrics each month:

- Removed container count
- Removed image count
- Removed volume count
- Estimated disk space recovered
- Any rollback actions taken

---

**Last Updated:** May 1, 2026
**Owner:** Operations / Platform