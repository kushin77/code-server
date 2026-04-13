# Configuration Profiles for On-Premises Deployments

**Phase**: 10 - On-Premises Performance Optimization  
**Focus**: Pre-configured profiles for different hardware tiers  
**Target**: Deploy code-server optimized for available resources

## Profile Selection Guide

```
Hardware Available          Recommended Profile      Typical Use Case
─────────────────────────────────────────────────────────────────────
1 Server: 4 CPU, 8 GB      small (single-node)      Dev/Test, Small Team
1 Server: 8 CPU, 16 GB     medium (single-node)     Production, <50 users
3 Servers: 4 CPU, 8 GB     medium (multi-node)      HA, Medium Org
5+ Servers: 8 CPU, 16 GB   enterprise (multi-node)  Enterprise, 200+ users
```

## Profile 1: Small (Single Node - 4 CPU / 8 GB RAM)

### Use Case
- Development/testing environment
- Small teams (<20 users)
- Budget-constrained deployments
- Proof-of-concept

### Deployment Configuration

```yaml
# kubernetes/overlays/on-premises/small/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- ../../../base

namespace: code-server

replicas:
- name: code-server
  count: 1
- name: agent-api
  count: 1
- name: embeddings
  count: 1
- name: redis
  count: 1
- name: prometheus
  count: 1
- name: grafana
  count: 1

# Resource constraints
patchesStrategicMerge:
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: code-server
  spec:
    template:
      spec:
        containers:
        - name: code-server
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi

- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: agent-api
  spec:
    template:
      spec:
        containers:
        - name: agent-api
          resources:
            requests:
              cpu: 1000m
              memory: 1Gi
            limits:
              cpu: 2000m
              memory: 2Gi

- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: embeddings
  spec:
    template:
      spec:
        containers:
        - name: embeddings
          resources:
            requests:
              cpu: 1000m
              memory: 1Gi
            limits:
              cpu: 2000m
              memory: 3Gi

# No HPA for small deployments (fixed replicas)
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: performance-config-small
data:
  # Caching
  redis_maxmemory: "1gb"
  redis_maxmemory_policy: "allkeys-lru"
  
  # Database
  pg_max_connections: "100"
  pg_shared_buffers: "512MB"
  pg_effective_cache_size: "1500MB"
  pgbouncer_default_pool_size: "20"
  pgbouncer_max_client_conn: "300"
  
  # Application
  max_workers: "2"
  gunicorn_workers: "2"
  node_cluster_workers: "1"
  
  # Timeouts
  request_timeout_seconds: "30"
  db_pool_timeout_seconds: "10"
```

### Service Configuration

```yaml
# services configuration for small deployments
code-server:
  replicas: 1
  cpu_request: 500m
  cpu_limit: 1000m
  memory_request: 512Mi
  memory_limit: 1Gi
  hpa_enabled: false

agent-api:
  replicas: 1
  cpu_request: 1000m
  cpu_limit: 2000m
  memory_request: 1Gi
  memory_limit: 2Gi
  hpa_enabled: false
  max_workers: 2

embeddings:
  replicas: 1
  cpu_request: 1000m
  cpu_limit: 2000m
  memory_request: 1Gi
  memory_limit: 3Gi
  hpa_enabled: false
  batch_size: 16

redis:
  memory_limit: 1Gi
  persistence: true
  replication: false
  
postgresql:
  backup_schedule: "0 2 * * *"  # Daily at 2 AM
  retention_days: 7
```

### Deploy Command

```bash
# Deploy small profile
kubectl apply -k kubernetes/overlays/on-premises/small

# Verify deployment
kubectl get pods -n code-server
kubectl describe nodes

# Expected resource usage
# - Total: ~1.5 CPU / 9 GB RAM (fits in 2 CPU / 10 GB available)
```

### Performance Expectations

```
Concurrent Users:     5-15
Requests Per Second:  50-150
P99 Latency:          2-5 seconds
Cache Hit Ratio:      70-80%
```

---

## Profile 2: Medium (Single Node - 8 CPU / 16 GB RAM)

### Use Case
- Production single-server deployments
- Medium teams (20-100 users)
- Budget-friendly HA option
- Standard corporate deployments

### Deployment Configuration

```yaml
# kubernetes/overlays/on-premises/medium/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- ../../../base

namespace: code-server

replicas:
- name: code-server
  count: 2  # Multiple replicas via local scheduling
- name: agent-api
  count: 2
- name: embeddings
  count: 1
- name: redis
  count: 1
- name: prometheus
  count: 1
- name: grafana
  count: 1

# Resource constraints (per replica)
patchesStrategicMerge:
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: code-server
  spec:
    template:
      spec:
        containers:
        - name: code-server
          resources:
            requests:
              cpu: 1000m
              memory: 1Gi
            limits:
              cpu: 2000m
              memory: 1.5Gi

- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: agent-api
  spec:
    template:
      spec:
        containers:
        - name: agent-api
          resources:
            requests:
              cpu: 1500m
              memory: 1.5Gi
            limits:
              cpu: 2500m
              memory: 2Gi

- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: embeddings
  spec:
    template:
      spec:
        containers:
        - name: embeddings
          resources:
            requests:
              cpu: 2000m
              memory: 2Gi
            limits:
              cpu: 3000m
              memory: 4Gi

# ConfigMap for medium profile
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: performance-config-medium
data:
  redis_maxmemory: "2gb"
  redis_maxmemory_policy: "allkeys-lru"
  
  pg_max_connections: "200"
  pg_shared_buffers: "1GB"
  pg_effective_cache_size: "4GB"
  pgbouncer_default_pool_size: "40"
  pgbouncer_max_client_conn: "600"
  
  max_workers: "4"
  gunicorn_workers: "4"
  node_cluster_workers: "2"
  
  request_timeout_seconds: "30"
  db_pool_timeout_seconds: "10"
  
  # Enable caching
  varnish_memory: "512m"
  redis_cluster_enabled: "false"
```

### Service Configuration

```yaml
code-server:
  replicas: 2
  cpu_request: 1000m
  cpu_limit: 2000m
  memory_request: 1Gi
  memory_limit: 1.5Gi
  hpa_enabled: false

agent-api:
  replicas: 2
  cpu_request: 1500m
  cpu_limit: 2500m
  memory_request: 1.5Gi
  memory_limit: 2Gi
  hpa_enabled: false
  max_workers: 4

embeddings:
  replicas: 1
  cpu_request: 2000m
  cpu_limit: 3000m
  memory_request: 2Gi
  memory_limit: 4Gi
  hpa_enabled: false
  batch_size: 32

redis:
  memory_limit: 2Gi
  persistence: true
  replication: false
  
postgresql:
  backup_schedule: "0 1 * * *"  # Daily at 1 AM
  retention_days: 14
```

### Performance Expectations

```
Concurrent Users:     30-80
Requests Per Second:  300-800
P99 Latency:          1-3 seconds
Cache Hit Ratio:      75-85%
```

---

## Profile 3: Enterprise (Multi-Node - 5+ nodes, 8 CPU / 16 GB RAM each)

### Use Case
- Enterprise deployments
- 200+ concurrent users
- High availability required
- Complex integrations

### Cluster Configuration

```yaml
# kubernetes/overlays/on-premises/enterprise/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- ../../../base

namespace: code-server

# High availability replicas
replicas:
- name: code-server
  count: 3-5
- name: agent-api
  count: 3-5
- name: embeddings
  count: 2-3
- name: redis
  count: 3  # Redis cluster
- name: prometheus
  count: 2  # Replicated monitoring
- name: grafana
  count: 1

# Resource configuration (optimized for multi-node)
patchesStrategicMerge:
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: code-server
  spec:
    replicas: 3
    template:
      spec:
        affinity:
          podAntiAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values: ["code-server"]
              topologyKey: kubernetes.io/hostname
        containers:
        - name: code-server
          resources:
            requests:
              cpu: 2000m
              memory: 1.5Gi
            limits:
              cpu: 3000m
              memory: 2Gi

- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: agent-api
  spec:
    replicas: 3
    template:
      spec:
        affinity:
          podAntiAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values: ["agent-api"]
              topologyKey: kubernetes.io/hostname
        containers:
        - name: agent-api
          resources:
            requests:
              cpu: 2500m
              memory: 2Gi
            limits:
              cpu: 3500m
              memory: 3Gi

- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: embeddings
  spec:
    replicas: 2
    template:
      spec:
        nodeSelector:
          instance-type: compute
        affinity:
          podAntiAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values: ["embeddings"]
              topologyKey: kubernetes.io/hostname
        containers:
        - name: embeddings
          resources:
            requests:
              cpu: 4000m
              memory: 6Gi
            limits:
              cpu: 6000m
              memory: 8Gi

# Enterprise performance configuration
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: performance-config-enterprise
data:
  redis_maxmemory: "4gb"
  redis_cluster_enabled: "true"
  redis_replicas: "1"
  
  pg_max_connections: "500"
  pg_shared_buffers: "4GB"
  pg_effective_cache_size: "12GB"
  pgbouncer_default_pool_size: "80"
  pgbouncer_max_client_conn: "1500"
  
  max_workers: "12"
  gunicorn_workers: "8"
  node_cluster_workers: "4"
  
  request_timeout_seconds: "60"
  db_pool_timeout_seconds: "30"
  
  varnish_memory: "2gb"
  varnish_cache_vcl_version: "4.1"
```

### Multi-Node Architecture

```
┌─────────────────────────────────────────────────┐
│           Load Balancer (Nginx/Envoy)          │
│         Round-robin / Least Connections         │
└───────────┬─────────────────────────┬───────────┘
            │                         │
    ┌───────▼──────┐          ┌───────▼──────┐
    │  Node 1      │          │  Node 2      │
    │ 8 CPU/16GB   │          │ 8 CPU/16GB   │
    │              │          │              │
    │ code-srv: 1  │          │ code-srv: 1  │
    │ agent: 1     │          │ agent: 1     │
    │ prometheus   │          │ grafana      │
    └──────────────┘          └──────────────┘
    
    ┌──────────────┐    ┌──────────────┐
    │  Node 3      │    │  Node 4      │
    │ 8 CPU/16GB   │    │ 8 CPU/16GB   │
    │              │    │              │
    │ code-srv: 1  │    │ embeddings: 1│
    │ agent: 1     │    │ embeddings: 1│
    │ redis: 1     │    │ redis: 1     │
    └──────────────┘    └──────────────┘
    
    ┌──────────────┐
    │  Node 5      │
    │  8 CPU/16GB  │
    │              │
    │ postgres     │
    │ (primary)    │
    │ redis: 1     │
    └──────────────┘

Shared Storage:
  - NAS/SAN for PostgreSQL WAL and backups
  - Local NVMe for Redis cluster
  - Object storage for backups (S3-compatible)
```

### Performance Expectations

```
Concurrent Users:     300-800
Requests Per Second:   3000-8000
P99 Latency:           0.5-1.5 seconds
Cache Hit Ratio:       80-90%
Availability:          99.9%+ (3-node resilience)
```

---

## Deployment Guide by Profile

### Small Profile Deployment

```bash
# 1. Prepare single node
kubectl label node node-1 tier=small

# 2. Deploy small profile
kubectl apply -k kubernetes/overlays/on-premises/small

# 3. Verify
kubectl get all -n code-server
kubectl describe nodes

# 4. Monitor
./kubernetes/scripts/health-check.sh -n code-server
```

### Medium Profile Deployment

```bash
# 1. Prepare single node
kubectl label node node-1 tier=medium

# 2. Deploy medium profile
kubectl apply -k kubernetes/overlays/on-premises/medium

# 3. Configure load balancing (local)
# Pod affinity spreads replicas across CPU/memory

# 4. Verify high availability
kubectl get pods -n code-server -o wide
```

### Enterprise Profile Deployment

```bash
# 1. Label nodes
kubectl label node node-1 tier=enterprise
kubectl label node node-2 tier=enterprise
kubectl label node node-3 tier=enterprise
kubectl label node node-4 tier=compute
kubectl label node node-5 tier=database

# 2. Deploy enterprise profile
kubectl apply -k kubernetes/overlays/on-premises/enterprise

# 3. Configure persistent storage
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-pv
spec:
  capacity:
    storage: 100Gi
  nfs:
    server: nas.internal
    path: "/postgres"
EOF

# 4. Verify cluster
./kubernetes/scripts/health-check.sh -n code-server --watch
```

---

## Profile Comparison Matrix

| Metric | Small | Medium | Enterprise |
|--------|-------|--------|-----------|
| **Hardware** | 1 Node: 4C/8GB | 1 Node: 8C/16GB | 5+ Nodes: 8C/16GB |
| **Replicas** | 1 each | 2 each (code-server, agent-api) | 3-5 each |
| **Redis Memory** | 1GB | 2GB | 4GB (cluster) |
| **Concurrent Users** | 5-15 | 30-80 | 300-800 |
| **RPS** | 50-150 | 300-800 | 3000-8000 |
| **P99 Latency** | 2-5s | 1-3s | 0.5-1.5s |
| **HA** | Single point of failure | Single point of failure | Multi-node resilience |
| **Cache Hit** | 70-80% | 75-85% | 80-90% |
| **Complexity** | Low | Medium | High |
| **Cost** | $ | $$ | $$$ |

---

## Switching Between Profiles

```bash
# Upgrade from small to medium
kubectl apply -k kubernetes/overlays/on-premises/medium

# Kubernetes will handle rolling updates (no downtime)

# Downgrade from medium to small (if needed)
kubectl apply -k kubernetes/overlays/on-premises/small
```

---

## Next Steps

1. **Assess** your hardware availability
2. **Choose** the appropriate profile
3. **Deploy** using the profile overlay
4. **Monitor** performance metrics
5. **Scale** up/down as needs change

---

**Phase 10**: Configuration Profiles  
**Status**: ✅ Complete  
**Total Phase 10 Files**: 8 documents, 10,000+ lines  
**Next Phase**: Testing and validation
