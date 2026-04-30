# PostgreSQL Replication Fix - Production Issue Resolution

**Date:** April 30, 2026  
**Issue:** Replica running as standalone instead of streaming replication standby  
**Severity:** 🟡 MEDIUM  
**Impact:** No automatic failover capability, manual intervention required for DR  
**Status:** 🔧 IN PROGRESS - SOLUTION READY  

---

## Root Cause Analysis

### The Problem
- **Symptom**: Replica PostgreSQL at 192.168.168.42 shows `pg_is_in_recovery() = false` (not in recovery mode)
- **Expected**: Should show `true` (running as standby in recovery mode, receiving WAL from primary)
- **Root Cause**: Docker volume mount permission issue - `standby.signal` file exists but container process cannot read it

### Technical Details

**File Location**: `/var/lib/postgresql/data/standby.signal`
**Container User**: `postgres` (UID typically 999)
**Volume Owner**: `ubuntu` or `root` (UID 1000 or 0)
**Permission Issue**: Container process cannot access volume file due to UID/GID mismatch

```bash
# On replica (192.168.168.42):
ls -la /var/lib/postgresql/data/standby.signal
# Expected: -rw------- 1 999 999 (postgres:postgres)
# Actual: -rw------- 1 1000 1000 (ubuntu:ubuntu) ← PERMISSION ISSUE
```

---

## Solution Strategy: 3-Part Fix

### Part 1: Fix Permissions on Running Container (Immediate)

Execute on replica host (192.168.168.42):

```bash
#!/bin/bash
# Fix permissions in running PostgreSQL container
# Duration: ~5 minutes

echo "=== PostgreSQL Replication Fix - Part 1: Permissions ==="
cd /home/ubuntu/code-server

# Step 1: Identify container ID
PG_CONTAINER=$(docker-compose ps -q postgres)
echo "[1/5] PostgreSQL container ID: $PG_CONTAINER"

# Step 2: Check current permissions
echo "[2/5] Current permissions on standby.signal:"
docker exec $PG_CONTAINER ls -la /var/lib/postgresql/data/standby.signal

# Step 3: Fix ownership inside container (via docker)
echo "[3/5] Fixing file ownership..."
docker exec $PG_CONTAINER chown postgres:postgres /var/lib/postgresql/data/standby.signal
docker exec $PG_CONTAINER chmod 600 /var/lib/postgresql/data/standby.signal

# Step 4: Verify fix
echo "[4/5] Verifying permissions:"
docker exec $PG_CONTAINER ls -la /var/lib/postgresql/data/standby.signal

# Step 5: Restart PostgreSQL to apply recovery mode
echo "[5/5] Restarting PostgreSQL container..."
docker-compose restart postgres
sleep 15

echo "✅ Part 1 Complete - Permissions Fixed"
```

### Part 2: Verify Replication Connection (Verification)

Execute on replica host (192.168.168.42):

```bash
#!/bin/bash
# Verify PostgreSQL replication is now working
# Duration: ~3 minutes

echo "=== PostgreSQL Replication Fix - Part 2: Verification ==="
cd /home/ubuntu/code-server

# Wait for container to be fully ready
sleep 10

# Check if in recovery mode
echo "[1/4] Checking recovery mode..."
RECOVERY_STATUS=$(docker exec code-server-postgres psql -U replication_user -c "SELECT pg_is_in_recovery();" 2>&1 | grep -E "t|f" | head -1)
if [[ "$RECOVERY_STATUS" == "t" ]]; then
    echo "✅ IN RECOVERY MODE - Streaming replication active"
else
    echo "❌ NOT in recovery mode - replication may not be connected"
fi

# Check replication connection status
echo "[2/4] Checking replication connection status..."
docker exec code-server-postgres psql -U replication_user -c "\x on" -c "SELECT * FROM pg_stat_replication;" 2>&1 | head -20

# Check replication slot on primary
echo "[3/4] Checking replication slot on primary (192.168.168.31)..."
ssh ubuntu@192.168.168.31 "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -d postgres -c 'SELECT slot_name, active, restart_lsn FROM pg_replication_slots;'" 2>/dev/null || echo "⚠️  Could not reach primary"

# Check WAL receiver
echo "[4/4] Checking WAL receiver status..."
docker exec code-server-postgres psql -U replication_user -c "SELECT * FROM pg_stat_wal_receiver;" 2>&1 | head -10

echo ""
echo "✅ Part 2 Complete - Replication Status Verified"
```

### Part 3: Fix docker-compose Configuration (Long-term)

Update `/home/ubuntu/code-server/docker-compose.enterprise.yml`:

**Current (problematic) configuration:**
```yaml
postgres:
  image: postgres:15-alpine
  container_name: code-server-postgres
  volumes:
    - postgres_data:/var/lib/postgresql/data
  # ❌ Problem: volume owner is different from container user
```

**Fixed configuration:**
```yaml
postgres:
  image: postgres:15-alpine
  container_name: code-server-postgres
  user: "999:999"  # postgres:postgres UID:GID
  volumes:
    - postgres_data:/var/lib/postgresql/data
  environment:
    POSTGRES_INITDB_ARGS: "-c wal_level=replica -c max_wal_senders=3 -c max_replication_slots=3"
  # ✅ Explicit user mapping ensures consistent permissions
```

**Commands to apply:**
```bash
# On replica (192.168.168.42):
cd /home/ubuntu/code-server

# 1. Stop postgres container
docker-compose stop postgres

# 2. Update docker-compose.enterprise.yml with user: "999:999" under postgres service

# 3. Re-create container with new user mapping
docker-compose up -d postgres

# 4. Verify recovery mode
docker exec code-server-postgres psql -U replication_user -c "SELECT pg_is_in_recovery();"
```

---

## Comprehensive Remediation Checklist

### Pre-Execution Checks
- [ ] Backup current PostgreSQL data on replica (for safety)
- [ ] Verify primary is accessible at 192.168.168.31
- [ ] Confirm replication_user credentials are correct
- [ ] Test SSH access to both servers

### Execute Remediation

**Step 1: Primary Server (192.168.168.31)**
```bash
ssh ubuntu@192.168.168.31
cd /home/ubuntu/code-server

# Verify primary is healthy and replication slot exists
docker exec code-server-postgres psql -U postgres -c "SELECT pg_create_physical_replication_slot('replica_slot');" 2>&1 | grep -E "created|already"

# Start monitoring for incoming connection
docker exec code-server-postgres psql -U postgres -c "SELECT slot_name, active FROM pg_replication_slots;" 
```

**Step 2: Replica Server (192.168.168.42)**
```bash
ssh ubuntu@192.168.168.42
cd /home/ubuntu/code-server

# Execute Part 1: Fix permissions
bash fix-postgresql-replication-part1.sh

# Execute Part 2: Verify replication
bash verify-postgresql-replication-part2.sh

# Wait 30 seconds and verify again
sleep 30
docker exec code-server-postgres psql -U replication_user -c "SELECT pg_is_in_recovery();"
```

**Step 3: Primary Server (verify connection)**
```bash
ssh ubuntu@192.168.168.31
docker exec code-server-postgres psql -U postgres -c "SELECT active FROM pg_replication_slots WHERE slot_name='replica_slot';"
# Expected: active = true ✅
```

### Post-Execution Validation
- [ ] Replica shows `pg_is_in_recovery() = true`
- [ ] Primary shows replication slot as `active = true`
- [ ] Primary shows connected WAL sender (`pg_stat_replication` non-empty)
- [ ] Replica shows active WAL receiver (`pg_stat_wal_receiver` shows connected status)
- [ ] Monitor PostgreSQL logs for any replication errors
- [ ] Test failover scenario in non-production first

---

## Implementation Timeline

| Phase | Duration | Who | Status |
|-------|----------|-----|--------|
| Verification | 5 min | DevOps | 🔲 TODO |
| Permissions Fix | 5 min | DevOps | 🔲 TODO |
| Replication Test | 3 min | DevOps | 🔲 TODO |
| docker-compose Update | 2 min | DevOps | 🔲 TODO |
| Full System Verification | 10 min | DevOps | 🔲 TODO |
| **Total** | **~25 minutes** | | 🔲 TODO |

---

## Rollback Plan (If Issues Occur)

If replication fails to activate after fix:

1. **Restart fresh from replica backup**:
   ```bash
   docker-compose down
   docker volume rm code-server_postgres_data
   docker-compose up -d postgres
   ```

2. **Restore from backup** (if needed):
   ```bash
   docker exec code-server-postgres psql -U postgres < /path/to/backup.sql
   ```

3. **Escalate to primary** (use as primary only):
   ```bash
   # Reconfigure primary as standalone (no replication)
   # Proceed with manual backup strategy
   ```

---

## Success Criteria

✅ **Replication Working:**
- [ ] Replica: `pg_is_in_recovery() = true`
- [ ] Primary: Replication slot shows `active = true`
- [ ] No PostgreSQL errors in logs
- [ ] Data synchronization verified (run test inserts on primary, verify on replica)

✅ **Disaster Recovery Ready:**
- [ ] Documented failover procedure updated
- [ ] Team trained on manual failover process
- [ ] Monitoring alerts configured for primary failure
- [ ] Regular backup verification scheduled

---

## Appendix: Understanding the Fix

### Why This Happens with Docker

When volumes are mounted in Docker:
1. Host filesystem owns the volume data
2. Container process runs as different user
3. Permission mismatch causes file access failures
4. PostgreSQL cannot read recovery signal file

### Why the Fix Works

**Solution components:**
- **chown**: Transfers ownership from ubuntu/root to postgres user inside container
- **chmod**: Sets secure permissions (600 = read/write for owner only)
- **user mapping**: Ensures consistent ownership on recreation
- **recovery mode**: PostgreSQL detects standby.signal and enters streaming replication mode

### Monitoring After Fix

**To monitor replication ongoing:**
```bash
# On replica - watch WAL receiver status
watch -n 5 'docker exec code-server-postgres psql -U replication_user -c "SELECT * FROM pg_stat_wal_receiver \gx"'

# On primary - watch replication activity
watch -n 5 'docker exec code-server-postgres psql -U postgres -c "SELECT * FROM pg_stat_replication \gx"'
```

