# Phase 4-7 Deployment: Traffic Migration Strategy

**Status:** ✅ PRODUCTION READY  
**Date:** May 1, 2026  
**Duration:** 4 weeks (Week 1-4)

---

## Executive Summary

This document defines the 4-week traffic migration strategy for transitioning from Docker HA stack (primary: 192.168.168.31, replica: 192.168.168.42) to Kubernetes (Azure AKS) infrastructure. The strategy ensures **zero-downtime cutover** with automated rollback capability at each phase.

### Key Principles

- **Gradual Traffic Shift**: Start small, expand in controlled phases
- **Continuous Monitoring**: Real-time metrics drive go/no-go decisions
- **Automatic Rollback**: Revert traffic instantly if issues detected
- **Zero Data Loss**: PostgreSQL/Redis data replicated before traffic migration
- **Team Coordination**: Clear handoff points and escalation procedures

---

## Pre-Migration Checklist

### Infrastructure Validation
- ✅ Kubernetes cluster provisioned (3 nodes, Standard_D2s_v3)
- ✅ Istio service mesh deployed (production profile)
- ✅ All 38 microservices deployed to K8s
- ✅ PostgreSQL StatefulSet with PVC configured
- ✅ Redis StatefulSet with PVC configured
- ✅ Redpanda (Kafka) cluster operational
- ✅ Persistent storage verified (test reads/writes)

### Data Sync Validation
- ✅ PostgreSQL replication verified (Docker → K8s)
- ✅ Redis RDB snapshot restored (Docker → K8s)
- ✅ Redpanda topics synchronized
- ✅ Data integrity checksums match
- ✅ Application databases ready for K8s

### Monitoring Setup
- ✅ Prometheus scraping K8s metrics
- ✅ Grafana dashboards configured (K8s services)
- ✅ Jaeger tracing enabled
- ✅ Alert rules deployed
- ✅ Slack notifications configured

### Team Readiness
- ✅ On-call schedule established
- ✅ Runbooks prepared and tested
- ✅ Rollback procedures rehearsed
- ✅ Communication channels established
- ✅ Escalation contacts documented

---

## Week 1: Canary Deployment (90% Docker → 10% K8s)

### Objective
Validate K8s infrastructure with low-risk stateless services under production traffic.

### Scope
- **Canary Services** (10% traffic):
  - API Gateway
  - Authentication Server (read-only queries)
  - Execution Scheduler (non-critical jobs)
  - Reputation Engine (background scoring)
  
- **Primary Services** (90% traffic):
  - All stateful services (PostgreSQL, Redis, Redpanda)
  - All current API Gateway replicas on Docker

### Deployment Steps

#### Day 1: Pre-Deployment Testing
```bash
# 1. Validate K8s cluster readiness
kubectl get nodes
kubectl get pods -n code-server-enterprise

# 2. Check service connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  wget -q -O- http://api-gateway:3100/health

# 3. Verify ingress routing
curl -H "Host: api.code-server.example.com" \
  http://<ingress-ip>/health
```

#### Day 1-2: Canary Configuration
```yaml
# Istio VirtualService: 90% Docker → 10% K8s
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-gateway
  namespace: code-server-enterprise
spec:
  hosts:
  - api.code-server.example.com
  http:
  - match:
    - headers:
        user-segment:
          exact: canary-testers
    route:
    - destination:
        host: api-gateway.code-server-enterprise.svc.cluster.local
        port:
          number: 3100
      weight: 100
  - route:
    - destination:
        host: docker-api-gateway.external
        port:
          number: 3100
      weight: 90
    - destination:
        host: api-gateway.code-server-enterprise.svc.cluster.local
        port:
          number: 3100
      weight: 10
```

**Apply Configuration**:
```bash
kubectl apply -f istio/traffic-migration/week1-canary.yaml
```

#### Day 3-5: Monitoring Phase
**Success Criteria**:
- ✅ Error rate on K8s services < 0.1%
- ✅ P99 latency difference < 50ms (K8s vs Docker)
- ✅ CPU/memory usage on K8s nodes stable
- ✅ No data consistency issues
- ✅ All 10% of traffic routed successfully

**Monitoring Commands**:
```bash
# Check pod metrics
kubectl top pods -n code-server-enterprise
kubectl top nodes

# View service logs
kubectl logs -n code-server-enterprise \
  -l app=api-gateway --tail=100 -f

# Check Istio metrics
kubectl exec -it -n istio-system \
  <prometheus-pod> -- \
  curl 'localhost:9090/api/v1/query?query=rate(requests_total[5m])'
```

#### Day 5-6: Decision Gate
**Go Decision**:
- All success criteria met → Proceed to Phase 2
- No anomalies in logs or metrics
- Team consensus on readiness

**No-Go Decision**:
- Revert traffic to 100% Docker
- Investigate issues (likely causes: resource limits, network policies, data sync)
- Reschedule for next week

#### Day 7: Rollback Drill
**Test Rollback Procedure** (even if Go):
```bash
# Simulate failure: scale down K8s deployments
kubectl scale deployment -n code-server-enterprise \
  api-gateway --replicas=0

# Verify traffic routed to Docker (100%)
# Monitor: Should see zero errors, all requests served by Docker

# Restore K8s deployments
kubectl scale deployment -n code-server-enterprise \
  api-gateway --replicas=3

# Verify traffic returns to 10% K8s
```

---

## Week 2: Expanded Canary (50% Docker → 50% K8s)

### Objective
Validate full stateless service tier under 50% production traffic.

### Scope
- **K8s Services** (50% traffic):
  - API Gateway (3+ replicas)
  - Authentication Server
  - Execution Scheduler
  - Reputation Engine
  - Memory Engine
  - All supporting microservices
  
- **Docker Services** (50% traffic):
  - PostgreSQL (HA primary)
  - Redis (HA primary)
  - Redpanda brokers
  - All current services

### Deployment Steps

#### Day 1: Traffic Increase
```yaml
# Istio VirtualService: 50% Docker → 50% K8s
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-gateway
  namespace: code-server-enterprise
spec:
  hosts:
  - api.code-server.example.com
  http:
  - route:
    - destination:
        host: docker-api-gateway.external
        port:
          number: 3100
      weight: 50
    - destination:
        host: api-gateway.code-server-enterprise.svc.cluster.local
        port:
          number: 3100
      weight: 50
```

**Apply Configuration**:
```bash
kubectl apply -f istio/traffic-migration/week2-expanded-canary.yaml
```

#### Days 2-6: Validation Phase
**Success Criteria**:
- ✅ Error rate (K8s + Docker combined) < 0.1%
- ✅ No service-to-service communication failures
- ✅ Database query latency stable (P99 < 100ms)
- ✅ Cache hit rate stable (>85%)
- ✅ Consistent request distribution (50/50 ±5%)
- ✅ No cascading failures between K8s and Docker services

**Extended Monitoring**:
```bash
# Check request distribution
kubectl exec -it -n istio-system <prometheus-pod> -- \
  curl 'localhost:9090/api/v1/query?query=sum by (destination) (rate(requests_total[5m]))'

# Monitor end-to-end latency
kubectl exec -it -n istio-system <jaeger-pod> -- \
  curl 'http://localhost:16686/api/traces?service=api-gateway'

# Database replication lag
kubectl exec -it -n code-server-enterprise postgres-0 -- \
  psql -c "SELECT extract(epoch FROM (now() - pg_last_xact_replay_timestamp())) as lag;"
```

#### Day 7: Decision Gate & Drill
- **Go Criteria**: All monitoring metrics within thresholds
- **Rollback Drill**: Reduce to 10% → verify → restore to 50%

---

## Week 3: Primary Cutover (10% Docker → 90% K8s)

### Objective
Prepare for total Kubernetes takeover by validating stateful service migration.

### Scope
- **K8s Services** (90% traffic):
  - All stateless microservices
  - PostgreSQL StatefulSet (data synced from Docker)
  - Redis StatefulSet (data synced from Docker)
  - Redpanda Kafka cluster (topics synced)
  
- **Docker Services** (10% traffic):
  - Old PostgreSQL primary (standby only)
  - Old Redis (read-only for comparison)
  - Old Redpanda (archive only)

### Pre-Migration Tasks

#### Data Sync Verification
```bash
# PostgreSQL: Verify replication is in sync
kubectl exec -it -n code-server-enterprise postgres-0 -- \
  pg_basebackup -v -Pv -X stream -l code-server-backup -D /tmp/backup

# Redis: Compare keys between Docker and K8s
docker exec postgres-redis-primary redis-cli --raw DBSIZE
kubectl exec -it -n code-server-enterprise redis-0 -- \
  redis-cli DBSIZE

# Redpanda: Verify all topics replicated
kubectl exec -it -n code-server-enterprise redpanda-0 -- \
  rpk topic list
```

#### Application Readiness
```bash
# Test K8s PostgreSQL connectivity
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h postgres.code-server-enterprise.svc.cluster.local -U postgres -c "\dt"

# Test K8s Redis connectivity
kubectl run -it --rm debug --image=redis:7 --restart=Never -- \
  redis-cli -h redis.code-server-enterprise.svc.cluster.local ping

# Test K8s Kafka connectivity
kubectl exec -it -n code-server-enterprise redpanda-0 -- \
  rpk topic list
```

### Deployment Steps

#### Day 1: Stateful Services Cutover
```yaml
# Istio VirtualService: Full K8s stateful services
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: postgres
  namespace: code-server-enterprise
spec:
  hosts:
  - postgres.code-server-enterprise.svc.cluster.local
  http:
  - route:
    - destination:
        host: postgres.code-server-enterprise.svc.cluster.local
        port:
          number: 5432
      weight: 90
    - destination:
        host: docker-postgres.external
        port:
          number: 5432
      weight: 10
```

#### Days 2-5: Stateful Service Validation
**Success Criteria**:
- ✅ PostgreSQL replication lag < 1 second
- ✅ Redis key eviction working correctly
- ✅ Redpanda replication factor maintained
- ✅ All application reads serving from K8s
- ✅ Write consistency maintained (ACID guarantees)

#### Day 6-7: Final Preparations
- Backup Docker PostgreSQL and Redis
- Verify all K8s PVC backups created
- Test disaster recovery procedures
- Review rollback playbooks

---

## Week 4: Full Cutover (0% Docker → 100% K8s)

### Objective
Complete migration to Kubernetes, decommission Docker infrastructure.

### Scope
- **Kubernetes Services** (100% traffic):
  - All 38 microservices
  - All stateful services
  - Complete application stack
  
- **Docker Services** (0% traffic):
  - All services scaled to 0
  - Infrastructure ready for archival

### Deployment Steps

#### Day 1: Final Cutover
```yaml
# Istio VirtualService: 100% K8s
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-gateway
  namespace: code-server-enterprise
spec:
  hosts:
  - api.code-server.example.com
  http:
  - route:
    - destination:
        host: api-gateway.code-server-enterprise.svc.cluster.local
        port:
          number: 3100
      weight: 100
```

**Apply Configuration**:
```bash
kubectl apply -f istio/traffic-migration/week4-full-cutover.yaml
```

#### Days 2-3: Validation
**Success Criteria**:
- ✅ All traffic successfully routed to K8s
- ✅ Error rate < 0.01%
- ✅ Latency P99 < 100ms
- ✅ Resource utilization optimal
- ✅ All monitoring dashboards green

#### Days 4-5: Docker Decommissioning
```bash
# Scale Docker services to 0
docker-compose -f docker-compose.enterprise.yml scale \
  api-gateway=0 \
  auth-server=0 \
  execution-scheduler=0

# Verify all Docker containers stopped
docker ps | grep code-server

# Archive Docker configuration
tar -czf archive/docker-compose-archive-$(date +%Y%m%d).tar.gz \
  docker-compose.*.yml \
  docker/configs/ \
  scripts/docker/

# Remove Docker infrastructure (optional)
docker-compose -f docker-compose.enterprise.yml down -v
```

#### Day 6-7: Finalization
- Archive Docker host configuration
- Remove Docker host from DNS
- Update documentation to reflect K8s as primary
- Conduct post-deployment retrospective

---

## Automatic Rollback Procedures

### Scenario 1: High Error Rate Detected
```bash
# If error rate exceeds 1% for 5 minutes:
kubectl patch virtualservice api-gateway \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"docker-api-gateway.external"},"weight":100}]}]}}'

# Verify rollback
kubectl logs -n code-server-enterprise deployment/api-gateway --tail=50
```

### Scenario 2: Database Inconsistency
```bash
# Check data consistency
kubectl exec -it -n code-server-enterprise postgres-0 -- \
  psql -c "SELECT count(*) FROM information_schema.tables;"

# If issues detected, fail over to Docker PostgreSQL
kubectl patch virtualservice postgres \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"docker-postgres.external"},"weight":100}]}]}}'
```

### Scenario 3: Service Outage
```bash
# Check pod status
kubectl get pods -n code-server-enterprise -o wide

# If pods failing, immediately revert
kubectl patch virtualservice <service> \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"docker-<service>.external"},"weight":100}]}]}}'

# Scale up Docker service
docker-compose -f docker-compose.enterprise.yml up -d <service>
```

---

## Monitoring Dashboard

### Real-Time Metrics
- **Request Rate**: requests/second (target: 5k-10k)
- **Error Rate**: errors/total requests (target: < 0.1%)
- **Latency P99**: microseconds (target: < 100ms)
- **Memory Usage**: % of node capacity (target: 60-75%)
- **CPU Usage**: millicores (target: 40-60%)

### Alerting Rules
```yaml
groups:
- name: migration.rules
  interval: 30s
  rules:
  - alert: HighErrorRate
    expr: rate(errors_total[5m]) > 0.01
    for: 5m
    annotations:
      summary: "Error rate exceeds 1%"
      action: "Review logs and consider rollback"
  
  - alert: HighLatency
    expr: histogram_quantile(0.99, latency_buckets) > 100
    for: 5m
    annotations:
      summary: "P99 latency exceeds 100ms"
      action: "Check resource utilization and K8s metrics"
  
  - alert: PodNotReady
    expr: kube_pod_status_ready{namespace="code-server-enterprise"} == 0
    for: 2m
    annotations:
      summary: "Pod not ready"
      action: "Investigate pod logs and events"
```

---

## Success Criteria Summary

| Metric | Week 1 | Week 2 | Week 3 | Week 4 |
|--------|--------|--------|--------|--------|
| K8s Traffic | 10% | 50% | 90% | 100% |
| Error Rate | <0.1% | <0.1% | <0.1% | <0.01% |
| P99 Latency | <150ms | <100ms | <100ms | <100ms |
| Pods Ready | 90%+ | 95%+ | 98%+ | 100% |
| Data Sync | ✅ | ✅ | ✅ | ✅ |
| Rollback Time | <5 min | <5 min | <5 min | N/A |

---

## Escalation Procedures

### Severity Levels

**Critical (P1)**: Production outage, data loss risk
- Escalate to: @infrastructure, @security
- Action: Immediate rollback to Docker
- Communication: All stakeholders via Slack #deployments

**High (P2)**: Degraded performance, errors > 1%
- Escalate to: @infrastructure, @ops
- Action: Reduce K8s traffic 50%, investigate
- Communication: Stakeholders every 15 minutes

**Medium (P3)**: Minor issues, < 1% error rate
- Escalate to: @ops team
- Action: Monitor closely, gather logs
- Communication: Standup meeting

**Low (P4)**: Warnings, informational
- Escalate to: @devops
- Action: Log issue for post-deployment review
- Communication: Async update to #deployments

---

## Post-Cutover Activities

### Immediate (Hours)
- [ ] Verify all services healthy in K8s
- [ ] Confirm no data inconsistencies
- [ ] Run integration test suite
- [ ] Notify stakeholders of successful migration

### Short-term (Days 1-7)
- [ ] Archive Docker configuration
- [ ] Update documentation (DNS, IPs, runbooks)
- [ ] Conduct lessons learned retrospective
- [ ] Plan Phase 5-7 activation

### Medium-term (Weeks 2-4)
- [ ] Optimize resource allocation
- [ ] Fine-tune auto-scaling policies
- [ ] Implement additional monitoring
- [ ] Plan HA improvements

---

## Contact & Support

**During Migration**:
- Slack: #deployments (for updates)
- War Room: TBD (if issues occur)
- On-Call: @infrastructure

**Post-Migration**:
- Documentation: `docs/kubernetes/`
- Issues: GitHub Issues with `migration` label
- Retrospective: TBD

---

*Traffic Migration Strategy - Phase 4 Deployment*  
*Created: May 1, 2026*  
*Status: ✅ READY FOR EXECUTION*
