# P0 #1635 - NVMe Failure: Comprehensive Incident Action Plan

**Status:** INCIDENT IN PROGRESS  
**Date Started:** April 23, 2026 14:45 UTC  
**Severity:** P0 CRITICAL - Hardware failure + missing DB replication  
**Risk:** Cluster-wide availability if Replica 1 fails (no DB failover capability)

---

## Executive Summary

**What Happened:**
- Replica 2 (192.168.168.42) NVMe drive failed (SMART 0x04 - reliability degraded, self-test failed)
- PostgreSQL is single-instance (only on Replica 1)
- No database replication configured between replicas
- Session state IS protected (Redis Sentinel HA)

**Risk Assessment:**
- ⚠️ **MODERATE:** NVMe failure on Replica 2 (can isolate replica)
- 🔴 **CRITICAL:** Missing PostgreSQL replication (single point of failure on Replica 1)
- ✅ **LOW:** Session/cache loss (Redis Sentinel protects this)

**Action Required:**
1. Isolate Replica 2 immediately (prevent data corruption from failing drive)
2. Backup PostgreSQL (even though empty now, process must be documented)
3. Implement PostgreSQL replication (Patroni) in parallel
4. Order and replace NVMe on Replica 2
5. Redeploy cluster with HA database

---

## Phase 1: Immediate Isolation (15 minutes)

### Step 1.1: Verify Replica 1 Health
```bash
# SSH to Replica 1
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31

# Check all services running
cd code-server-enterprise && docker-compose ps | grep -c "Up"
# Expected: 19-22 services up

# Verify no errors in main services
docker-compose logs --tail 10 caddy oauth2-proxy code-server | grep -i error
# Expected: minimal/no errors

# Test application connectivity
curl -I https://ide.kushnir.cloud/health
# Expected: HTTP 200 OK
```

### Step 1.2: Isolate Replica 2 (Prevent Data Corruption)
```bash
# Option A: Network isolation (non-destructive, keeps data intact)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'sudo iptables -I INPUT 1 -j DROP'

# Verify isolation
ping 192.168.168.42
# Expected: timeout (no response)

# Option B: If Option A doesn't work, gracefully shutdown services
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose down'

# Verify Replica 2 is offline
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'docker-compose logs --tail 5 caddy | grep 192.168.168.42'
# Expected: no connection attempts after isolation
```

### Step 1.3: Verify Replica 1 Handles All Traffic
```bash
# Monitor Replica 1 logs for 5 minutes
for i in {1..5}; do
  echo "=== Minute $i ==="
  ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose logs --tail 2 caddy'
  sleep 60
done

# Check resource utilization on Replica 1
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'top -bn1 | head -20'
# Expected: CPU <60%, Memory <70%
```

---

## Phase 2: Data Protection (30 minutes)

### Step 2.1: Backup PostgreSQL (Even if Empty)
```bash
# Create backup on Replica 1
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose exec -T postgres pg_dump -U codeserver codeserver | gzip > /tmp/pg-backup-$(date +%s).sql.gz'

# Verify backup
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'ls -lh /tmp/pg-backup-*.sql.gz'

# Copy backup to persistent location (NAS)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cp /tmp/pg-backup-*.sql.gz /mnt/nas-export/backups/pg/ 2>/dev/null || echo "NAS mount not available"'
```

### Step 2.2: Document Current State
```bash
# Capture current docker-compose state
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose ps > /tmp/replica-1-services.txt && cat /tmp/replica-1-services.txt'

# Document environment variables
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && cat .env > /tmp/replica-1-env-backup.txt 2>/dev/null || echo "No .env file"'

# Document Replica 2 NVMe status one final time before isolation
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'sudo smartctl -a /dev/nvme0n1 > /tmp/nvme-status-final.txt 2>/dev/null || echo "smartctl not available"'
```

---

## Phase 3: PostgreSQL Replication Setup (2-3 hours)

### Architecture Decision: Patroni vs Streaming Replication

**Patroni (Recommended):**
- ✅ Automatic failover (< 5 seconds)
- ✅ Distributed consensus (uses etcd/Consul)
- ✅ Works with Docker Swarm/Kubernetes
- ✅ Handles split-brain scenarios
- ❌ Additional dependency (etcd/Consul)
- ❌ More complex configuration

**Streaming Replication (Simpler):**
- ✅ Built-in to PostgreSQL
- ✅ No additional dependencies
- ✅ Native WAL replication
- ❌ Manual failover promotion required
- ❌ No automatic split-brain detection

**Recommendation:** Patroni for production, but streaming replication if time-constrained.

### Step 3.1: Streaming Replication (Quick Path - 1 hour)
```bash
# On Replica 1 (Primary)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31

# Update PostgreSQL configuration for replication
docker-compose exec -T postgres psql -U codeserver -d codeserver -c "ALTER SYSTEM SET wal_level = replica"
docker-compose exec -T postgres psql -U codeserver -d codeserver -c "ALTER SYSTEM SET max_wal_senders = 10"
docker-compose exec -T postgres psql -U codeserver -d codeserver -c "ALTER SYSTEM SET wal_keep_size = '1GB'"

# Create replication user
docker-compose exec -T postgres psql -U codeserver -d codeserver -c "CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'CHANGE_ME'"

# Restart PostgreSQL to apply settings
docker-compose restart postgres

# Wait for restart
sleep 10

# Test replication user can connect
docker-compose exec -T postgres psql -U replicator -c "IDENTIFY_SYSTEM" || echo "Replication setup incomplete"
```

### Step 3.2: Restore Replica 2 (Post-Hardware-Replacement)
```bash
# After NVMe replacement and OS reinstall on Replica 2
# Set up replication replica

ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42

# Create base backup from primary
sudo mkdir -p /var/lib/postgresql/replica
sudo pg_basebackup -h 192.168.168.31 -U replicator -D /var/lib/postgresql/replica -Pv -W

# Configure standby mode
echo "standby_mode = 'on'" | sudo tee /var/lib/postgresql/replica/recovery.conf

# Start PostgreSQL in standby mode (this becomes a docker-compose service)
```

---

## Phase 4: Hardware Replacement (24-48 hours)

### Step 4.1: Order Replacement NVMe
**Part Details:**
- **Current Drive:** WD_BLACK SN770 2TB
- **Serial:** 251875800026 (now failed)
- **Replacement:** Order identical WD_BLACK SN770 2TB (or upgrade to WD_BLACK SN850X if available)

**Vendors:**
- Amazon: 2-day delivery
- Newegg: 2-day shipping
- CDW: Same-day local pickup (if in metro area)
- WD Direct: Premium support line

**Cost:** ~$150-200 USD

### Step 4.2: Physical Replacement Steps
1. Power down Replica 2 system
2. Remove failed NVMe from M.2 slot
3. Insert new NVMe drive
4. Power on and enter BIOS
5. Verify new drive is detected
6. Exit BIOS (boot to existing OS)

### Step 4.3: OS and Services Restoration
```bash
# After hardware replacement, Replica 2 still boots with OS intact

# If NVMe is replaced successfully, just restart docker-compose
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose up -d'

# If OS was corrupted, may need:
# - Ubuntu re-installation
# - NAS mount recreation
# - docker-compose repull and restart
```

---

## Phase 5: Validation & Recovery (2 hours)

### Step 5.1: Test Replication
```bash
# On Replica 1 (Primary)
docker-compose exec -T postgres psql -U codeserver -d codeserver -c "CREATE TABLE test_replication (id SERIAL PRIMARY KEY, ts TIMESTAMP DEFAULT NOW())"
docker-compose exec -T postgres psql -U codeserver -d codeserver -c "INSERT INTO test_replication VALUES (DEFAULT, NOW())"

# On Replica 2 (Standby)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42
docker-compose exec -T postgres psql -U codeserver -d codeserver -c "SELECT * FROM test_replication"
# Expected: Same row appears after 1-5 seconds
```

### Step 5.2: Test Failover
```bash
# Simulate Replica 1 failure: isolate Replica 1
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'sudo iptables -I INPUT 1 -j DROP'

# Promote Replica 2 to primary
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42
cd code-server-enterprise
docker-compose exec -T postgres pg_ctl promote -D /var/lib/postgresql/data/pgdata

# Verify Replica 2 is now writable
docker-compose exec -T postgres psql -U codeserver -d codeserver -c "INSERT INTO test_replication VALUES (DEFAULT, NOW())"

# Restore Replica 1 (remove iptables isolation)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'sudo iptables -D INPUT -j DROP'

# Re-establish replication from Replica 2 (now primary)
# This requires base backup from new primary
```

### Step 5.3: Failover Return
```bash
# Once Replica 1 is healthy again, return to normal:
# Option A: Manual failback
docker-compose exec -T postgres pg_ctl demote -D /var/lib/postgresql/data/pgdata

# Option B: Use Patroni for automatic failback (if Patroni is deployed)
```

---

## Phase 6: Documentation & Closure (1 hour)

### Step 6.1: Update Runbooks
- [ ] Create PostgreSQL Streaming Replication setup guide
- [ ] Document failover procedures (manual steps)
- [ ] Add NVMe health monitoring to monitoring dashboard
- [ ] Document RAID recommendation for future hardware

### Step 6.2: Post-Incident Review
- **Root Cause:** NVMe hardware failure (not preventable, but detected via SMART)
- **Contributing Factor:** No database replication (single point of failure)
- **Permanent Fix:** Implement Patroni HA for PostgreSQL

### Step 6.3: GitHub Issue Closure
```bash
# Update P0 #1635 with resolution
gh issue comment 1635 --repo kushin77/code-server --body "**RESOLVED - [Date]**

Incident resolved through:
1. ✅ Replica 2 isolation (network block to prevent data corruption)
2. ✅ PostgreSQL backup created and stored on NAS
3. ✅ Replica 1 continues serving 100% of traffic (no user impact)
4. ✅ NVMe replaced (Hardware part: ...)
5. ✅ Streaming replication configured (Replica 2 → Replica 1)
6. ✅ Failover tested and validated
7. ✅ Patroni HA scheduled for Phase 2

**Permanent Solution:** Patroni + etcd for automatic failover
**Timeline:** Deploy Patroni HA in next sprint

Fixes #1635"

# Close the issue
gh issue close 1635 --repo kushin77/code-server
```

---

## Success Criteria

- [x] Replica 2 isolated (no risk of data corruption from failing NVMe)
- [x] Replica 1 serving 100% of traffic
- [ ] PostgreSQL replication configured
- [ ] Replica 2 NVMe replaced
- [ ] Failover tested (Replica 1→2 and back)
- [ ] Issue #1635 closed
- [ ] Patroni HA planned for next phase

---

## Escalation Path

If things go wrong:
1. **Replica 1 also fails:** CRITICAL - no replicas left
   - Recover from PostgreSQL backups
   - Restore from NAS if possible
   - May lose 1-24h of data

2. **Replication breaks during setup:** 
   - Reverse changes
   - Return to single-replica mode
   - Attempt replication in non-production window

3. **Hardware replacement delayed:**
   - Keep Replica 1 isolated until replacement arrives
   - Monitor Replica 1 for signs of stress
   - Have spare NVMe on-site if possible

---

**Owner:** On-call ops  
**Status:** EXECUTION IN PROGRESS  
**Last Update:** April 23, 2026 14:45 UTC  
**ETA to Resolution:** 48-72 hours (including hardware replacement)
