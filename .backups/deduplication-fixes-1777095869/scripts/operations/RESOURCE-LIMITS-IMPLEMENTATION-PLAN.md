# Resource Limits Implementation Plan

**Status**: 📋 PLANNING PHASE - Ready for implementation  
**Date**: April 24, 2026  
**Priority**: 🟠 HIGH - Required for Q3 Kubernetes migration  
**Impact**: Improves compliance from 60/100 → 90/100 (Resource Limits)  

---

## Current Gap Analysis

### Compliance Score Breakdown

| Category | Current | Target | Gap |
|----------|---------|--------|-----|
| Services with CPU limits | 24/32 | 32/32 | 8 services |
| Services with Memory limits | 24/32 | 32/32 | 8 services |
| Memory swap limits | 0/32 | 32/32 | 32 services |
| Network QoS policies | 0/32 | 20/32 | 20 services |
| Disk I/O limits | 0/32 | 16/32 | 16 services (high-volume) |

### Missing Resource Limits

**Services Without CPU/Memory Limits**:
1. paperclip-scheduler
2. edge-agent
3. paperclip-reputation
4. ollama-init
5. qdrant
6. temporal-server
7. temporal-worker
8. redis-cluster

### Configuration Changes Needed

Each service needs updates in `docker-compose.yml`:

```yaml
# BEFORE (no limits)
services:
  paperclip-api:
    image: paperclip:api
    ports:
      - "3100:3100"

# AFTER (with limits)
services:
  paperclip-api:
    image: paperclip:api
    ports:
      - "3100:3100"
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
          memswap_limit: 2G
        reservations:
          cpus: '1'
          memory: 1G
    sysctls:
      - net.core.somaxconn=1024
      - net.ipv4.ip_local_port_range=1024 65535
```

---

## Implementation Strategy

### Phase 1: Resource Profiling (2-3 hours)

**Goal**: Determine correct resource limits for each service

**Methods**:
```bash
# 1. Monitor current usage with Prometheus
curl 'http://prometheus:9090/api/v1/query?query=container_memory_usage_bytes'

# 2. Check Docker stats
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"

# 3. Review application logs for OOM/CPU throttling
grep -r "OOMKilled\|SIGKILL" /var/paperclip/logs/

# 4. Load test to find realistic peaks
# Run test suite: test suite duration 2-3 hours
./scripts/load-test/run-full-load-test.sh
```

**Resource Sizing Guide**:

| Service Type | CPU | Memory | Rationale |
|---|---|---|---|
| API Servers | 2 | 2G | Request handling, session management |
| Workers | 4 | 4G | Async processing, batch jobs |
| Databases | 4 | 8G | Query execution, caching |
| Caches | 2 | 4G | High throughput, in-memory |
| Services | 1 | 1G | Lightweight services |

### Phase 2: Configuration Updates (3-4 hours)

**Process**:
1. Update each service in `docker-compose.yml`
2. Add resource limits and reservations
3. Add sysctls for network optimization
4. Create configuration backup

**Example Update**:
```bash
# For each service:
# 1. Determine optimal limits from Phase 1 data
# 2. Update docker-compose.yml
# 3. Test in staging environment
# 4. Deploy to primary node
# 5. Monitor for 30 minutes
# 6. If OK, deploy to replica
```

### Phase 3: Validation & Testing (2-3 hours)

**Tests to Run**:
```bash
# 1. Service health check
./scripts/health-check-full.sh

# 2. Memory limit enforcement
# Run services to 90% limit
# Verify no OOMKilled events after 1 hour

# 3. CPU throttling
# Run CPU-intensive operation
# Verify performance degrades gracefully

# 4. Network QoS
# Run under high network load
# Verify packet loss < 0.1%

# 5. Disk I/O limits
# Run database backup
# Verify I/O not affecting other services
```

### Phase 4: Monitoring Setup (1-2 hours)

**Prometheus Metrics**:
```yaml
# Track resource limits vs usage
- job_name: 'resource-limits'
  static_configs:
    - targets: ['localhost:9090']
  metrics_path: '/api/v1/query'
  params:
    query: ['container_memory_usage_bytes', 'container_cpu_usage_seconds_total']
```

**Alerts**:
```yaml
groups:
  - name: resource_limits
    rules:
      # Memory pressure
      - alert: MemoryUsageHigh
        expr: 'container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.8'
        for: 5m
        annotations:
          summary: "Container {{ $labels.name }} memory usage > 80%"
      
      # CPU throttling
      - alert: CPUThrottling
        expr: 'rate(container_cpu_throttled_seconds_total[5m]) > 0.1'
        annotations:
          summary: "Container {{ $labels.name }} CPU throttled"
      
      # OOM killed
      - alert: OOMKilled
        expr: 'increase(container_oom_kills_total[5m]) > 0'
        severity: critical
        annotations:
          summary: "Container {{ $labels.name }} OOM killed"
```

---

## Implementation Rollout Schedule

### Week 1: High-Priority Services (Highest resource consumers)

```
Monday:   Phase 1 - Profile high-priority services
          qdrant, ollama-init, temporal-server
          
Tuesday:  Phase 2 - Update docker-compose.yml
          Phase 3 - Test in staging
          
Wednesday: Phase 4 - Deploy to primary node
           Monitor for issues
           
Thursday: Deploy to replica node
          Full validation
```

### Week 2: Medium-Priority Services

```
Monday:   Profile medium-priority services
          paperclip-api, edge-agent, reputation
          
Tuesday:  Update configs
          
Wednesday: Deploy and test
```

### Week 3: Low-Priority Services

```
Complete remaining services
Final validation
```

---

## Resource Limits by Service Category

### Stateful Services (Databases & Caches)

**qdrant** (Vector Database)
- CPU: 4 cores (search operations)
- Memory: 8GB (in-memory index)
- Disk I/O: 500MB/s
- Justification: Heavy search queries

**Redis Cluster**
- CPU: 2 cores
- Memory: 4GB (working set)
- Memswap: 1GB (emergency)
- Justification: High throughput caching

**PostgreSQL**
- CPU: 4 cores
- Memory: 8GB (buffers, cache)
- Swap: 2GB
- Justification: Query execution

### Compute Services (Workers & Processors)

**paperclip-scheduler**
- CPU: 4 cores
- Memory: 2GB
- Disk I/O: 200MB/s
- Justification: Parallel job execution

**temporal-server**
- CPU: 2 cores
- Memory: 2GB
- Justification: Workflow orchestration

**temporal-worker**
- CPU: 4 cores
- Memory: 2GB
- Justification: Task processing

### API Services

**paperclip-api**
- CPU: 2 cores
- Memory: 2GB
- Network: 100Mbps (burst)
- Justification: Request handling

**edge-agent**
- CPU: 1 core
- Memory: 512MB
- Network: 50Mbps
- Justification: Lightweight agent

### Infrastructure Services

**caddy**
- CPU: 1 core
- Memory: 256MB
- Network: 1Gbps
- Justification: Reverse proxy

**prometheus**
- CPU: 2 cores
- Memory: 2GB
- Disk I/O: 100MB/s
- Justification: Metrics scraping

---

## Kubernetes Readiness Impact

### Why This Matters for Q3 Phase 4

**Docker Compose Limitations**:
- No automatic resource enforcement
- Manual limit configuration
- No horizontal scaling support
- Difficult to debug resource issues

**Kubernetes Requirements**:
- Resource requests (min guaranteed)
- Resource limits (max cap)
- HPA (Horizontal Pod Autoscaling) based on metrics
- LimitRange policies
- ResourceQuota per namespace

**Current State → Kubernetes Ready**:
```
✅ Resource limits defined → Kubernetes requests/limits
✅ Monitoring in place → HPA metrics available
✅ Testing done → Real-world performance data
✅ Alerting configured → Resource pressure detection
```

---

## Implementation Checklist

### Pre-Implementation
- [ ] Back up current docker-compose.yml
- [ ] Provision staging environment
- [ ] Set up monitoring dashboard

### Phase 1: Profiling
- [ ] Collect baseline resource usage
- [ ] Run load tests
- [ ] Document findings

### Phase 2: Configuration
- [ ] Update docker-compose.yml for all 32 services
- [ ] Review resource allocations
- [ ] Create change documentation

### Phase 3: Testing
- [ ] Health checks pass
- [ ] Memory limits enforced
- [ ] CPU throttling works
- [ ] Network QoS operational
- [ ] Disk I/O limited

### Phase 4: Deployment
- [ ] Deploy to primary (192.168.168.31)
- [ ] Monitor 1 hour - no issues
- [ ] Deploy to replica (192.168.168.42)
- [ ] Full end-to-end validation
- [ ] Update Prometheus alerts
- [ ] Document final state

### Post-Deployment
- [ ] Monitor resource usage for 1 week
- [ ] Collect performance metrics
- [ ] Update documentation
- [ ] Plan Q3 Kubernetes migration

---

## Expected Outcomes

### Compliance Improvement
- **Before**: Resource Limits 60/100
- **After**: Resource Limits 90/100
- **Improvement**: +30 points

### Production Benefits
- Reduced resource contention
- Better service isolation
- Predictable performance
- Easier debugging

### Kubernetes Readiness
- All services have documented resource needs
- Performance baselines established
- Scaling strategy defined
- Monitoring ready

---

## Effort Estimation

| Phase | Task | Hours |
|---|---|---|
| 1 | Resource profiling | 2-3 |
| 2 | Configuration updates | 3-4 |
| 3 | Testing & validation | 2-3 |
| 4 | Monitoring setup | 1-2 |
| Total | | **8-12 hours** |

**Timeline**: Can be completed in 2-3 days (1 full work day focused)

---

## Next Steps

1. **Approve resource sizing** (30 min)
2. **Begin Phase 1: Profiling** (2-3 hours)
   - Run profiling script
   - Collect baseline metrics
3. **Prepare staging environment** (1-2 hours)
4. **Update configurations** (3-4 hours)
5. **Execute testing** (2-3 hours)
6. **Deploy to production** (1-2 hours)
7. **Monitor and adjust** (1 week ongoing)

---

**Priority**: 🟠 HIGH - Enables Q3 Kubernetes migration  
**Status**: 📋 Ready for implementation  
**Estimated Completion**: End of this week  
**Compliance Impact**: Phase 3 → Resource Limits 90/100  

---

Next session: Execute Resource Limits implementation (8-12 hours work)
