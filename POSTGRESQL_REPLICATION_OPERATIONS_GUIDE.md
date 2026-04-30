# PostgreSQL Replication Fix - Operations Execution Guide

**Date:** April 30, 2026  
**Target:** May 1 Go-Live Day Preparation  
**Duration:** ~30 minutes total  
**Complexity:** MEDIUM (technical, but fully automated)  

---

## Executive Summary

The PostgreSQL replica database at 192.168.168.42 is currently running as a standalone database instead of in streaming replication mode from the primary. This means:

❌ **Current State:** No automatic failover capability
✅ **After Fix:** Automatic failover enabled, full disaster recovery ready
⏱️ **Time Required:** ~30 minutes including verification

---

## Prerequisites

### Required Access
- [ ] SSH access to primary server (192.168.168.31) as ubuntu user
- [ ] SSH access to replica server (192.168.168.42) as ubuntu user
- [ ] Ability to run docker and docker-compose commands on both servers
- [ ] PostgreSQL database must be running on both servers

### Required Knowledge
- [ ] Basic Docker container operations
- [ ] Understanding of PostgreSQL replication (optional but helpful)
- [ ] SSH key authentication configured (preferred over password)

### Verification Commands (Run Before Starting)

```bash
# On both primary and replica
ssh ubuntu@192.168.168.31 "docker-compose ps"
ssh ubuntu@192.168.168.42 "docker-compose ps"

# Both should show postgres container as "Up"
# If not, start: docker-compose up -d postgres
```

---

## Execution Steps

### Step 1: Prepare (5 minutes)

**Run on your management/jump host:**

```bash
# Download or verify you have all fix scripts
cd /path/to/deployment
ls -la fix-postgresql-replication-part*.sh
ls -la verify-postgresql-replication-part*.sh
ls -la update-postgresql-replication-part*.sh
ls -la orchestrate-postgresql-replication-fix.sh

# Verify scripts are executable
file fix-postgresql-replication-part1.sh | grep "executable"
```

**If scripts not present:**
```bash
# Copy from control repository
git pull origin main
git checkout POSTGRESQL_REPLICATION_FIX.md
git checkout fix-postgresql-replication-part*.sh
git checkout verify-postgresql-replication-part*.sh
git checkout update-postgresql-replication-part*.sh
git checkout orchestrate-postgresql-replication-fix.sh
```

**Make executable:**
```bash
chmod +x *postgresql-replication*.sh
```

### Step 2: Execute Fix on Replica (10 minutes)

**SSH to replica and run orchestrated fix:**

```bash
# Connect to replica
ssh ubuntu@192.168.168.42

# Navigate to deployment directory
cd /home/ubuntu/code-server

# Run the master orchestration script
bash orchestrate-postgresql-replication-fix.sh

# The script will:
# 1. Run Part 1: Fix permissions (4-5 min)
# 2. Run Part 2: Verify replica status (3-5 min)
# 3. Run Part 3: Check primary from replica (2-3 min)
# 4. Ask if you want Part 4: Update docker-compose (optional)
```

**Expected Output:**
```
✅ Part 1: PostgreSQL permissions fixed
✅ Part 2: Replication status verified (replica side)
✅ Part 3: Replication status verified (primary side)
```

**Watch for these success indicators:**

**Replica side (Part 2):**
```
✅ IN RECOVERY MODE - Streaming replication is ACTIVE
```

**Primary side (Part 3):**
```
✅ Replication slot ACTIVE - Replica is connected
✅ 1 WAL sender(s) connected
```

### Step 3: Verify Replication is Working (10 minutes)

**On replica host:**

```bash
# Monitor replication status in real-time
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && watch -n 5 'docker exec code-server-postgres psql -U postgres -d postgres -t -c \"SELECT pg_is_in_recovery(); SELECT client_addr, state, sync_state FROM pg_stat_wal_receiver \\\\gx\"'"

# Should see:
# pg_is_in_recovery = t  ✅ (in recovery mode)
# client_addr = 192.168.168.31  ✅ (connected to primary)
# state = streaming  ✅ (actively receiving WAL)
```

**On primary host:**

```bash
# Monitor replication slot
ssh ubuntu@192.168.168.31 "cd /home/ubuntu/code-server && watch -n 5 'docker exec code-server-postgres psql -U postgres -d postgres -t -x -c \"SELECT * FROM pg_replication_slots; SELECT * FROM pg_stat_replication\"'"

# Should see:
# slot_name = replica_slot
# active = t  ✅ (slot is active)
# client_addr = 192.168.168.42  ✅ (replica connected)
```

**Run manual test (verify data sync):**

```bash
# Create test data on primary
ssh ubuntu@192.168.168.31 "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -d postgres -c 'CREATE TABLE IF NOT EXISTS replication_test (id SERIAL PRIMARY KEY, test_data TEXT); INSERT INTO replication_test (test_data) VALUES (NOW()::text);'"

# Verify on replica (should see the same data)
sleep 2
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -d postgres -c 'SELECT * FROM replication_test;'"

# If you see the inserted data, replication is working! ✅

# Clean up
ssh ubuntu@192.168.168.31 "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -d postgres -c 'DROP TABLE replication_test;'"
```

### Step 4: Optional - Update docker-compose (2 minutes)

This makes the fix permanent so it survives container recreation:

```bash
# If not already done during orchestration:
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && bash update-postgresql-replication-part4.sh"

# This updates the user mapping in docker-compose so that:
# - On next container recreation
# - Permissions will be automatically correct
# - No manual fix needed in the future
```

### Step 5: Document & Handoff (3 minutes)

**Create deployment record:**

```bash
# Save fix logs to deployment records
mkdir -p /deployment-records/$(date +%Y-%m-%d)

# Copy from replica
scp ubuntu@192.168.168.42:/home/ubuntu/postgresql*.log /deployment-records/$(date +%Y-%m-%d)/

# Document in operations log
cat >> OPERATIONS_LOG.md <<EOF

## PostgreSQL Replication Fix - Applied $(date)
- Status: ✅ COMPLETED
- Replica: 192.168.168.42
- Primary: 192.168.168.31
- Result: Streaming replication ACTIVE
- Verified: Data sync working
- Notes: Replication ready for May 1 go-live

EOF
```

**Notify team:**
```
✅ PostgreSQL replication fix completed
✅ Replica now in streaming replication mode
✅ Automatic failover enabled
✅ Ready for May 1 go-live deployment
```

---

## Troubleshooting

### Issue: Replication not activating after Part 1

**Check 1: Is standby.signal file present?**
```bash
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker exec code-server-postgres ls -la /var/lib/postgresql/data/standby.signal"
```

**Check 2: Verify permissions are correct**
```bash
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker exec code-server-postgres stat /var/lib/postgresql/data/standby.signal | grep Access"
# Should show: Uid: ( 999/ postgres)
```

**Check 3: Review PostgreSQL logs**
```bash
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker logs code-server-postgres 2>&1 | tail -50"
# Look for replication error messages
```

**Check 4: Verify primary is reachable**
```bash
ssh ubuntu@192.168.168.42 "nc -zv 192.168.168.31 5432"
# Should show: Connection to 192.168.168.31 port 5432 [tcp/postgresql] succeeded!
```

### Issue: Replica says "NOT in recovery mode" after Part 1

**This is normal if:**
- Fix was just applied (replication takes a few seconds to activate)
- Primary is temporarily unreachable
- Network connectivity between servers is disrupted

**Solution:**
```bash
# Wait 30-60 seconds
sleep 30

# Manually restart PostgreSQL
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker-compose restart postgres"

# Check again
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -d postgres -c 'SELECT pg_is_in_recovery();'"
```

### Issue: Primary has no connected replication slot

**Primary output shows:**
```
slot_name | active
-----------+--------
           |       
(0 rows)
```

**Or shows active=false**

**Solutions (in order of preference):**

1. **Wait 30-60 seconds** - Replica may still be connecting
2. **Check network connectivity** - Ensure firewall allows 5432 between hosts
3. **Verify credentials** - Replica replication_user can connect to primary
4. **Restart replica PostgreSQL** - Hard reset for fresh connection attempt
5. **Check primary logs** - Look for authentication or replication errors

---

## Rollback Procedures

If replication fix causes issues:

### Option 1: Restart Containers (Fastest)

```bash
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker-compose restart"

# Wait 30 seconds, verify state
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker-compose ps"
```

### Option 2: Revert to Previous Config

```bash
# If Part 4 was run and backup exists:
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && ls -la docker-compose.enterprise.yml.backup_* | head -1"

# Restore most recent backup
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && cp docker-compose.enterprise.yml.backup_$(date +%Y%m%d)_* docker-compose.enterprise.yml"

# Recreate containers
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker-compose down && docker-compose up -d"
```

### Option 3: Manual PostgreSQL Recovery

```bash
# If database is corrupted, restore from backup
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker volume rm code-server_postgres_data"

# Restore from backup
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker-compose up -d postgres"

# Wait for container to initialize
sleep 30

# Run restore procedure
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres < /path/to/backup.sql"
```

---

## Monitoring After Fix

### Short-term (First 24 hours)

Monitor for any issues:
```bash
# Every 30 minutes, check replication status
ssh ubuntu@192.168.168.42 "cd /home/ubuntu/code-server && docker exec code-server-postgres psql -U postgres -d postgres -c 'SELECT pg_is_in_recovery(); SELECT state FROM pg_stat_wal_receiver;'"

# Should consistently show:
# pg_is_in_recovery = t
# state = streaming
```

### Long-term (Ongoing)

Set up monitoring:
- [ ] PostgreSQL replication lag monitoring (Prometheus/Grafana)
- [ ] Alert if `pg_is_in_recovery = false` on replica
- [ ] Alert if replication lag > 1 second
- [ ] Daily backup verification from replica
- [ ] Monthly failover test (in non-production environment)

---

## Success Criteria Checklist

After completing this procedure, verify:

- [ ] Replica in recovery mode (`pg_is_in_recovery = true`)
- [ ] Primary replication slot active (`active = true`)
- [ ] WAL sender connected on primary (`pg_stat_replication` shows 1 sender)
- [ ] WAL receiver streaming on replica (`state = streaming`)
- [ ] Data replication verified (test insert/select successful)
- [ ] All logs clean (no replication errors)
- [ ] Operations team trained on failover procedure
- [ ] Disaster recovery runbook updated

---

## Logs & Records

All operations generate logs automatically:

```bash
# On replica after execution:
ls -la /home/ubuntu/postgresql_*.log

# Archive for records
scp ubuntu@192.168.168.42:/home/ubuntu/postgresql_*.log /deployment-records/
```

---

## Summary

✅ **Objective:** Enable PostgreSQL streaming replication for automatic failover
✅ **Duration:** ~30 minutes
✅ **Risk Level:** LOW (fully reversible, comprehensive logging)
✅ **Ready for:** May 1 go-live with full disaster recovery capability

**After this fix, your PostgreSQL deployment will have:**
- ✅ Streaming replication from primary to replica
- ✅ Automatic failover on primary failure
- ✅ Real-time data consistency
- ✅ Production-grade disaster recovery capability

