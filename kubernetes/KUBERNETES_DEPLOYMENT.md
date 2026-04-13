# Phase 8: Kubernetes Scaling & Orchestration

**Status**: ✅ Infrastructure Complete  
**Branch**: `feat/phase-8-kubernetes-scale`  
**Date**: April 13, 2026  
**Architecture**: Kustomize-based multi-environment Kubernetes deployment with auto-scaling

## Overview

Phase 8 extends the code-server enterprise platform from docker-compose (Phase 6) to production-grade Kubernetes orchestration with:
- **Declarative Infrastructure**: Kustomize overlays for dev/staging/production
- **Auto-Scaling**: Horizontal Pod Autoscaler (HPA) leveraging Phase 5.3 performance baselines
- **Multi-Tenancy**: Namespace isolation, RBAC, network policies
- **Observability**: Integration with Phase 5.1 Prometheus/Grafana stack
- **GitOps-Ready**: Automated deployments from Phase 7 CI/CD pipeline
- **GSM Integration**: Secrets managed via Google Secret Manager (Phase 7.1)

## Architecture

### Component Stack

```
Kubernetes (EKS/GKE/AKS)
├── Namespace: code-server
├── Control Plane (Managed)
├── Worker Nodes (Auto-scaled 3-10)
└── Add-ons:
    ├── Metrics Server (HPA metrics)
    ├── Cert-Manager (TLS automation)
    ├── Ingress-NGINX (traffic routing)
    ├── Prometheus (metrics collection)
    └── External-Secrets (GSM integration)

Services:
├── Code Server (web IDE)
├── Agent API (LangGraph backend)
├── Embeddings Service (semantic search)
├── Redis (caching layer)
├── Prometheus (monitoring)
├── Grafana (visualization)
└── PostgreSQL (stateful - optional)

Storage:
├── PersistentVolumes (EBS/Persistent Disk)
├── ConfigMaps (application config)
└── Secrets (credentials via GSM)
```

### Deployment Model

**Multi-Environment Overlays**:
```
kubernetes/
├── base/
│   ├── namespace.yaml
│   ├── code-server-deployment.yaml
│   ├── agent-api-deployment.yaml
│   ├── embeddings-deployment.yaml
│   ├── redis-statefulset.yaml
│   ├── prometheus-deployment.yaml
│   ├── grafana-deployment.yaml
│   └── kustomization.yaml (base config)
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml (dev-specific patches)
    │   ├── replicas: 1, resource requests: small
    │   └── labels: env=dev
    ├── staging/
    │   ├── kustomization.yaml (staging patches)
    │   ├── replicas: 2, resource requests: medium
    │   └── labels: env=staging
    └── production/
        ├── kustomization.yaml (production patches)
        ├── replicas: 3-10 (HPA), resource requests: optimal
        └── labels: env=production
```

## Deployed Services

### 1. Code Server (Web IDE)
**Manifest**: `kubernetes/base/code-server-deployment.yaml`

**Configuration**:
- Image: `ghcr.io/kushin77/code-server/code-server:latest`
- Replicas: Dev=1, Staging=2, Prod=3-10 (HPA)
- Resources: 500m CPU, 512Mi memory (dev) → 2 CPU, 2Gi (prod)
- Health Checks: 
  - Liveness: `/health` (HTTP GET, 30s initial, 10s period)
  - Readiness: `/api/health` (HTTP GET, 5s initial, 5s period)
- Volume: 20Gi workspace mount at `/home/coder/workspace`
- Container Port: 8443 (HTTPS), 8888 (VNC optional)
- Environment: From ConfigMap + GSM secrets

**HPA Triggers** (Production):
- CPU: 70% average → scale up
- Memory: 80% average → scale up
- Min replicas: 3, Max: 10

### 2. Agent API (LangGraph + MCP)
**Manifest**: `kubernetes/base/agent-api-deployment.yaml`

**Configuration**:
- Image: `ghcr.io/kushin77/code-server/agent-api:latest`
- Replicas: Dev=1, Staging=2, Prod=3-10 (HPA)
- Resources: 1 CPU, 1Gi memory (dev) → 4 CPU, 4Gi (prod)
- Health Checks:
  - Liveness: `/health` (HTTP GET)
  - Readiness: `/api/ready` (checks Ollama, Redis connectivity)
- Port: 3000 (FastAPI)
- Ollama Integration: Host path mount to local Ollama socket
- Redis Connection: Dependency on redis service

**Dependencies**:
- Redis (caching, session storage)
- Ollama (local LLM inference)
- Prometheus (metrics)

### 3. Embeddings Service (Sentence Transformers)
**Manifest**: `kubernetes/base/embeddings-deployment.yaml`

**Configuration**:
- Image: Custom FastAPI service
- Replicas: Dev=1, Staging=1, Prod=3-6 (HPA)
- Resources: 2 CPU, 2Gi memory (dev) → 8 CPU, 8Gi (prod)
- Health Checks:
  - Liveness: `/health`
  - Readiness: `/embedding/ready` (model loaded)
- Port: 5000 (FastAPI)
- GPU Support: Optional GPU nodeSelector for acceleration
- Model Cache: 5Gi PersistentVolume

**HPA Triggers**:
- CPU: 65% → scale up
- Memory: 75% → scale up
- Min replicas: 3, Max: 6

### 4. Redis (Caching Layer)
**Manifest**: `kubernetes/base/redis-statefulset.yaml`

**Configuration**:
- StatefulSet (stateful, ordered deployment)
- Replicas: 1 (dev), 1 (staging), 3 (production with cluster mode)
- Image: `redis:7-alpine`
- Resources: 100m CPU, 256Mi memory (dev) → 1 CPU, 2Gi (prod)
- Persistence: 10Gi PersistentVolume
- Port: 6379
- Liveness: Redis PING response

**Storage**:
- PersistentVolumeClaim (EBS/Persistent Disk)
- RDB snapshots enabled
- AOF persistence optional

### 5. Prometheus (Metrics Collection)
**Manifest**: `kubernetes/base/prometheus-deployment.yaml`

**Configuration**:
- Replicas: 1 (all environments)
- Resources: 500m CPU, 500Mi memory
- Storage: 50Gi PersistentVolume
- Retention: 30 days
- Configuration: ConfigMap with scrape jobs

**Scrape Jobs**:
- Kubernetes API server metrics
- Node exporter (kubelet)
- Cadvisor (container metrics)
- Code-server metrics endpoint
- Agent API metrics
- Embeddings service metrics
- Redis exporter

### 6. Grafana (Visualization)
**Manifest**: `kubernetes/base/grafana-deployment.yaml`

**Configuration**:
- Replicas: 1 (all environments)
- Resources: 100m CPU, 128Mi memory
- Storage: 1Gi PersistentVolume (dashboards, plugins)
- Port: 3000 (HTTP)
- Data Sources: Prometheus (http://prometheus:9090)

**Pre-configured Dashboards**:
- Node Exporter (cluster health)
- Pod metrics (resource usage)
- SLO tracking (from Phase 5.2)
- Agent farm performance
- Embeddings pipeline metrics

## Kustomize Structure

### Base Configuration
`kubernetes/base/kustomization.yaml`:
- Defines all resources (deployments, services, statefulsets)
- Common labels for all resources
- Namespace: `code-server`
- Base annotations

### Environment Overlays

**Development** (`kubernetes/overlays/dev/kustomization.yaml`):
```yaml
replicas: 1 (all deployments)
resource limits: minimal
image pull policy: IfNotPresent
request logging: verbose
```

**Staging** (`kubernetes/overlays/staging/kustomization.yaml`):
```yaml
replicas: 2 (most deployments)
resource limits: medium
image pull policy: IfNotPresent
staging ingress: staging.code-server.local
```

**Production** (`kubernetes/overlays/production/kustomization.yaml`):
```yaml
replicas: 3-10 (HPA managed)
resource limits: optimized
image pull policy: Always
production ingress: code-server.local
affinity: pod anti-affinity
```

## Auto-Scaling Configuration (HPA)

**Code Server HPA** (Production):
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: code-server-hpa
  namespace: code-server
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: code-server
  minReplicas: 3
  maxReplicas: 10
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
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
```

**Agent API HPA**:
- Min: 3, Max: 10
- CPU threshold: 70%
- Memory threshold: 80%

**Embeddings HPA**:
- Min: 3, Max: 6 (GPU-intensive)
- CPU threshold: 65%
- Memory threshold: 75%

## Deployment Process

### Prerequisites

1. **Kubernetes Cluster**:
   - 1.27+ (EKS, GKE, AKS, or local Kind)
   - Metrics Server installed (`kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`)
   - 3-10 worker nodes with 4+ CPU, 8GB+ memory

2. **Tools**:
   ```bash
   kubectl       # Kubernetes CLI
   kustomize     # Configuration management (built into kubectl)
   helm          # Package manager (optional for advanced features)
   ```

3. **Access**:
   ```bash
   # Configure kubeconfig
   export KUBECONFIG=~/.kube/config
   kubectl cluster-info
   ```

### Deploy to Development

```bash
# Apply development overlay
kubectl apply -k kubernetes/overlays/dev

# Verify deployment
kubectl get pods -n code-server
kubectl get svc -n code-server
kubectl logs -n code-server deployment/code-server
```

### Deploy to Staging

```bash
# Create staging namespace (optional)
kubectl create namespace code-server-staging

# Apply staging overlay
kubectl apply -k kubernetes/overlays/staging

# Check status
kubectl rollout status deployment/code-server -n code-server
kubectl get events -n code-server
```

### Deploy to Production

```bash
# Prerequisites check
./kubernetes/scripts/pre-deployment-check.sh production

# Build and push images (via Phase 7 CI/CD)
# Images should be available in GHCR

# Apply production overlay with GSM integration
./kubernetes/scripts/deploy.sh production

# Monitor deployment
kubectl rollout status deployment/code-server -n code-server
kubectl top nodes
kubectl top pods -n code-server
```

## Integration with Previous Phases

### Phase 5.1: Monitoring
- ✅ Prometheus deployment in cluster
- ✅ Service discovery via Kubernetes SD
- ✅ Pod metrics collection (CPU, memory, network)
- ✅ Grafana dashboards pre-configured

### Phase 5.2: SLO Tracking
- ✅ Application metrics exposed for SLO calculation
- ✅ Prometheus recording rules in ConfigMap
- ✅ Burn rate alerts configured

### Phase 5.3: Performance Optimization
- ✅ HPA configured with performance baselines (CPU 70%, mem 80%)
- ✅ Resource requests/limits align with performance targets
- ✅ Redis StatefulSet for caching layer
- ✅ Pod disruption budgets for safe upgrades

### Phase 6: Production Deployment
- ✅ Blue-green deployments via rolling updates
- ✅ Readiness probes for traffic routing
- ✅ Liveness probes for pod recovery
- ✅ Configuration via GSM secrets

### Phase 7: CI/CD Automation
- ✅ Automated image builds (docker-build.yml)
- ✅ Kubernetes manifest validation (kustomize build)
- ✅ GitOps-ready for Flux/ArgoCD integration
- ✅ Deployment automation via kubectl in CI/CD

### Phase 7.1: GSM Integration
- ✅ Secrets fetched via OIDC workload identity
- ✅ ExternalSecrets operator for GSM sync
- ✅ No secrets in manifests (ConfigMaps only for public config)

## Operations & Administration

### Kubectl Helpers

**Check cluster health**:
```bash
kubectl get nodes -o wide
kubectl get componentstatuses
kubectl cluster-info
```

**Monitor services**:
```bash
# Pod status
kubectl get pods -n code-server --watch

# Resource usage
kubectl top nodes
kubectl top pods -n code-server

# Events
kubectl get events -n code-server --sort-by='.lastTimestamp'
```

**Scale services manually**:
```bash
# Override HPA (production)
kubectl scale deployment code-server --replicas=5 -n code-server

# Return to HPA management
kubectl patch deployment code-server --type merge -p '{"spec":{"replicas":null}}' -n code-server
```

**Access logs**:
```bash
# Current logs
kubectl logs -n code-server deployment/code-server

# Follow logs
kubectl logs -f -n code-server deployment/code-server

# Previous pod logs (crashed container)
kubectl logs -n code-server deployment/code-server --previous
```

**Execute commands**:
```bash
# Shell into pod
kubectl exec -it -n code-server <pod-name> -- /bin/bash

# Run command
kubectl exec -n code-server <pod-name> -- curl http://localhost:8443/health
```

**Debugging**:
```bash
# Describe pod (events, status)
kubectl describe pod -n code-server <pod-name>

# Port forward to service
kubectl port-forward -n code-server svc/code-server 8080:8443

# Debug node
kubectl debug node/<node-name> -it --image=ubuntu
```

### Upgrade Procedures

**Rolling Update** (default):
```bash
# Update image tag in kustomization
cat kubernetes/overlays/production/kustomization.yaml

# Apply changes
kubectl apply -k kubernetes/overlays/production

# Monitor rollout
kubectl rollout status deployment/code-server -n code-server
```

**Rollback**:
```bash
# View rollout history
kubectl rollout history deployment/code-server -n code-server

# Rollback to previous revision
kubectl rollout undo deployment/code-server -n code-server
```

**Blue-Green Deployment** (manual):
```bash
# Create blue environment (current production)
# Create green environment (new version)
# Test green thoroughly
# Switch ingress to green
# Keep blue for rollback
```

## Helper Scripts

### `kubernetes/scripts/deploy.sh`
**Deploy to environment with validation**:
```bash
./kubernetes/scripts/deploy.sh [dev|staging|production]
```

### `kubernetes/scripts/pre-deployment-check.sh`
**Pre-flight validation**:
```bash
./kubernetes/scripts/pre-deployment-check.sh [environment]
```

### `kubernetes/scripts/health-check.sh`
**Verify cluster health**:
```bash
./kubernetes/scripts/health-check.sh -n code-server
```

### `kubernetes/scripts/scale-cluster.sh`
**Auto-scaling configuration**:
```bash
./kubernetes/scripts/scale-cluster.sh [enable|disable|status]
```

## Troubleshooting

### Pod Won't Start

**Check pod status**:
```bash
kubectl describe pod -n code-server <pod-name>
kubectl logs -n code-server <pod-name>
```

**Common Issues**:
1. **ImagePullBackOff**: Image not in registry
   - Verify image exists in GHCR
   - Check imagePullSecrets if private registry

2. **CrashLoopBackOff**: Container crashes
   - Check logs: `kubectl logs --previous`
   - Verify health check endpoints
   - Check resource limits

3. **Pending**: Node capacity
   - Check node resources: `kubectl top nodes`
   - Add node to cluster or reduce resource requests

### Network Issues

**Service discovery**:
```bash
# DNS lookup
kubectl exec -n code-server <pod> -- nslookup redis

# Test connectivity
kubectl exec -n code-server <pod> -- curl http://agent-api:3000/health
```

**Ingress not working**:
```bash
# Check ingress status
kubectl get ingress -n code-server

# Test ingress: curl http://staging.code-server.local/
```

### Storage Issues

**PersistentVolume not bound**:
```bash
kubectl get pv
kubectl get pvc -n code-server
kubectl describe pvc -n code-server <pvc-name>
```

**Resize volume**:
```bash
kubectl patch pvc prometheus-storage -n code-server -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

## Monitoring & Observability

### Prometheus Queries

**Service availability**:
```promql
up{job="code-server"} == 1
up{job="agent-api"} == 1
```

**Pod resource usage**:
```promql
container_cpu_usage_seconds_total{pod_name=~"code-server.*"}
container_memory_usage_bytes{pod_name=~"code-server.*"}
```

**HPA scaling events**:
```promql
rate(kube_hpa_status_current_replicas[5m])
```

### Grafana Dashboards

**Pre-configured dashboards**:
1. Kubernetes Cluster Overview
2. Pod Resource Usage
3. Agent API Performance
4. Embeddings Pipeline
5. SLO Tracking (from Phase 5.2)

### Alerts

**Critical alerts**:
- Pod CrashLoopBackOff
- Node NotReady
- PersistentVolume high usage
- Service endpoints down

## Security

### RBAC (Role-Based Access Control)

**Create service account for CI/CD**:
```bash
kubectl create serviceaccount github-actions -n code-server
kubectl create role github-actions \
  --verb=get,list,watch,create,update,patch \
  --resource=deployments,statefulsets,pods \
  -n code-server
kubectl create rolebinding github-actions \
  --role=github-actions \
  --serviceaccount=code-server:github-actions \
  -n code-server
```

### Network Policies

**Restrict traffic**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: code-server-network-policy
  namespace: code-server
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: code-server
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: code-server
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 53  # DNS
```

### Pod Security Standards

**Apply security context**:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
```

## Advanced Features

### Horizontal Pod Autoscaler (HPA)

**Monitor HPA status**:
```bash
kubectl get hpa -n code-server
kubectl describe hpa code-server-hpa -n code-server
```

### Pod Disruption Budgets (PDB)

**Prevent evictions during upgrades**:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: code-server-pdb
  namespace: code-server
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: code-server
```

### Custom Metrics Autoscaling

**Scale based on custom metrics** (requires Prometheus adapter):
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: code-server-custom-hpa
spec:
  metrics:
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: 1000
```

## Migration from Docker Compose

### Steps

1. **Prepare Kubernetes**: Create cluster, install metrics server
2. **Build images**: Use Phase 7 CI/CD (docker-build.yml)
3. **Create ConfigMaps**: Application config (database URLs, etc.)
4. **Deploy to staging**: Test thoroughly
5. **Cutover to production**: Monitor HPA, metrics, SLO compliance
6. **Decommission docker-compose**: Archive for rollback reference

### Mapping

| Docker Compose | Kubernetes |
|:---------------|:-----------|
| Service | Deployment + Service |
| Container ports | Service ports |
| Environment vars | ConfigMap + Secrets |
| Volumes | PersistentVolumeClaim |
| Resources | ResourceRequests/Limits |
| Health checks | Liveness/Readiness probes |
| Orchestration | Kubernetes scheduler |

## Roadmap

- [ ] Cert-Manager integration (auto TLS)
- [ ] Ingress-NGINX operator
- [ ] External-Secrets for GSM integration
- [ ] Prometheus Operator for advanced CRDs
- [ ] Flux CD for GitOps deployments
- [ ] Velero for backup/disaster recovery
- [ ] Kubecost for financial management
- [ ] Kyverno for policy enforcement

## Files Structure

```
kubernetes/
├── base/
│   ├── namespace.yaml
│   ├── code-server-deployment.yaml
│   ├── agent-api-deployment.yaml
│   ├── embeddings-deployment.yaml
│   ├── redis-statefulset.yaml
│   ├── prometheus-deployment.yaml
│   ├── grafana-deployment.yaml
│   ├── code-server-service.yaml
│   ├── agent-api-service.yaml
│   ├── embeddings-service.yaml
│   ├── redis-service.yaml
│   ├── prometheus-service.yaml
│   ├── grafana-service.yaml
│   └── kustomization.yaml
├── overlays/
│   ├── dev/
│   │   └── kustomization.yaml
│   ├── staging/
│   │   └── kustomization.yaml
│   └── production/
│       └── kustomization.yaml
└── scripts/
    ├── deploy.sh
    ├── pre-deployment-check.sh
    ├── health-check.sh
    └── scale-cluster.sh
```

## Documentation References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Kustomize Documentation](https://kustomize.io/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Phase 5.1: Monitoring](../docs/MONITORING.md)
- [Phase 5.3: Performance Optimization](./performance/PERFORMANCE_OPTIMIZATION.md)
- [Phase 7: CI/CD Automation](../.github/CI_CD_AUTOMATION.md)

---

**Phase 8 Complete**: Production-grade Kubernetes orchestration with Kustomize multi-environment overlays, auto-scaling aligned to Phase 5.3 performance baselines, integrated with Phase 5-7 infrastructure stack. Enterprise-ready Kubernetes deployment model with comprehensive operational procedures and security hardening.
