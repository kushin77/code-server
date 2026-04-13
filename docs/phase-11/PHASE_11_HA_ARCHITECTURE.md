# Phase 11: High Availability Architecture

**Document**: Detailed HA design for code-server
**Date**: April 13, 2026

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Application Layer HA](#application-layer-ha)
3. [Data Layer HA](#data-layer-ha)
4. [Cache Layer HA](#cache-layer-ha)
5. [Service Discovery](#service-discovery)
6. [Load Balancing](#load-balancing)
7. [Network Design](#network-design)
8. [Failure Scenarios](#failure-scenarios)
9. [Configuration](#configuration)
10. [Monitoring](#monitoring)

## Architecture Overview

### HA Principles

The Phase 11 HA architecture follows these principles:

1. **Redundancy**: Every component has replicas (N+2 redundancy for critical paths)
2. **Automatic Failover**: Manual intervention not required for planned failures
3. **No Single Point of Failure**: SPOF elimination everywhere
4. **Health-Driven Routing**: Load balancers route only to healthy instances
5. **Graceful Degradation**: System continues at reduced capacity during failures
6. **Transparent to Clients**: Failures are invisible to API consumers

### Component Redundancy Matrix

| Component | Instances | Replication | Failover | RTO |
|-----------|-----------|------------|----------|-----|
| code-server app | 3+ | N/A (stateless) | Automatic | <5s |
| PostgreSQL primary | 1 | 2 streaming | Automatic | <30s |
| PostgreSQL standby | 1 | From primary | Manual | N/A |
| Redis master | 3 (cluster) | Per master | Automatic | <10s |
| Redis replica | 3 (cluster) | Per master | N/A | N/A |
| HAProxy/Caddy | 2+ | VIP failover | Automatic | <5s |
| Consul | 3+ | Raft consensus | Automatic | <10s |

## Application Layer HA

### Stateless Design

Code-server is designed as stateless:
- No local session state
- All sessions in Redis (shared)
- All data in PostgreSQL (shared)
- Can be restarted without impact

### Node Deployment

**Kubernetes StatelessSet**:
```yaml
apiVersion: apps/v1
kind: StatelessSet
metadata:
  name: code-server
spec:
  replicas: 3
  serviceName: code-server
  selector:
    matchLabels:
      app: code-server
  template:
    metadata:
      labels:
        app: code-server
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - code-server
            topologyKey: kubernetes.io/hostname
      containers:
      - name: code-server
        image: code-server:phase-11
        ports:
        - containerPort: 8080
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2
        resources:
          requests:
            cpu: 1000m
            memory: 2Gi
          limits:
            cpu: 2000m
            memory: 4Gi
        env:
        - name: REDIS_URL
          value: "redis://redis-cluster:6379"
        - name: DATABASE_URL
          value: "postgresql://user:pass@postgres-primary:5432/code-server"
        - name: CIRCUIT_BREAKER_ENABLED
          value: "true"
```

### Pod Disruption Budgets (PDB)

Ensures minimum availability during maintenance:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: code-server-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: code-server
```

### Probes

**Liveness Probe** (restarts dead pods):
- Path: `/health`
- Interval: 10s
- Timeout: 5s
- Failure threshold: 3

**Readiness Probe** (removes from LB):
- Path: `/ready`
- Interval: 5s
- Timeout: 3s
- Failure threshold: 2

### Circuit Breakers

Code-server integrates circuit breaker pattern:

```typescript
// Protect database calls
const result = await resilience.executeProtected(
  'database.query',
  () => db.query('SELECT ...')
);

// Protect cache operations
const cached = await resilience.executeProtected(
  'cache.get',
  () => redis.get('key')
);
```

**Circuit Breaker States**:
- **Closed**: Normal operation, all requests pass through
- **Open**: Failures detected, requests rejected immediately
- **Half-Open**: Testing recovery, limited requests allowed

**Failure Thresholds**:
- Database: 5 failures in 60s window
- Cache: 10 failures in 60s window
- External APIs: 3 failures in 30s window

## Data Layer HA

### PostgreSQL Architecture

**Multi-node Setup**:
```
Primary (Read/Write)
  ↓ Streaming Replication
Replica 1 (Read-only)
  ↓ Cascading Replication
Replica 2 (Read-only)
```

**Streaming Replication Configuration**:
```ini
# postgresql.conf (primary)
wal_level = replica
max_wal_senders = 3
wal_keep_size = 1GB
hot_standby = on

# synchronous_commit settings
synchronous_commit = on  # Ensure replicas sync before ACK
synchronous_standby_names = 'standby1,standby2'

# Continuous archiving for PITR
archive_mode = on
archive_command = 'test ! -f /backup/wal_archive/%f && cp %p /backup/wal_archive/%f'
archive_timeout = 300
```

### Automatic Failover

Using Patroni for automatic failover:

```yaml
# Patroni config
scope: code-server-cluster
name: pg-primary

postgresql:
  data_dir: /var/lib/postgresql/data
  bin_dir: /usr/lib/postgresql/13/bin
  listen: 0.0.0.0:5432
  connect_address: primary.postgres.local:5432

  parameters:
    wal_level: replica
    max_wal_senders: 10
    hot_standby: 'on'
    synchronous_commit: 'on'

etcd:
  host: consul-cluster:2379

ttl: 30
loop_wait: 10
maximum_lag_on_failover: 1048576

failsafe:
  enabled: true
  max_followers: 2
  reset_members:
    - leader
```

**Failover Trigger**:
When primary is unreachable for 30s (configurable):
1. Patroni detects failure via health check
2. Replicas vote on new primary
3. Highest LSN replica becomes primary
4. Other replicas reconnect to new primary
5. Applications resume via connection pool

### Point-in-Time Recovery (PITR)

**WAL Archiving**:
```bash
# Continuous WAL archiving to S3
archive_command = 'aws s3 cp %p s3://backups/wal/%f && sleep 0'

# PITR window: 30 days
# Can restore to any point in last 30 days
```

**Restore Procedure**:
```bash
# Create new cluster from backup
pg_basebackup -h primary -D /var/lib/postgresql/data -Ft -Pv

# Place WAL archive list
recovery_target_timeline = 'latest'
recovery_target_time = '2026-04-13 10:15:00'

# Restore to specific point
pg_ctl start
```

### Backup Strategy

**Daily Full Backup**:
```bash
#!/bin/bash
# Execute at 2:00 AM UTC

# Full backup to local storage
pg_basebackup -h primary -D /backups/full/$(date +%Y%m%d) \
  -F tar -x -P

# Compress and upload to S3
cd /backups/full/
tar czf - $(date +%Y%m%d) | aws s3 cp - \
  s3://backups/postgresql/full/$(date +%Y%m%d).tar.gz

# Verify checksum
sha256sum $(date +%Y%m%d)/* > checksums.txt
aws s3 cp checksums.txt s3://backups/postgresql/full/
```

**Incremental Backup** (hourly):
```bash
# Via WAL archiving - continuous
# ~1 MB per second of WAL
# Retention: 7 days on primary, 30 days off-site
```

## Cache Layer HA

### Redis Cluster Architecture

**Cluster Configuration** (6 nodes, 3 masters + 3 replicas):

```
Master 0 (Slots 0-5460) → Replica 0
  ├─ Handles keys: {user:*, session:*}
  └─ ~30% of cache

Master 1 (Slots 5461-10922) → Replica 1
  ├─ Handles keys: {cache:*, embedding:*}
  └─ ~35% of cache

Master 2 (Slots 10923-16383) → Replica 2
  ├─ Handles keys: {feature:*, index:*}
  └─ ~35% of cache
```

**Redis Cluster Configuration**:
```
port 6379
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 15000
appendonly yes
appendfsync everysec
cluster-require-full-coverage no
replica-serve-stale-data yes
```

### Connection Pooling

**Application Connection Pool**:
```python
# Using redis-py with cluster support
from rediscluster import RedisCluster

redis = RedisCluster(
    startup_nodes=[
        {'host': 'redis-0.redis', 'port': 6379},
        {'host': 'redis-1.redis', 'port': 6379},
        {'host': 'redis-2.redis', 'port': 6379},
    ],
    decode_responses=True,
    skip_full_coverage_check=True,
    connection_pool_class=BlockingConnectionPool,
    connection_pool_config={
        'max_connections': 50,
        'timeout': 5,
    }
)
```

**Connection Pooling Features**:
- Max connections: 50 per node
- Timeout: 5 seconds
- Automatic reconnect on failure
- Exponential backoff for retries

### Failover Behavior

When a Redis master fails:

1. **Detection**: Sentinel monitors detect failure (5-10s)
2. **Consensus**: Sentinels vote on promotion (5s)
3. **Promotion**: Replica becomes master
4. **Recovery**: Failed master comes back as replica
5. **Application**: Cluster topology update via gossip (100ms)

## Service Discovery

### Consul Integration

**Service Registration**:
```json
{
  "service": {
    "id": "code-server-1",
    "name": "code-server",
    "address": "192.168.1.10",
    "port": 8080,
    "tags": ["v1", "primary"],
    "check": {
      "http": "http://192.168.1.10:8080/health",
      "interval": "5s",
      "timeout": "3s",
      "deregister_critical_service_after": "30s"
    }
  }
}
```

**Health Check Details**:
- Interval: 5 seconds
- Timeout: 3 seconds
- Critical threshold: 6 failed checks (30s total)
- Auto-deregister after 30s of critical state

### DNS Interface

Applications can use DNS directly:
```
code-server.service.consul  → Load balanced IP
code-server-1.service.consul → Specific node
postgres-primary.service.consul → Master node
postgres.service.consul → Any replica (read-only)
```

## Load Balancing

### HAProxy Configuration

**Frontend (Client-facing)**:
```haproxy
global
  maxconn 4096
  daemon

defaults
  mode http
  timeout connect 5000ms
  timeout client 50000ms
  timeout server 50000ms

frontend code-server-frontend
  bind *:80
  bind *:443 ssl crt /etc/ssl/cert.pem
  default_backend code-server-backend

  # Redirect HTTP to HTTPS
  http-request redirect scheme https code 301 if !{ ssl_fc }

  # Add tracing headers
  http-request set-header X-Request-ID %[rand,hex,bytes(16)]
  http-request set-header X-Forwarded-For %[src]

backend code-server-backend
  balance roundrobin
  option httpchk GET /health

  # Health check parameters
  default-server inter 5s fall 3 rise 2

  # Backend servers
  server app1 10.0.1.10:8080 check
  server app2 10.0.1.11:8080 check
  server app3 10.0.1.12:8080 check

  # Remove unhealthy servers
  option forwardfor
  http-reuse safe
```

### Sticky Sessions

For WebSocket connections:
```haproxy
backend websocket-backend
  balance source  # Source IP-based persistence
  cookie SERVERID insert indirect nocache
  server app1 10.0.1.10:8080 check cookie app1
  server app2 10.0.1.11:8080 check cookie app2
  server app3 10.0.1.12:8080 check cookie app3
```

## Network Design

### VPC Architecture

```
VPC (10.0.0.0/16)
├── Public Subnet (10.0.1.0/24) - Bastion hosts
├── Private Subnet A (10.0.2.0/24) - code-server nodes
├── Private Subnet B (10.0.3.0/24) - PostgreSQL primary
├── Private Subnet C (10.0.4.0/24) - Redis cluster
└── Private Subnet D (10.0.5.0/24) - PostgreSQL replicas
```

### Security Groups

**Load Balancer SG**:
- Inbound: 80/tcp, 443/tcp (from anywhere)
- Outbound: 8080/tcp (to app servers)

**Application Server SG**:
- Inbound: 8080/tcp (from LB), 22/tcp (from bastion)
- Outbound: 5432/tcp (PostgreSQL), 6379/tcp (Redis)

**Database SG**:
- Inbound: 5432/tcp (from app servers)
- Outbound: None

**Redis SG**:
- Inbound: 6379/tcp (from app servers), 16379/tcp (cluster bus)
- Outbound: None

## Failure Scenarios

### Scenario 1: Single App Server Failure

**Failure Detection**: 10s (2 failed health checks)
**Auto-Recovery**: Yes (restart pod)
**Impact**: None (2remaining app servers handle traffic)
**User Impact**: Transparent

### Scenario 2: Load Balancer Failure

**Failover**: 5s
**Method**: HAProxy VIP failover to secondary LB
**Impact**: Brief DNS resolution delay
**User Impact**: <2s latency spike

### Scenario 3: PostgreSQL Primary Failure

**Detection**: 30s
**Failover**: Automatic replica promotion
**Recovery Time**: 30-45s
**Data Loss**: 0 (synchronous replication)
**User Impact**: Brief connection errors (app retry)

### Scenario 4: PostgreSQL Replica Failure

**Detection**: 10s
**Impact**: Reduced read capacity
**Auto-Recovery**: No (manual intervention)
**User Impact**: None (reads redirect to primary)

### Scenario 5: Redis Master Failure

**Detection**: 5-10s (Sentinel detection)
**Failover**: Sentinel promot replica
**Recovery**: 10-15s
**Data Loss**: ~1-2% (recently added keys)
**User Impact**: Transparent (cache miss leads to DB query)

### Scenario 6: Entire DC Failure

**Detection**: 60s (multiple failures detected)
**Failover**: All traffic → Standby DC
**Recovery Time**: 30 minutes (failover window)
**Data Loss**: < 15 minutes (based on last backup + WAL replay)
**User Impact**: 30-minute outage

## Configuration

### Environment Variables

```bash
# HA-specific settings
HA_ENABLED=true
NODE_NAME=${HOSTNAME}
CONSUL_HOST=consul-cluster:8500
CONSUL_SERVICE_NAME=code-server

# Circuit breaker settings
CIRCUIT_BREAKER_ENABLED=true
CIRCUIT_BREAKER_DATABASE_THRESHOLD=5
CIRCUIT_BREAKER_DATABASE_RESET_TIMEOUT=30000
CIRCUIT_BREAKER_CACHE_THRESHOLD=10
CIRCUIT_BREAKER_CACHE_RESET_TIMEOUT=10000

# Database replication
DB_REPLICA_ENABLED=true
DB_REPLICA_HOST=postgres-replica:5432
DB_REPLICA_READONLY=true

# Cache cluster
REDIS_CLUSTER_ENABLED=true
REDIS_CLUSTER_NODES=redis-0,redis-1,redis-2
REDIS_CONNECTION_POOL_SIZE=50
REDIS_FAILOVER_ENABLED=true
```

### Kubernetes ConfigMap

```yaml
apiVersion: v1kind: ConfigMap
metadata:
  name: code-server-ha-config
data:
  ha-config.json: |
    {
      "ha": {
        "enabled": true,
        "nodeCount": 3,
        "healthCheckInterval": 5000,
        "failureThreshold": 3
      },
      "database": {
        "primary": "postgres-primary:5432",
        "replicas": ["postgres-replica-1:5432", "postgres-replica-2:5432"],
        "replication": "streaming",
        "syncCommit": true
      },
      "cache": {
        "cluster": {
          "enabled": true,
          "nodes": ["redis-0:6379", "redis-1:6379", "redis-2:6379"]
        },
        "failover": true
      },
      "circuitBreaker": {
        "enabled": true,
        "database": {
          "threshold": 5,
          "resetTimeout": 30000,
          "monitoringWindow": 60000
        }
      }
    }
```

## Monitoring

### Key Metrics

**Application Level**:
- Active connection count (per node)
- Request latency (p50, p95, p99)
- Error rate (per endpoint)
- Circuit breaker state (open/closed)

**Database Level**:
- Replication lag (should be <100ms)
- Active connections (per replica)
- Query latency (slow query log)
- WAL archive rate

**Cache Level**:
- Key eviction rate
- Hit/miss ratio (should be >90%)
- Memory usage (per node)
- Cluster rebalancing events

**Infrastructure Level**:
- CPU utilization
- Memory utilization
- Disk I/O
- Network throughput

### Alert Rules

```yaml
groups:
- name: ha-alerts
  rules:
  - alert: HighReplicationLag
    expr: pg_replication_lag_bytes > 10485760  # 10MB
    for: 5m
    annotations:
      summary: "PostgreSQL replication lag > 10MB"

  - alert: CircuitBreakerOpen
    expr: circuit_breaker_open == 1
    for: 1m
    annotations:
      summary: "Service circuit breaker is open"

  - alert: RedisClusterUnhealthy
    expr: redis_cluster_healthy_nodes < 4
    for: 30s
    annotations:
      summary: "Redis cluster degraded"

  - alert: AppServerDown
    expr: up{job="code-server"} == 0
    for: 10s
    annotations:
      summary: "Application server is down"
```

---

**Status**: Complete
**Last Updated**: April 13, 2026
