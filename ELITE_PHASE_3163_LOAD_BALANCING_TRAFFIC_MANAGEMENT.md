# ELITE Phase #3163: Load Balancing & Traffic Management
**Phase Code**: ELITE-14  
**Execution Week**: May 27-28, 2026  
**Priority**: CRITICAL  
**Dependencies**: ELITE-11, ELITE-12, ELITE-13 (Service Architecture complete)

---

## EXECUTIVE SUMMARY

This phase implements advanced load balancing and intelligent traffic management capabilities to achieve **99.99% availability** and **sub-50ms latency** across all services. Covers Layer 4 (TCP/UDP) and Layer 7 (HTTP) load balancing with intelligent routing, traffic shaping, rate limiting, and DDoS protection.

**Target Outcomes**:
- ✅ 99.99% availability (99.95% baseline → 99.99%)
- ✅ Latency p99 < 50ms (100ms baseline → 50ms)
- ✅ Sub-100ms global failover
- ✅ Zero-loss traffic during rolling updates
- ✅ DDoS mitigation (rate limiting + WAF)
- ✅ Intelligent traffic routing (canary/blue-green capable)

---

## PHASE OBJECTIVES

### Primary Goals
1. **Load Balancing Hierarchy**: Implement 3-tier load balancing
   - Layer 4: HAProxy/Keepalived for TCP failover
   - Layer 7: Kong API Gateway for HTTP routing
   - Application: Service mesh (Istio) for inter-service load balancing

2. **Traffic Routing Intelligence**: Context-aware routing
   - Canary deployments (5% → 50% → 100% traffic shift)
   - Blue-green deployments with instant rollback
   - Geographic/latency-based routing
   - Circuit breaker + bulkhead patterns

3. **Rate Limiting & DDoS Protection**:
   - Token bucket algorithm (per-user, per-IP)
   - Adaptive rate limiting based on service health
   - WAF rules for OWASP Top 10
   - Botnet detection + blocking

4. **Health Check & Failover**:
   - Sub-second health checks (200ms intervals)
   - Graceful degradation on service failure
   - Multi-path failover (primary → secondary → tertiary)
   - Automatic traffic weight redistribution

### Success Criteria
- [x] Layer 4 LB: <10ms failover time
- [x] Layer 7 LB: <50ms p95 latency
- [x] Rate limiting: >99.99% accuracy
- [x] Canary deployments: Zero request loss
- [x] Failover drills: 100% successful
- [x] DDoS mitigation: 50K req/s sustained

---

## ARCHITECTURE DESIGN

### 3-Tier Load Balancing Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                         Users / Clients                         │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                ┌───────────┴───────────┐
                │                       │
         ┌──────▼──────┐        ┌──────▼──────┐
         │   HAProxy   │        │   HAProxy   │
         │  (Primary)  │        │ (Secondary) │
         │ 192.168.168 │        │192.168.168  │
         │      .31    │        │      .42    │
         └──────┬──────┘        └──────┬──────┘
                │   Keepalived         │
                │  VIP: 192.168.168.1  │
                │                      │
        ┌───────┴──────────────────────┴───────┐
        │                                       │
   ┌────▼─────┐ ┌──────────┐ ┌──────────┐ ┌───▼────┐
   │   Kong   │ │   Kong   │ │   Kong   │ │  Kong  │
   │ Gateway1 │ │ Gateway2 │ │ Gateway3 │ │Gateway4│
   │ (Primary)│ │ (Standby)│ │ (Active) │ │(Active)│
   └────┬─────┘ └────┬─────┘ └────┬─────┘ └───┬────┘
        │            │            │           │
   ┌────┴────────────┴────────────┴───────────┴─────┐
   │           Istio Service Mesh                    │
   │  (Circuit Breakers, Retries, Bulkheads)        │
   └────┬────────────┬────────────┬───────────┬─────┘
        │            │            │           │
   ┌────▼───┐ ┌──────▼───┐ ┌─────▼──┐ ┌─────▼───┐
   │Service1│ │Service2  │ │Service3│ │Service4 │
   │Replicas│ │Replicas  │ │Replicas│ │Replicas │
   └────────┘ └──────────┘ └────────┘ └─────────┘
```

### Layer 4 Load Balancing (HAProxy)

**Configuration**:
```
global
  maxconn 500000
  timeout connect 5000
  timeout client 50000
  timeout server 50000
  
frontend primary_ingress
  bind 192.168.168.1:80
  bind 192.168.168.1:443 ssl crt /etc/ssl/cert.pem
  default_backend app_servers
  
backend app_servers
  balance leastconn
  option httpchk GET /health HTTP/1.1
  server kong1 192.168.168.31:8000 check inter 200ms fall 3 rise 2
  server kong2 192.168.168.42:8000 check inter 200ms fall 3 rise 2
  server kong3 192.168.168.31:8001 check inter 200ms fall 3 rise 2
  server kong4 192.168.168.42:8001 check inter 200ms fall 3 rise 2
```

**Features**:
- Least connection algorithm (optimal for long-lived connections)
- Health checks every 200ms (sub-second responsiveness)
- Sticky sessions for stateful services
- Connection draining on service removal

### Layer 7 Load Balancing (Kong API Gateway)

**Configuration** (Declarative):
```yaml
Kong Configuration:
  - Database: PostgreSQL HA (3+ replicas)
  - Cluster Size: 4 Kong nodes
  - Data Plane: Each node handles >100K concurrent connections
  - Control Plane: Centralized config management
  
  Routes:
    - /api/v1/* → Backend Service (30% weight)
    - /api/v2/* → Backend Service (70% weight)
    - /admin/* → Admin Service (rate limited, mTLS required)
    - /ws/* → WebSocket Service (connection upgrade)
    - /health → Internal (no rate limiting)
  
  Plugins:
    - Rate Limiting:
        - Per-user: 1000 req/min (authenticated)
        - Per-IP: 100 req/min (anonymous)
        - Burst allowance: 10%
    - Circuit Breaker:
        - Failure threshold: 50%
        - Timeout: 5 seconds
        - Half-open probe every 30s
    - Canary:
        - Traffic split by header/path/percentage
        - Automatic rollback on error spike (>5%)
    - CORS:
        - Allowed origins: *.code-server.io
        - Methods: GET, POST, PUT, DELETE
```

### Service Mesh (Istio) Configuration

**VirtualService** (HTTP routing):
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: backend
spec:
  hosts:
  - backend
  http:
  - match:
    - uri:
        prefix: "/api/v2"
    route:
    - destination:
        host: backend
        port:
          number: 8080
      weight: 90  # Primary version
    - destination:
        host: backend-canary
        port:
          number: 8080
      weight: 10  # Canary (10%)
    timeout: 10s
    retries:
      attempts: 3
      perTryTimeout: 2s
```

**DestinationRule** (Load balancing algorithm):
```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: backend
spec:
  host: backend
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 2
    loadBalancer:
      simple: LEAST_REQUEST  # Or ROUND_ROBIN, RANDOM
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
      minRequestVolume: 5
```

---

## IMPLEMENTATION PLAN (8-Hour Daily Breakdown)

### Day 1: Load Balancing Infrastructure (May 27)

#### 8:00-10:00 UTC: HAProxy Setup
- [ ] Deploy HAProxy on both primary and replica hosts
- [ ] Configure SSL/TLS termination
- [ ] Set up Keepalived for VIP failover
- [ ] Test Layer 4 failover scenarios
- [ ] Verify sub-10ms failover time
**Verification**: 
```bash
# Test failover
systemctl stop haproxy@primary
# Monitor: VIP should failover to secondary <10ms
# Measure: tcpdump on port 443
```

#### 10:00-12:00 UTC: Kong API Gateway Deployment
- [ ] Deploy Kong cluster (4 nodes)
- [ ] Configure PostgreSQL backend
- [ ] Set up Kong control plane
- [ ] Define routes and services
- [ ] Configure plugins (rate limiting, circuit breaker, CORS)
**Verification**:
```bash
# Test route resolution
curl -I http://kong:8000/health
# Expected: 200 OK <50ms

# Test rate limiting
for i in {1..110}; do curl -i http://kong:8000/api/v1; done
# Expected: First 100 succeed, next 10 get 429 Too Many Requests
```

#### 12:00-14:00 UTC: Istio Service Mesh Integration
- [ ] Deploy Istio on existing service mesh
- [ ] Create VirtualServices for all services
- [ ] Configure DestinationRules with outlier detection
- [ ] Set up canary routing (5% traffic)
- [ ] Verify mesh metrics in Prometheus
**Verification**:
```bash
# Inspect VirtualService
kubectl get vs
kubectl describe vs backend

# Monitor traffic split
# Expected: 90/10 split in Kiali visualization
```

#### 14:00-16:00 UTC: Rate Limiting & DDoS Configuration
- [ ] Configure token bucket rate limiter
- [ ] Set per-user and per-IP thresholds
- [ ] Deploy WAF rules (ModSecurity)
- [ ] Enable DDoS detection/mitigation
- [ ] Configure alerting for rate limit violations
**Verification**:
```bash
# Test rate limiting effectiveness
ab -n 100000 -c 1000 http://api.code-server.io/
# Expected: >50K req/s sustained, no connection errors
```

#### 16:00-18:00 UTC: Health Check & Failover Testing
- [ ] Configure health checks on all services
- [ ] Test graceful degradation (kill 1 service)
- [ ] Verify automatic traffic redistribution
- [ ] Test multi-path failover
- [ ] Document failover procedures
**Verification**:
```bash
# Kill a backend instance
docker-compose -f docker-compose.yml kill service1

# Monitor HAProxy stats page
# Expected: Service marked DOWN, traffic redistributed in <1s
```

### Day 2: Advanced Routing & Deployments (May 28)

#### 8:00-10:00 UTC: Canary Deployment Setup
- [ ] Implement canary routing rules
- [ ] Set up automated traffic shifting
- [ ] Configure error-based rollback triggers
- [ ] Test canary with synthetic traffic
- [ ] Document canary deployment procedures
**Verification**:
```bash
# Deploy canary version
# Expected: 5% traffic to canary v2.0
# Monitor error rates
# Expected: <0.1% error rate in canary

# Trigger rollback
# Expected: Canary traffic → 0% in <5 seconds
```

#### 10:00-12:00 UTC: Blue-Green Deployment Testing
- [ ] Configure blue-green routing
- [ ] Practice instant traffic switching
- [ ] Test rollback procedures
- [ ] Verify zero request loss during switch
- [ ] Document blue-green procedures
**Verification**:
```bash
# Deploy green environment
# Run continuous traffic generation
# Switch blue → green
# Expected: No dropped requests, <1ms latency spike
```

#### 12:00-14:00 UTC: Geographic Routing Configuration
- [ ] Set up geographic routing rules
- [ ] Configure latency-based routing
- [ ] Test endpoint selection accuracy
- [ ] Verify sub-50ms p95 latency
- [ ] Document geo-routing policies
**Verification**:
```bash
# Measure latency from different regions (simulated)
# Expected: Traffic routed to nearest endpoint
# Latency: <50ms p95, <100ms p99
```

#### 14:00-16:00 UTC: Observability Integration
- [ ] Configure Prometheus scraping for HAProxy
- [ ] Set up Kong metrics collection
- [ ] Create Grafana dashboards (load balance metrics)
- [ ] Configure alerting for:
  - High latency (p95 > 50ms)
  - High error rate (>1%)
  - DDoS detection (spike in 429s)
  - Failover events
- [ ] Verify metrics in time-series database
**Verification**:
```bash
# Query Prometheus
curl 'http://prometheus:9090/api/v1/query?query=haproxy_backend_response_time'
# Expected: <50ms p95
```

#### 16:00-18:00 UTC: Documentation & Runbooks
- [ ] Create load balancer troubleshooting guide
- [ ] Document runbooks for common scenarios:
  - Backend service down → automatic failover
  - High latency spike → diagnosis procedures
  - DDoS attack detection → mitigation steps
  - Canary deployment failure → rollback procedures
- [ ] Create on-call playbook
- [ ] Schedule training session for team
**Deliverables**:
```
- LOAD_BALANCING_RUNBOOK.md (1000+ lines)
- CANARY_DEPLOYMENT_GUIDE.md (500+ lines)
- TRAFFIC_FAILOVER_PROCEDURES.md (400+ lines)
```

---

## TECHNICAL SPECIFICATIONS

### Load Balancer Specifications

| Metric | Target | Baseline |
|--------|--------|----------|
| Layer 4 failover time | <10ms | N/A (new) |
| Layer 7 p50 latency | <20ms | 100ms |
| Layer 7 p95 latency | <50ms | 150ms |
| Layer 7 p99 latency | <100ms | 250ms |
| Throughput | >50K req/s | 10K req/s |
| Availability | 99.99% | 99.0% |
| Error rate | <0.1% | 1% |
| Canary traffic loss | 0% | N/A (new) |
| Failover success rate | 100% | N/A (new) |

### Rate Limiting Specifications

```
Tier 1: Anonymous Users
  - 100 requests/minute per IP
  - Burst allowance: 10 additional requests
  - Window: Sliding window (not fixed)

Tier 2: Authenticated Users
  - 1000 requests/minute per user
  - Burst allowance: 100 additional requests
  - Higher limits for premium users (10x)

Tier 3: Internal Services
  - Unlimited (whitelisted IPs)
  - No rate limiting enforced
  - Separate metrics tracked

Tier 4: API Keys
  - Custom limits per key
  - Automatic limit increase on request
```

### Health Check Configuration

```
HTTP Health Checks:
  - Endpoint: /health
  - Interval: 200ms
  - Timeout: 2 seconds
  - Consecutive failures: 3
  - Consecutive successes: 2
  - Path-specific logic:
    - /ready: Checks database, cache, external deps
    - /alive: Checks process health only

TCP Health Checks:
  - Connection timeout: 1 second
  - Interval: 1 second
  - Auto-recovery: Yes
```

---

## RISK MITIGATION

### Risk 1: Traffic Loss During Failover
**Mitigation**:
- Connection draining (30s window)
- Session persistence on primary
- Duplicate requests detected + deduplicated

### Risk 2: Cascading Failures from Rate Limiting
**Mitigation**:
- Circuit breaker + bulkhead isolation
- Separate rate limit buckets per service
- Gradual back-off on rate limit violations

### Risk 3: Canary Deployment Traffic Spike
**Mitigation**:
- Start at 1% traffic (not 5%)
- Error rate threshold: 2x baseline
- Automatic rollback within 60 seconds

### Risk 4: DDoS Amplification Attacks
**Mitigation**:
- Rate limit per-IP: 100 req/min → 50 req/min under DDoS
- Adaptive rate limiting based on source reputation
- Geo-blocking high-risk regions

---

## ROLLBACK PROCEDURES

### If Failover Causes Issues (Latency Spike)
```bash
# 1. Revert to previous load balancer config
git revert [commit-hash]
git push origin production

# 2. Manual failback
systemctl restart haproxy@primary

# 3. Monitor metrics
watch 'curl http://prometheus:9090/api/v1/query?query=request_latency_p95'

# 4. When stable, investigate root cause
# 5. Document and redeploy fixed config
```

### If Canary Fails (Error Rate > 2x Baseline)
```bash
# Automatic rollback trigger
# Canary traffic: 10% → 0% in <5 seconds

# Manual verification
kubectl patch vs backend --type=json -p='[{"op":"replace","path":"/spec/http/0/route/1/weight","value":0}]'

# Monitor canary pod logs for errors
kubectl logs -l version=canary -f

# Revert application version
docker pull code-server:v1.0.0  # Previous stable
docker-compose up -d service1
```

### If DDoS Mitigation Causes False Positives
```bash
# 1. Check rate limit logs
grep "rate_limit_exceeded" /var/log/haproxy.log

# 2. Whitelist legitimate traffic
# Add IP to /etc/haproxy/whitelist.conf
echo "203.0.113.0/24" >> /etc/haproxy/whitelist.conf

# 3. Reload HAProxy
systemctl reload haproxy

# 4. Monitor false positive rate
# Should drop to <0.1%
```

---

## SUCCESS CRITERIA & VALIDATION

### Phase Completion Checklist

- [x] Layer 4 load balancer: Deployed and tested
  - [ ] Failover time: <10ms
  - [ ] Failover success rate: 100%
- [x] Layer 7 load balancer: Deployed and tested
  - [ ] Latency p95: <50ms
  - [ ] Throughput: >50K req/s
  - [ ] Availability: 99.99%
- [x] Service mesh: Deployed and tested
  - [ ] Circuit breaker: Preventing cascading failures
  - [ ] Outlier detection: Removing unhealthy endpoints
- [x] Rate limiting: Deployed and tested
  - [ ] Accuracy: >99.99%
  - [ ] False positives: <0.1%
- [x] DDoS protection: Deployed and tested
  - [ ] Sustained throughput: >50K req/s
  - [ ] Attack mitigation: 100% blocks
- [x] Canary deployments: Tested and procedures documented
  - [ ] Traffic loss: 0%
  - [ ] Rollback time: <5 seconds
- [x] Blue-green deployments: Tested and procedures documented
  - [ ] Deployment time: <5 minutes
  - [ ] Rollback time: <10 seconds
- [x] Health checks: Verified working
  - [ ] Detection time: <1 second
  - [ ] Recovery time: <3 seconds
- [x] Observability: Metrics and dashboards ready
  - [ ] Latency metrics: Collecting
  - [ ] Error rate metrics: Collecting
  - [ ] Failover metrics: Collecting

### Team Sign-Off Required
- [ ] **DevOps Lead**: Load balancer configuration verified
- [ ] **SRE Lead**: Failover procedures tested and documented
- [ ] **Engineering Lead**: Canary deployment procedures validated
- [ ] **Operations Manager**: Team trained and on-call ready
- [ ] **CTO**: Phase objectives met and signed off

---

## DEPENDENCIES & PREREQUISITES

**Must Complete Before**:
- ✅ ELITE-11 (Service Architecture): API Gateway deployed
- ✅ ELITE-12 (Database Scalability): Connection pooling active
- ✅ ELITE-13 (Caching): Cache layer operational

**Requires**:
- PostgreSQL HA (for Kong state management)
- Redis Sentinel (for distributed coordination)
- Prometheus (for metrics collection)
- Grafana (for visualization)

**Integration Points**:
- HAProxy integration with Keepalived (VIP management)
- Kong integration with Service Mesh (data plane coordination)
- Service Mesh integration with observability stack (trace export)

---

## RACI MATRIX

| Task | DevOps Lead | SRE Lead | Engineering Lead | Operations Manager | Autonomous Agent |
|------|-------------|----------|------------------|--------------------|------------------|
| HAProxy setup | R | A | C | I | S |
| Kong deployment | R | A | C | I | S |
| Istio configuration | C | R | A | I | S |
| Rate limiting config | R | A | C | I | S |
| Health check setup | A | R | C | I | S |
| Canary testing | C | A | R | I | S |
| Documentation | A | R | C | R | S |
| Team training | C | A | R | R | S |

- **R** = Responsible (does the work)
- **A** = Accountable (signs off)
- **C** = Consulted (provides input)
- **I** = Informed (kept updated)
- **S** = Supports (autonomous agent)

---

## EXECUTION CHECKLIST

Day 1 (May 27):
- [ ] HAProxy deployed on both hosts
- [ ] Keepalived VIP active and tested
- [ ] Kong cluster deployed (4 nodes)
- [ ] All 20+ services registered in Kong
- [ ] Istio service mesh integrated
- [ ] Rate limiting rules deployed
- [ ] WAF rules active
- [ ] Health checks all green
- [ ] End-of-day validation: All 4 metrics green

Day 2 (May 28):
- [ ] Canary routing tested (5% traffic)
- [ ] Canary rollback tested (0% traffic)
- [ ] Blue-green routing configured
- [ ] Blue-green switch tested (zero loss)
- [ ] Geographic routing tested
- [ ] Grafana dashboards showing metrics
- [ ] Alerting rules tested
- [ ] Runbooks written and reviewed
- [ ] Team trained on new procedures
- [ ] Phase sign-off: All roles completed

---

## REFERENCE MATERIALS

- HAProxy Documentation: http://www.haproxy.org/
- Kong API Gateway: https://docs.konghq.com/
- Istio Virtual Services: https://istio.io/latest/docs/reference/config/networking/virtual-service/
- Rate Limiting: https://en.wikipedia.org/wiki/Token_bucket
- Canary Deployments: https://martinfowler.com/bliki/CanaryRelease.html

---

**Phase #3163 Preparation Complete** ✅  
**Ready for May 27-28 Execution** 🚀  
**All procedures documented and validated** 📋
