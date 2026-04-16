# Alert Runbook: Backup Failed

**Alert**: `BackupFailed`  
**Severity**: CRITICAL  
**SLA**: Resolve within 2 hours  
**Owner**: Database/Infrastructure Team  

---

## Problem

Automated backup has not completed successfully in 25+ hours. This indicates:
- Backup process crashed or hung
- Storage destination unreachable (NAS, cloud storage, etc.)
- Insufficient disk space to write backup
- Backup script permissions changed
- Data loss risk if primary database fails before successful backup

---

## Immediate Investigation (< 5 minutes)

### 1. Check Backup Service Status

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# View backup service status
docker ps | grep backup
docker logs backup-service --tail 50

# Check if backup is currently running
pgrep -f "backup.sh" || echo "No backup process running"
ps aux | grep backup
```

### 2. Check Last Backup Timestamp

```bash
# Query Prometheus for last successful backup
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=time() - backup_last_success_timestamp_seconds' | jq .

# Check backup directory
ls -lh /mnt/backups/ | tail -10
stat /mnt/backups/latest.sql.gz

# Check backup log
tail -100 /var/log/backup.log
```

### 3. Check Storage Connectivity

```bash
# If NAS-mounted:
mount | grep backup
df -h /mnt/backups/

# If cloud storage (S3, etc.):
aws s3 ls s3://backup-bucket/ --region us-west-1 --max-items 10

# If local storage:
du -sh /mnt/backups/
df -h /  # Check root disk space
```

---

## Common Root Causes & Fixes

### Cause 1: NAS Disconnected

**Symptoms**:
- `mount | grep backup` shows no mount
- `/mnt/backups/` is empty or inaccessible
- Logs: "Connection refused" or "Stale NFS handle"

**Fix**:
```bash
# Remount NAS
sudo umount /mnt/backups/
sudo mount -t nfs nas.internal:/export/backups /mnt/backups

# Verify connectivity
touch /mnt/backups/test.txt && rm /mnt/backups/test.txt

# Trigger backup manually
/opt/scripts/backup.sh --force

# Verify success
ls -lh /mnt/backups/latest.sql.gz
stat /mnt/backups/latest.sql.gz | grep Modify
```

### Cause 2: Insufficient Disk Space

**Symptoms**:
- `df /mnt/backups/` shows full or near-full
- Logs: "No space left on device"
- Database size increased unexpectedly

**Fix**:
```bash
# Check disk usage
du -sh /mnt/backups/* | sort -h | tail -5

# Archive/delete old backups (keep last 30 days)
find /mnt/backups -name "*.sql.gz" -mtime +30 -delete

# Compress older backups (if not already)
for f in /mnt/backups/*.sql; do gzip "$f"; done

# Verify space
df -h /mnt/backups/

# Retry backup
/opt/scripts/backup.sh --force
```

### Cause 3: PostgreSQL Process Down

**Symptoms**:
- `docker ps` shows postgres container not running
- Logs: "Connection refused" or "PostgreSQL not responding"

**Fix**:
```bash
# Check postgres container
docker logs postgres --tail 50

# Restart postgres
docker-compose down
docker-compose up -d postgres
docker-compose logs postgres  # Wait for "ready to accept connections"

# Trigger backup
/opt/scripts/backup.sh --force
```

### Cause 4: Insufficient Permissions

**Symptoms**:
- Logs: "Permission denied" when writing to /mnt/backups
- Logs: "Cannot read from PostgreSQL" or "Access denied"

**Fix**:
```bash
# Check permissions
ls -ld /mnt/backups/
getfacl /mnt/backups/

# Fix ownership
sudo chown backup:backup /mnt/backups/
sudo chmod 755 /mnt/backups/

# Verify backup user can connect to PostgreSQL
docker exec postgres psql -U backup -d template1 -c "SELECT 1;"

# Retry backup
/opt/scripts/backup.sh --force
```

### Cause 5: Backup Script Timeout

**Symptoms**:
- Database > 100GB
- Backup takes > 2 hours to complete
- Logs: "Timeout exceeded" or process killed

**Fix**:
```bash
# Check backup size and estimated time
du -sh /var/lib/postgresql/data/
time /opt/scripts/backup.sh --estimate  # Dry run to see duration

# If > 2 hours, increase timeout
vi /opt/scripts/backup.sh
# Change: timeout 90m → timeout 180m

# Run full backup in background
nohup /opt/scripts/backup.sh --force > /var/log/backup.log 2>&1 &

# Monitor progress
tail -f /var/log/backup.log
watch "du -sh /mnt/backups/latest.sql*"
```

---

## Verification

After applying fix, verify success:

```bash
# 1. Check Prometheus metric
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=backup_last_success_timestamp_seconds' | jq .

# 2. Verify file exists and recent
ls -lh /mnt/backups/latest.sql.gz
stat /mnt/backups/latest.sql.gz | grep "Modify:"

# 3. Verify file is not corrupted
file /mnt/backups/latest.sql.gz
gunzip -t /mnt/backups/latest.sql.gz && echo "OK" || echo "CORRUPTED"

# 4. Alert should clear within 5 minutes
# Query alerts
curl -s http://localhost:9093/api/v1/alerts | jq '.data[] | select(.labels.alertname=="BackupFailed")'
```

---

## Escalation

If backup still failing after 30 minutes of troubleshooting:

1. **Check for database corruption**:
   ```bash
   docker exec postgres pg_dump -U backup -d postgres --pre-data > /tmp/test_dump.sql
   echo $?  # Should be 0
   ```

2. **Check PostgreSQL logs**:
   ```bash
   docker logs postgres | grep -i error | tail -20
   docker exec postgres journalctl -u postgresql --no-pager
   ```

3. **Contact DBA/Infrastructure team**:
   - Slack: @dba-oncall
   - Page: pagerduty incident for critical data loss risk
   - Include: Backup logs, PostgreSQL logs, disk space stats, error messages

---

## Prevention

**Schedule post-backup verification**:
```bash
# In crontab after backup completes:
if [ ! -f /mnt/backups/latest.sql.gz ]; then
  # Alert: Backup verification failed
  send_alert "CRITICAL" "Backup file does not exist"
fi

if [ $(stat -c %Y /mnt/backups/latest.sql.gz) -lt $(date -d '25 hours ago' +%s) ]; then
  # Alert: Backup is too old
  send_alert "CRITICAL" "Backup is stale"
fi
```

**Monitor backup size trends**:
- If growing faster than expected, investigate data explosion
- If shrinking, investigate data deletion (potential breach)

**Test restore procedure weekly**:
```bash
# Restore to test database once per week
docker-compose up -d postgres-test
gunzip -c /mnt/backups/latest.sql.gz | docker exec -i postgres-test psql -U backup
# Verify data integrity
```

---

**Document**: ops-runbooks/backup-failure.md  
**Last Updated**: 2026-04-15  
**Approved By**: Infrastructure Lead  
