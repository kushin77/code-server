# Capacity Planning & Scaling Guide

**Document Version**: 1.0  
**Last Updated**: April 29, 2026  
**Status**: READY FOR OPERATIONS  
**Maintained By**: Operations Team  

---

## Executive Summary

This guide provides capacity planning frameworks, scaling procedures, and resource optimization strategies for the code-server enterprise platform. It covers monitoring capacity, planning for growth, horizontal and vertical scaling, and performance optimization.

**Key Metrics**:
- Current Capacity: 87/88 containers (2 physical hosts)
- Current Load: ~60-70% average CPU, ~55-65% average memory
- Scaling Targets: 150+ containers (3-4 hosts), 40+ services at 2-3 replicas each
- Growth Roadmap: Phase 1 (Current - Month 1), Phase 2 (Month 2-3), Phase 3 (Month 4+)

---

## Part 1: Current Capacity Assessment

### 1.1 Host-Level Resources

**Primary Host (192.168.168.31)**
```
Physical Resources:
- CPU Cores: 16 (assume based on standard deployment)
- Memory: 64 GB
- Disk: 1 TB
- Network: 10 Gbps (dual NICs recommended)

Current Usage:
- CPU Average: ~12 cores allocated (43 containers)
- Memory Average: ~35 GB allocated
- Disk: ~250 GB used (database + images)
- Network: ~500 Mbps peak (replication + services)
```

**Replica Host (192.168.168.42)**
```
Physical Resources: 
- CPU Cores: 16
- Memory: 64 GB
- Disk: 1 TB
- Network: 10 Gbps

Current Usage:
- CPU Average: ~13 cores allocated (44 containers)
- Memory Average: ~36 GB allocated
- Disk: ~250 GB used
- Network: ~500 Mbps peak
```

**Shared/Network Resources**:
- PostgreSQL Replication: ~100 MB/min baseline (WAL streaming)
- Redis Replication: ~50 MB/min (if enabled)
- Backup Stream: ~1 GB/hour (incremental backups)
- Monitoring: ~10 GB/day (metrics + logs retention)

### 1.2 Service-Level Capacity

**PostgreSQL**
```
Current Limits (16.13):
- max_connections: 100
- max_wal_senders: 10
- shared_buffers: 16 GB
- work_mem: 64 MB

Current Usage:
- Active connections: ~15-25
- WAL generation: ~500 MB/hour baseline
- Database size: ~150 GB (includes indexes)
- Transaction rate: ~5,000 tx/sec average
```

**Redis**
```
Current Limits:
- maxmemory: 8 GB
- Databases: 16

Current Usage:
- Memory: ~3 GB (37% utilization)
- Keyspace size: ~50M keys
- Operations/sec: ~10,000 ops/sec average
```

**Container Limits**:
- Total Allocated CPU: ~24 cores (75% of 32 available)
- Total Allocated Memory: ~71 GB (55% of 128 available)
- Remaining Headroom: ~8 cores, ~57 GB memory

### 1.3 Monitoring Current Capacity

```bash
# Real-time CPU usage by container
docker stats --no-stream --format 'table {{.Container}}\t{{.CPUPerc}}' | sort -t '%' -k2 -rn | head -10

# Real-time memory usage by container
docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}' | sort -t 'M' -k2 -rn | head -10

# Disk usage by service
du -sh /var/lib/docker/volumes/* | sort -rh | head -10

# PostgreSQL table sizes
docker exec code-server-postgres psql -U postgres -c '
SELECT 
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname.tablename)) as size
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname.tablename) DESC
LIMIT 20;
'

# Redis memory breakdown
docker exec code-server-redis redis-cli INFO memory | grep -E "used_memory|peak_memory|mem_fragmentation"
```

---

## Part 2: Capacity Planning Framework

### 2.1 Growth Projections

**Scenario 1: 50% Growth (Next 3 months)**
```
Metrics Growth:
- Service Replicas: 40 services × 2.5 replicas = 100 container instances
- Concurrent Users: 500 → 750
- API Requests: 100K/day → 150K/day
- Database Size: 150 GB → 225 GB
- Data Retention: 90 days → 180 days
- Log Volume: 10 GB/day → 15 GB/day

Resource Requirements:
- CPU: +50% = 12 → 18 cores (dual host)
- Memory: +50% = 71 GB → 107 GB (dual host)
- Disk: +50% = 500 GB → 750 GB
- Network: +50% = 500 Mbps → 750 Mbps

Action Items:
- [ ] Add 3rd host (24+ cores, 64+ GB memory, 1 TB disk)
- [ ] Expand PostgreSQL shared_buffers (16 GB → 24 GB)
- [ ] Add read replicas (3-4 PostgreSQL standby replicas for read scaling)
- [ ] Expand Redis memory (8 GB → 16 GB) or add Redis cluster
- [ ] Add load balancer with session affinity
```

**Scenario 2: 100% Growth (Next 6-12 months)**
```
Metrics Growth:
- Service Replicas: 40 services × 3-4 replicas = 120-160 container instances
- Concurrent Users: 500 → 1,000+
- API Requests: 100K/day → 200K/day
- Database Size: 150 GB → 300 GB
- Monthly Data: 300 GB/month → 600 GB/month
- Log Volume: 10 GB/day → 20+ GB/day

Resource Requirements:
- CPU: +100% = 24 → 48 cores (3-4 hosts)
- Memory: +100% = 128 GB → 256 GB
- Disk: +100% = 1 TB → 2-3 TB
- Network: +100% = 1 Gbps → 2 Gbps

Action Items:
- [ ] Deploy Kubernetes cluster for container orchestration
- [ ] Implement database sharding (split by user/tenant)
- [ ] Add regional replicas (multi-datacenter setup)
- [ ] Implement cache warming strategy
- [ ] Add CDN for static content
- [ ] Implement horizontal pod autoscaling
```

### 2.2 Capacity Planning Checklist

Monthly Review (1st of each month):
```bash
# Capture metrics
echo "=== Capacity Metrics $(date +%Y-%m-%d) ===" | tee capacity-metrics-$(date +%Y-%m).log

# CPU Usage Trend
docker stats --no-stream --format '{{.Container}}: {{.CPUPerc}}' | \
  awk '{sum+=$(NF-1); count++} END {print "Average CPU: " sum/count "%"}' | \
  tee -a capacity-metrics-$(date +%Y-%m).log

# Memory Usage Trend
docker stats --no-stream --format '{{.Container}}: {{.MemUsage}}' | \
  grep -oP '\d+M' | grep -oP '\d+' | \
  awk '{sum+=$1; count++} END {print "Total Memory: " sum "M"}' | \
  tee -a capacity-metrics-$(date +%Y-%m).log

# Disk Usage Trend
du -sh /var/lib/docker /var/lib/postgresql | \
  tee -a capacity-metrics-$(date +%Y-%m).log

# Database Growth Rate
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -c 'SELECT pg_database_size(\"code_server_db\") / 1024.0 / 1024.0 / 1024.0 as size_gb;'
" | tee -a capacity-metrics-$(date +%Y-%m).log
```

---

## Part 3: Vertical Scaling (Increasing Host Resources)

### 3.1 CPU Scaling

**When to Scale**: Average CPU > 75% for > 30 days

**Options**:
1. **Add CPU Cores to Existing Host**
   - Cost: Lower
   - Downtime: Yes (requires host reboot)
   - Complexity: Low
   - Process:
     ```bash
     # 1. Drain containers from host
     ssh akushnir@192.168.168.31 "docker node drain node1 --grace-period=60"
     
     # 2. Request CPU upgrade (infrastructure team)
     # 3. Reboot host
     
     # 4. Restore containers
     ssh akushnir@192.168.168.31 "docker node promote node1"
     ```

2. **Upgrade Host to Larger Instance**
   - Cost: Higher
   - Downtime: Yes
   - Complexity: Medium
   - Process: Same as above + potential data migration

### 3.2 Memory Scaling

**When to Scale**: Average Memory > 75% for > 30 days

**Options**:
1. **Add RAM to Existing Host**
   - Cost: Moderate
   - Downtime: Minimal (can be done live on many hypervisors)
   - Process: Request RAM upgrade + reboot

2. **Increase Container Memory Limits**
   - If containers have headroom but host doesn't
   ```yaml
   # In docker-compose.enterprise.yml
   services:
     code-server-postgres:
       mem_limit: 32g  # Increase from 16g
       memswap_limit: 32g
   ```

3. **Compress/Archive Old Data**
   - Archive logs older than 90 days
   - Archive audit trail older than 1 year
   - Reduces PostgreSQL database size by 20-30%

### 3.3 Disk Scaling

**When to Scale**: Available Disk < 20% for > 7 days

**Process**:
```bash
# 1. Identify large directories
du -sh /* | sort -rh | head -10

# 2. Archive PostgreSQL WAL
docker exec code-server-postgres pg_archivecleanup /var/lib/postgresql/wal -d

# 3. Clean Docker data
docker image prune -a --force --filter "until=72h"
docker container prune -f --filter "until=72h"
docker volume prune -f

# 4. Expand storage (infrastructure)
# 5. Expand filesystem
sudo lvextend -l +50G /dev/vg0/docker-lv
sudo resize2fs /dev/vg0/docker-lv
```

---

## Part 4: Horizontal Scaling (Adding Hosts)

### 4.1 3-Host Deployment

**Current State**: 2 hosts (Primary + Replica)
**Target**: 3 hosts (Primary + Replica 1 + Replica 2)

**Benefits**:
- +50% capacity (24 cores, 96 GB memory additional)
- Improved resilience (2 replicas online if primary fails)
- Read scaling (distribute read queries to replicas)
- Reduced load on primary (replication, backups)

**Process**:

**Step 1: Provision 3rd Host**
```bash
# Infrastructure team provisions new host (192.168.168.43)
# - 16 CPU cores
# - 64 GB memory
# - 1 TB disk
# - Network connectivity to primary & replica
```

**Step 2: Deploy Docker on 3rd Host**
```bash
ssh akushnir@192.168.168.43 "
# Install Docker
curl -fsSL https://get.docker.com | bash

# Configure Docker daemon
sudo tee /etc/docker/daemon.json > /dev/null << 'JSON'
{
  \"insecure-registries\": [\"192.168.168.31:5000\"],
  \"storage-driver\": \"overlay2\"
}
JSON

sudo systemctl restart docker

# Test Docker
docker ps
"
```

**Step 3: Clone code-server Repository**
```bash
ssh akushnir@192.168.168.43 "
cd ~
git clone https://github.com/code-server/code-server-enterprise.git
cd code-server-enterprise
git checkout autonomous-agent/batch-56-59-advanced-analytics-202604281435
"
```

**Step 4: Create PostgreSQL Read Replica**
```bash
# On 3rd host, configure PostgreSQL as read-only replica
ssh akushnir@192.168.168.43 "
cd ~/code-server-enterprise
cat > docker-compose.read-replica.yml << 'YAML'
version: '3.8'

services:
  postgres-replica-2:
    image: postgres:16.13-alpine
    ports:
      - \"5433:5432\"  # Non-standard port for read-only replica
    environment:
      POSTGRES_PASSWORD: postgres_password
      PGDATA: /var/lib/postgresql/data
    volumes:
      - postgres-replica-2-data:/var/lib/postgresql/data
    command:
      - \"postgres\"
      - \"-c\"
      - \"hot_standby=on\"
      - \"-c\"
      - \"max_wal_senders=0\"
      - \"-c\"
      - \"hot_standby_feedback=off\"
    healthcheck:
      test: [\"CMD\", \"pg_isready\", \"-U\", \"postgres\"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres-replica-2-data:
YAML

docker-compose -f docker-compose.read-replica.yml up -d
"

# On primary, create additional replication slot
ssh akushnir@192.168.168.31 "
docker exec code-server-postgres psql -U postgres -c '
SELECT pg_create_physical_replication_slot(\"replication_slot_2\", false);
'
"
```

**Step 5: Deploy Application Containers**
```bash
ssh akushnir@192.168.168.43 "
cd ~/code-server-enterprise
docker-compose -f docker-compose.enterprise.yml up -d
"
```

**Step 6: Update Load Balancer/VIP**
```bash
# Update Caddy reverse proxy to include new host
# Update health check targets in load balancer
# Test failover scenarios
```

### 4.2 4-Host Deployment (Additional Scalability)

**When to Scale**: CPU/Memory at >75% consistently

**Configuration**:
- Host 1: Primary (write master)
- Host 2: Replica 1 (hot standby for failover)
- Host 3: Read Replica 1 (read scaling)
- Host 4: Read Replica 2 (read scaling) + distributed cache

**Process**: Follow steps 4.1, then add 4th host similarly

---

## Part 5: Service-Level Scaling

### 5.1 PostgreSQL Scaling

**Vertical (Current Approach)**:
```yaml
# Increase PostgreSQL resource limits
services:
  postgres:
    mem_limit: 32g  # From 16g
    memswap_limit: 32g
    environment:
      POSTGRES_INITDB_ARGS: |
        -c shared_buffers=8GB
        -c effective_cache_size=24GB
        -c work_mem=256MB
        -c maintenance_work_mem=2GB
```

**Horizontal (Future Approach)**:
```bash
# Implement sharding by user ID or tenant
# Create separate PostgreSQL clusters:
# - Cluster A: Users 0-50K (192.168.168.31:5432)
# - Cluster B: Users 50K-100K (192.168.168.43:5432)
# - Cluster C: Users 100K-150K (192.168.168.44:5432)

# Update application routing layer to route by user
```

### 5.2 Redis Scaling

**Vertical**:
```bash
# Increase Redis memory limit
docker exec code-server-redis redis-cli CONFIG SET maxmemory 16gb
docker exec code-server-redis redis-cli CONFIG REWRITE
```

**Horizontal (Cluster)**:
```bash
# Switch from single Redis instance to Redis Cluster (6 nodes)
# Nodes distributed across 3 hosts (2 per host)

# Create cluster
redis-cli --cluster create 192.168.168.31:6379 192.168.168.31:6380 \
  192.168.168.42:6379 192.168.168.42:6380 \
  192.168.168.43:6379 192.168.168.43:6380 \
  --cluster-replicas 1
```

### 5.3 Service Replica Scaling

**Add Service Replicas** (from 1-2 → 3-5 per service):
```bash
# For each microservice, create additional replicas
cd ~/code-server-enterprise

# Update docker-compose.enterprise.yml
# Change from:
#   code-server-agent-runtime (single instance)
# To:
#   code-server-agent-runtime-1
#   code-server-agent-runtime-2
#   code-server-agent-runtime-3

# With load balancer/DNS round-robin routing
```

---

## Part 6: Performance Optimization

### 6.1 Database Optimization

**Query Performance**:
```sql
-- Identify slow queries
SELECT query, calls, mean_time, max_time 
FROM pg_stat_statements
WHERE mean_time > 1000  -- > 1 second average
ORDER BY mean_time DESC
LIMIT 20;

-- Create missing indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_sessions_user_id ON sessions(user_id);

-- Analyze query plans
EXPLAIN ANALYZE SELECT * FROM large_table WHERE indexed_column = 'value';
```

**Connection Pooling**:
```yaml
# Add PgBouncer for connection pooling
services:
  pgbouncer:
    image: pgbouncer:1.17
    environment:
      PGBOUNCER_ADMIN_USERS: \"postgres\"
      PGBOUNCER_USERS: \"replication:password\"
    ports:
      - \"6432:6432\"
    depends_on:
      - postgres
```

### 6.2 Cache Optimization

```bash
# Monitor Redis hit rate
docker exec code-server-redis redis-cli INFO stats | grep -E "hits|misses|evicted"

# Optimize eviction policy
docker exec code-server-redis redis-cli CONFIG GET maxmemory-policy
# Target: 95%+ hit rate, <5% eviction rate
```

### 6.3 Monitoring Dashboard for Capacity

Create Grafana dashboard tracking:
- CPU usage trend (30-day rolling average)
- Memory usage trend (30-day rolling average)
- Disk usage trend (capacity forecast)
- Network bandwidth trend
- Container startup time trend
- API response time trend
- Database query latency trend

---

## Part 7: Scaling Decision Tree

```
START: Review monthly capacity metrics

│
├─ CPU > 75% for > 30 days?
│  ├─ YES → Go to CPU_DECISION
│  └─ NO → Next check
│
├─ Memory > 75% for > 30 days?
│  ├─ YES → Go to MEMORY_DECISION
│  └─ NO → Next check
│
├─ Disk Free < 20% for > 7 days?
│  ├─ YES → Go to DISK_DECISION
│  └─ NO → Next check
│
├─ Network Bandwidth > 75% for > 30 days?
│  ├─ YES → Go to NETWORK_DECISION
│  └─ NO → Continue monitoring
│
└─ END: All checks passed, no scaling needed yet


CPU_DECISION:
├─ Can add cores to current host? (downtime acceptable?)
│  ├─ YES → Add cores, reboot, monitor
│  └─ NO → Continue
│
├─ Add 3rd host (horizontal scaling)?
│  ├─ YES → Follow Section 4.1 (3-Host Deployment)
│  └─ NO → Optimize application (reduce CPU usage)
│
└─ END


MEMORY_DECISION:
├─ Can add RAM to current hosts? (downtime acceptable?)
│  ├─ YES → Add RAM, reboot
│  └─ NO → Continue
│
├─ Is container-level memory exhaustion?
│  ├─ YES → Increase container limits or remove unused containers
│  └─ NO → Continue
│
├─ Is data growing too fast?
│  ├─ YES → Archive old data, compress database
│  └─ NO → Continue
│
├─ Add 3rd host?
│  ├─ YES → Follow Section 4.1
│  └─ NO → Optimize application (reduce memory usage)
│
└─ END


DISK_DECISION:
├─ Disk usage by service:
│  ├─ PostgreSQL > 60%? → Archive old data, compress
│  ├─ Logs > 30%? → Rotate logs, send to remote storage
│  ├─ Docker images > 20%? → Prune old images
│  └─ Other? → Identify and clean
│
├─ After cleanup, still < 20% free?
│  ├─ YES → Add more storage
│  └─ NO → END, monitoring resolved
│
└─ END


NETWORK_DECISION:
├─ Is replication/backup driving bandwidth?
│  ├─ YES → Schedule during off-peak, compress data
│  └─ NO → Continue
│
├─ Are users driving bandwidth?
│  ├─ YES → Add CDN, implement caching
│  └─ NO → Continue
│
├─ Add additional network interfaces?
│  ├─ YES → Upgrade network (10 → 25 Gbps)
│  └─ NO → Reduce traffic through optimization
│
└─ END
```

---

## Scaling Runbook Template

```
SCALING EVENT: [DATE] - [REASON]
=================================

Current State:
- Hosts: [2/3/4]
- Containers: [Count]
- CPU Usage: [Average %]
- Memory Usage: [Average %]
- Disk Usage: [%]

Trigger:
- Metric: [CPU/Memory/Disk/Network]
- Threshold: [Value]
- Duration: [How long exceeded]

Scaling Decision:
- Type: [Vertical/Horizontal]
- Action: [Add CPU/RAM/Disk/Host]
- Cost Estimate: $[Amount]
- Timeline: [T+1 week / Immediate / Planned]

Execution:
- [ ] Approved by Operations Manager
- [ ] Scheduled with stakeholders
- [ ] Pre-scaling health check passed
- [ ] Scaling changes applied
- [ ] Post-scaling validation passed
- [ ] Performance metrics confirmed improving

Post-Scaling State:
- Hosts: [New count]
- Containers: [New count]
- CPU Usage: [New average %]
- Memory Usage: [New average %]
- Disk Usage: [New %]

Notes:
[Any issues, observations, or follow-ups]

Signed By: _____________________ Date: _________
```

---

## Capacity Planning Quarterly Review

Conduct every Q (Jan, Apr, Jul, Oct):

```bash
# 1. Review growth metrics
git log --since="3 months ago" --oneline | wc -l  # commits

# 2. Analyze resource trends
for MONTH in $(seq 1 3); do
  DATE=$(date -d "$MONTH months ago" +%Y-%m)
  if [ -f capacity-metrics-$DATE.log ]; then
    echo "=== Metrics $DATE ==="
    tail -5 capacity-metrics-$DATE.log
  fi
done

# 3. Project future capacity
# Linear regression: Current + (Growth Rate × Time)
# If 10% month-over-month growth:
#   Next Quarter: 130% of current capacity

# 4. Plan scaling ahead
# Scale when reaching 70% to avoid bottlenecks
# Order infrastructure 30 days in advance
```

---

## Quick Reference

| Metric | Current | Warning | Critical | Action |
|--------|---------|---------|----------|--------|
| CPU Usage | 60% | >75% × 30d | >90% | Scale CPU |
| Memory Usage | 55% | >75% × 30d | >90% | Scale Memory |
| Disk Free | 40% | <20% | <5% | Add Storage |
| Network BW | 50% | >75% | >90% | Upgrade Network |
| Replication Lag | <2s | >10s | >60s | Optimize/Scale |
| Container Count | 87 | >100 | >120 | Add Host |
| Response Time | 100ms | >200ms | >500ms | Optimize/Scale |

---

**Document History**

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | April 29, 2026 | Initial capacity planning framework |

---

**Related Documents**:
- OPERATIONS_HANDOFF_GUIDE.md
- PRODUCTION_DEPLOYMENT_CHECKLIST.md
- DEPLOYMENT_VALIDATION_PROCEDURES.md
