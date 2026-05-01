# Phase 7+ Deployment Roadmap - Next Continuation Sessions
## Code-Server HA Platform - Continuation Planning

**Document Date**: April 29, 2026  
**Current Phase**: 6 ✅ COMPLETE  
**Next Phase**: 7 (Ready for deployment)  
**Platform Status**: Production-ready HA cluster, operations hardened

---

## Phase 7: Redis Sentinel Automatic Failover (30-45 minutes)

### Objectives
1. Deploy Redis Sentinel on both nodes
2. Configure automatic failover monitoring
3. Test failover procedures (manual trigger)
4. Verify cluster self-heals after node failure

### Prerequisites
- ✅ Both nodes have Redis running and healthy
- ✅ Network connectivity between nodes verified
- ✅ Sentinel configuration template created in Phase 6
- ✅ External networks ready

### Deployment Steps

**Step 1: Deploy Sentinel Container to Primary**
```bash
docker run -d --name code-server-redis-sentinel-1 \
  --network net-secure \
  -p 26379:26379 \
  -v /tmp/sentinel/sentinel.conf:/etc/redis/sentinel.conf \
  redis:7-alpine \
  redis-sentinel /etc/redis/sentinel.conf
```

**Step 2: Deploy Sentinel to Replica**
```bash
docker run -d --name code-server-redis-sentinel-2 \
  --network net-secure \
  -p 26379:26379 \
  -v /tmp/sentinel/sentinel.conf:/etc/redis/sentinel.conf \
  redis:7-alpine \
  redis-sentinel /etc/redis/sentinel.conf
```

**Step 3: Test Failover**
```bash
# Force primary Redis to fail
docker stop code-server-redis

# Wait 30 seconds (Sentinel detection timeout)
# Watch Sentinel logs
docker logs code-server-redis-sentinel-1 -f

# Verify replica promoted
docker exec code-server-redis-sentinel-1 redis-cli -p 26379 info

# Restore primary
docker start code-server-redis
```

### Success Criteria
- ✅ Sentinel containers running on both nodes
- ✅ Sentinel consensus achieved (quorum: 2)
- ✅ Primary failover detected within 30 seconds
- ✅ Replica promoted to master within 10 seconds
- ✅ Original primary rejoins as slave after recovery

### Estimated Time: 30-45 minutes
### Difficulty: Medium (configuration + testing)

---

## Phase 8: External Load Balancer Integration (45-60 minutes)

### Options

**Option A: HAProxy** (recommended for on-prem)
- Lightweight, easy to configure
- Health check intervals: 5-30 seconds
- Support for sticky sessions
- Failover: ~5 seconds

**Option B: Nginx** (lightweight alternative)
- Similar features to HAProxy
- Excellent performance
- Good documentation

**Option C: Cloud LB** (if moving to cloud later)
- AWS ALB, Azure LB, GCP LB
- Managed service (no ops overhead)
- Higher latency (internet-based)

### Objectives
1. Deploy HAProxy on primary node (or separate node)
2. Configure health checks for both primary/replica
3. Set up sticky sessions for client consistency
4. Test failover traffic routing

### Prerequisites
- ✅ Both nodes verified healthy
- ✅ All services accessible on individual nodes
- ✅ Network connectivity between all nodes and LB

### High-Level Steps

**Step 1: Deploy HAProxy**
```bash
# Create haproxy.cfg
cat > /tmp/haproxy.cfg << 'EOF'
global
  maxconn 1024

frontend web
  bind *:80
  default_backend servers
  
frontend web_https
  bind *:443 ssl crt /path/to/cert.pem
  default_backend servers

backend servers
  balance roundrobin
  
  server primary 192.168.168.31:80 check inter 5s rise 2 fall 2
  server replica 192.168.168.42:80 check inter 5s rise 2 fall 2

listen stats
  bind *:8404
  stats enable
  stats uri /stats
  stats refresh 30s
EOF

docker run -d --name haproxy \
  -p 80:80 -p 443:443 -p 8404:8404 \
  -v /tmp/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg \
  haproxy:2.8-alpine
```

**Step 2: Configure DNS**
```
code-server.example.com -> HAProxy IP (or primary IP)
```

**Step 3: Test Failover**
```bash
# Primary operational
curl http://code-server.example.com  # should work

# Simulate primary failure
ssh akushnir@192.168.168.31 "docker stop code-server-postgres code-server-redis ..."

# Verify traffic routes to replica
curl http://code-server.example.com  # should still work (via replica)
```

### Success Criteria
- ✅ HAProxy running and accessible
- ✅ Both backends marked "up" in stats
- ✅ Requests distributed across both nodes
- ✅ Failover to replica completes < 15 seconds
- ✅ Stats dashboard shows 0 errors

### Estimated Time: 45-60 minutes
### Difficulty: Medium (configuration, DNS setup)

---

## Phase 9: Additional AI/ML Services Deployment (30-45 minutes)

### Available Services

Based on docker-compose.complete.yml, consider deploying:

1. **memory-engine** (Memory management service)
   - Purpose: Store and retrieve contextual information
   - Port: 8001
   - Dependencies: Redis, PostgreSQL
   - Estimated CPU: 500m, Memory: 512MB

2. **reputation-engine** (Reputation tracking)
   - Purpose: Score and track service reliability
   - Port: 8002
   - Dependencies: PostgreSQL
   - Estimated CPU: 200m, Memory: 256MB

3. **execution-scheduler** (Task scheduling)
   - Purpose: Schedule and execute background tasks
   - Port: 8003
   - Dependencies: PostgreSQL, Redis
   - Estimated CPU: 300m, Memory: 512MB

4. **activity-feed** (Activity logging)
   - Purpose: Track platform activities
   - Port: 8004
   - Dependencies: PostgreSQL, Loki
   - Estimated CPU: 200m, Memory: 256MB

### Deployment

**Step 1: Verify compose file availability**
```bash
ssh akushnir@192.168.168.31 "
  cd ~/code-server-enterprise-ops && \
  docker-compose -f docker-compose.complete.yml config --services | grep -E 'memory|reputation|scheduler|activity'
"
```

**Step 2: Deploy services**
```bash
ssh akushnir@192.168.168.31 "
  cd ~/code-server-enterprise-ops && \
  docker-compose -f docker-compose.complete.yml up -d \
    memory-engine reputation-engine execution-scheduler activity-feed
"
```

**Step 3: Verify on replica**
```bash
ssh akushnir@192.168.168.42 "
  cd ~/code-server-enterprise-ops && \
  docker-compose -f docker-compose.complete.yml up -d \
    memory-engine reputation-engine execution-scheduler activity-feed
"
```

### Success Criteria
- ✅ All 4 services running on both nodes
- ✅ Health checks passing
- ✅ Services accessible on configured ports
- ✅ No errors in logs
- ✅ PostgreSQL/Redis integration verified

### Estimated Time: 30-45 minutes
### Difficulty: Low (proven deployment pattern)

### Impact
- Increases deployed services from 12 to 16 per node
- Total containers: 24 → 32 (both nodes)
- Enables memory management and task scheduling features

---

## Phase 10: Centralized Logging & Monitoring (60-90 minutes)

### Objectives
1. Deploy Elasticsearch for log storage
2. Deploy Kibana for log visualization
3. Configure Loki to forward logs to Elasticsearch
4. Create comprehensive dashboards

### Prerequisites
- ✅ Loki already running and collecting logs
- ✅ Sufficient disk space for log storage (100GB+ recommended)
- ✅ Network connectivity between nodes

### Key Components

**Elasticsearch** (Log Storage)
- Version: 8.x
- Storage: 50-100GB volumes
- CPU: 1-2 cores per node
- Memory: 2-4GB per node

**Kibana** (Visualization)
- Version: 8.x compatible with ES
- Port: 5601
- CPU: 500m
- Memory: 1GB

### Estimated Time: 60-90 minutes
### Difficulty: High (multiple services, configuration complexity)
### Impact: Full log visibility across cluster

---

## Phase 11: Distributed Tracing (45-60 minutes)

### Technology
**Jaeger** (distributed tracing system)
- Helps track requests across services
- Performance debugging
- Dependency mapping

### Components
1. Jaeger Agent (sidecar on each container)
2. Jaeger Collector (central collection)
3. Jaeger Query (UI - port 16686)

### Estimated Time: 45-60 minutes
### Difficulty: Medium
### Impact: Complete request tracing across cluster

---

## Phase 12: Auto-Scaling & Orchestration (60-120 minutes)

### Kubernetes Migration (if scaling beyond 2-3 nodes)

**When to Consider**:
- > 3 nodes
- > 50 services
- Complex scheduling requirements

**Alternative: Docker Swarm Mode**
- Simpler than Kubernetes
- Built into Docker
- Good for 3-5 node clusters

### Current Recommendation
- **Continue with Docker-Compose**: Sufficient for 2-3 nodes
- **Migrate to Kubernetes**: When > 3 nodes or enterprise requirements
- **Timeline**: Phase 12+ (6-12 months out)

---

## Continuation Session Planning

### Session 3 (Recommended Next)
- **Duration**: 45-60 minutes
- **Phases**: 7 + 8 (Sentinel + HAProxy)
- **Outcome**: Full automatic failover + external load balancing
- **Impact**: Production-grade resilience

### Session 4 (Optional, Enhancement)
- **Duration**: 30-45 minutes
- **Phases**: 9 (AI/ML services)
- **Outcome**: Extended platform capabilities
- **Impact**: Feature completeness

### Session 5+ (Future Scaling)
- **Duration**: Variable
- **Phases**: 10, 11, 12 (Logging, Tracing, Kubernetes)
- **Outcome**: Enterprise-grade operations
- **Impact**: Full observability and scaling

---

## Quick Phase Reference

| Phase | Name | Time | Difficulty | Prerequisites | Impact |
|-------|------|------|------------|---------------|--------|
| 4-5 | Cluster Deploy | 60 min | Medium | Nodes + Docker | 24 services |
| 6 | Operations | 30 min | Low | Cluster ready | Runbook + procedures |
| 7 | Redis Sentinel | 45 min | Medium | Both Redis up | Auto failover |
| 8 | Load Balancer | 60 min | Medium | Both nodes ready | External traffic routing |
| 9 | AI/ML Services | 45 min | Low | Compose file | +4 services |
| 10 | ELK Stack | 90 min | High | Loki running | Centralized logging |
| 11 | Jaeger | 60 min | Medium | Network ready | Distributed tracing |
| 12 | Kubernetes | 120 min | High | Multiple nodes | Full orchestration |

---

## Deployment Checklist for Next Session

### Before Starting Phase 7+

- [ ] Both nodes verified accessible
- [ ] All 12 core services confirmed running
- [ ] PostgreSQL replication status checked
- [ ] Network connectivity between nodes confirmed
- [ ] No active incidents or issues
- [ ] Team notified of maintenance window
- [ ] Backup taken of current state
- [ ] Runbooks reviewed and current

### During Deployment

- [ ] Monitor both nodes continuously
- [ ] Track service start times
- [ ] Verify health checks passing
- [ ] Test failover scenarios
- [ ] Document any deviations
- [ ] Capture logs for review

### After Deployment

- [ ] Verify all services healthy
- [ ] Test end-to-end functionality
- [ ] Run load tests (if applicable)
- [ ] Update documentation
- [ ] Commit changes with detailed message
- [ ] Schedule post-deployment review

---

## Contact & Notes

**For Phase 7 Deployment**:
- Estimated time: 45 minutes
- Difficulty: Medium
- Risk level: Low (Sentinel is isolated service)
- Rollback path: Remove Sentinel containers, revert to manual failover

**For Phase 8 Deployment**:
- Estimated time: 60 minutes
- Difficulty: Medium
- Risk level: Medium (external service, affects traffic routing)
- Rollback path: Remove HAProxy, route directly to primary IP

**For Questions**:
- Refer to OPERATIONS_RUNBOOK_PHASE6_ACTIVE.md
- Review git commit history for context
- Check docker-compose.complete.yml for service definitions

---

## Summary

The code-server platform is now at **Phase 6 completion** with a solid foundation:

✅ **Phases 4-5**: Cluster deployed and operational (24 containers)  
✅ **Phase 6**: Operations hardened with comprehensive runbook  
⏳ **Phase 7**: Redis Sentinel ready for deployment  
⏳ **Phase 8**: Load balancer framework ready  
⏳ **Phase 9+**: Additional services available  

**Next step**: Begin Phase 7 continuation session to deploy automatic Redis failover and external load balancing. Estimated total time for Phases 7-8: 90-120 minutes for production-grade HA.

---

**Document Version**: 1.0  
**Status**: Ready for Next Continuation  
**Last Updated**: April 29, 2026  
**Prepared By**: Autonomous Agent (Continuation Session 2)
