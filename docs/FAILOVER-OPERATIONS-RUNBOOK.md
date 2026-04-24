# Kushnir.cloud Cluster Failover Operations Runbook

**Version**: 1.0  
**Last Updated**: April 24, 2026  
**Scope**: Production cluster on-prem infrastructure (192.168.168.31 and 192.168.168.42)  

---

## 1. OVERVIEW

This runbook documents manual failover procedures for the Kushnir.cloud production cluster. The cluster uses **active-active** replication with automatic failover, but manual intervention procedures are documented here for edge cases.

**Automatic Failover**: < 5 seconds (health check based)  
**Manual Failover**: 2-5 minutes (including verification)  

---

## 2. CLUSTER ARCHITECTURE QUICK REFERENCE

### Replicas
- **Replica 1 (R31)**: 192.168.168.31
- **Replica 2 (R42)**: 192.168.168.42

### Shared Resources
- **NAS**: 192.168.168.56 (Persistent storage, mounted on both replicas)
- **Session State**: Redis HA (Sentinel or cluster mode, synchronized across replicas)
- **Database**: PostgreSQL HA with Patroni replication
- **Load Balancer**: HAProxy or Cloudflare (automatic round-robin)

### Services per Replica
- **Total**: 20 services running per replica
- **Core**: code-server, oauth2-proxy, caddy, prometheus, grafana, etc.
- **Database**: postgres, redis, redis-sentinel, pgbouncer
- **Monitoring**: prometheus, alertmanager, loki, promtail, jaeger

---

## 3. REPLICA HEALTH ASSESSMENT

### Quick Health Check (< 30 seconds)

```bash
# SSH to each replica
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker ps -q | wc -l"  # Should be 20
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q | wc -l"  # Should be 20

# Check health endpoint (expect 403 auth redirect or 200 OK)
curl -k https://192.168.168.31/health
curl -k https://192.168.168.42/health

# Check load balancer status (if HAProxy)
curl http://LOADBALANCER:8080/stats  # Replace with actual LB IP

# Check Prometheus metrics (both replicas)
curl -k https://192.168.168.31:9090/api/v1/query?query=up
curl -k https://192.168.168.42:9090/api/v1/query?query=up
```

### Detailed Health Check (2-3 minutes)

```bash
# Check replica 31
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 << 'EOF'
echo "=== REPLICA 31 HEALTH ==="
echo "Git commit:"
git -C code-server-enterprise rev-parse --short HEAD
echo "Service status:"
docker ps --format "table {{.Names}}\t{{.Status}}"
echo "Code-server port:"
netstat -tlnp 2>/dev/null | grep 8080
echo "Caddy SSL:"
openssl s_client -connect localhost:443 -showcerts 2>/dev/null | grep subject
echo "PostgreSQL replication:"
docker exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;" 2>/dev/null || echo "N/A"
echo "Redis Sentinel:"
docker exec redis-sentinel-1 redis-cli -p 26379 info sentinel 2>/dev/null || echo "N/A"
EOF

# Check replica 42
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 << 'EOF'
echo "=== REPLICA 42 HEALTH ==="
echo "Git commit:"
git -C code-server-enterprise rev-parse --short HEAD
echo "Service status:"
docker ps --format "table {{.Names}}\t{{.Status}}"
echo "Code-server port:"
netstat -tlnp 2>/dev/null | grep 8080
echo "Caddy SSL:"
openssl s_client -connect localhost:443 -showcerts 2>/dev/null | grep subject
echo "PostgreSQL replication:"
docker exec postgres psql -U postgres -c "SELECT * FROM pg_stat_replication;" 2>/dev/null || echo "N/A"
echo "Redis Sentinel:"
docker exec redis-sentinel-1 redis-cli -p 26379 info sentinel 2>/dev/null || echo "N/A"
EOF
```

### Health Check Results Interpretation

| Indicator | Healthy | Warning | Critical |
|-----------|---------|---------|----------|
| Services Running | 20/20 | 18-19/20 | < 18/20 |
| Health Endpoint | 200 OK or 403 | Timeout | Connection refused |
| PostgreSQL Lag | < 1s | 1-10s | > 10s |
| Git Commit | 4bfcaa2a | Old commit | Divergent |
| Redis Sentinel | Up | One sentinel down | Both down |
| Caddy SSL | Valid cert | Expired warning | Invalid/missing |

---

## 4. MANUAL FAILOVER PROCEDURES

### Scenario A: Single Replica Down (One of Two)

**Trigger Conditions:**
- One replica (31 or 42) is completely unreachable
- Health endpoint returns 500+ errors or connection refused
- All 20 services stopped on that replica

**Impact:**
- Cluster operates at reduced capacity (50%)
- Some user sessions may be dropped (Redis HA will reconnect)
- Response time may increase due to single-node load

**Procedure:**

#### Step 1: Verify the Problem (2 min)

```bash
# Confirm replica 31 is down
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker ps" 2>&1
# Expected: Connection timeout or refused

# Confirm replica 42 is healthy
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q | wc -l"
# Expected: 20

# Check load balancer removed replica 31
curl http://LOADBALANCER:8080/stats | grep "192.168.168.31"
# Expected: marked DOWN or NOLB
```

#### Step 2: Investigate Root Cause (2-5 min)

```bash
# Try to reach the down replica's host
ping 192.168.168.31
# If unreachable: network issue, power failure, or host hung

# If host is reachable, check SSH
ssh -i ~/.ssh/id_rsa_onprem -v akushnir@192.168.168.31 "date" 2>&1 | head -20

# Check NAS mount if SSH works
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "mount | grep /export"
```

#### Step 3: Recovery Decision

**Option A: Restart the Down Replica**

```bash
# If network is OK but services are down, restart docker-compose
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 << 'EOF'
cd code-server-enterprise
git pull origin main  # Get latest code
docker-compose down --remove-orphans
docker-compose up -d
# Wait 5 minutes for services to fully start
sleep 300
docker ps -q | wc -l  # Should be 20
EOF
```

**Option B: Isolate the Down Replica (Permanent Failover)**

If the replica cannot be recovered quickly:

```bash
# On healthy replica (42), verify it's handling all traffic
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q | wc -l"
# Confirm 20 services running

# Check PostgreSQL replication to ensure single node is accepting writes
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker exec postgres psql -U postgres -c 'SELECT version();'"

# Verify load balancer has removed replica 31
curl http://LOADBALANCER:8080/stats | grep -A5 "192.168.168"
# Expected: R31 marked DOWN, R42 marked UP
```

#### Step 4: Verification (5 min)

```bash
# Test user functionality on healthy replica
curl -k https://ide.kushnir.cloud/health
# Expected: 200 OK

# Check Grafana cluster health dashboard
# Expected: R42 HEALTHY, R31 DOWN

# Monitor error logs for 2 minutes
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker logs caddy 2>&1 | grep -i error | tail -20"
```

---

### Scenario B: Network Partition (Both Replicas Isolated)

**Trigger Conditions:**
- Both replicas unreachable
- Load balancer cannot reach either replica
- Health checks failing on both

**Immediate Impact:**
- **CLUSTER IS DOWN** - All services unreachable
- Users cannot connect to IDE
- All user sessions will fail

**Recovery Priority**: P0 - Immediate escalation required

**Procedure:**

#### Step 1: Confirm Network Partition (1 min)

```bash
# Try both replicas
ping 192.168.168.31
ping 192.168.168.42

# Check NAS (shared storage)
ping 192.168.168.56

# If NAS is reachable but replicas are not:
# → Replica-specific network issue (switch, cables, NIC failure)

# If both replicas and NAS unreachable:
# → Site-wide network outage (core switch down, ISP issue)
```

#### Step 2: Restore Connectivity (2-10 min)

**If Replica-Specific Issue:**

```bash
# Check physical connectivity at the replica location
# - Verify network cables are plugged in
# - Check switch port is active
# - Restart network interface if possible

ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "ip link show | grep UP"
# If output is empty: network adapter down
# Recover by contacting on-site support or physical restart
```

**If Site-Wide Outage:**

```bash
# Wait for network to restore (coordinate with NOC)
# Monitor ping to determine when connectivity returns

# Once connectivity is restored, verify replicas come online
ping 192.168.168.31  # Should respond
ping 192.168.168.42  # Should respond
```

#### Step 3: Restart Cluster Services (3 min)

Once network connectivity is restored:

```bash
# Restart both replicas in parallel
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose up -d' &
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose up -d' &
wait

# Wait for services to stabilize (3-5 minutes)
sleep 180

# Verify both replicas healthy
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker ps -q | wc -l"  # Should be 20
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q | wc -l"  # Should be 20
```

---

### Scenario C: Data Corruption (One Replica HA State Inconsistent)

**Trigger Conditions:**
- PostgreSQL replication lag > 60 seconds
- Redis Sentinel master election in progress repeatedly
- Grafana shows divergent service counts between replicas

**Impact:**
- Cluster operates at reduced capacity with data inconsistency
- User sessions may be lost
- Database writes may be blocked

**Procedure:**

#### Step 1: Stop the Corrupted Replica (1 min)

```bash
# Identify which replica has the problem (check Grafana dashboard)
# Example: Replica 31 is lagging or showing inconsistent state

# Stop services on problematic replica
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose down'

# Verify healthy replica is still running
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q | wc -l"  # Should be 20
```

#### Step 2: Reset the Corrupted Replica (5 min)

```bash
# On the corrupted replica, clear stale state
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 << 'EOF'
cd code-server-enterprise

# Remove corrupt container volumes (WARNING: data loss - only if necessary)
docker-compose down --volumes

# Verify git is at latest commit
git fetch origin main
git reset --hard origin/main

# Rebuild and restart
docker-compose pull
docker-compose up -d

# Wait for services to stabilize
sleep 300
EOF
```

#### Step 3: Verify Data Consistency (2 min)

```bash
# Check PostgreSQL replication is caught up
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker exec postgres psql -U postgres -c 'SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;'"

# Check Redis Sentinel master is stable
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker exec redis-sentinel-1 redis-cli -p 26379 sentinel masters"

# Check Grafana: both replicas should show 20/20 services and healthy status
```

---

## 5. FAILOVER VERIFICATION CHECKLIST

After any failover event, verify the following:

- [ ] **Service Count**: 20/20 services running on all healthy replicas
- [ ] **Health Endpoint**: `curl -k https://ide.kushnir.cloud/health` returns 200 or 403
- [ ] **Git Parity**: Both replicas at same commit (4bfcaa2a or latest)
- [ ] **Database Replication**: PostgreSQL replication lag < 1 second
- [ ] **Redis HA**: Redis Sentinel showing master + replicas in sync
- [ ] **Load Balancer**: Healthy replicas marked UP, failed replicas marked DOWN
- [ ] **Grafana Dashboard**: No red/critical alerts, all gauges green
- [ ] **User Connectivity**: Test IDE login and file access work
- [ ] **NAS Mount**: Verify /export mounts accessible on all replicas
- [ ] **No Data Loss**: Verify recent user sessions still present in database

---

## 6. ESCALATION PROCEDURES

### Level 1: Single Replica Issue (Partial Degradation)

**Owner**: Platform Ops Team  
**Response Time**: 15 minutes  
**Escalation Trigger**: Health check fails > 2 min  

```bash
# Level 1 response
1. Confirm issue (2 min)
2. Attempt restart of failed service (3 min)
3. If restart fails, move to Level 2
```

### Level 2: Cluster-Wide Issue (Complete Outage)

**Owner**: Infrastructure Lead + Platform Ops  
**Response Time**: 5 minutes (Page on-call)  
**Escalation Trigger**: Both replicas unreachable  

```bash
# Level 2 response
1. Confirm network connectivity (2 min)
2. Restart both replicas in parallel (3 min)
3. Verify recovery (5 min)
4. If recovery fails, move to Level 3
```

### Level 3: Data Corruption (Manual Recovery Needed)

**Owner**: Database Administrator + Infrastructure Lead  
**Response Time**: 30 minutes  
**Escalation Trigger**: PostgreSQL corruption or replication divergence  

```bash
# Level 3 response
1. Stop corrupted services (1 min)
2. Review database state (5 min)
3. Execute recovery procedure (10-20 min)
4. Verify data consistency (5 min)
```

---

## 7. CONTACT INFORMATION

**On-Call Platform Ops**: [TBD - team preference]  
**Infrastructure Lead**: [TBD - team preference]  
**Database Administrator**: [TBD - team preference]  

---

## 8. APPENDIX: Quick Command Reference

```bash
# Health check all replicas
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker ps -q | wc -l"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q | wc -l"

# Restart replica
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose restart"

# Redeploy replica
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose down && docker-compose up -d"

# View Grafana dashboard
https://grafana.kushnir.cloud  # Replace with actual Grafana domain

# View Prometheus metrics
https://prometheus.kushnir.cloud  # Replace with actual Prometheus domain

# Check git status
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "git -C code-server-enterprise status"
```

---

**Document Version**: 1.0  
**Last Reviewed**: April 24, 2026  
**Next Review**: May 24, 2026
