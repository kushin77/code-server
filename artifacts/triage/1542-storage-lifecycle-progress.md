## P3 #1542 Storage Lifecycle Progress

Implemented:
- Added `docs/operations/STORAGE-LIFECYCLE.md`
- Captured retention policy for Docker images, volumes, NAS backups, artifacts, metrics, and stale branches
- Documented the planned cleanup automation surface and validation steps
- Added `scripts/ops/audit-idle-resources.sh` as a non-destructive audit path for idle resources and rate limits

CI enforcement:
- Added `scripts/ci/validate-storage-lifecycle-doc.sh`
- Wired storage lifecycle validation into `.github/workflows/code-smell-governance.yml`

Validation:
- `bash -n scripts/ops/audit-idle-resources.sh` passed
- `bash scripts/ci/validate-storage-lifecycle-doc.sh` passed
