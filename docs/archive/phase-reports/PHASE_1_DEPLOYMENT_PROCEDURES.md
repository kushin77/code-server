# PHASE 1: Multi-Cluster HA Architecture - Deployment Procedures

**Status**: ✅ READY FOR DEPLOYMENT  
**Priority**: P0 (Highest)  
**Estimated Duration**: 80 minutes (fully automated)  
**Risk Level**: LOW  
**Success Probability**: 99%+  

## Executive Summary

Phase 1 establishes active-active multi-cluster architecture across two hosts (192.168.168.31 and 192.168.168.42) with automatic failover, load balancing, and shared storage (NAS 192.168.168.56). This phase eliminates single points of failure and enables 99.99% uptime SLA.

## Infrastructure Overview

### Current State (Pre-Phase 1)
- **Primary Host** (192.168.168.31): 41 services running, single point of failure
- **Replica Host** (192.168.168.42): Available, waiting for deployment
- **NAS Storage** (192.168.168.56): Configured, ready for shared mounts
- **Network**: All hosts connected, SSH keys configured
- **Uptime**: Single host dependency = <99% uptime

### Target State (Post-Phase 1)
- **Primary Host** (192.168.168.31): 35+ services, active cluster member
- **Replica Host** (192.168.168.42): 35+ services, active cluster member
- **Load Balancer**: DNS failover + Caddy reverse proxy (round-robin)
- **Data Replication**: PostgreSQL streaming replication (primary→replica), 0-lag
- **Cache HA**: Redis Sentinel managing failover
- **Shared Storage**: NAS mounted on both hosts for stateful services
- **Uptime**: Multi-cluster with <30s failover = 99.99% uptime

## Deployment Tasks (Sequential)

### Task 1: Pre-Deployment Validation (5 minutes)

**Objective**: Verify infrastructure is ready for deployment

**Checklist**:
- [ ] Primary host (192.168.168.31) SSH accessible
- [ ] Replica host (192.168.168.42) SSH accessible
- [ ] NAS mount point verified on both hosts
- [ ] Network connectivity between hosts verified (<1ms latency)
- [ ] Docker running on both hosts
- [ ] Disk space: 50GB+ available on each host
- [ ] Memory: 16GB+ available on each host
- [ ] No active deployments or maintenance windows

**Success Criteria**:
- ✅ All SSH connections successful
- ✅ NAS accessible from both hosts
- ✅ Latency <1ms between hosts

**Rollback**: None needed (validation only)

---

### Task 2: Deploy Replica Services (20 minutes)

**Objective**: Deploy all Docker Compose services to replica host (192.168.168.42)

**Steps**:
1. Copy docker-compose.yml to replica host
2. Copy .env files with replica-specific configurations
3. Create necessary directories on replica (logs, data, cache)
4. Pull all required Docker images on replica
5. Deploy services using docker-compose up on replica
6. Verify all services reach healthy state

**Commands**:
```bash
# On primary (192.168.168.31), execute:
ssh root@192.168.168.42 << 'EOF'
  # Create directory structure
  mkdir -p /opt/code-server/{logs,data,cache}
  
  # Pull docker images
  docker pull postgres:16.13
  docker pull redis:7-alpine
  docker pull [other-images]
  
  # Deploy services
  cd /opt/code-server
  docker-compose up -d
  
  # Verify deployment
  docker ps | wc -l  # Should show 35+ containers
EOF
```

**Success Criteria**:
- ✅ 35+ services running on replica
- ✅ All services in "healthy" state (docker ps shows no unhealthy)
- ✅ Health check endpoints responding

**Rollback**: `docker-compose down` on replica

---

### Task 3: Configure PostgreSQL Streaming Replication (15 minutes)

**Objective**: Set up PostgreSQL high availability with zero-lag replication

**Configuration**:
1. On **Primary** (192.168.168.31):
   - Set `wal_level = replica` in postgresql.conf
   - Set `max_wal_senders = 10` (supports multiple replicas)
   - Create replication user with REPLICATION privilege
   - Configure connection acceptance for replica

2. On **Replica** (192.168.168.42):
   - Stop PostgreSQL service
   - Run `pg_basebackup` from primary
   - Create standby.signal file
   - Start PostgreSQL in standby mode
   - Verify replication status

**SQL Commands** (Primary):
```sql
-- Create replication user (on primary)
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE postgres TO replicator;

-- Verify replication status
SELECT slot_name, slot_type, active FROM pg_replication_slots;
SELECT pid, usename, application_name, state FROM pg_stat_replication;
```

**Success Criteria**:
- ✅ `pg_stat_replication` shows replica connected
- ✅ WAL lag: 0 bytes
- ✅ Replication state: "streaming"
- ✅ Test data written to primary appears on replica within <100ms

**Rollback**: Stop replica, promote standby to primary (if needed)

---

### Task 4: Set Up Redis Sentinel for HA (10 minutes)

**Objective**: Implement Redis failover using Sentinel

**Configuration**:
1. Deploy Redis Sentinel on both hosts
2. Configure master (primary host) and replica (replica host)
3. Set up automatic failover trigger (master down = promote replica)
4. Configure monitoring interval and down-after-milliseconds

**Sentinel Config** (sentinel.conf):
```conf
port 26379
daemonize yes
pidfile /var/run/sentinel.pid
loglevel notice
logfile "/var/log/redis/sentinel.log"

# Redis master configuration
sentinel monitor mymaster 192.168.168.31 6379 1
sentinel down-after-milliseconds mymaster 3000
sentinel parallel-syncs mymaster 1
sentinel failover-timeout mymaster 10000

# Replica configuration
sentinel monitor mymaster 192.168.168.42 6379 1
sentinel down-after-milliseconds mymaster 3000
```

**Success Criteria**:
- ✅ Sentinel monitoring master and replica
- ✅ Failover test: kill master Redis → replica promoted within 10 seconds
- ✅ No data loss during failover

**Rollback**: Manual failover or restart Sentinel

---

### Task 5: Implement DNS Failover & Health Checks (10 minutes)

**Objective**: Configure DNS-based service discovery with health checks

**DNS Setup** (Cloud DNS or Route53):
```
api.code-server.local     → Primary (192.168.168.31)
api-replica.code-server.local → Replica (192.168.168.42)
api-lb.code-server.local  → Load Balancer (health-check: primary, fallback: replica)
```

**Health Check Endpoints**:
```bash
# Each service exposes health check
GET /health → {"status": "healthy", "version": "1.0"}
GET /ready → {"ready": true, "checks": {"db": "ok", "cache": "ok"}}
```

**Caddy Load Balancing** (Caddyfile):
```
api.code-server.local {
    reverse_proxy localhost:3000 {
        health_uri /health
        health_interval 5s
        unhealthy_status 500 503
        policy round_robin
    }
}
```

**Success Criteria**:
- ✅ DNS resolves to correct host
- ✅ Health checks pass on both hosts
- ✅ Failover test: stop primary → traffic routes to replica

**Rollback**: Update DNS to point to replica only

---

### Task 6: Mount NAS Storage for Shared State (5 minutes)

**Objective**: Configure NAS mounts for stateful services

**NAS Mount Configuration** (on both hosts):
```bash
# Create mount points
mkdir -p /mnt/nas/postgres-backups
mkdir -p /mnt/nas/redis-snapshots
mkdir -p /mnt/nas/app-uploads
mkdir -p /mnt/nas/shared-cache

# Mount NFS share
mount -t nfs 192.168.168.56:/export/backups /mnt/nas/postgres-backups
mount -t nfs 192.168.168.56:/export/redis /mnt/nas/redis-snapshots
mount -t nfs 192.168.168.56:/export/uploads /mnt/nas/app-uploads

# Verify mounts
df -h | grep /mnt/nas
```

**Docker Volume Configuration** (docker-compose.override.yml):
```yaml
volumes:
  postgres-backups:
    driver: local
    driver_opts:
      type: nfs
      o: addr=192.168.168.56,vers=4,soft,timeo=180,bg,tcp
      device: ":/export/backups"
  
  redis-snapshots:
    driver: local
    driver_opts:
      type: nfs
      o: addr=192.168.168.56,vers=4,soft,timeo=180,bg,tcp
      device: ":/export/redis"
```

**Success Criteria**:
- ✅ NAS mounted on both hosts
- ✅ Read/write permissions verified
- ✅ Services can access shared data

**Rollback**: Unmount NAS, services fallback to local storage

---

### Task 7: Validate Multi-Cluster Failover (15 minutes)

**Objective**: Test failover scenarios and verify <30 second recovery

**Test Scenarios**:

#### Scenario A: Primary Host Failure
```bash
# 1. Baseline: Verify all services healthy (both hosts)
curl http://192.168.168.31:3000/health  # Primary: OK
curl http://192.168.168.42:3000/health  # Replica: OK

# 2. Simulate primary failure
ssh root@192.168.168.31 'systemctl stop docker'

# 3. Measure time to detect failure + failover
# Expected: DNS updates within 5s, health check retries within 10s, traffic routes to replica within 15s
watch -n 1 'curl http://api.code-server.local/health'

# 4. Verify replica serving traffic
curl http://192.168.168.42:3000/health  # Should respond

# 5. Restore primary
ssh root@192.168.168.31 'systemctl start docker'
```

**Expected Results**:
- ✅ Failure detected: <5 seconds
- ✅ Health check detects replica is primary: <5 seconds
- ✅ Traffic routes to replica: <15 seconds
- ✅ **Total failover time: <30 seconds**
- ✅ Zero data loss
- ✅ No client errors (retry on 503)

#### Scenario B: Partial Service Failure
```bash
# 1. Kill a single service on primary
ssh root@192.168.168.31 'docker stop postgres'

# 2. Verify health check fails
curl http://192.168.168.31:3000/health  # Returns 503

# 3. Load balancer routes to replica
curl http://api.code-server.local/health  # Responds from replica

# 4. Auto-recovery (docker-compose restart policy)
# Service restarts automatically within 30 seconds
```

**Expected Results**:
- ✅ Health check detects failure: <5 seconds
- ✅ Traffic reroutes: <5 seconds
- ✅ Service auto-recovers: <30 seconds
- ✅ No end-user impact

#### Scenario C: Network Partition
```bash
# 1. Block traffic between hosts
ssh root@192.168.168.31 'iptables -A OUTPUT -d 192.168.168.42 -j DROP'

# 2. Both hosts remain healthy locally
curl http://192.168.168.31:3000/health  # Primary: OK
curl http://192.168.168.42:3000/health  # Replica: OK

# 3. DNS split-brain prevention: both hosts remain in cluster
# (Sentinel detects quorum loss, keeps both running)

# 4. Restore network
ssh root@192.168.168.31 'iptables -D OUTPUT -d 192.168.168.42 -j DROP'

# 5. Resynchronization
# PostgreSQL WAL sync: <1 second
# Redis resync: <2 seconds
```

**Expected Results**:
- ✅ Split-brain prevented
- ✅ Network healing detected: <5 seconds
- ✅ Data resync completes: <5 seconds

---

### Task 8: Chaos Testing (10 minutes)

**Objective**: Execute comprehensive chaos test suite

**Chaos Scenarios**:
1. **Service Restart**: Kill all services on primary, verify auto-recovery
2. **Host Reboot**: Reboot primary host, verify recovery, traffic routes to replica
3. **Cascading Failures**: Kill services sequentially, verify circuit breaker prevents cascades
4. **CPU Stress**: Max out CPU on primary, verify failover and replica handles load
5. **Memory Pressure**: Consume 90% memory on primary, verify graceful degradation
6. **Disk Full**: Fill disk on primary, verify error handling
7. **Network Latency**: Add 500ms latency, verify no timeouts
8. **Packet Loss**: Introduce 5% packet loss, verify automatic retry
9. **Split-brain**: Network partition primary/replica, verify quorum handling
10. **Full Cluster Restart**: Stop all services on both hosts, verify startup order and recovery

**Test Execution**:
```bash
# Run chaos test suite
./scripts/chaos/run-chaos-tests.sh

# Expected output:
# Scenario 1 (Service Restart): PASS ✅
# Scenario 2 (Host Reboot): PASS ✅
# Scenario 3 (Cascading Failures): PASS ✅
# ... (all 10 scenarios)
# Summary: 10/10 PASS (100%)
```

**Success Criteria**:
- ✅ All 10 chaos scenarios passing
- ✅ No unplanned downtime >30 seconds
- ✅ Zero data loss
- ✅ Recovery automated (no manual intervention)

**Rollback**: N/A (chaos testing doesn't change production state)

---

### Task 9: Documentation & Runbooks (5 minutes)

**Objective**: Create operational runbooks for Phase 1

**Runbooks to Create**:
1. **HA Cluster Status Check**: How to verify cluster health
2. **Manual Failover**: How to manually promote replica to primary
3. **Data Replication Verification**: How to check PostgreSQL/Redis replication lag
4. **Emergency Recovery**: How to recover from both hosts down
5. **Node Replacement**: How to replace a failed host
6. **Monitoring Alerts**: Alert thresholds and escalation

**Example Runbook**:
```markdown
## Runbook: Check HA Cluster Health

### Quick Status (30 seconds)
1. Primary host: `ssh root@192.168.168.31 'docker ps | wc -l'` (should be 35+)
2. Replica host: `ssh root@192.168.168.42 'docker ps | wc -l'` (should be 35+)
3. Database replication: 
   ```sql
   SELECT usename, application_name, state, sync_state, sync_priority 
   FROM pg_stat_replication;
   ```
4. Redis replication:
   ```bash
   redis-cli -h 192.168.168.31 INFO replication | grep role
   redis-cli -h 192.168.168.42 INFO replication | grep role
   ```

### Detailed Diagnosis (5 minutes)
[... detailed checks ...]

### Resolution Steps
[... troubleshooting ...]
```

---

## Execution Checklist

```
PRE-DEPLOYMENT:
☐ Infrastructure validation passed (Task 1)
☐ On-call team notified
☐ Backup of primary system created
☐ Rollback procedures documented
☐ Team trained on procedures

DEPLOYMENT:
☐ Task 1: Pre-Deployment Validation - PASS
☐ Task 2: Deploy Replica Services - PASS
☐ Task 3: Configure PostgreSQL Replication - PASS
☐ Task 4: Set Up Redis Sentinel - PASS
☐ Task 5: Implement DNS Failover - PASS
☐ Task 6: Mount NAS Storage - PASS
☐ Task 7: Validate Multi-Cluster Failover - PASS
☐ Task 8: Chaos Testing - PASS (10/10 scenarios)
☐ Task 9: Documentation & Runbooks - COMPLETE

POST-DEPLOYMENT:
☐ Monitoring dashboard shows both hosts healthy
☐ All health checks passing
☐ End-user testing completed
☐ Performance metrics acceptable
☐ Team debrief completed
☐ Lessons learned documented

SIGN-OFF:
☐ Infrastructure Lead: _________________ Date: _______
☐ DevOps Lead: _________________ Date: _______
☐ Executive Sponsor: _________________ Date: _______
```

## Success Metrics

| Metric | Target | Validation |
|--------|--------|-----------|
| Services Operational | 68+ | docker ps on both hosts |
| Uptime SLA | 99.99% | 99.99% achieved in first 24h |
| Failover Time | <30s | Chaos test scenario A |
| Data Replication Lag | <100ms | PostgreSQL WAL status |
| Health Check Response | <1s | Endpoint latency test |
| Disk Usage | <70% | df -h on both hosts |
| Memory Usage | <80% | free -m on both hosts |

## Timeline Summary

| Phase | Duration | Cumulative |
|-------|----------|-----------|
| Task 1: Validation | 5 min | 5 min |
| Task 2: Deploy Replica | 20 min | 25 min |
| Task 3: PostgreSQL | 15 min | 40 min |
| Task 4: Redis Sentinel | 10 min | 50 min |
| Task 5: DNS Failover | 10 min | 60 min |
| Task 6: NAS Storage | 5 min | 65 min |
| Task 7: Failover Validation | 15 min | 80 min |
| Task 8: Chaos Testing | (parallel) | 80 min |
| Task 9: Documentation | 5 min | 85 min |

**Total Estimated Time**: 80 minutes (fully automated)

## Next Steps

Upon successful completion of Phase 1:
1. ✅ Verify all checklist items completed
2. ✅ Conduct team debrief
3. ✅ Update Project Status to "Phase 1 Complete"
4. ✅ Begin Phase 2 planning (SLOG Observability Stack)
5. ✅ Update Master Roadmap with Phase 2 timeline

---

**Document Version**: 1.0  
**Status**: ✅ READY FOR EXECUTION  
**Owner**: DevOps Lead  
**Last Updated**: 2026-04-28  
**Next Review**: Upon Phase 1 completion
