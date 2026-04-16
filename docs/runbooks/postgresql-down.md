# Runbook: PostgreSQL Down

**Alert**: PostgreSQLDown  
**Severity**: CRITICAL  
**SLA**: Resolve within 20 minutes (data not accessible)  
**Owner**: Database Team  

## Symptoms

- Alert: "PostgreSQL is down"
- Database connection refused (port 5432)
- All services depending on database are failing
- Prometheus postgres_exporter cannot connect

## Root Causes

1. PostgreSQL process crashed
2. Disk full (cannot write WAL)
3. Out of memory
4. Port conflict or firewall issue
5. Corrupted database files

## Diagnosis

```bash
# Check container
docker ps | grep postgres
docker logs postgres | tail -50

# Test connectivity
psql -h localhost -U postgres -d postgres -c "SELECT 1"

# Check port
netstat -tuln | grep 5432

# Check volumes
docker inspect postgres | grep -A 5 Mounts

# Check disk
df -h /var/lib/docker/volumes/
```

## Remediation

### Step 1: Check Container (1 min)
```bash
docker ps -a | grep postgres
```

**If running**: Likely connection issue → Step 2  
**If stopped**: Crashed → Step 3  

### Step 2: Test Connectivity (2 min)
```bash
psql -h localhost -U postgres -d postgres -c "SELECT 1"

# If error: check logs
docker logs postgres --tail 100
```

**If "too many connections"**: Kill idle connections
```bash
psql -h localhost -U postgres -d postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle'"
```

### Step 3: Restart Container (5 min)
```bash
docker-compose restart postgres
sleep 10

# Verify connectivity
psql -h localhost -U postgres -d postgres -c "SELECT 1"
```

**If healthy**: Resolved  
**If still failing**: Go to Step 4  

### Step 4: Check Disk Space (3 min)
```bash
df -h | grep var
df -h /data

# If > 90% full: cleanup
# WAL archive: docker exec postgres rm /var/lib/postgresql/pg_wal/*.backup
```

### Step 5: Check Data Integrity (5 min)
```bash
# If disk was full or crash detected, check FSCK
docker exec postgres pg_controldata /var/lib/postgresql/data | grep "Database cluster state"

# If state != "shut down", need recovery
docker exec postgres postgres --single -D /var/lib/postgresql/data < /dev/null
```

### Step 6: Recovery from Backup (10 min)
```bash
# If data corrupted, restore from latest backup
docker-compose down postgres
docker volume rm codeserver_postgres_data

# Restore from NAS backup
rsync -av /mnt/nas-56/backups/postgres-latest/ /var/lib/docker/volumes/codeserver_postgres_data/_data/

docker-compose up -d postgres
sleep 10

# Verify
psql -h localhost -U postgres -d postgres -c "SELECT 1"
```

## Prevention

- [ ] Configure automated backups (hourly snapshots to NAS)
- [ ] Set up disk space monitoring alert (< 20% free)
- [ ] Review crash logs in postgresql.log
- [ ] Implement connection pooling (pgbouncer)
- [ ] Set max_connections to reasonable limit (50 default is low)

## Escalation

If unresolved after 20 minutes:
1. All data access is blocked
2. Page database team lead immediately
3. Evaluate restore from backup
4. Consider RTO/RPO impact
5. Implement manual transaction log recovery if backup not viable

---

**Status**: Ready for production deployment  
**Last Updated**: April 16, 2026  
**Runbook Owner**: Database Team
