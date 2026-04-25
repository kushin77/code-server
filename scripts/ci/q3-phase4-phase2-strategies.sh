#!/bin/bash
################################################################################
# Q3 Phase 4: Phase 2 Deployment Strategies & Load Balancing
# @governance IaC, immutable, idempotent, environment-driven
# @purpose Define deployment strategies for stateless services migration
# @phase Q3 Phase 4 - Phase 2 (May 13-26, 2026)
# @date $(date '+%Y-%m-%d %H:%M:%S')
################################################################################

set -euo pipefail
IFS=$'\n\t'

# Source environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

# Configuration (SSOT via environment)
OUTPUT_DIR="${PROJECT_ROOT}/artifacts/q3-phase4-phase2"
TIMESTAMP=$(date '+%Y-%m-%d')
REPORT_FILE="${OUTPUT_DIR}/PHASE2-DEPLOYMENT-STRATEGIES-${TIMESTAMP}.md"

mkdir -p "${OUTPUT_DIR}"

################################################################################
# Report Generation
################################################################################

cat > "${REPORT_FILE}" <<'EOF'
# Q3 Phase 4: Phase 2 Deployment Strategies & Load Balancing
## Stateless Services Migration (May 13-26, 2026)

**Date**: $(date '+%Y-%m-%d %H:%M:%S')  
**Duration**: May 13-26, 2026 (2 weeks, 30-40 hours)  
**Status**: READY FOR PLANNING  
**Team**: 2 Platform Engineers, QA Lead  
**Scope**: 8 stateless microservices (auth-server, api-gateway, control-plane, etc.)  

---

## Executive Summary

Phase 2 focuses on **stateless services migration from Docker Compose to Kubernetes**. This document defines:

1. **Deployment Strategies** (blue-green, canary, rolling update)
2. **Load Balancing Architecture** (VRRP 192.168.168.100, Ingress routing)
3. **Traffic Management** (traffic shifting, health checks, gradual rollout)
4. **Validation Procedures** (endpoint verification, integration tests, smoke tests)
5. **Rollback Procedures** (service cutover, traffic redirect, fallback)

---

## Phase 2 Success Criteria

### Primary Objectives

| Objective | Success Criteria | Metric |
|-----------|------------------|--------|
| **Service Migration** | All 8 stateless services in K8s | 100% deployed |
| **Zero-Downtime** | < 1 second traffic interruption | p99 < 1s |
| **Health Checks** | All services passing readiness/liveness | 100% Green |
| **Performance** | p99 latency < 100ms maintained | < 100ms |
| **Traffic Continuity** | No dropped requests during cutover | 0 errors |
| **Monitoring** | All services metrics flowing | 100% coverage |
| **Documentation** | Phase 3 runbook ready | Complete |

### Success Metrics

```
Availability During Cutover: 99.95%+
Request Success Rate:        100% (0 drops)
Latency p99:                 < 100ms
Error Rate:                  < 0.1%
Pod Ready Rate:              100%
Deployment Time per Service: < 5 minutes
Rollback Capability:         < 2 minutes
```

---

## Stateless Services in Scope (8 services)

| Service | Purpose | Replicas | Strategy |
|---------|---------|----------|----------|
| auth-server | Authentication | 3 | Canary |
| api-gateway | Request routing | 3 | Blue-green |
| control-plane | Orchestration | 3 | Rolling |
| prompt-gateway | AI routing | 2 | Canary |
| memory-engine | Memory service | 2 | Canary |
| execution-scheduler | Job scheduling | 2 | Rolling |
| activity-feed | Activity logging | 2 | Canary |
| event-bus | Event routing | 2 | Canary |

**Total**: 18 replicas across 8 services (3 per high-traffic service, 2 per standard)

---

## Deployment Strategies

### Strategy 1: Blue-Green Deployment

**Best For**: High-traffic services (auth-server, api-gateway)  
**Risk Level**: Low  
**Rollback**: Instant (traffic switch)  

**How It Works**:

```
PHASE 1: PREPARE GREEN (New K8s deployment)
  1. Deploy new service version to K8s in "green" state (no traffic)
  2. Run integration tests against green deployment
  3. Wait for readiness probes to pass
  4. Verify metrics flowing to Prometheus

PHASE 2: VALIDATE GREEN
  1. Run smoke tests against green (non-production traffic)
  2. Monitor latency, error rate, CPU/memory
  3. Verify service-to-service communication
  4. Check database connections (no stale connections)

PHASE 3: SWITCH TRAFFIC
  1. Update Ingress service selector: blue → green
  2. Monitor request distribution (should see 100% to green)
  3. Verify latency and error rates
  4. Hold for 5 minutes (catch any delayed failures)

PHASE 4: CLEANUP BLUE (After 15 min stability)
  1. If green stable: scale down blue deployment to 0
  2. Keep docker-compose services running (emergency cutback)
  3. Document cutover timestamp
```

**Rollback Procedure** (< 30 seconds):
```bash
# If critical issue detected during green validation:
# 1. Switch traffic back to blue (Ingress update)
kubectl patch service api-gateway -p '{"spec":{"selector":{"version":"blue"}}}'

# 2. Scale down green to 0
kubectl scale deployment api-gateway-green --replicas=0 -n production

# 3. Monitor metrics return to normal
kubectl port-forward svc/api-gateway 3100:80 &
curl http://localhost:3100/health
```

**Traffic Switch Command**:
```bash
# Update Ingress to route to green deployment
kubectl patch ingress code-server-enterprise \
  -p '{"spec":{"rules":[{"http":{"paths":[{"backend":{"serviceName":"api-gateway-green"}}]}}]}}'

# Verify traffic shift (check logs)
kubectl logs deployment/api-gateway-green -n production -f --tail=50 | grep "GET /api"
```

---

### Strategy 2: Canary Deployment

**Best For**: Standard services (prompt-gateway, memory-engine, activity-feed)  
**Risk Level**: Very Low  
**Rollback**: Gradual (traffic shift back)  

**How It Works**:

```
PHASE 1: DEPLOY CANARY (5% traffic)
  1. Deploy new version alongside existing service
  2. Ingress routes 5% of requests to canary
  3. Monitor canary metrics (error rate, latency)
  4. Expected: no increase in error rate or latency

PHASE 2: RAMP CANARY (25% traffic)
  1. After 5 minutes of green metrics: shift to 25% traffic
  2. Continue monitoring
  3. Check for any degradation

PHASE 3: FULL CANARY (50% traffic)
  1. After 5 more minutes: shift to 50%
  2. Equal split between old and new
  3. Monitor latency p50/p95/p99

PHASE 4: FULL MIGRATION (100% traffic)
  1. After 5 more minutes: route all traffic to canary
  2. Keep old deployment running for 30 minutes
  3. If all metrics green: proceed to next service

PHASE 5: CLEANUP
  1. Scale down old deployment
  2. Delete canary label (service now "stable")
  3. Document success metrics
```

**Traffic Distribution Configuration**:
```bash
# Using Istio VirtualService for canary (if Istio installed)
kubectl apply -f - <<'YAML'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: prompt-gateway
spec:
  hosts:
  - prompt-gateway
  http:
  - match:
    - headers:
        user-agent:
          regex: ".*canary.*"
    route:
    - destination:
        host: prompt-gateway
        subset: v2
      weight: 100
  - route:
    - destination:
        host: prompt-gateway
        subset: v1
      weight: 95
    - destination:
        host: prompt-gateway
        subset: v2
      weight: 5
YAML
```

**Monitoring During Canary**:
```bash
# Compare metrics between old (v1) and new (v2)
kubectl exec -it prometheus-0 -n monitoring -- \
  promtool query instant \
  'rate(http_request_duration_seconds_bucket{job="prompt-gateway",version="v2"}[5m])'

# Alert thresholds during canary:
# - Error rate v2 > error rate v1 + 0.5% → ROLLBACK
# - Latency p99 v2 > 150ms → INVESTIGATE
# - Memory increase > 20% → INVESTIGATE
```

---

### Strategy 3: Rolling Update

**Best For**: Fault-tolerant services (execution-scheduler, event-bus)  
**Risk Level**: Medium  
**Rollback**: Full rollback (recreate pods)  

**How It Works**:

```
PHASE 1: START ROLLING
  1. Set maxSurge=1, maxUnavailable=0 (one extra pod, zero down)
  2. Kubernetes terminates 1 old pod, starts 1 new pod
  3. New pod passes readiness probe → traffic routed to it
  4. Repeat until all replicas updated

PHASE 2: MONITOR DURING ROLLING
  1. Watch pod startup logs
  2. Monitor request latency (should stay consistent)
  3. Verify no connection errors

PHASE 3: COMPLETION
  1. All pods running new version
  2. Keep old ReplicaSet (for quick rollback)
  3. Continue monitoring for 15 minutes
```

**Rolling Update Configuration**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: execution-scheduler
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1         # 1 extra pod allowed
      maxUnavailable: 0   # 0 pods can be down
  template:
    spec:
      containers:
      - name: scheduler
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
```

**Rollback Command** (if issues detected):
```bash
# Rollback to previous ReplicaSet
kubectl rollout undo deployment/execution-scheduler

# Monitor rollback
kubectl rollout status deployment/execution-scheduler --watch
```

---

## Load Balancing Architecture

### Ingress Controller Configuration

**Virtual IP**: 192.168.168.100 (VRRP)  
**External Port**: 443 (TLS)  
**Internal Port**: 80 (HTTP)  

```bash
# Ingress rules (example for api-gateway)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-gateway-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - api.kushnir.cloud
    secretName: api-gateway-tls
  rules:
  - host: api.kushnir.cloud
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-gateway
            port:
              number: 3100
```

### Service Load Balancing

**Round-Robin** (default K8s):
- Each request goes to next pod in rotation
- Good for uniform load distribution
- Used for: auth-server, api-gateway, control-plane

**Least Connections**:
- Route to pod with fewest active connections
- Good for long-lived connections
- Used for: event-bus, activity-feed

**Session Affinity**:
- Route same client to same pod (sticky sessions)
- Used for: session-heavy services

---

## Traffic Management During Cutover

### Health Check Strategy

**Readiness Probes** (traffic eligibility):
```bash
# Endpoint: /health/ready
# Success: HTTP 200, response time < 100ms
# Failure: Remove from load balancer immediately
# Check interval: 10 seconds
# Initial delay: 5 seconds
```

**Liveness Probes** (pod restart check):
```bash
# Endpoint: /health/live
# Success: HTTP 200
# Failure: Kubernetes restarts pod
# Check interval: 30 seconds
# Initial delay: 15 seconds
```

### Request Flow During Phase 2

```
Client Request
  ↓
Ingress (192.168.168.100:443)
  ↓
TLS Termination (cert-manager)
  ↓
NGINX Service Routing (api.kushnir.cloud → api-gateway)
  ↓
Service Load Balancer (Round-robin to 3 replicas)
  ↓
Pod Selection:
  - Pod 1 (old version, blue) → 33% traffic
  - Pod 2 (new version, green) → 33% traffic
  - Pod 3 (new version, green) → 34% traffic
  ↓
Container Processing
  ↓
Response (< 100ms for p99)
```

### Gradual Traffic Shift (Canary Example)

**Time Period**: 20 minutes total

```
T+0min:   5% traffic to canary (95% to stable)
T+5min:   25% traffic to canary (75% to stable)
T+10min:  50% traffic to canary (50% to stable)
T+15min:  100% traffic to canary (0% to stable)
T+20min:  Scale down stable, mark canary as new stable
```

**Monitoring During Each Stage**:
- Latency: p99 < 100ms
- Error rate: < 0.1%
- CPU: < 50% per pod
- Memory: < 60% per pod

---

## Validation During Cutover

### Pre-Deployment Validation (Before cutover)

```bash
# 1. Helm chart validation
helm lint helm/code-server-enterprise/ --strict

# 2. Manifest validation
helm template prompt-gateway helm/code-server-enterprise/ \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml \
  --set targetService=prompt-gateway | kubeval

# 3. Integration test
./tests/integration/test-service-communication.sh

# 4. Dependency check
./scripts/ci/verify-service-dependencies.sh prompt-gateway
```

### Live Validation (During cutover)

```bash
# 1. Endpoint verification
for i in {1..10}; do
  curl -v http://prompt-gateway:3100/health
  sleep 1
done

# 2. Request latency monitoring
kubectl exec -it pod/prometheus-0 -n monitoring -- \
  promtool query range \
  'histogram_quantile(0.99, http_request_duration_seconds)' \
  5m | grep prompt-gateway

# 3. Error rate monitoring
kubectl logs deployment/prompt-gateway --since=5m | grep ERROR | wc -l

# 4. Service-to-service communication
kubectl exec -it pod/api-gateway-0 -n production -- \
  curl -v http://prompt-gateway:3100/health
```

### Post-Deployment Validation (After 15 min)

```bash
# 1. All pods running
kubectl get pods -l service=prompt-gateway

# 2. Metrics normal
kubectl top pods -l service=prompt-gateway

# 3. Logs clean (no errors)
kubectl logs -l service=prompt-gateway --since=15m | grep -i error

# 4. Integration still working
./tests/integration/test-prompt-gateway.sh

# 5. Old version data validation (if applicable)
./scripts/ci/validate-data-migration.sh prompt-gateway
```

---

## Rollback Procedures (Service-Specific)

### Blue-Green Rollback (< 30 seconds)

**Scenario**: Green deployment showing 5xx errors

```bash
# 1. Switch traffic back to blue
kubectl patch service api-gateway \
  -p '{"spec":{"selector":{"version":"blue"}}}'

# 2. Monitor metrics return to normal
kubectl top pods -l version=blue

# 3. Scale down green
kubectl scale deployment api-gateway-green --replicas=0

# 4. Investigate failure
kubectl logs deployment/api-gateway-green --all-containers=true \
  | grep ERROR | tail -20
```

### Canary Rollback (Gradual)

**Scenario**: Canary showing increased latency

```bash
# 1. Immediately shift traffic back to 0%
# (via Istio VirtualService or Ingress update)
kubectl patch virtualservice prompt-gateway \
  -p '{"spec":{"http":[{"route":[{"destination":{"subset":"v1"},"weight":100}]}]}}'

# 2. Wait 5 minutes (confirm metrics normal)
sleep 300

# 3. Investigate canary deployment
kubectl describe pod prompt-gateway-v2-xxxxx
kubectl logs prompt-gateway-v2-xxxxx

# 4. Scale down canary
kubectl scale deployment prompt-gateway-v2 --replicas=0
```

### Full Service Rollback (Complete restoration)

**Scenario**: Database schema incompatibility discovered post-cutover

```bash
# 1. Immediate traffic switch to old version
kubectl patch service auth-server \
  -p '{"spec":{"selector":{"version":"old"}}}'

# 2. Scale old deployment back up
kubectl scale deployment auth-server-old --replicas=3

# 3. Wait for old pods to be ready
kubectl wait --for=condition=Ready pods \
  -l deployment=auth-server-old --timeout=300s

# 4. Run database rollback (if needed)
kubectl exec -it postgres-0 -- pg_restore /backups/pre-phase2-backup.sql

# 5. Verify service healthy
./tests/integration/test-auth-server.sh

# 6. Post-incident: update schema migration, test locally
```

---

## Phase 2 Timeline & Execution

### Week 1 (May 13-19)

**Day 1-2 (May 13-14)**: Stateless Services Cutover Batch 1
- Services: auth-server, api-gateway (high-traffic)
- Time: 2 per day
- Strategy: Blue-green for both
- Team: 1 Platform Engineer + 1 QA Lead per service
- Duration: 2 hours per service

**Day 3-4 (May 15-16)**: Stateless Services Cutover Batch 2
- Services: control-plane, execution-scheduler
- Strategy: Rolling updates
- Duration: 1.5 hours per service

**Day 5 (May 17)**: Stateless Services Cutover Batch 3
- Services: prompt-gateway, memory-engine
- Strategy: Canary deployment
- Duration: 2 hours per service

**Day 6-7 (May 18-19)**: Stateless Services Cutover Batch 4
- Services: activity-feed, event-bus
- Strategy: Canary deployment
- Duration: 2 hours per service
- Plus: 4 hours for validation and cleanup

### Week 2 (May 20-26)

**Days 1-3 (May 20-22)**: Performance Testing & Optimization
- Load testing all 8 services in K8s
- Identify bottlenecks
- Optimize resource limits
- Update HPA (Horizontal Pod Autoscaler) policies

**Days 4-5 (May 23-24)**: Integration Testing & Hardening
- Full regression test suite
- Service-to-service integration tests
- Disaster recovery validation
- Security scanning

**Days 6-7 (May 25-26)**: Monitoring & Documentation
- Phase 2 sign-off checklist
- Phase 3 runbook preparation (stateful services)
- Team retrospective
- Go/No-Go review for Phase 3

---

## Resource Allocation (30-40 hours)

| Role | Hours | Responsibility |
|------|-------|-----------------|
| Platform Engineer #1 | 15-20 | Deployments, load testing |
| Platform Engineer #2 | 10-15 | Canary monitoring, rollbacks |
| QA Lead | 10-15 | Validation, integration tests |

**Total**: 35-50 hours over 2 weeks (4-5 engineers available)

---

## Success Checklist for Phase 2

### Pre-Execution (May 12)

- [ ] All 8 stateless services tagged and ready for migration
- [ ] Docker Compose → K8s translation validated
- [ ] Helm charts tested in staging
- [ ] Load test scenarios prepared (k6 or Apache Bench)
- [ ] Rollback procedures tested
- [ ] Monitoring dashboards created (one per service)
- [ ] Team trained on deployment strategies
- [ ] Communication plan established (daily updates, incident channel)

### During Execution

- [ ] Each service cutover completed successfully
- [ ] Zero dropped requests during traffic shift
- [ ] Health checks passing on all new services
- [ ] Metrics flowing to Prometheus
- [ ] No performance degradation observed
- [ ] Team confidence in rollback procedures verified
- [ ] Incidents (if any) resolved < 15 minutes

### Post-Execution (May 26)

- [ ] All 8 services running in K8s production
- [ ] Docker Compose services still running (fallback)
- [ ] Monitoring showing normal patterns
- [ ] Integration tests passing 100%
- [ ] Performance baseline documented
- [ ] Phase 3 readiness assessment complete
- [ ] Team retrospective completed
- [ ] Stakeholder approval for Phase 3

---

## Phase 2 → Phase 3 Transition

**Phase 3 Focus**: Stateful Services Migration (May 27-Jun 9)
- Services: PostgreSQL, Redis, Kafka/Redpanda, Elasticsearch
- Challenge: Data persistence, replication, failover
- Duration: 2 weeks, 40-50 hours
- Strategy: Streaming replication, backup validation

**Go/No-Go Criteria**:
- ✅ All stateless services stable in K8s (48+ hour baseline)
- ✅ Monitoring and alerting working correctly
- ✅ Incident response procedures tested
- ✅ Team trained on stateful service migration
- ✅ Backup and disaster recovery verified
- ✅ Database migration scripts reviewed

---

## Deployment Strategy Decision Matrix

| Service | Traffic | Replicas | Strategy | Rollback | Risk |
|---------|---------|----------|----------|----------|------|
| auth-server | High | 3 | Blue-Green | Instant | Low |
| api-gateway | High | 3 | Blue-Green | Instant | Low |
| control-plane | Medium | 3 | Rolling | Full | Medium |
| execution-scheduler | Medium | 2 | Rolling | Full | Medium |
| prompt-gateway | Medium | 2 | Canary | Gradual | Very Low |
| memory-engine | Low | 2 | Canary | Gradual | Very Low |
| activity-feed | Low | 2 | Canary | Gradual | Very Low |
| event-bus | Low | 2 | Canary | Gradual | Very Low |

---

## Conclusion

Phase 2 is **stateless services migration with zero-downtime cutover**. Using a combination of blue-green, canary, and rolling update strategies, all 8 stateless services will be migrated to Kubernetes while maintaining 99.95%+ availability.

**Key Outcomes**:
- ✅ 8 stateless services running in K8s (production)
- ✅ Zero unplanned downtime
- ✅ Performance baseline established
- ✅ Team trained on zero-downtime deployments
- ✅ Phase 3 ready to launch (May 27)

**Status**: ✅ READY FOR PHASE 2 EXECUTION (May 13)  
**Next Review**: May 26 (Go/No-Go for Phase 3)  

---

**Report Generated**: $(date '+%Y-%m-%d %H:%M:%S')  
**Phase 2 Owner**: Platform & QA Teams  
**Phase 2 Timeline**: May 13-26, 2026  
**Total Effort**: 30-40 hours, 2-3 engineers  

EOF

echo "✓ Phase 2 Deployment Strategies report generated"
echo "  Location: ${REPORT_FILE}"
echo "  Lines: $(wc -l < "${REPORT_FILE}")"
