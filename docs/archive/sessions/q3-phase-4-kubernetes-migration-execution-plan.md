# Q3 Phase 4 Kubernetes Migration - Execution Plan

**Version**: 2.0  
**Created**: April 26, 2026  
**Status**: READY FOR EXECUTION  
**Timeline**: 4-5 weeks (starting May 1, 2026)  

---

## Executive Summary

Transition from Docker Compose (Q2 foundation) to Kubernetes orchestration with Helm 3.x, Istio service mesh, and horizontal autoscaling. This document outlines the complete execution plan, timeline, resource requirements, and risk mitigation strategy.

### Success Metrics
- All 26 microservices running in managed K8s cluster
- 99.99% SLA maintained during migration
- <5 minute failover recovery (RTO)
- <15 minute RPO (recovery point objective)
- Multi-region readiness (Phase 5 prerequisite)

---

## Phase 4 Execution Timeline

### Week 1: Infrastructure & Cluster Setup (May 1-3, 2026)
**Duration**: 3 days (24-32 engineering hours)  
**Owners**: Infrastructure team, SRE  

#### Day 1: Provider Selection & Cluster Provisioning
- [ ] Select cloud provider (EKS recommended for AWS existing infrastructure)
- [ ] Create managed K8s cluster (3 nodes: 1 control-plane, 2 workers)
- [ ] Configure kubectl context and authentication
- [ ] Verify cluster health and API server responsiveness
- [ ] Set up persistent storage classes (EBS volumes, dynamic provisioning)

**Deliverables**:
```bash
# Verify cluster
kubectl cluster-info
kubectl get nodes -o wide
kubectl get storage-classes
```

#### Day 2: CNI & Service Mesh Setup
- [ ] Install Calico or Flannel CNI plugin
- [ ] Verify pod-to-pod networking
- [ ] Install Istio 1.18.0 with demo profile
- [ ] Configure Istio ingress gateway and service mesh namespace
- [ ] Deploy Prometheus and Jaeger for metrics/tracing

**Deliverables**:
```bash
# Verify CNI
kubectl get pod -n kube-system -o wide
# Verify Istio
kubectl get deployments -n istio-system
```

#### Day 3: Configuration & Prerequisites
- [ ] Create namespaces: `production`, `monitoring`, `istio-system`
- [ ] Set up RBAC policies (role-based access control)
- [ ] Configure Pod Security Policies (restricted, baseline)
- [ ] Create ConfigMaps for service configurations
- [ ] Set up Secrets for database credentials, API keys

**Deliverables**:
```bash
# Verify setup
kubectl get ns
kubectl get configmaps -n production
kubectl get secrets -n production
```

### Week 2: Helm Deployment (May 6-10, 2026)
**Duration**: 5 days (40-50 engineering hours)  
**Owners**: Platform engineering, DevOps  

#### Day 1: Stateless Services Deployment
- [ ] Deploy frontend (2-3 replicas, HPA: 2-10)
- [ ] Deploy API services (3-5 replicas, HPA: 3-20)
- [ ] Deploy reputation-engine (2 replicas, HPA: 2-10)
- [ ] Deploy activity-feed (2 replicas, HPA: 2-5)
- [ ] Verify services are responding on cluster IPs

**Helm Command**:
```bash
helm install code-server ./helm/code-server-enterprise \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml \
  -n production \
  --set=stateless_only=true
```

#### Day 2: Data Services Deployment
- [ ] Deploy PostgreSQL StatefulSet with 3 replicas
- [ ] Deploy Redis cluster mode
- [ ] Deploy Redpanda broker cluster
- [ ] Verify persistence volumes are attached
- [ ] Run database migrations

**StatefulSet Verification**:
```bash
kubectl get statefulsets -n production
kubectl get pvc -n production
kubectl exec -it postgres-0 -- psql -U postgres
```

#### Day 3: Observability Stack
- [ ] Deploy Prometheus (scrape interval: 15s)
- [ ] Deploy Loki for log aggregation
- [ ] Deploy Grafana dashboards
- [ ] Deploy AlertManager for alerting
- [ ] Configure alert routing to PagerDuty/Slack

**Monitoring Stack Verification**:
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n production svc/grafana 3000:3000
```

#### Day 4: Specialized Services
- [ ] Deploy Ollama (LLM inference)
- [ ] Deploy Qdrant (vector database)
- [ ] Deploy Temporal (workflow orchestration)
- [ ] Deploy OPA (policy engine)
- [ ] Verify specialized workload scheduling

#### Day 5: Verification & Readiness
- [ ] All services in RUNNING/READY state
- [ ] Health checks passing on all pods
- [ ] Inter-service communication verified
- [ ] Ingress routing working
- [ ] Generate readiness checklist

---

### Week 3: Data Migration & Sync (May 13-17, 2026)
**Duration**: 5 days (40-50 engineering hours)  
**Owners**: Database team, Platform engineering  

#### Day 1: Database Migration
- [ ] Backup production PostgreSQL (Docker Compose)
- [ ] Restore to Kubernetes PostgreSQL StatefulSet
- [ ] Verify data integrity (row count, checksums)
- [ ] Run migration validation tests
- [ ] Test replication from primary to standby

**Commands**:
```bash
# Backup from Docker Compose
docker-compose exec postgres-db pg_dump -U $DB_USER $DB_NAME | gzip > backup.sql.gz

# Restore to K8s
kubectl exec -it postgres-0 -- psql -U postgres < backup.sql

# Verify
kubectl exec -it postgres-0 -- psql -U postgres -c "SELECT count(*) FROM information_schema.tables;"
```

#### Day 2: Cache & Session State Migration
- [ ] Backup Redis snapshots from Docker Compose
- [ ] Restore to Kubernetes Redis cluster
- [ ] Verify TTL policies on keys
- [ ] Load-test cache hit ratio
- [ ] Monitor memory utilization

#### Day 3: Message Queue Sync
- [ ] Establish Redpanda cluster replication (Docker → K8s)
- [ ] Verify topic/partition alignment
- [ ] Test consumer group offsets
- [ ] Monitor broker health and ISR (in-sync replicas)

#### Day 4: Vector Database Migration
- [ ] Backup Qdrant collection (Docker Compose)
- [ ] Restore to Kubernetes Qdrant cluster
- [ ] Verify vector count and index status
- [ ] Run vector search accuracy tests
- [ ] Load-test query latency (target <100ms P95)

#### Day 5: Full Sync Verification
- [ ] Run parallel deployment (50% traffic → Docker, 50% → K8s)
- [ ] Monitor metrics divergence
- [ ] Test failover scenarios
- [ ] Verify no data loss during failures
- [ ] Document sync procedures

---

### Week 4: Cutover & Validation (May 20-24, 2026)
**Duration**: 5 days (30-40 engineering hours)  
**Owners**: SRE, Operations, Platform engineering  

#### Day 1: Traffic Shift (10% → K8s)
- [ ] Configure traffic split 90/10 (Docker/K8s)
- [ ] Monitor error rates, latencies, availability
- [ ] Set alert thresholds (5% error rate = automatic rollback)
- [ ] Document baseline metrics
- [ ] Prepare rollback procedures

**Istio Configuration**:
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api
spec:
  hosts:
  - api.kushnir.cloud
  http:
  - route:
    - destination:
        host: api.svc.cluster.local
      weight: 10
    - destination:
        host: docker-compose-api.external
      weight: 90
```

#### Day 2: Traffic Shift (50/50)
- [ ] Increase K8s traffic to 50%
- [ ] Monitor for any anomalies
- [ ] Load-test with 1.5x normal traffic
- [ ] Verify multi-region capability (if applicable)

#### Day 3: Traffic Shift (100% → K8s)
- [ ] Complete cutover to Kubernetes
- [ ] Monitor SLAs continuously
- [ ] Decommission Docker Compose services (keep for 48h backup)
- [ ] Update DNS to point to K8s ingress
- [ ] Run final validation tests

#### Day 4-5: Stabilization & Monitoring
- [ ] Monitor metrics for 48 hours continuously
- [ ] Respond to any production issues
- [ ] Document final operational procedures
- [ ] Create runbooks for K8s-specific tasks
- [ ] Update team documentation

---

## Detailed Infrastructure Setup

### Cluster Requirements

| Component | Spec | Quantity |
|-----------|------|----------|
| Node Type | 4 CPU, 16GB RAM | 3 |
| Storage Class | SSD (io1, 1000 IOPS) | For data services |
| Load Balancer | ALB/NLB | 1 |
| Database Subnet | Multi-AZ | 1 |
| NAT Gateway | For egress | 1-2 |

### Cost Estimation (AWS EKS)

| Component | Monthly Cost | Notes |
|-----------|-------------|-------|
| EKS Control Plane | $73 | Managed by AWS |
| EC2 Nodes (3x t3.xlarge) | $450 | Auto-scaling enabled |
| Storage (100GB EBS) | $10 | gp3 volumes |
| Load Balancer | $16 | ALB for ingress |
| Data Transfer | ~$50 | Egress charges |
| **Total** | **~$599/month** | Assuming 2TB/month egress |

### Network Architecture

```
┌─────────────────────────────────────────┐
│   AWS VPC (10.0.0.0/16)                 │
├─────────────────────────────────────────┤
│ ALB (Load Balancer)                     │
│   └─ Ingress Controller                 │
│       └─ Istio Gateway                  │
├─────────────────────────────────────────┤
│ Kubernetes Cluster                      │
│   ├─ Control Plane (EKS Managed)       │
│   ├─ Worker Nodes (3x t3.xlarge)       │
│   │   ├─ Stateless Pods (Deployments)  │
│   │   ├─ Stateful Pods (StatefulSets)  │
│   │   └─ System Pods (CNI, monitoring) │
│   └─ Storage                            │
│       ├─ EBS Volumes (PostgreSQL, Redis)
│       ├─ EFS (Shared: Ollama models)    │
│       └─ S3 (Backups, archives)        │
└─────────────────────────────────────────┘
```

---

## Helm Chart Deployment Strategy

### Values Override Priority
1. `helm install` command-line values (`--set`)
2. Environment-specific values files (`values.prod.yaml`)
3. Base values file (`values.phase4-k8s.yaml`)
4. Chart defaults

### Deployment Commands

```bash
# Deploy all services
helm install code-server ./helm/code-server-enterprise \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml \
  -f helm/code-server-enterprise/values.prod.yaml \
  -n production \
  --create-namespace \
  --wait \
  --timeout 10m

# Upgrade after changes
helm upgrade code-server ./helm/code-server-enterprise \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml \
  -n production

# Rollback if needed
helm rollback code-server 1 -n production
```

---

## Autoscaling Configuration

### HPA (Horizontal Pod Autoscaling) Policies

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: 1000
```

### Custom Metrics for Scaling

| Metric | Target | Scale Up Threshold | Scale Down Threshold |
|--------|--------|-------------------|----------------------|
| CPU | 70% | >70% for 2 min | <30% for 5 min |
| Memory | 80% | >80% for 2 min | <40% for 5 min |
| Requests/sec | 1000 req/s | >1500 for 2 min | <500 for 5 min |
| Queue Depth | 1000 items | >2000 for 2 min | <500 for 5 min |

---

## Service Mesh (Istio) Configuration

### mTLS Policy (Zero-Trust)

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT  # Require mTLS on all connections
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: allow-plaintext-for-external
spec:
  selector:
    matchLabels:
      version: v1
  mtls:
    mode: PERMISSIVE  # Allow plaintext only for external APIs
```

### Traffic Management

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api
spec:
  hosts:
  - api.kushnir.cloud
  http:
  - timeout: 5s
    retries:
      attempts: 3
      perTryTimeout: 2s
    route:
    - destination:
        host: api
        port:
          number: 3000
      weight: 100
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api
spec:
  host: api
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1000
      http:
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
```

---

## Monitoring & Observability

### Metrics Collection (Prometheus)

**Scrape Targets**:
- Kubernetes API server
- Kubelet (node metrics)
- Kube-state-metrics (object state)
- Istio metrics (traffic, latency)
- Application metrics (custom)

**Retention**:
- Real-time: 15 days (1s resolution)
- Long-term: 1 year (1d resolution via Thanos)

### Key Dashboards in Grafana

1. **Kubernetes Cluster Overview**
   - Node resource usage, Pod distribution
   - Network I/O, Storage utilization
   - Cluster health score

2. **Microservices Performance**
   - Request latency (P50, P95, P99)
   - Error rates by service
   - Throughput and load distribution

3. **SLA Compliance**
   - Uptime % by service tier
   - Service dependency status
   - Alert firing status

---

## Risk Mitigation & Rollback

### Identified Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Data corruption during migration | Low | Critical | Checksums, parallel validation |
| Service degradation during cutover | Medium | High | Canary deployment, monitoring |
| Network latency increase | Low | Medium | CNI optimization, direct attach |
| Resource exhaustion | Low | High | HPA limits, quota enforcement |
| Istio mTLS connectivity issues | Low | Medium | PERMISSIVE mode fallback |

### Rollback Procedures

```bash
# Immediate rollback (minute 0-30)
# Route 100% traffic back to Docker Compose
kubectl patch vs api --type merge -p '{"spec":{"http":[{"route":[{"destination":{"host":"docker-compose"},"weight":100}]}]}}'

# Full rollback (hour 1-4)
# Decommission Kubernetes services and restore Docker Compose
docker-compose -f primary_compose_full.yml up -d

# Data rollback (hour 4+)
# Restore from latest backup snapshot
./scripts/operations/restore-from-backup.sh latest
```

---

## Success Criteria Checklist

- [ ] All 26 microservices running in K8s cluster
- [ ] Pod-to-pod networking verified (latency <5ms)
- [ ] Persistent data verified (PostgreSQL, Redis, Redpanda, Qdrant)
- [ ] Ingress routing working for all services
- [ ] mTLS enabled and functioning (all connections encrypted)
- [ ] Horizontal autoscaling tested and working
- [ ] Prometheus metrics collection at 15s interval
- [ ] Grafana dashboards populated with live data
- [ ] AlertManager routing alerts successfully
- [ ] Jaeger distributed tracing working
- [ ] Zero data loss observed during migration
- [ ] SLA metrics maintained (99.99% uptime, <100ms P95)
- [ ] Failover tested (node failure, pod crash recovery)
- [ ] Multi-region readiness verified (Phase 5 prerequisite)

---

## Next Phase (Phase 5): Global Distribution

After Phase 4 completion and 1 week of stabilization:

1. **Distributed Deployment**
   - Multi-region Kubernetes clusters (AWS regions)
   - Cross-region data replication
   - Global load balancing

2. **Edge Computing**
   - Deploy edge agents near client locations
   - Local caching for latency reduction
   - Sync with central cluster

3. **Timeline**: 3-4 weeks (estimated June 2026)

---

## Go/No-Go Decision Points

### Before Day 1 (Cluster Provisioning)
- [ ] Cloud provider account verified
- [ ] Budget approved
- [ ] Team availability confirmed
- [ ] Runbooks reviewed

### Before Week 2 (Helm Deployment)
- [ ] Cluster healthy and all nodes ready
- [ ] Storage classes functioning
- [ ] Network connectivity verified
- [ ] Backup strategy tested

### Before Week 3 (Data Migration)
- [ ] All K8s services deployed and responsive
- [ ] Helm charts validated
- [ ] Communication between services working
- [ ] Monitoring stack operational

### Before Week 4 (Cutover)
- [ ] Data migration verified (no loss)
- [ ] Parallel deployment stable
- [ ] Performance metrics baseline established
- [ ] Runbooks and procedures documented

---

**Status**: ✅ READY FOR EXECUTION  
**Estimated Start Date**: May 1, 2026  
**Estimated Completion Date**: May 24, 2026  
**Total Engineering Hours**: 150-170 hours  
**Production Downtime**: 0 hours (canary cutover)  

---

*Document Version: 2.0*  
*Last Updated: April 26, 2026*  
*Next Review: May 1, 2026 (Pre-execution)*
