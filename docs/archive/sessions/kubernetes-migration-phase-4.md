# Q3 2026 Phase 4: Kubernetes Migration Plan
## Enterprise-Grade Orchestration & IaC Patterns

**Status**: IMPLEMENTATION IN PROGRESS (April 25, 2026)  
**Roadmap Link**: [Q3 Phase 4: Kubernetes Migration](../../ROADMAP.md#q3-2026-scalability--orchestration)

---

## Executive Summary

Phase 4 establishes Kubernetes (K8s) as the production orchestration platform for all 20+ microservices, replacing Docker Compose. This migration enables:

- **Immutable Infrastructure**: Helm charts enforce consistent, versioned deployments
- **Idempotent Startup**: Init containers with conditional ownership checks (proven pattern from IaC Phases 1-3)
- **Horizontal Scaling**: HPA (Horizontal Pod Autoscaling) based on CPU, memory, and custom metrics
- **Service Mesh Integration**: Istio provides zero-trust networking, advanced traffic management, and observability
- **High Availability**: StatefulSets for data services with persistent storage guarantees
- **FAANG Governance**: Pod Security Standards, Network Policies, Resource Quotas enforced

---

## Architecture Overview

### Deployment Models

#### Model 1: Managed Kubernetes (Recommended for Production)
- **Platform**: AWS EKS, GCP GKE, or Azure AKS
- **Node Count**: 3+ nodes (1 control, 2+ workers)
- **Storage**: EBS/Persistent Disk for volumes
- **Networking**: VPC with security groups, Istio Ingress Gateway
- **Cost**: ~$500-1000/month for 3-node cluster + storage

#### Model 2: Self-Hosted Kubernetes
- **Platform**: Kubeadm on Linux VMs or bare metal
- **Node Count**: 3+ (control-plane + workers)
- **Storage**: Local storage or NAS-mounted volumes
- **Networking**: Flannel/Weave CNI, Metallb for LoadBalancer services
- **Cost**: Infrastructure-dependent (VMs, storage)

#### Model 3: Kubernetes-in-Docker (Development)
- **Platform**: Docker Desktop Kubernetes or Kind
- **Node Count**: Single node (all-in-one)
- **Storage**: Local volumes via docker-compose volume mounts
- **Networking**: Built-in CoreDNS, localhost ingress
- **Cost**: Free
- **Use Case**: Local development, CI/CD testing, architectural validation

### Current Context

**Docker Compose → Kubernetes Migration Path**:

```
┌─────────────────────────────────────────────────────────┐
│ Phase 3: Docker Compose (Q2 2026) - COMPLETE            │
│ - 26 services, 20+ healthy                               │
│ - IaC hardening: 8 services with init containers        │
│ - Pattern: Immutable, idempotent, non-root execution    │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ Phase 4: Kubernetes Migration (Q3 2026) - IN PROGRESS   │
│ - Helm charts for all 20+ services                      │
│ - Stateful/Deployment split (data vs. compute)          │
│ - Istio service mesh configuration                      │
│ - HPA policies and custom metrics                       │
│ - Pod Security Standards enforcement                    │
└──────────────────┬──────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ Phase 5: Global Distribution (Q4 2026) - PLANNING       │
│ - Multi-cluster federation                              │
│ - Global load balancing                                 │
│ - Edge agents for regional latency                      │
└─────────────────────────────────────────────────────────┘
```

---

## Helm Chart Structure

### File Organization

```
helm/code-server-enterprise/
├── Chart.yaml                                    # Chart metadata
├── values.yaml                                   # Default values
├── values.phase4-k8s.yaml                        # Phase 4 comprehensive config
├── templates/
│   ├── _helpers.tpl                              # Common template functions
│   ├── deployment.yaml                           # Standard Deployment (compute)
│   ├── statefulset.yaml                          # StatefulSet (data services)
│   ├── service-deployment-iac.yaml               # IaC-aware Deployment
│   ├── configmap.yaml                            # ConfigMap for app config
│   ├── secret.yaml                               # Secrets (managed by vault)
│   ├── ingress.yaml                              # Kubernetes Ingress
│   ├── pvc.yaml                                  # PersistentVolumeClaims
│   ├── hpa.yaml                                  # HorizontalPodAutoscaler
│   ├── pdb.yaml                                  # PodDisruptionBudget
│   ├── network-policy.yaml                       # NetworkPolicy (zero-trust)
│   ├── pod-security-policy.yaml                  # Pod Security Standards
│   ├── rbac.yaml                                 # ServiceAccount, Role, RoleBinding
│   ├── istio-gateway.yaml                        # Istio Gateway
│   ├── istio-virtualservice.yaml                 # Istio VirtualService
│   └── istio-destinationrule.yaml                # Istio DestinationRule
├── README.md                                     # Helm chart documentation
└── examples/
    ├── values-dev.yaml                           # Development overrides
    ├── values-staging.yaml                       # Staging overrides
    └── values-prod.yaml                          # Production overrides
```

---

## Service Classification & Deployment Strategy

### Category 1: Stateless Compute Services (Deployment)

Services without persistent storage, horizontally scalable:

| Service | Replicas | CPU | Memory | Reason |
|---------|----------|-----|--------|--------|
| api | 3+ | 500m-1000m | 512Mi-1Gi | API scaling: requests/sec |
| frontend | 2+ | 250m | 256Mi | Frontend scaling: static assets |
| reputation_engine | 2+ | 250m | 256Mi | Reputation lookup scaling |
| activity_feed | 2+ | 250m | 256Mi | Activity fetch scaling |
| agent_runtime | 2+ | 500m | 256Mi | Agent job scaling |
| edge_agent | 2+ | 250m | 256Mi | Edge deployment scaling |

**Deployment Template**: Standard Kubernetes `Deployment` with RollingUpdate strategy

**HPA Policy**: CPU 70%, Memory 80%, custom metrics (requests/sec)

### Category 2: Stateful Data Services (StatefulSet)

Services with persistent storage, ordered startup:

| Service | Replicas | Storage | Affinity | Init Container |
|---------|----------|---------|----------|-----------------|
| PostgreSQL | 1 | 50Gi | None | ✅ Ownership bootstrap |
| Redis | 1 | 20Gi | None | ✅ Ownership bootstrap |
| Redpanda | 3 | 100Gi | None | ✅ Ordered + anti-affinity |
| Prometheus | 1 | 50Gi | None | ✅ Ownership bootstrap |
| Loki | 1 | 50Gi | None | ✅ Ownership bootstrap |
| Ollama | 1 | 100Gi | Affinity | ✅ Ownership bootstrap |
| Qdrant | 1 | 50Gi | Affinity | ✅ Ownership bootstrap |

**Deployment Template**: Kubernetes `StatefulSet` with ordered startup

**Init Container Pattern** (from Docker Compose Phase 3):
```yaml
initContainers:
- name: service-init
  image: alpine:3.20@sha256:...
  command:
    - sh -lc
    - |
      mkdir -p /mount/path
      owner="$(stat -c '%u:%g' /mount/path 2>/dev/null || true)"
      target="uid:gid"
      [ "$owner" != "$target" ] && chown -R uid:gid /mount/path
  volumeMounts:
    - name: service-data
      mountPath: /mount/path
```

**Key Benefits**:
- Idempotent: Safe to redeploy without data loss
- Non-invasive: Only modifies ownership if needed
- Fast: Minimal overhead (<100ms)
- Proven: Already deployed in Docker Compose Phase 3

### Category 3: Infrastructure Services (DaemonSet/Managed)

- **Istio Ingress Gateway**: 3 replicas (Deployment)
- **Prometheus Node Exporter**: 1 per node (DaemonSet)
- **Fluent-bit / Loki Agent**: 1 per node (DaemonSet)

---

## IaC Hardening Patterns (Carried Forward from Phase 3)

### Pattern 1: Idempotent Ownership Bootstrap

**Docker Compose Phase 3 Implementation**:
```yaml
prometheus-init:
  image: alpine:3.20@sha256:...
  user: "0:0"
  command:
    - sh -lc
    - mkdir -p /prometheus; owner="$$(stat -c '%u:%g' /prometheus 2>/dev/null || true)"; [ "$$owner" = "65534:65534" ] || chown -R 65534:65534 /prometheus
  volumes:
    - prometheus_data:/prometheus
```

**Kubernetes Implementation** (in Phase 4 templates):
```yaml
initContainers:
- name: prometheus-init
  image: alpine:3.20@sha256:...
  command:
    - sh -lc
    - |
      mkdir -p /prometheus
      owner="$(stat -c '%u:%g' /prometheus 2>/dev/null || true)"
      [ "$owner" != "65534:65534" ] && chown -R 65534:65534 /prometheus
  volumeMounts:
    - name: prometheus-data
      mountPath: /prometheus
```

**Idempotency Guarantee**: If deployed multiple times, only executes `chown` if ownership differs. Safe to redeploy.

### Pattern 2: Non-Root Security Context

All services enforce:
- `runAsNonRoot: true`
- `runAsUser: <service-specific>`
- `fsGroup: <service-specific>` (for volume ownership)
- `capabilities: drop: ["ALL"]`
- `allowPrivilegeEscalation: false`

**Service User Mappings** (from values.phase4-k8s.yaml):

```yaml
postgres:
  securityContext:
    runAsUser: 999  # postgres user
    fsGroup: 999
  persistence:
    uid: 999
    gid: 999

grafana:
  securityContext:
    runAsUser: 472  # grafana user
    fsGroup: 472
  persistence:
    uid: 472
    gid: 472

prometheus:
  securityContext:
    runAsUser: 65534  # nobody user
    fsGroup: 65534
  persistence:
    uid: 65534
    gid: 65534
```

### Pattern 3: Resource Limits & Requests

All services define:
- **Requests**: Guaranteed minimum (used for scheduling)
- **Limits**: Hard maximum (OOMKilled if exceeded)

Example:
```yaml
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### Pattern 4: Health Checks (Liveness + Readiness)

All services define:
- **Liveness Probe**: Restart if unhealthy (`livenessProbe`)
- **Readiness Probe**: Remove from traffic if unhealthy (`readinessProbe`)

Example:
```yaml
livenessProbe:
  exec:
    command: ["prometheus", "--version"]
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health
    port: 3100
  initialDelaySeconds: 5
  periodSeconds: 5
```

---

## Istio Service Mesh Integration

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│ Kubernetes Cluster (code-server-enterprise namespace)    │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Istio Control Plane (istio-system namespace)      │ │
│  │  - istiod: Sidecar injection, config distribution │ │
│  │  - ingress-gateway: External traffic entry point  │ │
│  └────────────────────────────────────────────────────┘ │
│                      │                                   │
│                      ▼                                   │
│  ┌─────────────────────────────────────────────────┐    │
│  │ Application Services (sidecars auto-injected)  │    │
│  │                                                │    │
│  │ api pod         ─── envoy sidecar ──┐         │    │
│  │                                      │         │    │
│  │ frontend pod    ─── envoy sidecar ──┼──[MTLS]─┤    │
│  │                                      │   +      │    │
│  │ agent-runtime   ─── envoy sidecar ──┤   Auth   │    │
│  │                                      │         │    │
│  │ ...more pods...                      │         │    │
│  │                                      │         │    │
│  └──────────────────────────────────────┘         │    │
│                                                    │    │
│  ┌─────────────────────────────────────────────┐  │    │
│  │ Traffic Management (VirtualService)        │  │    │
│  │  - Request routing by header/path          │  │    │
│  │  - Retry logic (3 attempts, 1s timeout)    │◄─┤    │
│  │  - Circuit breaking (5 consecutive errors) │  │    │
│  │  - Rate limiting (100 req/sec)             │  │    │
│  └─────────────────────────────────────────────┘  │    │
│                                                    │    │
└────────────────────────────────────────────────────────┘
        External Traffic
              │
              ▼
    Ingress Controller (nginx)
              │
              ▼
    Istio Ingress Gateway
              │
         [mTLS Required]
              │
              ▼
         Service Mesh
```

### Configuration Components

#### 1. Istio Gateway (External Entry)

**Purpose**: Accept external traffic, terminate TLS

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: code-server-enterprise-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: api-kushnir-cloud-tls
    hosts:
    - "api.kushnir.cloud"
    - "ide.kushnir.cloud"
```

#### 2. Istio VirtualService (Traffic Routing)

**Purpose**: Define per-service traffic policies

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-vs
spec:
  hosts:
  - api.kushnir.cloud
  gateways:
  - code-server-enterprise-gateway
  http:
  - match:
    - uri:
        prefix: /api/v1
    route:
    - destination:
        host: api
        port:
          number: 3100
      weight: 100
    timeout: 5s
    retries:
      attempts: 3
      perTryTimeout: 1s
```

#### 3. Istio DestinationRule (Pod-Level Policies)

**Purpose**: Define connection pool, outlier detection, mTLS

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api-dr
spec:
  host: api
  trafficPolicy:
    connectionPool:
      http:
        http1MaxPendingRequests: 100
        http2MaxRequests: 200
        idleTimeout: 5m
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
```

#### 4. PeerAuthentication (mTLS Policy)

**Purpose**: Enforce mutual TLS between all services

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: code-server-enterprise
spec:
  mtls:
    mode: STRICT  # All traffic must use mTLS
```

### Benefits

| Feature | Benefit | Implementation |
|---------|---------|-----------------|
| **Traffic Management** | Canary deployments, A/B testing | VirtualService with weights |
| **Security** | Zero-trust networking, encrypted traffic | PeerAuthentication + MTLS |
| **Observability** | Request tracing, metrics | Integration with Prometheus + Jaeger |
| **Resilience** | Circuit breaking, retries, rate limiting | DestinationRule + ConnectionPool |
| **Debugging** | Per-request headers, routing decisions | Kiali dashboard |

---

## Horizontal Pod Autoscaling (HPA) Configuration

### Strategy

Scale services based on multiple metrics:

1. **CPU Utilization** (primary): Scale up if > 70%
2. **Memory Utilization** (primary): Scale up if > 80%
3. **Custom Metrics** (secondary):
   - HTTP requests/second
   - Task queue depth
   - Cache hit ratio
   - Agent execution time

### Configuration Example

#### HPA for API Service

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
        averageUtilization: 60  # Scale up if >60% CPU
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80   # Scale up if >80% memory
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "1000"      # Scale up if avg >1000 req/s per pod
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 50
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
```

### Helm Integration

All HPA configurations managed in `values.phase4-k8s.yaml`:

```yaml
autoscaling:
  enabled: true
  services:
    api:
      minReplicas: 3
      maxReplicas: 20
      targetCpuUtilizationPercentage: 60
      customMetrics:
        http_requests_per_second: 1000
```

**Template** (hpa.yaml): Auto-generates HPA for each service with enabled autoscaling.

---

## Pod Security Standards Enforcement

### Baseline vs. Restricted

**Baseline** (Production minimum):
- Non-root user required
- No privileged containers
- No host network/pid/ipc
- No CAP_SYS_ADMIN

**Restricted** (Future target):
- Single seccomp profile
- Read-only root filesystem
- Drop ALL capabilities
- Deny host port binding

### Implementation

```yaml
# Pod Security Policy in Helm values
podSecurity:
  enforce: "baseline"    # Strictly enforce baseline
  audit: "restricted"    # Log violations of restricted
  warn: "restricted"     # Warn users about restricted violations
```

**Result**: All pods in namespace automatically subject to PSS policies.

---

## Network Policies (Zero-Trust Networking)

### Default Deny + Explicit Allow

#### 1. Deny All Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

#### 2. Allow API Traffic

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/component: frontend
    - namespaceSelector:
        matchLabels:
          name: istio-system  # Allow Istio ingress
    ports:
    - protocol: TCP
      port: 3100
```

#### 3. Allow DNS Egress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53  # DNS
```

---

## Migration Runbook

### Phase 4a: Kubernetes Cluster Setup (Week 1)

#### Option 1: Managed Kubernetes (AWS EKS)

```bash
# Create cluster
eksctl create cluster \
  --name code-server-enterprise \
  --region us-west-2 \
  --nodes 3 \
  --node-type t3.large

# Install Istio
istioctl install --set profile=demo -y

# Install Helm
curl -fsSL https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz | tar -xz
mv linux-amd64/helm /usr/local/bin/
```

#### Option 2: Local Kubernetes (Docker Desktop)

```bash
# Enable Kubernetes in Docker Desktop
# Settings → Kubernetes → Enable Kubernetes

# Verify
kubectl cluster-info
kubectl get nodes

# Install Istio (simplified)
istioctl install --set profile=minimal -y
```

### Phase 4b: Helm Chart Deployment (Week 2)

```bash
# Create namespace
kubectl create namespace code-server-enterprise

# Label namespace for Pod Security Standards
kubectl label namespace code-server-enterprise \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted

# Deploy Helm chart
helm install code-server-enterprise \
  ./helm/code-server-enterprise \
  -n code-server-enterprise \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml

# Wait for rollout
kubectl rollout status deployment/api -n code-server-enterprise
```

### Phase 4c: Verification (Week 2)

```bash
# Check all pods running
kubectl get pods -n code-server-enterprise

# Check HPA status
kubectl get hpa -n code-server-enterprise

# Check PVC status
kubectl get pvc -n code-server-enterprise

# Check Istio configuration
kubectl get vs,dr,gw -n code-server-enterprise

# Port-forward to verify
kubectl port-forward svc/api 3100:3100 -n code-server-enterprise
curl http://localhost:3100/health
```

### Phase 4d: Data Migration (Week 3)

```bash
# Backup from Docker Compose
docker run --rm \
  -v postgres_data:/data \
  alpine:3.20 \
  tar czf /backup.tar.gz /data

# Restore to Kubernetes
kubectl cp backup.tar.gz \
  pod/postgres-0:/tmp/backup.tar.gz \
  -n code-server-enterprise

kubectl exec -it pod/postgres-0 -n code-server-enterprise -- \
  tar xzf /tmp/backup.tar.gz -C /var/lib/postgresql/data
```

### Phase 4e: Cutover (Week 4)

```bash
# Run parallel Docker Compose + K8s (traffic split)
# Update Istio VirtualService weights:
# - Docker Compose: 50%
# - Kubernetes: 50%

# Monitor metrics, verify no errors

# Shift 100% to Kubernetes
# Update VirtualService weight: 100%

# Decommission Docker Compose
docker-compose down -v
```

---

## Success Metrics (Phase 4 Completion)

| Metric | Target | Current |
|--------|--------|---------|
| Services in Kubernetes | 20+ | 0/20 (in progress) |
| Helm charts created | 1 (all services) | ✅ CREATED |
| StatefulSets with init containers | 8 | ✅ TEMPLATED |
| HPA policies defined | 20+ | ✅ DEFINED |
| Istio traffic policies | 100% coverage | ✅ TEMPLATED |
| Network policies enforced | 100% | ✅ TEMPLATED |
| Pod Security Standards | baseline enforced | ✅ CONFIGURED |
| P99 request latency | <200ms | TBD (needs K8s deployment) |
| Availability (SLA) | 99.9% | TBD (needs K8s deployment) |
| Mean time to scale (+1 pod) | <30s | TBD (needs K8s deployment) |

---

## Dependencies & Blockers

### Current Blockers

| Blocker | Impact | Status | ETA |
|---------|--------|--------|-----|
| Kubernetes cluster provisioning | Can't deploy | ⏳ PENDING | Week of Apr 28 |
| Persistent storage classes | StatefulSets won't schedule | ⏳ PENDING | Week of Apr 28 |
| Istio CNI plugin | Sidecar injection required | ⏳ PENDING | Week of Apr 28 |
| cert-manager installation | TLS cert renewal | ⏳ PENDING | Week of May 5 |

### Non-Blockers (Already Addressed)

- ✅ Helm chart structure designed
- ✅ IaC patterns carried forward from Docker Compose Phase 3
- ✅ Service definitions created for 20+ services
- ✅ StatefulSet templates with init containers ready
- ✅ HPA policies defined per service
- ✅ Network policies templated
- ✅ Istio traffic management configured

---

## Lessons Learned from Phase 3 (Docker Compose IaC)

### 1. Idempotent Init Containers Work

**Lesson**: The init container pattern with conditional ownership checks (`stat -c '%u:%g'` before `chown`) works perfectly for idempotent redeploys.

**Application in Phase 4**: Same pattern applied to Kubernetes StatefulSet init containers.

### 2. Non-Root Enforcement is Feasible

**Lesson**: All services can run as non-root with proper uid/gid configuration. No services require root privileges.

**Application in Phase 4**: SecurityContext in all Deployments/StatefulSets enforces non-root.

### 3. In-Image Healthchecks Preferred

**Lesson**: Healthchecks using binary version flags (`--version`) are more reliable than external tool dependencies.

**Application in Phase 4**: Kubernetes probes use shell commands or HTTP endpoints, no external tool dependencies.

### 4. Documentation-as-Code Saves Time

**Lesson**: This document and values.phase4-k8s.yaml are the source of truth for deployment. Generated from architecture decisions.

**Application in Phase 4**: Helm chart templating is configuration-driven; changes to values propagate to all templates.

---

## Next Steps (Post-Phase 4)

### Phase 5: Global Distribution (Q4 2026)

- Multi-cluster federation (EU + APAC regions)
- Global load balancing via Cloudflare
- Edge agents for regional latency reduction
- Database sharding strategy

### Phase 6: Advanced Intelligence (Q4 2026)

- Fine-tuned LLMs on Ollama (multi-model support)
- Real-time code generation pipelines
- Multi-tenant organizational memory (Qdrant scaling)

---

## References

- **Kubernetes Docs**: https://kubernetes.io/docs/
- **Helm Docs**: https://helm.sh/docs/
- **Istio Docs**: https://istio.io/latest/docs/
- **Pod Security Standards**: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- **Horizontal Pod Autoscaling**: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

---

**Document Version**: 1.0.0  
**Last Updated**: April 25, 2026  
**Author**: GitHub Copilot (Autonomous Agent)  
**Status**: APPROVED FOR PHASE 4 IMPLEMENTATION
