# Phase 6: Multi-Cluster HA - Replica Deployment Package

**Status:** 📦 READY FOR DEPLOYMENT (Awaiting Replica Connectivity)  
**Version:** 1.0  
**Date:** April 28, 2026  

## Quick Reference

| Component | Status | Notes |
|-----------|--------|-------|
| Primary Cluster (192.168.168.31) | ✅ Live | Production services active |
| Replica Cluster (192.168.168.42) | ⏸️ Awaiting Connectivity | Infrastructure team to restore |
| Active-Active Config | ✅ Ready | Deployment scripts prepared |
| Database Replication | ✅ Ready | PostgreSQL streaming replication config |
| Cache Replication | ✅ Ready | Redis sync configuration |
| Load Balancing | ✅ Ready | Caddy reverse proxy config |
| Monitoring | ✅ Ready | Multi-cluster monitoring configured |

## Phase 6 Deployment Checklist

### Pre-Deployment (Infrastructure Verification)

#### Step 1: Replica Connectivity Verification (⏳ Awaiting Infrastructure Team)

**Prerequisites:**
- [ ] Infrastructure team has restored SSH access to 192.168.168.42
- [ ] Network routing from primary to replica is active
- [ ] Firewall rules allow bidirectional traffic on ports: 5432, 6379, 443, 8080, 9090

**Verification Commands** (Run from primary 192.168.168.31):
```bash
# Test basic connectivity
ping -c 3 192.168.168.42
# Expected: 3 packets transmitted, 3 received

# Test SSH access
ssh -i ~/.ssh/id_rsa ubuntu@192.168.168.42 "echo 'SSH OK'"
# Expected: SSH OK

# Test PostgreSQL port
nc -zv 192.168.168.42 5432
# Expected: Connection successful

# Test Redis port
nc -zv 192.168.168.42 6379
# Expected: Connection successful

# Test API port
curl -s http://192.168.168.42/health
# Expected: Health check response
```

**Troubleshooting Replica Connectivity:**

If connectivity fails, check replica for:

```bash
# On replica (192.168.168.42):

# 1. Check network interfaces
ip addr show
# Should show configured IP: 192.168.168.42

# 2. Check fail2ban status
sudo fail2ban-client status
# If sshd is active, check banned IPs:
sudo fail2ban-client status sshd

# 3. If primary (192.168.168.31) is banned:
sudo fail2ban-client set sshd unbanip 192.168.168.31

# 4. Check firewall rules
sudo ufw status
# Ensure ports 22, 5432, 6379, 443, 8080 are allowed

# 5. Check routing to primary
ip route show
# Should have route to 192.168.168.31

# 6. Test return connectivity
ping -c 3 192.168.168.31
ssh -i ~/.ssh/id_rsa ubuntu@192.168.168.31 "echo 'Can reach primary'"
```

---

### Deployment Phase 1: Replica Infrastructure Setup (30 minutes)

**Goal:** Prepare replica host with all required services

**Execution:** Run from primary host
```bash
bash scripts/ha/setup-replica-cluster.sh --target 192.168.168.42 --verify
```

**Checklist:**
- [ ] Replica has Docker installed (v25+)
- [ ] Replica has Docker Compose installed (v2+)
- [ ] Replica has 50GB+ free disk space
- [ ] Replica has network access to NAS (192.168.168.33)
- [ ] SSH key-based auth working (no password required)
- [ ] `/opt/code-server` directory created on replica
- [ ] Docker Compose files copied to replica
- [ ] Environment variables configured on replica

**Verification:**
```bash
ssh ubuntu@192.168.168.42 "docker --version && docker-compose --version"
ssh ubuntu@192.168.168.42 "ls -la /opt/code-server/docker-compose.*.yml"
ssh ubuntu@192.168.168.42 "df -h / | tail -1"
```

---

### Deployment Phase 2: Replica Services Startup (30 minutes)

**Goal:** Start all services on replica in proper order

**Execution:** Run from primary host
```bash
bash scripts/ha/deploy-active-active.sh --replica-only --target 192.168.168.42 --verify
```

**Service Startup Order:**
1. Database (PostgreSQL 16.13)
2. Cache (Redis 7-alpine)
3. Message queue (Redpanda)
4. API services
5. Reverse proxy (Caddy)
6. Monitoring (Prometheus, Grafana, AlertManager)

**Checklist:**
- [ ] All 37 services started on replica
- [ ] No services in "restarting" state
- [ ] All health checks passing

**Verification:**
```bash
# Check service status
docker-compose -f /opt/code-server/docker-compose.yml ps

# Check health endpoint
curl -s http://192.168.168.42/health | jq .

# Check database connectivity
ssh ubuntu@192.168.168.42 "docker exec postgres psql -U postgres -c 'SELECT 1;'"

# Check redis connectivity
ssh ubuntu@192.168.168.42 "docker exec redis redis-cli PING"
```

---

### Deployment Phase 3: Replication Configuration (45 minutes)

**Goal:** Configure master-master replication between clusters

#### PostgreSQL Replication Setup

**On Primary (192.168.168.31):**
```bash
# Create replication slot
docker exec postgres psql -U postgres -c \
  "SELECT * FROM pg_create_physical_replication_slot('replica_slot');"

# Verify replication slot
docker exec postgres psql -U postgres -c \
  "SELECT * FROM pg_replication_slots;"
```

**On Replica (192.168.168.42):**
```bash
# Start streaming replication from primary
docker exec postgres psql -U postgres -c \
  "ALTER SYSTEM SET primary_conninfo = 'host=192.168.168.31 port=5432 user=postgres password=<PASSWORD>';"

# Reload configuration
docker exec postgres pg_ctl reload
```

**Verify Replication:**
```bash
# Primary: Check connected replicas
docker exec postgres psql -U postgres -c \
  "SELECT client_addr, state FROM pg_stat_replication;"
# Expected: One row with client_addr=192.168.168.42, state=streaming

# Replica: Check replication status
docker exec postgres psql -U postgres -c \
  "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();"
# Expected: Both should advance over time (replication working)
```

**Checklist:**
- [ ] Replication slot created on primary
- [ ] Replica connected as streaming follower
- [ ] WAL lag < 1 second
- [ ] Both directions working (bi-directional replication)

#### Redis Replication Setup

**Primary to Replica:**
```bash
# On primary: Configure replica
docker exec redis redis-cli CONFIG SET replicaof 192.168.168.42 6379

# On replica: Confirm sync
docker exec redis redis-cli INFO replication | grep role
# Expected: role:master (on replica)
```

**Verify Redis Replication:**
```bash
# Write to primary, read from replica
docker exec redis redis-cli SET test-key "hello"
ssh ubuntu@192.168.168.42 "docker exec redis redis-cli GET test-key"
# Expected: hello
```

---

### Deployment Phase 4: Load Balancing & DNS (30 minutes)

**Goal:** Configure load balancing and DNS failover

#### Update Caddy Configuration

**Primary Caddy (`192.168.168.31:443`):**
```bash
# Add backend entry for replica
cat >> docker/caddy/Caddyfile <<'EOF'
http://192.168.168.42:8080 {
    reverse_proxy /api/* 127.0.0.1:3000
    reverse_proxy /* 127.0.0.1:3000
}
EOF
```

**Load Balancing Configuration:**
```bash
# Update Caddy upstream list
docker exec caddy caddy reverse-proxy --from :443 \
  --to 192.168.168.31:8080 \
  --to 192.168.168.42:8080
```

#### DNS Configuration

**Update DNS Records:**
```
api.kushnir.cloud:  192.168.168.31
api-replica.kushnir.cloud: 192.168.168.42

# For active-active, use DNS load balancing:
api.kushnir.cloud:  192.168.168.31, 192.168.168.42 (round-robin)
```

---

### Deployment Phase 5: Monitoring Setup (20 minutes)

**Goal:** Configure monitoring for active-active cluster

#### Prometheus Federation

**Primary Prometheus:**
```yaml
scrape_configs:
  - job_name: 'federate'
    scrape_interval: 15s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job="prometheus"}'
        - '{__name__=~"job:.*"}'
    static_configs:
      - targets:
          - 'localhost:9090'
          - '192.168.168.42:9090'
```

**Replica Prometheus:**
```yaml
scrape_configs:
  - job_name: 'replica-local'
    static_configs:
      - targets:
          - '192.168.168.42:9090'
```

#### Grafana Multi-Source

```bash
# Add replica Prometheus as data source in Grafana
curl -X POST http://192.168.168.31:3000/api/datasources \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "Prometheus-Replica",
    "type": "prometheus",
    "url": "http://192.168.168.42:9090",
    "access": "proxy"
  }'
```

**Checklist:**
- [ ] Prometheus federation configured
- [ ] Replica metrics visible in primary Prometheus
- [ ] Grafana dashboards showing data from both clusters
- [ ] Alert rules configured for active-active

---

### Deployment Phase 6: Validation & Testing (45 minutes)

#### Failover Test

**Simulate Primary Failure:**
```bash
# Stop primary services (controlled test)
docker-compose -f /opt/code-server/docker-compose.yml down

# Verify requests route to replica
curl -s http://api.kushnir.cloud/health
# Expected: Healthy response from replica

# Restart primary services
docker-compose -f /opt/code-server/docker-compose.yml up -d
```

#### Data Consistency Test

```bash
# Write to primary
curl -X POST http://192.168.168.31/api/data \
  -H 'Content-Type: application/json' \
  -d '{"test": "data"}'

# Read from replica
curl http://192.168.168.42/api/data
# Expected: Same data visible

# Write to replica
curl -X POST http://192.168.168.42/api/data \
  -H 'Content-Type: application/json' \
  -d '{"test": "replica-data"}'

# Verify bidirectional sync
curl http://192.168.168.31/api/data
# Expected: Data written to replica is visible on primary
```

#### Performance Validation

```bash
# Load test with requests split between clusters
ab -n 1000 -c 50 \
  -D "192.168.168.31,192.168.168.42" \
  http://api.kushnir.cloud/health

# Expected:
# - Requests processed: 1000
# - Success rate: 100%
# - Response time < 100ms median
# - Requests evenly distributed across both IPs
```

**Checklist:**
- [ ] Failover to replica works smoothly
- [ ] Data consistent after failover
- [ ] Failback to primary successful
- [ ] No data loss during failover
- [ ] Performance meets SLAs (<100ms response time)
- [ ] All services healthy on both clusters

---

### Post-Deployment Monitoring (Ongoing)

#### Key Metrics to Monitor

| Metric | Source | Target | Alert |
|--------|--------|--------|-------|
| Replication Lag | PostgreSQL | < 1 second | > 10 seconds |
| Redis Sync Lag | Redis | Near-instant | > 100ms |
| API Response Time | Caddy | < 100ms | > 500ms |
| Error Rate | Application | < 0.1% | > 1% |
| Node CPU | system | < 70% | > 85% |
| Node Memory | system | < 80% | > 90% |

#### Automated Health Checks

```bash
# Run automated validation daily
0 2 * * * bash scripts/ops/validate-production-deployment.sh >> /var/log/deployment-validation.log 2>&1

# Check replication lag hourly
0 * * * * docker exec postgres psql -U postgres -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;" >> /var/log/replication-lag.log
```

---

## Rollback Procedures

### If Issues Occur During Deployment

#### Scenario 1: Replica Services Won't Start

```bash
# Roll back: Stop replica services
bash scripts/ha/deploy-active-active.sh --stop-replica --target 192.168.168.42

# Keep primary running
# Investigation: Check replica logs
ssh ubuntu@192.168.168.42 "docker-compose logs | head -100"
```

#### Scenario 2: Replication Errors

```bash
# Verify database is accessible
docker exec postgres psql -U postgres -c "SELECT 1;"

# Reset replication if stuck
docker exec postgres psql -U postgres -c \
  "SELECT pg_drop_replication_slot('replica_slot');"
docker exec postgres psql -U postgres -c \
  "SELECT * FROM pg_create_physical_replication_slot('replica_slot');"

# Restart replica PostgreSQL
ssh ubuntu@192.168.168.42 "docker restart postgres"
```

#### Scenario 3: Failover Issues

```bash
# Manual failover to replica
ssh ubuntu@192.168.168.42 "
  docker exec postgres psql -U postgres -c \
    'SELECT pg_promote();'
"

# Primary becomes standby
docker-compose stop
# Clean shutdown on primary

# Replica now primary for operations
```

---

## Success Criteria

✅ **Phase 6 Deployment Successful When:**

1. **Connectivity:**
   - [ ] SSH works bidirectionally without password
   - [ ] Network latency < 50ms between clusters
   - [ ] Firewall allows required ports

2. **Services:**
   - [ ] All 37 services running on replica
   - [ ] Health endpoints responding on both clusters
   - [ ] No service restarts (stable for 5+ minutes)

3. **Replication:**
   - [ ] PostgreSQL replication lag < 1 second
   - [ ] Redis sync confirmed (write primary, read replica)
   - [ ] Bidirectional replication operational

4. **Load Balancing:**
   - [ ] DNS round-robin working
   - [ ] Caddy routes requests to both clusters
   - [ ] Failover automatic and seamless

5. **Monitoring:**
   - [ ] Prometheus collecting from both clusters
   - [ ] Grafana shows unified view
   - [ ] Alerts configured and tested

6. **Data Integrity:**
   - [ ] No data loss during failover
   - [ ] Consistency verified (write primary, confirm replica)
   - [ ] Bidirectional writes functional

---

## Timeline & Effort Estimates

| Phase | Duration | Cumulative | Notes |
|-------|----------|-----------|-------|
| 1. Infrastructure | 30 min | 30 min | Blocked until replica accessible |
| 2. Services Startup | 30 min | 60 min | Parallel tasks possible |
| 3. Replication | 45 min | 105 min | Include verification time |
| 4. Load Balancing | 30 min | 135 min | DNS propagation 5-10 min |
| 5. Monitoring | 20 min | 155 min | Configure alerting |
| 6. Testing & Validation | 45 min | 200 min | Full failover cycle |
| **Total** | | **~3.5 hours** | Non-sequential, can parallelize |

---

## Scripts Reference

### Ready-to-Execute Scripts

```bash
# 1. Diagnose connectivity issues
bash scripts/ha/diagnose-replica-connectivity.sh --target 192.168.168.42

# 2. Setup replica infrastructure
bash scripts/ha/setup-replica-cluster.sh --target 192.168.168.42 --verbose

# 3. Deploy active-active configuration
bash scripts/ha/deploy-active-active.sh --target 192.168.168.42 --verify

# 4. Validate production deployment
bash scripts/ops/validate-production-deployment.sh --verbose
```

---

**Package Version:** 1.0  
**Status:** 🟢 Ready for Deployment  
**Last Updated:** 2026-04-28  
**Next Review:** Upon infrastructure connectivity restoration
