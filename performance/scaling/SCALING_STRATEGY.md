# Scaling Strategy for On-Premises Deployments

**Phase**: 10 - On-Premises Performance Optimization  
**Focus**: Vertical and horizontal scaling strategies for resource-constrained environments  
**Target**: Maximize throughput and minimize latency within hardware constraints

## Scaling Paradigm

```
Vertical Scaling (Scale-Up)        Horizontal Scaling (Scale-Out)
│                                  │
├─ Add resources to single node    ├─ Add more nodes
├─ Simplest implementation         ├─ Higher complexity (distributed state)
├─ Limited by hardware/physics     ├─ Theoretically unlimited
├─ Single point of failure         ├─ Distributed resilience
└─ Easier operations               └─ More operational overhead

For On-Premises:
- Vertical first (common, 4-32 CPU systems available)
- Horizontal when vertical ceiling reached (typically 16+ CPU)
- Hybrid for large deployments
```

## Vertical Scaling (Single Node, Up to 32 CPU / 256GB RAM)

### Resource Allocation Strategy

```
Single 32-core Server (256GB RAM):

code-server:
  - 4 cores (CPU quota)
  - 4GB memory
  - 3-4 replicas (across cores)
  
agent-api:
  - 8 cores
  - 8GB memory
  - 4-6 replicas
  
embeddings:
  - 8 cores (can be GPU-accelerated)
  - 12GB memory
  - 2-3 replicas
  
redis:
  - 2 cores
  - 16GB memory
  - Single instance with persistence
  
postgresql:
  - 8 cores
  - 64GB memory
  - Shared with Kubernetes
  
prometheus/grafana:
  - 2 cores
  - 8GB memory (shared)
  
OS/System:
  - 2 cores reserved
  - 8GB memory reserved
  
Total: ~34 cores, 120GB in use, 8GB buffer
```

### Vertical Scaling Techniques

### 1. CPU Optimization

**Thread Pool Tuning**:
```python
import multiprocessing
import os

# For CPU-intensive work (embeddings, NLP)
cpu_count = multiprocessing.cpu_count()
optimal_threads = cpu_count - 1  # Leave one core for system

# FastAPI workers
WORKERS = optimal_threads
THREADS_PER_WORKER = 2

# NumPy/SciPy optimization
os.environ['OMP_NUM_THREADS'] = str(optimal_threads)
os.environ['OPENBLAS_NUM_THREADS'] = str(optimal_threads)

# Gunicorn configuration
# gunicorn --workers $WORKERS --threads 2 \
#   --worker-class gthread --max-requests 100 app:app
```

**Process Affinity** (CPU pinning):
```bash
# Pin agent-api to cores 2-9
taskset -c 2-9 python -m uvicorn agent_api:app --workers 4

# Pin embeddings to cores 10-17 (GPU pinning for CUDA)
taskset -c 10-17 python -m uvicorn embeddings:app --workers 2

# Kubernetes pod affinity (nodeAffinity)
nodeSelector:
  cpuCapacity: "high"
affinity:
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: tier
          operator: In
          values: ["compute"]
      topologyKey: kubernetes.io/hostname
```

**CPU Frequency Scaling**:
```bash
# Check current CPU frequency
cat /proc/cpuinfo | grep MHz

# Set to performance mode (vs powersave)
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Monitor CPU utilization
watch -n 1 'top -b -n 1 | head -20'
```

### 2. Memory Optimization

**JVM Heap Configuration** (if using Java):
```bash
# For applications using Java (Spring Boot, etc.)
export JAVA_OPTS="-Xms8g -Xmx8g -XX:+UseG1GC -XX:MaxGCPauseMillis=200"

# Enable memory mapping for large datasets
export JAVA_OPTS="$JAVA_OPTS -XX:+UseStringDeduplication"
```

**Python Memory Management**:
```python
import gc
import psutil

# Monitor memory usage
process = psutil.Process()
print(f"RSS: {process.memory_info().rss / 1024 / 1024:.2f} MB")

# Optimize garbage collection
gc.set_threshold(10000, 15, 15)

# For ML models, use gradient checkpointing
from transformers import AutoModelForCausalLM

model = AutoModelForCausalLM.from_pretrained(
    "model-name",
    gradient_checkpointing=True,  # Trade CPU for memory
    device_map="auto"  # Automatic device placement
)
```

**Redis Memory Configuration**:
```conf
# redis.conf - Vertical scaling

# Use more memory for larger deployments
maxmemory 32gb  # 32GB for large vertical setup

# Optimize memory usage
lazyfree-lazy-server-del yes
lazyfree-lazy-expire yes

# Use jemalloc for fragmentation reduction
# Compile with: ./configure --with-jemalloc

# Enable memory efficiency options
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
```

**Database Connection Pooling**:
```ini
# pgbouncer.ini - Vertical scaling

[pgbouncer]
# Increase for vertical scaling
max_client_conn = 2000
default_pool_size = 100
min_pool_size = 50
reserve_pool_size = 20

# Per-database
[databases]
code_server = host=localhost port=5432 dbname=code_server
```

### 3. I/O Optimization

**Storage Configuration**:
```bash
# Check I/O scheduler (should be 'none' for NVMe, 'mq-deadline' for HDD)
cat /sys/block/sda/queue/scheduler

# Set I/O scheduler
echo 'none' | sudo tee /sys/block/nvme0n1/queue/scheduler

# Check I/O performance
fio --name=test --filename=/data/test --rw=read --size=10G --bs=4k

# Enable writeback caching
echo 'on' | sudo tee /proc/sys/vm/dirty_writeback_centisecs

# Tune swappiness (prefer memory over swap)
sysctl -w vm.swappiness=10
```

**Kubernetes Storage Configuration**:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local-storage
provisioner: kubernetes.io/local-volume
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-nvme
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: fast-local-storage
  local:
    path: /mnt/nvme  # NVMe mount point
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: ["node-1"]
```

## Horizontal Scaling (Multi-Node Cluster)

### Cluster Architecture (3-Node Example)

```
┌─────────────────────────────────────────────────────────────┐
│                    Load Balancer                            │
│  (Nginx/Envoy - Round-robin or least-connections)          │
└──────┬──────────────┬──────────────┬──────────────────────┘
       │              │              │
       ▼              ▼              ▼
   ┌────────────┐ ┌────────────┐ ┌────────────┐
   │  Node 1    │ │  Node 2    │ │  Node 3    │
   │ 4cpu/8GB   │ │ 4cpu/8GB   │ │ 4cpu/8GB   │
   │            │ │            │ │            │
   │ code-srv:1,│ │code-srv:1, │ │code-srv:1, │
   │agent-api:1,│ │agent-api:1,│ │agent-api:1,│
   │embeddings:0│ │embeddings:0│ │embeddings:1│
   └────────────┘ └────────────┘ └────────────┘
       
      Shared Services:
        PostgreSQL (Master - Node 1, Replicas - Nodes 2,3)
        Redis (Cluster - all nodes)
        Prometheus (Node 1)
        Grafana (Node 2)
```

### Service Distribution Strategy

```yaml
# Code Server Distribution
code-server:
  replicas: 3
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app
              operator: In
              values: ["code-server"]
          topologyKey: kubernetes.io/hostname

# Agent API Distribution
agent-api:
  replicas: 3
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values: ["agent-api"]
        topologyKey: kubernetes.io/hostname

# Embeddings Distribution (resource-intensive)
embeddings:
  replicas: 2
  nodeSelector:
    instance-type: compute-optimized  # High-performance nodes
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values: ["embeddings"]
        topologyKey: kubernetes.io/hostname
```

### Multi-Node Redis Cluster

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-cluster-config
  namespace: code-server
data:
  redis-cluster.conf: |
    port 6379
    cluster-enabled yes
    cluster-config-file /data/nodes.conf
    cluster-node-timeout 15000
    
    # Replication
    replicaof-read-only yes
    
    # Memory and persistence
    maxmemory 2gb
    maxmemory-policy allkeys-lru
    save 900 1
    appendonly yes
    
    # Performance
    tcp-backlog 511
    timeout 0
    tcp-keepalive 300
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-cluster
  namespace: code-server
spec:
  serviceName: redis-cluster
  replicas: 3
  selector:
    matchLabels:
      app: redis-cluster
  template:
    metadata:
      labels:
        app: redis-cluster
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: client
        - containerPort: 16379
          name: gossip
        volumeMounts:
        - name: data
          mountPath: /data
        - name: config
          mountPath: /conf
          readOnly: true
        command:
        - redis-server
        - /conf/redis-cluster.conf
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 1000m
            memory: 2Gi
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      storageClassName: fast
      resources:
        requests:
          storage: 10Gi
```

### Load Balancing Strategy

**Round-Robin with Health Checks**:
```nginx
upstream code_server_backend {
    # Round-robin with health checks
    server code-server-pod-1:8443 max_fails=3 fail_timeout=30s;
    server code-server-pod-2:8443 max_fails=3 fail_timeout=30s;
    server code-server-pod-3:8443 max_fails=3 fail_timeout=30s;
    
    # Sticky sessions (optional, for WebSocket)
    hash $cookie_jsessionid consistent;
}

server {
    listen 443 ssl http2;
    server_name code-server.example.com;
    
    # SSL configuration...
    
    location / {
        proxy_pass https://code_server_backend;
        
        # Health check
        access_log /var/log/nginx/access.log;
        
        # Keep-alive
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        
        # Headers
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

**Least Connections Load Balancing**:
```nginx
upstream code_server_backend {
    least_conn;  # Route to pod with fewest connections
    
    server code-server-pod-1:8443;
    server code-server-pod-2:8443;
    server code-server-pod-3:8443;
}
```

### Database Replication (Multi-Node)

**PostgreSQL Streaming Replication**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql-primary
spec:
  template:
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_REPLICATION_MODE
          value: "master"
        - name: POSTGRES_REPLICATION_USER
          value: replicator
        volumeMounts:
        - name: pg-data
          mountPath: /var/lib/postgresql/data
        - name: pg-config
          mountPath: /etc/postgresql
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql-replica
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_REPLICATION_MODE
          value: "slave"
        - name: POSTGRES_MASTER_SERVICE
          value: postgresql-primary:5432
```

## Capacity Planning

### Vertical Scaling Capacity

```
Single Node Capacity (by CPU Core Count):

4 cores:     10-20 concurrent users, 100-200 RPS
8 cores:     50-100 concurrent users, 500-1000 RPS
16 cores:    200-300 concurrent users, 2000-3000 RPS
32 cores:    500-800 concurrent users, 5000-8000 RPS

(Depends on workload: AI inference is CPU-intensive)
```

### Horizontal Scaling Capacity

```
3-Node Cluster (3 x 4-core, 8GB each):
  - ~60-150 concurrent users
  - ~1500-3000 RPS
  - Service resilience with 1 node loss

5-Node Cluster (5 x 8-core, 16GB each):
  - ~300-500 concurrent users
  - ~5000-10000 RPS
  - Service resilience with 2 node loss

10-Node Cluster (10 x 8-core, 16GB each):
  - ~800-1200 concurrent users
  - ~15000-25000 RPS
  - Full HA with 3-node loss tolerance
```

## Auto-Scaling Configuration

### Vertical Auto-Scaling (within node limits)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: agent-api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: agent-api
  minReplicas: 2
  maxReplicas: 10  # Vertical limit on single node
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
```

### Horizontal Auto-Scaling (across nodes)
```yaml
# Same HPA configuration, but:
# - Cluster must support node auto-provisioning
# - Requires cluster autoscaler (on-premises: Kubernetes Autoscaler)
# - Max replicas set higher (50+)
```

## Monitoring Scaling Effectiveness

### Key Metrics

```promql
# HPA current vs desired replicas
kube_hpa_status_current_replicas vs kube_hpa_status_desired_replicas

# Pod resource utilization
rate(container_cpu_usage_seconds_total[5m]) / 
container_spec_cpu_cores * 100

# Request latency (should decrease with more replicas)
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Error rate (should stay low regardless of load)
rate(http_requests_total{status=~"5.."}[5m]) / 
rate(http_requests_total[5m]) * 100

# Node CPU/memory pressure
kube_node_status_allocatable / 
(kube_node_status_allocatable - kube_node_status_reserved)
```

## Scaling Decision Tree

```
START
  │
  ├─ Enough hardware for vertical?
  │  └─ YES: Use vertical scaling
  │     └─ Add CPU/RAM within node limits
  │     └─ Increase replicas per service
  │
  └─ NO: Ready for horizontal?
     └─ YES: Use horizontal scaling
        ├─ Add nodes to cluster
        ├─ Distribute services across nodes
        └─ Configure shared services (DB, cache)
     └─ NO: Optimize efficiency first
        └─ Implement caching (Phase 10)
        └─ Optimize queries (Phase 10)
        └─ Fine-tune resource requests
```

## Summary

**Vertical Scaling**: Best for up to 16-32 cores
- Single failure domain
- Simpler operations
- Lower latency communication
- Easier disaster recovery

**Horizontal Scaling**: For 16+ cores
- Distributed resilience
- Unlimited capacity (theoretically)
- More complex operations
- Higher latency communication (network)

**Hybrid**:
- Start vertical (single 4-core node)
- Expand vertically (8-16 cores)
- Add nodes horizontally when needed
- Typical sweet spot: 3-5 nodes of 8-16 cores each

---

**Phase 10**: Scaling Strategy  
**Status**: ✅ Complete  
**Next**: Optimization Guide
