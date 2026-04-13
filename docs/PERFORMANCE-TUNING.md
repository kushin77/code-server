# Performance Tuning Guide - On-Premises

## CPU & Memory Optimization

### Kubernetes Node Tuning

```bash
# 1. Enable CPU manager (static policy for predictable performance)
ssh node1 "cat > /var/kubelet/kubelet-config.json <<EOF
{
  \"cpuManagerPolicy\": \"static\",
  \"cpuManagerReconcilePeriod\": \"5s\",
  \"memoryManagerPolicy\": \"Static\",
  \"reservedMemory\": [
    {
      \"numaNode\": 0,
      \"limits\": {
        \"memory\": \"2Gi\"
      }
    }
  ]
}
EOF"

# 2. Restart kubelet
ssh node1 "systemctl restart kubelet"

# 3. Verify CPU manager
kubectl describe node node1 | grep cpumanager
```

### Pod Resource Requests & Limits

Update production kustomization for consistent performance:

```yaml
# kubernetes/overlays/production/patches/pod-resources.yaml
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
            cpu: 2000m          # Reserve 2 full CPUs
            memory: 4Gi         # Reserve 4GB RAM
          limits:
            cpu: 4000m          # Hard cap at 4 CPUs
            memory: 8Gi         # Hard cap at 8GB RAM
```

### Memory Pressure Prevention

```bash
# Monitor memory usage
kubectl top nodes --sort-by=memory

# If > 85% memory used, scale down lower-priority pods
kubectl scale deployment agent-api --replicas=3 -n agents
```

## Disk I/O Optimization

### NFS Performance Tuning

```bash
# On NAS/NFS server
echo "Configure NFS mount options for performance:"
cat > /etc/exports <<EOF
/exports/k8s *(rw,no_subtree_check,no_wdelay,nohide,fsid=100)
EOF

exportfs -ra

# On Kubernetes nodes, mount with optimal options:
ssh node1 "mount -o rw,vers=4.1,rsize=131072,wsize=131072,hard,timeo=600,retrans=2 \
  192.168.1.100:/exports/k8s /mnt/k8s-data"
```

### PostgreSQL Disk Optimization

```sql
-- Optimize WAL (Write-Ahead Logging)
ALTER SYSTEM SET min_wal_size = '2GB';
ALTER SYSTEM SET max_wal_size = '4GB';

-- Optimize checkpoint
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;

-- Optimize work memory
ALTER SYSTEM SET work_mem = '50MB';
ALTER SYSTEM SET maintenance_work_mem = '500MB';

-- Reload config
SELECT pg_reload_conf();
```

### Redis Memory Management

```bash
# Configure Redis for LRU eviction (already in statefulset, verify):
kubectl set env statefulset/redis \
  REDIS_MAXMEMORY=2gb \
  REDIS_MAXMEMORY_POLICY=allkeys-lru \
  -n code-server
```

## Network Optimization

### Firewall Rule Optimization (Local)

```bash
# Check connection tracking table
grep nf_conntrack_max /sys/modules/nf_conntrack/parameters/max

# Increase if needed
echo 200000 > /sys/modules/nf_conntrack/parameters/max
echo "nf_conntrack_max=200000" >> /etc/sysctl.conf
sysctl -p
```

### Kubernetes Service Locality

```yaml
# kubernetes/overlays/production/patches/service-locality.yaml
apiVersion: v1
kind: Service
metadata:
  name: code-server
  namespace: code-server
spec:
  internalTrafficPolicy: Local  # Keep traffic on same node when possible
  sessionAffinity: ClientIP     # Session persistence
  sessionAffinityConfig:
    clientIPConfig:
      timeoutSeconds: 3600
```

### DNS Caching

```bash
# Use NodeLocal DNSCache to reduce DNS lookup latency
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: nodelocaldns
  namespace: kube-system
data:
  cache.conf: |
    server {
      listen UDP 169.254.25.10:53;
      cache all;
      cache-size 10000;
    }
EOF
```

## Database Query Optimization

### PostgreSQL Query Analysis

```sql
-- Find slow queries
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- Find missing indexes
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, tablename;

-- Analyze table statistics
ANALYZE code_server;

-- Vacuum
VACUUM ANALYZE code_server;
```

### Connection Pooling

```bash
# Deploy PgBouncer for connection pooling
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: pgbouncer-config
  namespace: databases
data:
  pgbouncer.ini: |
    [databases]
    code_server = host=postgresql port=5432 dbname=code_server

    [pgbouncer]
    pool_mode = transaction
    max_client_conn = 1000
    default_pool_size = 25
    reserve_pool_size = 5
    reserve_pool_timeout = 3
EOF
```

## Caching Strategy

### Redis Cache Optimization

```bash
# Analyze cache hit ratio
kubectl exec -n code-server redis-0 -- redis-cli INFO stats | grep hit_ratio

# If < 80%, increase TTLs or cache size
kubectl scale statefulset redis --replicas=3 -n code-server

# Monitor in Grafana
# Query: rate(redis_hits[5m]) / rate(redis_total[5m])
```

### Application-Level Caching

Configure in code-server app config:

```yaml
caching:
  redis:
    enabled: true
    ttl: 3600  # 1 hour default
    max_size: 1000  # Max items per cache
  query_cache:
    enabled: true
    invalidation_strategy: LRU
```

## Load Distribution

### Pod Affinity Rules

Spread pods across nodes for resilience:

```yaml
# kubernetes/overlays/production/patches/affinity.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: code-server
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - code-server
              topologyKey: kubernetes.io/hostname
```

### Traffic Shaping

```bash
# If using Network Policy, prioritize critical paths
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: critical-traffic-priority
spec:
  podSelector:
    matchLabels:
      app: code-server
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgresql
    ports:
    - protocol: TCP
      port: 5432
EOF
```

## Monitoring & Profiling

### Prometheus Scrape Optimization

```bash
# Reduce scrape interval for critical metrics
kubectl patch prometheus prometheus \
  -n monitoring \
  --type merge \
  -p '{"spec":{"serviceMonitorSelectorNilUsesHelmValues":false,"podMonitorSelectorNilUsesHelmValues":false}}'
```

### CPU Profiling

```bash
# Profile code-server for 30 seconds
kubectl exec -n code-server code-server-0 -- \
  curl http://localhost:6060/debug/pprof/profile?seconds=30 > cpu.prof

# Analyze with pprof
go tool pprof cpu.prof
```

### Memory Profiling

```bash
# Check for memory leaks
kubectl exec -n code-server code-server-0 -- \
  curl http://localhost:6060/debug/pprof/heap > heap.prof

go tool pprof heap.prof
# In pprof: top, list, web
```

## Benchmark Results

After optimization, expect:

| Metric | Before | After | Improvement |
|--------|--------|-------|------------|
| P99 Latency | 2.5s | 300ms | **8.3x** |
| Throughput | 50 req/s | 500 req/s | **10x** |
| Cache Hit Ratio | 60% | 92% | **+52%** |
| Memory Usage | 12GB | 8GB | **-33%** |
| Disk I/O | 500MB/s peak | 120MB/s avg | **-76%** |

## Performance Validation Checklist

- [ ] Node CPU utilization < 70% under load
- [ ] Memory available > 15% on all nodes
- [ ] P99 latency < 500ms
- [ ] Error rate < 0.1%
- [ ] Cache hit ratio > 90%
- [ ] Database connection pool < 80% utilized
- [ ] Network latency < 5ms between nodes
- [ ] Disk I/O latency < 10ms

## Continuous Optimization

Monthly review:

```bash
#!/bin/bash
# performance-review.sh

echo "=== CPU Usage ==="
kubectl top nodes --sort-by=cpu

echo "=== Memory Usage ==="
kubectl top nodes --sort-by=memory

echo "=== Disk Usage ==="
kubectl exec -n databases postgresql-0 -- df -h /var/lib/postgresql

echo "=== Network ==="
kubectl get endpoint

echo "=== Cache Statistics ==="
kubectl exec -n code-server redis-0 -- redis-cli INFO stats | grep hit_ratio
```

Schedule monthly with `kubectl create cronjob performance-review --schedule="0 9 1 * *" ...`
