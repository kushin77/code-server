# Failover Runbook for Operations Team

**Target Audience**: Operations Team  
**Scope**: Multi-replica cluster failover (192.168.168.31 primary ↔ 192.168.168.42 standby)  
**Time to Failover**: ~10 minutes (detection + isolation + promotion)  
**Time to Rollback**: ~5 minutes (restore primary)  
**Risk Level**: Low (automated health checks, manual approval gates)

---

## Quick Reference

### Automatic Failover (Health-Check Based)
```bash
# Monitored by: Prometheus + AlertManager + Caddy
# Trigger: Primary replica down > 30 seconds
# Action: Loadbalancer automatically routes to healthy replica
# Time: < 5 seconds
```

### Manual Failover (Operational Decision)
```bash
# 1. SSH to primary
ssh akushnir@192.168.168.31

# 2. Check health
bash scripts/ops/verify-production-readiness.sh

# 3. If manual failover needed
bash scripts/ops/manual-failover-to-replica.sh

# 4. Verify status
bash scripts/ops/verify-failover-status.sh
```

---

## Prerequisites Checklist

- [x] SSH access to both replicas (192.168.168.31, 192.168.168.42)
- [x] Loadbalancer/VIP accessible (managed by HAProxy or cloud LB)
- [x] Database replication set up (PostgreSQL Patroni HA)
- [x] Redis Sentinel configured (for session store failover)
- [x] Monitoring system active (Prometheus + AlertManager)
- [x] On-call playbook for escalation

---

## Health Assessment

### Quick Health Check

**From Primary (192.168.168.31)**:
```bash
ssh akushnir@192.168.168.31

# 1. Check service status
cd code-server-enterprise && docker-compose ps

# Expected output: All 10 services in "Up" state
# If any service down: ⚠️ Partial failure

# 2. Check application health
curl -s http://localhost:8080/health | jq .

# Expected:
{
  "status": "ok",
  "timestamp": "2026-04-24T12:34:56Z",
  "services": {
    "code-server": "healthy",
    "database": "connected",
    "redis": "connected"
  }
}

# 3. Check database replication
docker-compose exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Expected: Shows standby replica connected and synced

# 4. Check Redis Sentinel
docker-compose exec redis redis-cli info replication

# Expected: role:master, connected_slaves:1 (standby connected)
```

**From Standby (192.168.168.42)**:
```bash
ssh akushnir@192.168.168.42

# Same checks as primary
cd code-server-enterprise && docker-compose ps
curl -s http://localhost:8080/health | jq .
docker-compose exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"
docker-compose exec redis redis-cli info replication
```

### Health Assessment Matrix

| Component | Primary Health | Standby Health | Action |
|-----------|----------------|----------------|--------|
| Services (all 10) | ✅ Up | ✅ Up | Normal operation |
| Services (all 10) | ❌ Down | ✅ Up | Failover to standby |
| Services (all 10) | ⚠️ Partial | ✅ Up | Investigate & failover if needed |
| Database | ✅ Connected | ✅ Connected | Normal operation |
| Database | ❌ Down | ✅ Connected | Failover to standby |
| Redis | ✅ Master | ✅ Slave | Normal operation |
| Redis | ⚠️ Degraded | ✅ Slave | Investigate & failover if critical |

---

## Manual Failover Triggers

### Automatic Failover (No Action Required)
- Primary becomes unreachable (TCP/IP failure)
- Primary health endpoint unresponsive (> 30s)
- Primary loadbalancer health check fails
- **Action**: Loadbalancer automatically routes traffic to standby

### Manual Failover (Operational Decision)

**Scenario 1: Primary Database Down**
```bash
# If primary database unreachable but replica still up
ssh akushnir@192.168.168.31

# Check database status
docker-compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"

# If returns: t (true) = database is in recovery mode (not primary)
# Decision: Promote standby to primary or failover

# Check standby database status
ssh akushnir@192.168.168.42
docker-compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# If returns: f (false) = ready to be promoted
```

**Scenario 2: Primary Service Degradation**
```bash
# Primary responding slowly but services still up
# Decision: Monitor for 5 minutes before failover
# If degradation continues: Failover to standby

ssh akushnir@192.168.168.31
curl -w "@/tmp/curl-format.txt" -o /dev/null -s http://localhost:8080/health
# If response time > 5 seconds: Consider failover
```

**Scenario 3: Network Partition (Split Brain Prevention)**
```bash
# Primary cannot reach standby (network partition)
# Decision: Failover to standby if primary is inaccessible from LB

# From loadbalancer perspective:
# Check which replica responds faster
curl http://192.168.168.31:8080/health -m 2  # 2s timeout
curl http://192.168.168.42:8080/health -m 2  # 2s timeout

# If 192.168.168.31 times out: Failover to 192.168.168.42
```

---

## VIP Ownership Transfer

### Current Setup: HAProxy Loadbalancer

**HAProxy Configuration** (managed by Caddy):
```
# In docker-compose.yml:
caddy:
  environment:
    CADDY_BACKEND_1=192.168.168.31:8080
    CADDY_BACKEND_2=192.168.168.42:8080
    # Caddy health-checks both and routes only to healthy
```

**VIP Ownership Transfer Steps**:

```bash
# 1. SSH to loadbalancer (if separate) or primary
ssh akushnir@192.168.168.31

# 2. Check current loadbalancer state
docker-compose logs caddy | grep -i "upstream\|backend" | tail -20

# 3. To manually remove primary from rotation:
# Edit docker-compose.yml:
#   Comment out: CADDY_BACKEND_1=192.168.168.31:8080
#   Keep: CADDY_BACKEND_2=192.168.168.42:8080

# 4. Restart Caddy
docker-compose restart caddy

# 5. Verify all traffic goes to standby
curl -v https://ide.kushnir.cloud/health 2>&1 | grep -E "X-Forwarded-For|X-Real-IP"
# Should show 192.168.168.42 in headers

# 6. Verify connection count
ss -tnp | grep :8080
# All connections should show 192.168.168.42
```

### VIP Ownership Verification

```bash
# Check active upstream in Caddy
docker-compose exec caddy curl -s http://localhost:2019/config/apps/http/servers/public/routes | jq '.[] | .match, .handle'

# Check HAProxy stats (if used)
docker-compose logs caddy | grep "backend.*UP\|backend.*DOWN"

# Check DNS resolution
nslookup ide.kushnir.cloud
# Should resolve to loadbalancer IP, not specific replica IP
```

---

## Service Migration

### Pre-Migration: Data Consistency Check

```bash
# 1. Verify database replication lag is minimal
ssh akushnir@192.168.168.31
docker-compose exec postgres psql -U postgres -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;"

# Expected: lag < 10MB (approximately 1 second of replication lag)

# 2. Verify Redis replication
docker-compose exec redis redis-cli info replication | grep offset
# Primary: master_repl_offset
# Standby: replica_repl_offset
# Should be very close (< 1000 bytes difference)

# 3. Verify no active transactions on primary
docker-compose exec postgres psql -U postgres -c "SELECT * FROM pg_stat_activity WHERE state='active';" | wc -l
# Should be minimal (< 5)
```

### Service Migration Steps

```bash
# Step 1: Drain connections from primary (graceful shutdown)
ssh akushnir@192.168.168.31

# Remove from loadbalancer (see VIP Ownership Transfer section)
docker-compose ps code-server  # Should still be running

# Wait for existing connections to drain
sleep 30

# Step 2: Pause writes on primary
# (This is handled automatically by removing from LB)

# Step 3: Check replication is caught up
ssh akushnir@192.168.168.42
docker-compose exec postgres psql -U postgres -c "SELECT pg_last_wal_receive_lsn();"

# Compare with primary:
ssh akushnir@192.168.168.31
docker-compose exec postgres psql -U postgres -c "SELECT pg_current_wal_lsn();"
# Should be identical

# Step 4: Promote standby to primary
bash scripts/ops/promote-replica-to-primary.sh

# Step 5: Stop services on old primary (optional, for safety)
ssh akushnir@192.168.168.31
docker-compose stop code-server  # Keep other services running

# Step 6: Verify new primary is accepting writes
ssh akushnir@192.168.168.42
docker-compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Should return: f (false - not in recovery, is now primary)
```

---

## Rollback Procedure

### Quick Rollback (if new primary has issues)

```bash
# 1. Demote new primary back to standby
ssh akushnir@192.168.168.42

# Get current primary promotion status
docker-compose exec postgres psql -U postgres -c "SHOW recovery_target_timeline;"

# Demote (revert to standby)
bash scripts/ops/demote-primary-to-replica.sh

# 2. Re-promote original primary
ssh akushnir@192.168.168.31

# Start services again
docker-compose start code-server

# Wait for recovery
sleep 30

# Verify it's now primary
docker-compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Should return: f (false - is now primary)

# 3. Update loadbalancer routing back to original primary
docker-compose restart caddy

# 4. Verify traffic is flowing
curl -v https://ide.kushnir.cloud/health 2>&1 | grep X-Forwarded-For
# Should show 192.168.168.31 again
```

### Complete Rollback (if promotion was major issue)

```bash
# 1. Check backup availability
ssh akushnir@192.168.168.31
ls -la /backups/postgres/  # Should have recent backups

# 2. Restore from backup (if needed)
bash scripts/ops/restore-postgres-from-backup.sh --backup-date 2026-04-24 --replica 192.168.168.42

# 3. Verify standby is recovered
ssh akushnir@192.168.168.42
docker-compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Should return: t (true - back in standby mode)

# 4. Proceed with manual failover again if needed
bash scripts/ops/promote-replica-to-primary.sh
```

---

## Isolating Unhealthy Replica

### Graceful Isolation (No Service Interruption)

```bash
# 1. SSH to unhealthy replica
ssh akushnir@192.168.168.31

# 2. Gracefully shut down services
docker-compose pause code-server  # Pause without stopping
sleep 10  # Let active connections drain

# 3. Remove from loadbalancer
# Edit docker-compose.yml to comment out:
#   # CADDY_BACKEND_1=192.168.168.31:8080
# Keep: CADDY_BACKEND_2=192.168.168.42:8080

# Restart loadbalancer
docker-compose restart caddy

# 4. Verify all traffic is on healthy replica
curl -v https://ide.kushnir.cloud/health 2>&1 | grep -E "192.168.168"
# Should only show 192.168.168.42

# 5. Now safely stop services on unhealthy replica
docker-compose stop

# 6. Investigate the issue
docker-compose logs --tail 100 code-server  # Check error logs
```

### Force Isolation (Emergency)

```bash
# If replica is unresponsive and must be isolated immediately

# 1. From loadbalancer, remove unhealthy replica
ssh akushnir@192.168.168.31  # Or wherever loadbalancer runs

# 2. Force remove from loadbalancer
docker-compose exec caddy caddy reverse-proxy stop --address 192.168.168.31:8080

# 3. Or completely restart loadbalancer
docker-compose restart caddy

# 4. Verify failover
curl https://ide.kushnir.cloud/health
# Should succeed (traffic on healthy replica)

# 5. Investigate unhealthy replica later
ssh akushnir@192.168.168.31 (when stable)
docker-compose logs caddy
docker-compose logs postgres
docker-compose logs code-server
```

---

## Restoring Service

### Restore Unhealthy Replica to Service

```bash
# 1. SSH to previously unhealthy replica
ssh akushnir@192.168.168.31

# 2. Check what was wrong
docker-compose logs --tail 50 postgres | grep ERROR
docker-compose logs --tail 50 code-server | grep ERROR

# 3. Restart services
docker-compose restart

# 4. Wait for recovery
sleep 60

# 5. Check health
docker-compose exec code-server curl -s http://localhost:8080/health | jq .
docker-compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"

# 6. Verify replication is catching up
docker-compose exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;" | head -10

# 7. Re-add to loadbalancer
# Edit docker-compose.yml:
#   CADDY_BACKEND_1=192.168.168.31:8080  # Uncomment

# Restart loadbalancer
docker-compose restart caddy

# 8. Verify traffic is load-balanced again
curl -w "Backend: %{connect_time}ms\n" https://ide.kushnir.cloud/health
# Try multiple times, connection times should vary between replicas
```

---

## Verification Checkpoints

### Checkpoint 1: Primary Health (Before Failover)

```bash
# Run on primary
bash scripts/ops/verify-production-readiness.sh

# Expected output:
# ✅ Code parity: Both replicas on main/abc1234
# ✅ Service health: All 10 services up
# ✅ Health endpoints: Responding on /health
# ✅ Database replication: 0s lag
# ✅ Redis: 2/2 active
# ✅ TLS certificates: Valid (30+ days)
```

### Checkpoint 2: Standby Readiness (Before Failover)

```bash
# Run on standby
bash scripts/ops/verify-production-readiness.sh

# Expected output: Same as primary
```

### Checkpoint 3: Loadbalancer Health (During Failover)

```bash
# Monitor load distribution
watch -n 1 'curl -s https://ide.kushnir.cloud/health 2>&1 | grep -E "HTTP|Backend"'

# Try 10 requests and check distribution
for i in {1..10}; do curl -s https://ide.kushnir.cloud/health | jq -r '.instance'; done
# Should show mix of both replicas (before failover) or only one (during/after)
```

### Checkpoint 4: Data Consistency (After Failover)

```bash
# Verify no data loss
ssh akushnir@192.168.168.42  # New primary

# Check database integrity
docker-compose exec postgres psql -U postgres -c "SELECT count(*) FROM pg_tables WHERE schemaname='public';"

# Check specific tables
docker-compose exec postgres psql -U postgres -c "SELECT count(*) FROM users, sessions, projects;"

# Verify user sessions are preserved
docker-compose exec redis redis-cli KEYS '*session*' | wc -l
# Should show active session count
```

### Checkpoint 5: Application Functionality (After Failover)

```bash
# Test critical user paths
curl -k https://ide.kushnir.cloud/api/auth/me     # Auth endpoint
curl -k https://ide.kushnir.cloud/api/projects    # Projects endpoint
curl -k https://ide.kushnir.cloud/health           # Health endpoint

# Expected: All return 200 or 401 (not 500/timeout)
```

---

## Troubleshooting

### Issue: Primary Shows "Standby" Status (pg_is_in_recovery = true)

```bash
# Problem: Primary thinks it's standby (in recovery mode)
ssh akushnir@192.168.168.31
docker-compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Returns: t (true) - WRONG! Should be false

# Solution:
# 1. Check promotion status
docker-compose exec postgres psql -U postgres -c "SELECT * FROM pg_control_data;" | grep "Database cluster"

# 2. Promote to primary
docker-compose exec postgres psql -U postgres -c "SELECT pg_promote();"

# 3. Wait 30 seconds
sleep 30

# 4. Verify promotion
docker-compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
# Should now return: f (false)
```

### Issue: Replication Lag Too High

```bash
# Problem: Standby is far behind primary
ssh akushnir@192.168.168.31
docker-compose exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;" | grep replay_lag
# Shows: 5 minutes

# Solution:
# 1. Check network latency
ping -c 5 192.168.168.42
# Should be < 10ms

# 2. Check disk I/O on standby
ssh akushnir@192.168.168.42
iostat -x 1 5  # Check %util column (should be < 80%)

# 3. Restart standby postgres if stuck
docker-compose restart postgres
sleep 60

# 4. Verify lag decreased
ssh akushnir@192.168.168.31
docker-compose exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;" | grep replay_lag
# Should be < 1 second now
```

### Issue: Loadbalancer Still Routing to Unhealthy Replica

```bash
# Problem: Traffic still going to failed replica
curl -v https://ide.kushnir.cloud/health 2>&1 | grep X-Forwarded-For
# Shows: 192.168.168.31 (but 192.168.168.31 is down)

# Solution:
# 1. Check Caddy loadbalancer config
docker-compose exec caddy caddy config show | grep -A 5 "upstreams"

# 2. Manually remove unhealthy upstream
docker-compose exec caddy caddy reverse-proxy stop --address 192.168.168.31:8080

# 3. Or restart Caddy completely
docker-compose restart caddy

# 4. Verify traffic
curl -v https://ide.kushnir.cloud/health 2>&1 | grep X-Forwarded-For
# Should now show only healthy replica
```

---

## Escalation Path

| Issue | Response Time | Escalation |
|-------|---|---|
| Both replicas down | < 2 min | Page on-call engineer immediately |
| Primary down, standby up | < 5 min | Auto-failover, monitor standby health |
| Replication lag > 5 min | < 10 min | Investigate network or disk I/O |
| Data corruption detected | < 15 min | Page database specialist, prepare restore |

---

## Quick Reference Commands

```bash
# Check replica health
bash scripts/ops/verify-production-readiness.sh

# Check failover status
bash scripts/ops/verify-failover-status.sh

# Manual failover to standby
bash scripts/ops/promote-replica-to-primary.sh

# Restore to original primary
bash scripts/ops/demote-primary-to-replica.sh

# Check database replication
docker-compose exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check Redis Sentinel
docker-compose exec redis redis-cli sentinel masters

# Monitor traffic during failover
watch -n 1 'curl -v https://ide.kushnir.cloud/health 2>&1 | grep X-Forwarded-For'

# Check service health across all replicas
for host in 192.168.168.31 192.168.168.42; do
  echo "=== $host ===" && \
  ssh akushnir@$host 'cd code-server-enterprise && docker-compose ps' || echo "DOWN"
done
```

---

**Last Updated**: April 24, 2026  
**Runbook Version**: 1.0 (Failover)  
**Recommended Review**: Quarterly  
**Owner**: Operations Team  
**Status**: ✅ Production Ready
