# Runbook: Backup Job Failures (BackupJobFailed)

**Alert**: `BackupJobFailed` (Severity: CRITICAL)  
**Component**: Backup system  
**Related Issue**: #569

## Overview

This alert fires when backup job errors are detected in the last 5 minutes. Backups are critical for disaster recovery and data retention.

## Quick Response

```bash
# 1. Check backup service status
docker-compose ps | grep backup

# 2. View recent backup logs
docker-compose logs --tail 100 backup

# 3. Check disk space availability
df -h /data/backups

# 4. Verify database connectivity
docker-compose exec postgres pg_isready -h postgres -U codeserver
```

## Detailed Investigation

### Step 1: Determine Failure Type

```bash
# Check Prometheus metrics
curl -s http://prometheus:9090/api/v1/query?query=backup_errors_total | jq .

# Check backup job status in database
docker-compose exec postgres psql -U codeserver -d codeserver -c \
  "SELECT job_id, status, last_error, created_at FROM backup_jobs ORDER BY created_at DESC LIMIT 5;"
```

### Step 2: Common Failure Causes

| Cause | Detection | Resolution |
|-------|-----------|------------|
| Disk full | `df -h /data` shows 100% | Delete old backups: `rm /data/backups/backup-*.tar.gz` (keep last 5) |
| PostgreSQL down | `docker-compose ps` postgres not running | `docker-compose restart postgres && wait 30s` |
| Network issue | `docker-compose exec backup ping postgres` fails | Check `docker network ls` and connectivity |
| Backup destination unreachable | Logs show connection timeout | Verify backup storage (S3, NFS, local) is accessible |
| Retention exceeded | Backup count too high | Increase `BACKUP_RETENTION_DAYS` in .env |

### Step 3: Manual Backup Execution

```bash
# Force a full backup now
docker-compose exec backup backup-now --full

# Monitor backup progress
docker-compose exec backup tail -f /var/log/backup.log

# Verify backup completed
docker-compose exec backup ls -lh /data/backups/ | tail -3
```

### Step 4: Verify Recovery

```bash
# Test backup restoration
docker-compose exec backup backup-test-restore --latest

# Check restored data integrity
docker-compose exec postgres psql -U codeserver -d codeserver -c "SELECT COUNT(*) FROM users;" 
```

## Prevention

- **Monitor backup_errors_total** continuously (alert: already configured)
- **Daily manual checks**: `docker-compose exec backup backup-status`
- **Monthly restore drill**: Test backup recovery process
- **Disk monitoring**: Alert at 80% capacity (see DiskSpaceWarning)

## Escalation

If error persists after remediation:
1. Check backup service logs: `docker-compose logs backup | grep -i error`
2. Contact database team — may indicate larger infrastructure issue
3. Check if this affects production backup SLA (typically 99.9% success rate)

## Related Runbooks

- [DiskSpaceWarning](disk-space-cleanup.md) — Check if disk is full
- [PostgreSQL Connection Issues](postgresql-replication-lag.md) — Database connectivity
