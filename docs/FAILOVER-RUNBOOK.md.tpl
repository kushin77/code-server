# Failover & High Availability Runbook
## Code-Server Production Environment

---

## Overview

This runbook documents all procedures for managing failover, high availability, and disaster recovery in the code-server production environment.

**Key Infrastructure**:
- **Primary Host**: 192.168.168.31 (Active)
- **Replica Host**: 192.168.168.42 (Standby)
- **Virtual IP (VIP)**: 192.168.168.100 (HAProxy + Services)
- **NAS Backup**: 192.168.168.55
- **Failover Protocol**: VRRP (Keepalived)
- **RTO Target**: 2 minutes
- **RPO Target**: 30 seconds

---

## Section 1: Understanding the HA Architecture

### Components
1. **HAProxy** (Layer 4-7 Load Balancer)
   - Listens on VIP 192.168.168.100
   - Routes traffic to services
   - Health checks every 5 seconds
   
2. **Keepalived** (VRRP Failover)
   - Primary priority: 200
   - Replica priority: 100
   - VIP ownership determined by priority + health
   
3. **PostgreSQL** (Primary-Replica Replication)
   - Streaming replication with WAL archiving
   - Automatic failover via pg_autoctl (optional)
   - Replica lag monitored continuously

4. **Redis** (Cache with Replication)
   - Primary-replica data replication
   - Sentinel for automatic failover (optional)
   - RDB snapshots for persistence

---

## Section 2: Automatic Failover Procedure

### When Automatic Failover Occurs

Keepalived monitors HAProxy health every 5 seconds. If 3 consecutive health checks fail, the following automatic sequence begins:

```
[Failure Detected] → [Health Check Fails x3] → [VIP Transfer] → [Traffic Routes to Replica]
     (5s)                 (15s)                   (< 5s)         (Immediate)
```

### Automatic Failover Timeline

| Step | Action | Time | Notes |
|------|--------|------|-------|
| 1 | HAProxy becomes unhealthy | 5s | First health check failure |
| 2 | Health checks confirm failure | 10s | 2 more failed attempts |
| 3 | Keepalived detects failure | 15s | Weight adjustment triggers |
| 4 | VIP transfer initiated | 15-20s | Primary loses VIP |
| 5 | Replica gains VIP | 20-30s | ARP announcements sent |
| 6 | Traffic redirects to replica | 30-60s | Clients reconnect |
| 7 | Failover complete | **< 2 minutes** | RTO met |

### What the Replica Becomes

When failover occurs:
- ✅ Replica HAProxy becomes **MASTER** (takes VIP)
- ✅ Replica PostgreSQL becomes **primary** (accepts writes)
- ✅ Original primary is **BACKUP** (takes reads only when back up)
- ✅ Services on replica are promoted to active

---

## Section 3: Manual Failover Procedure

### Trigger Manual Failover

**When to use**: When you need to failover for maintenance on the primary.

```bash
# Step 1: Connect to primary host
ssh -t akushnir@192.168.168.31

# Step 2: Verify replica is ready
ssh akushnir@192.168.168.42 "docker-compose ps | grep -c healthy"
# Should show: 8 (or your service count)

# Step 3: Trigger failover
# Option A: Stop HAProxy (will trigger automatic failover)
cd code-server-enterprise
docker-compose stop haproxy

# Option B: Lower Keepalived priority
sudo systemctl stop keepalived

# Wait for VIP transfer (monitor below)
```

### Monitor Failover Progress

```bash
# Terminal 1: Watch VIP movement
watch -n 1 'ip addr show | grep 192.168.168.100'

# Terminal 2: Monitor services
watch -n 2 'docker-compose ps --format "table {{.Names}}\t{{.Status}}"'

# Terminal 3: Check HAProxy stats
curl http://192.168.168.100:8404/stats | grep -E "^(code_server|postgresql|redis)"
```

### Verify Failover Success

```bash
# Check VIP is on replica
ssh akushnir@192.168.168.42 "ip addr show | grep 192.168.168.100"

# Verify services are responding
curl -I http://192.168.168.100:80/health
curl -I http://192.168.168.100:443/health
curl -I http://192.168.168.100:8404/stats

# Check database is writable
psql -h 192.168.168.100 -U admin_user -d code_server \
  -c "INSERT INTO test VALUES (now())"

# Check replication (should reverse direction)
ssh akushnir@192.168.168.42 "docker-compose exec -T postgres \
  psql -U postgres -c \
  'SELECT client_addr, state FROM pg_stat_replication;'"
```

---

## Section 4: Failback Procedure

### Return to Primary (After Maintenance)

```bash
# Step 1: Connect to original primary
ssh -t akushnir@192.168.168.31

# Step 2: Restart services on primary
cd code-server-enterprise
docker-compose restart haproxy

# Step 3: Wait for primary to become MASTER
watch -n 1 'ip addr show | grep 192.168.168.100'
# Should appear within 30 seconds

# Step 4: Verify services on primary are healthy
docker-compose ps
docker-compose logs --tail=20 haproxy
```

### Automatic Failback

If you used `docker-compose stop haproxy` (Step 3A above):
- Primary automatically becomes MASTER when HAProxy restarts ✅
- Keepalived priority (200 > 100) ensures primary wins
- Services automatically failback in < 60 seconds

If you used `systemctl stop keepalived` (Step 3B above):
- You must manually restart: `sudo systemctl start keepalived`
- Then primary reclaims VIP automatically

---

## Section 5: Database Failover & Replication

### Understanding PostgreSQL Replication

**Primary (192.168.168.31)**:
- Accepts all writes
- Archives WAL (Write-Ahead Logs)
- Replicates to replica via streaming

**Replica (192.168.168.42)**:
- Accepts reads only
- Receives WAL stream
- Replays transactions
- Keeps track of position (flush LSN)

### Check Replication Status

```bash
# From primary: View connected replicas
ssh akushnir@192.168.168.31 "docker-compose exec -T postgres \
  psql -U postgres -c \
  'SELECT usename, application_name, state, \
          pg_wal_lsn_diff(flush_lsn, replay_lsn) as lag_bytes \
   FROM pg_stat_replication;'"

# From replica: View replication progress
ssh akushnir@192.168.168.42 "docker-compose exec -T postgres \
  psql -U postgres -c \
  'SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();'"

# Check replication lag (seconds)
ssh akushnir@192.168.168.42 "docker-compose exec -T postgres \
  psql -U postgres -c \
  'SELECT EXTRACT(EPOCH FROM \
    (now() - pg_last_xact_replay_timestamp()))::int as lag_seconds;'"
```

### Promote Replica to Primary (if primary is lost)

```bash
# Step 1: SSH to replica
ssh -t akushnir@192.168.168.42

# Step 2: Promote replica to primary
docker-compose exec -T postgres \
  psql -U postgres -c \
  "SELECT pg_promote();"

# Step 3: Verify promotion
docker-compose exec -T postgres \
  psql -U postgres -c \
  "SELECT pg_is_in_recovery();"
# Should return: false (not in recovery = is primary)

# Step 4: Reconfigure services to point to replica as primary
# Update docker-compose.yml DATABASE_URL
docker-compose down
# Edit .env file to point to 192.168.168.42
vim .env
docker-compose up -d
```

---

## Section 6: Redis Failover

### Check Redis Status

```bash
# Primary Redis
ssh akushnir@192.168.168.31 "docker-compose exec -T redis \
  redis-cli INFO replication"

# Output should show: role:master

# Replica Redis
ssh akushnir@192.168.168.42 "docker-compose exec -T redis \
  redis-cli INFO replication"

# Output should show: role:slave
```

### Manual Redis Failover

```bash
# If using Sentinel (if configured):
redis-cli -h 192.168.168.100 -p 26379 sentinel failover mymaster

# If manual:
# Step 1: Stop primary Redis
ssh akushnir@192.168.168.31 "docker-compose stop redis"

# Step 2: Promote replica
ssh akushnir@192.168.168.42 "docker-compose exec -T redis \
  redis-cli SLAVEOF NO ONE"

# Step 3: Update connection strings to point to replica
```

---

## Section 7: Complete System Failover Test

### Full Failover Drill (Quarterly)

```bash
# Step 1: Schedule maintenance window (off-hours)
# Step 2: Notify stakeholders
# Step 3: Run test script
bash /code-server-enterprise/scripts/test-failover.sh

# The script will:
# 1. Verify primary is active
# 2. Check replication status
# 3. Stop HAProxy on primary (CAREFUL!)
# 4. Measure time to failover (target < 120s)
# 5. Verify services on replica
# 6. Restart primary
# 7. Verify failback

# Step 4: Review logs
tail -100 /var/log/failover.log
tail -100 /var/log/keepalived.log

# Step 5: Document results
# - Actual failover time
# - Any services that didn't failover properly
# - Database replication lag
```

---

## Section 8: Troubleshooting

### Issue: VIP Not Moving During Failover

**Symptoms**: Primary still has VIP even though HAProxy is down

**Causes**:
1. Keepalived not running on replica
2. Network firewall blocking VRRP
3. Both hosts have same priority

**Resolution**:
```bash
# Check Keepalived status on replica
ssh akushnir@192.168.168.42 "sudo systemctl status keepalived"

# Restart if needed
ssh akushnir@192.168.168.42 "sudo systemctl restart keepalived"

# Check VRRP traffic
tcpdump -i eth0 vrrp

# Verify priorities in config
grep "priority" /code-server-enterprise/config/keepalived/*.conf
```

### Issue: Database Replication Lag > 30s

**Symptoms**: 
```
SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int;
# Returns > 30

```

**Causes**:
1. Network latency/packet loss
2. Replica disk I/O slow
3. Large transactions on primary

**Resolution**:
```bash
# Check network
ping -c 10 192.168.168.42
# Should be < 5ms

# Check replica disk I/O
iostat -x 1 5

# Check pg_stat_replication
ssh akushnir@192.168.168.31 \
  "docker-compose exec -T postgres psql -U postgres -c \
   'SELECT client_addr, flush_lsn - replay_lsn as lag_bytes \
    FROM pg_stat_replication;'"
```

### Issue: Services Not Responding After Failover

**Symptoms**: HTTP requests timeout after failover

**Causes**:
1. Services not healthy on replica
2. Health checks failing
3. Firewall blocking traffic

**Resolution**:
```bash
# Check replica service health
ssh akushnir@192.168.168.42 "docker-compose ps"

# Restart services if needed
ssh akushnir@192.168.168.42 "docker-compose restart"

# Check HAProxy stats
curl http://192.168.168.100:8404/stats | grep -A5 "be_code_server"

# Monitor logs
ssh akushnir@192.168.168.42 "docker-compose logs -f haproxy"
```

---

## Section 9: Recovery Procedures

### Recover Failed Primary Host

```bash
# Step 1: SSH to primary and check status
ssh akushnir@192.168.168.31

# Step 2: View logs
docker-compose logs --tail=50 haproxy

# Step 3: Restart services
docker-compose restart

# Step 4: Wait for replica to detect recovery
# (HAProxy health checks should pass)

# Step 5: Initiate failback (when ready)
# Primary will automatically reclaim VIP due to higher priority
```

### Recover Failed Replica Host

```bash
# Step 1: SSH to replica
ssh akushnir@192.168.168.42

# Step 2: Restart all services
docker-compose restart

# Step 3: Restore database replication
docker-compose exec -T postgres \
  pg_basebackup -h 192.168.168.31 -U replication_user \
  -D /var/lib/postgresql/data -R

# Step 4: Start streaming replication
docker-compose exec -T postgres \
  systemctl restart postgresql

# Step 5: Verify replication
bash /code-server-enterprise/scripts/check-db-replication.sh
```

---

## Section 10: Important Contacts & Escalation

| Role | Name | Phone | Email |
|------|------|-------|-------|
| On-Call Engineer | TBD | +1-XXX-XXX-XXXX | oncall@company.com |
| Database Admin | TBD | +1-XXX-XXX-XXXX | dba@company.com |
| Infrastructure Lead | TBD | +1-XXX-XXX-XXXX | infra-lead@company.com |
| VP Engineering | TBD | +1-XXX-XXX-XXXX | vp-eng@company.com |

---

## Section 11: SLO Targets & Monitoring

### RTO (Recovery Time Objective)

| Scenario | Target | Method |
|----------|--------|--------|
| HAProxy failure | < 2 min | Automatic VIP transfer |
| Host failure | < 2 min | Replica assumes all services |
| Database failure | < 5 min | Promote replica to primary |
| Full datacenter | < 15 min | Restore from NAS backup |

### RPO (Recovery Point Objective)

| Component | Target | Method |
|-----------|--------|--------|
| PostgreSQL | < 30s | WAL streaming replication |
| Redis | < 5min | RDB snapshots |
| Code-Server Config | < 1h | NAS backup sync |
| User Data | < 1h | NAS backup sync |

### Monitoring Dashboard

Access at: `http://192.168.168.100:3000` (Grafana)

Key dashboards:
- **HA Status**: Primary/Replica roles, VIP ownership, failovers triggered
- **Database Replication**: Lag, throughput, error rate
- **Service Health**: All backends, response times, error rates
- **Network**: Keepalived VRRP traffic, health check packets

---

## Checklist: Post-Failover Verification

After any failover event:

- [ ] VIP is on expected host
- [ ] All services responding (HTTP 200)
- [ ] Database writes successful
- [ ] Redis cache working
- [ ] Monitoring alerts resolved
- [ ] Team notified of status
- [ ] Incident log created
- [ ] Root cause analysis scheduled
- [ ] Preventive measures identified

---

## Checklist: Pre-Maintenance Failover

Before planned maintenance:

- [ ] Backup fresh database snapshot
- [ ] Verify replica has < 30s replication lag
- [ ] All services healthy on both hosts
- [ ] Alerts configured and tested
- [ ] Team on-call aware of maintenance window
- [ ] Maintenance window scheduled during off-hours
- [ ] Rollback plan documented
- [ ] Client notifications sent (if needed)

---

**Document Version**: 1.0  
**Last Updated**: April 17, 2026  
**Next Review**: Quarterly (or after major incidents)  
**Maintained By**: Infrastructure Team
