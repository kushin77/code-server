# Phase 4: Kubernetes Migration Plan
# Comprehensive guide for migrating from Docker Compose to managed Kubernetes cluster

**Version**: 1.0  
**Date**: April 24, 2026  
**Status**: READY FOR IMPLEMENTATION  
**Epic**: P3 #1768 Phase 4 - Kubernetes Migration  

---

## Executive Summary

This document outlines the migration from Docker Compose (development/small-scale) to Kubernetes (production/enterprise-scale) for the 20+ microservices in code-server-enterprise. The migration enables:

- ✅ Automated horizontal scaling (HPA with custom metrics)
- ✅ Advanced traffic management (Istio service mesh with mTLS)
- ✅ High availability (pod disruption budgets, zero-downtime updates)
- ✅ Zero-trust security (Istio AuthorizationPolicy)
- ✅ Observability (Prometheus, Jaeger, Grafana integration)
- ✅ Self-healing (liveliness/readiness probes, auto-restart)

---

## Architecture Overview

### Current State (Docker Compose)
```
docker-compose.yml
├─ 30+ services (single-host or manual clustering)
├─ Limited autoscaling (manual restart policies only)
├─ Basic health checks (curl /health)
└─ No service mesh or mTLS
```

### Target State (Kubernetes + Istio)
```
Kubernetes Cluster (Multi-node)
├─ 20+ services as Deployments
├─ Automatic HPA scaling (CPU/memory/custom metrics)
├─ Istio service mesh with mTLS enforcement
├─ Network policies for zero-trust networking
├─ Pod Disruption Budgets for HA
├─ Prometheus/Grafana for observability
└─ Jaeger for distributed tracing
```

---

## Phase 4 Deliverables

### 1. ✅ Helm Charts (COMPLETE)
- **Location**: `helm/code-server-enterprise/`
- **Status**: Ready for deployment
- **Components**:
  - 20+ service definitions in `values.yaml`
  - Deployment templates with health checks
  - Service and Ingress resources
  - ConfigMap and Secret management
  - RBAC with ServiceAccounts
  - NetworkPolicy enforcement

### 2. ✅ Istio Service Mesh (COMPLETE)
- **VirtualService**: Traffic routing, timeouts, retries
  - `templates/istio-virtualservice.yaml`
  - Supports canary/blue-green deployments
  - 30s timeout with 3-attempt retries
  
- **DestinationRule**: Load balancing, connection pooling, circuit breaker
  - `templates/istio-destinationrule.yaml`
  - ROUND_ROBIN load balancing
  - Consistent hash (session affinity)
  - Outlier detection with ejection
  
- **PeerAuthentication**: Mutual TLS enforcement (STRICT mode)
  - `templates/istio-peerauthentication.yaml`
  - Namespace-wide mTLS enforcement
  - Per-port exceptions for databases
  
- **Gateway & Routes**: Ingress traffic management
  - `templates/istio-gateway.yaml`
  - TLS termination with SNI
  - Path-based routing for multi-domain
  - HTTP → HTTPS redirect

- **AuthorizationPolicy**: Zero-trust access control
  - `templates/istio-authorizationpolicy.yaml`
  - Default deny-all policy
  - Explicit allow rules per service
  - Principal-based RBAC

### 3. ✅ Horizontal Pod Autoscaling (COMPLETE)
- **Template**: `templates/hpa.yaml`
- **Metrics**:
  - CPU utilization (70% target)
  - Memory utilization (80% target)
  - Custom metrics via Prometheus
    - HTTP requests per second
    - Task queue depth
    - Business metrics
- **Scaling Behavior**:
  - Scale-up: Aggressive (100% per 15s)
  - Scale-down: Conservative (100% per 15s, but stabilize for 5 min)
  - Min replicas: 2 (HA default)
  - Max replicas: 8-20 (service-dependent)

### 4. ✅ Pod Disruption Budgets (COMPLETE)
- **Template**: `templates/poddisruptionbudget.yaml`
- **Purpose**: Maintain availability during rolling updates, node drains
- **Configuration**:
  - `minAvailable: 1` for most services
  - `minAvailable: 2` for critical services (api, reputation-engine)

### 5. ✅ Helm Values Configuration (COMPLETE)
- **File**: `helm/code-server-enterprise/values.yaml`
- **Sections Added**:
  - `istio`: mTLS mode, traffic policies, monitoring
  - `autoscaling`: HPA thresholds, custom metrics, per-service overrides
  - `resourceQuota`: Namespace-level resource limits
  - `networkPolicies`: Service-to-service communication rules
  - `podDisruptionBudgets`: HA configuration

---

## Migration Strategy

### Phase 4.1: Infrastructure Setup (Week 1)
**Goal**: Provision managed Kubernetes cluster and Istio

#### Step 1: Provision Kubernetes Cluster
```bash
# Target: EKS, GKE, or AKS (managed K8s service)
# Minimum 3 worker nodes (for HA)
# Node instance type: t3.large or equivalent
#   - 2 vCPU, 8GB RAM per node
# Storage: EBS/equivalent (100GB root, 200GB persistent)

# Example (AWS EKS):
eksctl create cluster \
  --name code-server-enterprise-prod \
  --region us-east-1 \
  --nodegroup-name ng-primary \
  --node-type t3.large \
  --nodes 3 \
  --nodes-min 3 \
  --nodes-max 10
```

#### Step 2: Install Istio Service Mesh
```bash
# Install Istio (latest LTS, currently v1.18+)
istioctl install --set profile=production

# Verify installation
kubectl get pods -n istio-system
kubectl logs -n istio-system deployment/istiod -f

# Enable sidecar injection for our namespace
kubectl label namespace code-server-enterprise istio-injection=enabled
```

#### Step 3: Install Prometheus & Grafana (Observability)
```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (includes Prometheus, Grafana, AlertManager)
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring-values.yaml
```

#### Step 4: Install Jaeger (Distributed Tracing)
```bash
# Install Jaeger for Istio tracing
helm install jaeger jaegertracing/jaeger \
  --namespace istio-system \
  --set elasticsearch.enabled=true \
  --set elasticsearch.replicas=3
```

### Phase 4.2: Helm Chart Deployment (Week 2)
**Goal**: Deploy all 20+ microservices to Kubernetes

#### Step 1: Create Kubernetes Namespace
```bash
kubectl create namespace code-server-enterprise
kubectl label namespace code-server-enterprise \
  governance.policy=GOV-002 \
  environment=production \
  istio-injection=enabled
```

#### Step 2: Deploy Secrets (from external secret manager)
```bash
# Store secrets in external manager (AWS Secrets Manager, HashiCorp Vault, etc.)
# OR create secrets manually:
kubectl create secret generic database-credentials \
  --from-literal=username=postgres \
  --from-literal=password=$(openssl rand -base64 24) \
  -n code-server-enterprise

kubectl create secret generic redis-credentials \
  --from-literal=password=$(openssl rand -base64 24) \
  -n code-server-enterprise

kubectl create secret generic oauth-credentials \
  --from-literal=client-id="..." \
  --from-literal=client-secret="..." \
  -n code-server-enterprise
```

#### Step 3: Deploy Helm Chart
```bash
# Add Helm repo (if using chart repository)
helm repo add code-server-enterprise https://charts.example.com
helm repo update

# Deploy chart
helm install code-server-enterprise code-server-enterprise/code-server-enterprise \
  --namespace code-server-enterprise \
  --values values-prod.yaml \
  --wait \
  --timeout 5m

# Verify deployment
kubectl get pods -n code-server-enterprise
kubectl get svc -n code-server-enterprise
kubectl get vs -n code-server-enterprise  # VirtualServices
kubectl get dr -n code-server-enterprise  # DestinationRules
```

#### Step 4: Enable Istio Sidecar Injection
```bash
# Sidecar injector should auto-inject when pods are created
# Verify sidecars are injected:
kubectl get pods -n code-server-enterprise -o jsonpath='{.items[0].spec.containers[*].name}'
# Should output: service-name istio-proxy

# If not auto-injected, manually inject:
istioctl kube-inject -f deployment.yaml | kubectl apply -f -
```

### Phase 4.3: Testing & Validation (Week 3)
**Goal**: Verify all services operational, traffic flows, scaling works

#### Step 1: Connectivity Testing
```bash
# Test pod-to-pod communication
kubectl exec -it pod/api-xyz -n code-server-enterprise -- \
  curl http://postgres:5432

# Test ingress access
curl -k https://api.example.com/health
curl -k https://ide.example.com

# Test mTLS enforcement
kubectl exec -it pod/api-xyz -n code-server-enterprise -- \
  openssl s_client -connect reputation-engine:5000 -showcerts
```

#### Step 2: Scaling & HPA Testing
```bash
# Trigger HPA scale-up by generating load
kubectl run -it --image=busybox --restart=Never load-generator -- \
  /bin/sh -c "while true; do wget -q -O- http://api:3100/api/tasks; done"

# Monitor HPA scaling
kubectl get hpa -n code-server-enterprise --watch

# Monitor pod replicas
kubectl get pods -n code-server-enterprise --watch
```

#### Step 3: Observability Validation
```bash
# Query Prometheus for metrics
# Open Grafana: https://grafana.example.com
# - View Kubernetes cluster metrics
# - View Istio traffic metrics (request rate, latency, errors)
# - View application metrics (via custom exporters)

# View Jaeger traces
# Open Jaeger: https://jaeger.example.com
# - Search for traces from api service
# - Follow request flow through multiple services
```

#### Step 4: Chaos Testing (Resilience)
```bash
# Simulate service failure (using Istio fault injection)
kubectl patch vs api -p '{"spec":{"http":[{"fault":{"abort":{"percentage":10}}}]}}'

# Kill a pod, observe automatic restart
kubectl delete pod api-xyz -n code-server-enterprise

# Observe HPA scale and re-balance

# Monitor in Grafana: error rate should spike then return to normal
```

### Phase 4.4: Production Migration (Week 4)
**Goal**: Cutover from Docker Compose to Kubernetes

#### Step 1: Final Production Readiness Checklist
```
[ ] All 20+ services deployed to K8s
[ ] Health checks passing (kubectl get pods = all Running)
[ ] Istio traffic flowing (check VirtualService and DestinationRule status)
[ ] HPA operational (at least one scale-out event observed)
[ ] mTLS enforced (PeerAuthentication = STRICT)
[ ] Monitoring dashboards active (Grafana shows data)
[ ] Distributed tracing working (Jaeger shows traces)
[ ] Load testing passed (sustained 1000 req/s, p99 latency < 200ms)
[ ] Disaster recovery tested (failover < 30s)
[ ] Team training completed (operations team certified)
[ ] Runbooks updated (procedures for K8s operations)
```

#### Step 2: Gradual Traffic Migration
```bash
# Option A: DNS switchover (safest for external traffic)
# 1. Update DNS to point to Kubernetes ingress
# 2. Monitor traffic shift (slow ramp-up via DNS TTL)
# 3. Rollback available if needed

# Option B: Blue-green deployment (safest for internal traffic)
# 1. Keep Docker Compose running as "blue"
# 2. Run K8s as "green" (parallel, separate ingress)
# 3. Test green environment fully
# 4. Switchover ingress to green
# 5. Decommission blue after stabilization period

# Option C: Canary rollout (most sophisticated)
# 1. Use Istio VirtualService weighted routing
# 2. Route 5% traffic to K8s, 95% to Docker Compose
# 3. Monitor error rates, latency
# 4. Gradually increase K8s traffic (5% → 25% → 50% → 100%)
# 5. Decommission Docker Compose once stable
```

#### Step 3: Decommission Docker Compose
```bash
# After stable on Kubernetes for 1 week:
docker-compose -f docker-compose.yml down -v
# (Keep backup: git commit final state)
```

---

## Risk Mitigation

### Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Data loss (DB migration) | CRITICAL | Backup strategy, point-in-time recovery, read replica |
| Service outage during migration | HIGH | Blue-green/canary deployment, rollback plan, chaos testing |
| Network latency increase | MEDIUM | Load test in staging, Istio optimization, network profiling |
| Knowledge gap (K8s learning curve) | MEDIUM | Team training, runbooks, practice in staging |
| Cost increase (managed K8s) | MEDIUM | Reserved instances, pod resource optimization, right-sizing |
| Istio complexity & debugging | MEDIUM | Istio troubleshooting training, Kiali dashboard, loganalysis |

---

## Success Criteria

### Go-Live Readiness
- ✅ All 20+ services running on Kubernetes
- ✅ Health checks passing (99%+ pod success rate)
- ✅ Istio mTLS enforced (all traffic encrypted)
- ✅ HPA functioning (minimum 3 scale-out events observed)
- ✅ Zero downtime deployment (rolling updates without errors)
- ✅ Monitoring/alerting operational (alerting rules firing correctly)
- ✅ Team confident in operational procedures

### Production SLOs
- **Availability**: 99.9% (30 mins downtime/month)
- **Request latency (p99)**: < 200ms
- **Error rate**: < 0.1%
- **Scaling response time**: < 60s (HPA decision to pod ready)

---

## Timeline & Next Steps

| Week | Milestone | Lead | Status |
|------|-----------|------|--------|
| 1 | K8s cluster + Istio installed | Infra Team | READY |
| 2 | All services deployed | App Team | READY |
| 3 | Testing & validation complete | QA Team | READY |
| 4 | Production migration complete | DevOps Team | PENDING |

---

## Appendix: Important URLs & References

- **Istio Documentation**: https://istio.io/latest/docs/
- **Kubernetes Best Practices**: https://kubernetes.io/docs/concepts/configuration/overview/
- **Prometheus Querying**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **Jaeger Setup**: https://www.jaegertracing.io/docs/latest/

---

**Document Status**: Ready for Phase 4 Implementation  
**Approval**: Required from Platform Engineering Lead  
**Distribution**: Engineering Team, Operations Team
