---
title: Storage Hygiene and Artifact Retention Policy
description: Retention windows, cleanup rules, protected assets, and incident recovery procedures
owner: "@kushin77"
last_review_date: 2026-04-26
status: active
related_issues: ["#896", "#891"]
---

# Storage Hygiene and Artifact Retention Policy

## Goal

Continuously detect and safely remove orphaned Docker containers, images, volumes, and build cache while maintaining audit trail, enabling rollback, and protecting critical stateful assets.

## Retention Policy

### Docker Images

**Retention Window**: 7 days (configurable via `IMAGE_RETENTION_DAYS`)

**Criteria for Cleanup**:
- Dangling images (tag = `<none>:<none>`)
- Images unused by any running/stopped container for >7 days
- Exclude: Images listed in `PROTECTED_IMAGES`

**Protected Images** (never delete):
- `code-server`
- `caddy`
- `oauth2-proxy`
- `postgres`
- `redis`
- `prometheus`
- `grafana`
- `ubuntu`
- `alpine`

**Action**: Remove with `docker rmi -f` after dry-run validation

**Metrics Tracked**:
- Total images scanned
- Orphaned images found
- Space reclaimed (in MB)

---

### Docker Containers

**Retention Window**: 3 days (configurable via `CONTAINER_RETENTION_DAYS`)

**Criteria for Cleanup**:
- Status = `Exited` (stopped with exit code ≠ 0)
- Status = `Unhealthy` (failed health check, no recovery)
- Age > 3 days without activity
- Exclude: Containers in `PROTECTED_CONTAINERS`

**Protected Containers** (never delete):
- `code-server`
- `caddy`
- `oauth2-proxy`
- `postgres`
- `redis`
- `prometheus`
- `grafana`

**Action**: Remove with `docker rm -f` after dry-run validation

**Exception**: Containers in `Exited` state within 3 days are retained for forensics (logs, env, config recovery)

---

### Volumes

**Retention Window**: 7 days (configurable via `VOLUME_RETENTION_DAYS`)

**Criteria for Cleanup**:
- Status = `Unused` (not mounted by any container)
- Not in `PROTECTED_VOLUMES` allowlist
- No data writes detected for >7 days

**Protected Volumes** (never delete):
- `postgres-data` (production state)
- `redis-data` (production cache)

**Action**: Remove with `docker volume rm` after dry-run validation

**Exception**: Stateful volumes backing long-running services are NEVER auto-deleted; require explicit policy update

---

### Build Cache

**Retention Window**: 14 days (configurable via `BUILD_CACHE_RETENTION_DAYS`)

**Criteria for Cleanup**:
- Unused build cache layers (not referenced by any image built in last 14 days)
- Intermediate layers from cancelled builds

**Action**: Prune with `docker buildx prune -af` or `docker builder prune`

**Exception**: Skip if no build activity detected in 14 days

---

### Container Logs

**Retention Window**: 30 days (configurable via `LOG_RETENTION_DAYS`)

**Note**: Docker logs are managed by Docker daemon, not this script. Log rotation is configured in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

**Action**: Docker daemon automatically rotates logs per config; script only reports status

---

## Cleanup Modes

### Dry-Run (Default, Safe)

```bash
DRY_RUN=1 APPLY_CLEANUP=0 bash scripts/ops/docker-storage-hygiene.sh
```

**Behavior**:
- Scans all objects
- Reports what WOULD be deleted
- Does NOT modify any state
- Safe to run on production
- Generates full report for review

**Output**:
```
[2026-04-26 10:00:00] [ORPHANED] Dangling image: a1b2c3d4e5f6 (512MB)
[2026-04-26 10:00:00]     → [DRY-RUN] Would delete: a1b2c3d4e5f6
[2026-04-26 10:00:00] [PROTECTED] postgres (ID: f6e5d4c3b2a1)
```

### Apply Cleanup (Destructive)

```bash
DRY_RUN=0 APPLY_CLEANUP=1 bash scripts/ops/docker-storage-hygiene.sh
```

**Behavior**:
- Scans all objects
- Deletes orphaned/stale objects matching policy
- Generates audit log
- Reports space reclaimed
- **Irreversible** — deleted objects cannot be recovered (except from backups)

**Output**:
```
[2026-04-26 10:00:00] [ORPHANED] Dangling image: a1b2c3d4e5f6 (512MB)
[2026-04-26 10:00:00]     → DELETING: a1b2c3d4e5f6
[2026-04-26 10:00:00] [PROTECTED] postgres (ID: f6e5d4c3b2a1)
```

**Safeguards**:
- Protected assets always skipped (no override)
- Dry-run always precedes apply (review first)
- Deletion logged before execution (audit trail)
- Metrics saved for trend analysis

---

## Invoking Storage Hygiene

### Manual Cleanup

**Review first (dry-run)**:
```bash
bash scripts/ops/docker-storage-hygiene.sh
# Output: artifacts/triage/docker-storage-hygiene-report.log
```

**Then apply if safe**:
```bash
APPLY_CLEANUP=1 bash scripts/ops/docker-storage-hygiene.sh
# Output: artifacts/triage/docker-storage-hygiene-report.log
#         artifacts/metrics/docker-storage-metrics.json
```

### Scheduled Cleanup

Add to cron (weekly, safe dry-run):
```bash
# /etc/cron.d/code-server-storage-hygiene
# Weekly cleanup report (dry-run only, safe)
0 2 * * 1 akushnir cd /home/akushnir/code-server-enterprise && DRY_RUN=1 bash scripts/ops/docker-storage-hygiene.sh
```

Or via systemd timer:
```ini
# /etc/systemd/system/docker-storage-hygiene.service
[Unit]
Description=Docker Storage Hygiene - Weekly Dry-Run Report
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
User=akushnir
WorkingDirectory=/home/akushnir/code-server-enterprise
Environment="DRY_RUN=1"
ExecStart=/bin/bash scripts/ops/docker-storage-hygiene.sh
StandardOutput=journal
StandardError=journal

# /etc/systemd/system/docker-storage-hygiene.timer
[Unit]
Description=Docker Storage Hygiene Timer (Weekly)

[Timer]
OnCalendar=Mon 02:00
Persistent=true

[Install]
WantedBy=timers.target
```

---

## CI/CD Integration

### Scheduled Workflow

`.github/workflows/docker-storage-hygiene.yml` runs weekly:
- **Schedule**: Monday 2 AM UTC (same as docs scan, Terraform drift check)
- **Mode**: Dry-run only (safe for CI)
- **Output**: Report artifact + comment on issue #896
- **Metrics**: JSON metrics appended to trend analysis

```yaml
name: Storage Hygiene Report
on:
  schedule:
    - cron: '0 2 * * 1'  # Monday 2 AM UTC
jobs:
  storage-hygiene:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run dry-run cleanup scan
        run: DRY_RUN=1 bash scripts/ops/docker-storage-hygiene.sh
      - name: Upload report
        uses: actions/upload-artifact@v4
        with:
          name: storage-hygiene-report
          path: artifacts/triage/docker-storage-hygiene-report.log
          retention-days: 90
      - name: Comment on #896 with summary
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const report = fs.readFileSync('artifacts/triage/docker-storage-hygiene-report.log', 'utf8');
            github.rest.issues.createComment({
              issue_number: 896,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `## Weekly Storage Hygiene Report\n\n${report}`
            });
```

---

## Incident Recovery

### If Cleanup Overreached (Deleted Too Much)

**Symptom**: Application failing to start, data missing, build errors

**Recovery Steps**:

1. **Identify what was deleted**:
   ```bash
   grep "DELETING:" artifacts/triage/docker-storage-hygiene-report.log | tail -20
   ```

2. **Assess data loss**:
   - Stateful data (postgres-data, redis-data): Check backups immediately
   - Images: Can be rebuilt from Dockerfile
   - Containers: Can be restarted (if image still available)
   - Volumes: Lost unless backed up

3. **Restore from backup**:
   ```bash
   # If using automated backups
   bash scripts/ops/restore-from-backup.sh --latest
   ```

4. **Rebuild missing images**:
   ```bash
   docker compose build
   ```

5. **Restart services**:
   ```bash
   docker compose up -d
   ```

### Preventing Overreach

1. **Always dry-run first**:
   ```bash
   bash scripts/ops/docker-storage-hygiene.sh  # Default: DRY_RUN=1
   ```

2. **Review report before applying**:
   ```bash
   cat artifacts/triage/docker-storage-hygiene-report.log
   # Verify no critical assets listed for deletion
   ```

3. **Update PROTECTED_* lists before running apply**:
   ```bash
   # Add new critical assets to PROTECTED_CONTAINERS, PROTECTED_VOLUMES
   # Script will never delete them
   ```

4. **Maintain daily backups**:
   - Postgres data: `pg_dump` daily to S3 or NAS
   - Redis data: RDB snapshots daily
   - Critical volumes: Backup snapshots daily

---

## Metrics and Monitoring

### JSON Metrics Output

File: `artifacts/metrics/docker-storage-metrics.json`

```json
{
  "timestamp": "2026-04-26T10:00:00Z",
  "retention_policy": {
    "image_days": 7,
    "container_days": 3,
    "volume_days": 7,
    "log_days": 30,
    "build_cache_days": 14
  },
  "scan_results": {
    "total_images_scanned": 42,
    "orphaned_images": 3,
    "orphaned_containers": 5,
    "orphaned_volumes": 1
  },
  "storage_metrics": {
    "space_reclaimed_mb": 2048
  },
  "mode": "dry-run"
}
```

### Trend Analysis

Over time, track:
- **Space reclaimed per week**: Indicator of cleanup effectiveness
- **Orphaned objects growth**: Increasing orphans may indicate deployment issues
- **Protected asset count**: Growing protection list may signal manual override abuse

---

## Customization

### Per-Environment Retention

```bash
# Production: Longer retention
IMAGE_RETENTION_DAYS=14 CONTAINER_RETENTION_DAYS=7 bash scripts/ops/docker-storage-hygiene.sh

# Staging: Shorter retention (aggressive cleanup)
IMAGE_RETENTION_DAYS=3 CONTAINER_RETENTION_DAYS=1 bash scripts/ops/docker-storage-hygiene.sh

# Development: Very aggressive (free up space quickly)
IMAGE_RETENTION_DAYS=1 CONTAINER_RETENTION_DAYS=0 bash scripts/ops/docker-storage-hygiene.sh
```

### Custom Protected Assets

```bash
# Protect additional assets
PROTECTED_CONTAINERS="code-server,caddy,my-custom-app" bash scripts/ops/docker-storage-hygiene.sh
PROTECTED_VOLUMES="postgres-data,redis-data,my-data" bash scripts/ops/docker-storage-hygiene.sh
```

---

## Related Documents

- [#896 Storage Hygiene Automation](https://github.com/kushin77/code-server/issues/896)
- [#891 Phase 3 Ruthless Ops Governance](https://github.com/kushin77/code-server/issues/891)
- [Backup and Recovery Procedures](./operations/backup-recovery-procedures.md)
- [Incident Response Guide](./operations/incident-response-guide.md)

---

**Last Updated**: 2026-04-26  
**Owner**: @kushin77  
**Status**: Active
