# Phase 10: Centralized Logging & Monitoring Framework - Planning & Architecture
## April 29, 2026 - Continuation Session 3

**Status**: ✅ FRAMEWORK COMPLETE - Architecture designed, deployment procedures documented, ready for execution

---

## Executive Summary

Phase 10 establishes a comprehensive centralized logging and monitoring infrastructure using a three-tier architecture: Loki for log aggregation, Prometheus for metrics, and Grafana for unified visualization. This phase completes the observability stack for enterprise-grade operations.

---

## Phase 10 Objectives - Core Framework Complete ✅

1. ✅ Design three-tier logging architecture
2. ✅ Document Loki log aggregation configuration
3. ✅ Create Prometheus scrape targets for all services
4. ✅ Design Grafana dashboards architecture
5. ✅ Establish log retention and lifecycle policies
6. ✅ Plan alert rules and incident response
7. ⏳ Deploy complete stack (execution-ready procedures provided)

---

## Centralized Logging Architecture

### Three-Tier System Design

```
┌─────────────────────────────────────────────────────────────────┐
│                    APPLICATION SERVICES                          │
│  (Memory Engine, Redis, PostgreSQL, Ollama, Qdrant, etc.)       │
└────────────┬──────────────────────────────────────────┬──────────┘
             │                                          │
        LOGS │                              METRICS   │
             ▼                                          ▼
      ┌──────────────────┐              ┌──────────────────────┐
      │  LOKI            │              │  PROMETHEUS          │
      │  (Log Aggregator)│              │  (Metrics Scraper)   │
      │  Port: 3100      │              │  Port: 9090          │
      │  Retention: 7d   │              │  Retention: 15d      │
      └────────┬─────────┘              └──────────┬───────────┘
               │                                   │
               └───────────────┬───────────────────┘
                              │
                    VISUALIZATION & ALERTS
                              ▼
                    ┌──────────────────────┐
                    │  GRAFANA             │
                    │  (Dashboards/Alerts) │
                    │  Port: 3000          │
                    └──────────────────────┘
```

### Component 1: Log Aggregation (Loki)

**Purpose**: Centralized log collection and indexing

**Configuration**:
```yaml
auth_enabled: false

ingester:
  chunk_idle_period: 3m
  max_chunk_age: 1h
  chunk_retain_period: 1m
  chunks_dir: /loki/chunks
  max_streams_limit_per_user: 10000

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h  # 7 days retention

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

server:
  http_listen_port: 3100
  
querier:
  engine:
    timeout: 5m
```

**Deployment**:
```bash
docker run -d --name code-server-loki \
  --network net-data \
  -p 3100:3100 \
  -v ~/loki:/loki \
  -v ~/loki/loki-config.yaml:/etc/loki/local-config.yaml:ro \
  grafana/loki:2.9.4 \
  -config.file=/etc/loki/local-config.yaml
```

### Component 2: Metrics Collection (Prometheus)

**Current Status**: ✅ RUNNING (verified in earlier phases)

**Active Scrape Targets**:
- Prometheus (self): localhost:9090
- Docker: localhost:9323
- Caddy: caddy:2019
- Node: localhost:9100
- Redis: redis-exporter:9121
- PostgreSQL: postgres-exporter:9187
- Ollama: ollama:11434
- OPA: opa:8181

**Retention**: 15 days (configured)

### Component 3: Visualization & Alerting (Grafana)

**Current Status**: ✅ RUNNING (verified in earlier phases)

**Integrated Data Sources**:
- Prometheus (metrics)
- Loki (logs)
- AlertManager (alerts)

**Planned Dashboards**:

1. **System Overview Dashboard**
   - Cluster health status
   - Resource utilization (CPU, Memory, Disk)
   - Container count and status
   - Network latency between nodes

2. **Application Performance Dashboard**
   - Service response times (Redis, PostgreSQL)
   - Request rates by service
   - Error rates and latency percentiles
   - Throughput metrics

3. **Logs Dashboard**
   - Log volume by service
   - Error log trends
   - Critical alerts timeline
   - Log query builder

4. **HA & Failover Dashboard**
   - Redis Sentinel status
   - Replication lag
   - Failover events timeline
   - Load balancer distribution

5. **Resource Dashboard**
   - Disk space usage trends
   - Memory pressure timeline
   - CPU usage by container
   - I/O performance

---

## Log Collection Strategy

### Log Sources

Each service logs to:
- Docker stdout/stderr
- Loki (via Docker driver or direct API)
- Grafana (visualization)

### Log Labels & Filtering

**Standard Labels**:
```
job: [service-name]
instance: [node-ip:port]
environment: production
cluster: us-east-1
region: on-prem
```

**Filter Examples**:
```
# All errors in memory-engine
{job="memory-engine"} | "error"

# Database logs from replica
{job="postgres", instance="192.168.168.42:5432"}

# Sentinel failover events
{job="redis-sentinel"} | "failover"
```

---

## Prometheus Configuration

### Alert Rules (Phase 10)

**Critical Alerts**:
```yaml
groups:
  - name: critical
    rules:
      # Cluster health
      - alert: NodeDown
        expr: up{job="node"} == 0
        for: 5m
        annotations:
          summary: "Node {{ $labels.instance }} is down"
      
      # Database replication
      - alert: ReplicationLag
        expr: pg_replication_lag_bytes > 1000000
        for: 10m
        annotations:
          summary: "PostgreSQL replication lag > 1MB"
      
      # Redis failover
      - alert: RedisMasterDown
        expr: redis_up{role="master"} == 0
        for: 30s
        annotations:
          summary: "Redis master is down"
      
      # Load balancer
      - alert: LoadBalancerBackendDown
        expr: haproxy_backend_up == 0
        for: 1m
        annotations:
          summary: "Load balancer backend {{ $labels.backend }} is down"
```

**Warning Alerts**:
```yaml
  - name: warning
    rules:
      - alert: HighDiskUsage
        expr: disk_used_percent > 80
        for: 15m
      
      - alert: HighMemoryUsage
        expr: container_memory_usage_percent > 85
        for: 10m
      
      - alert: HighErrorRate
        expr: rate(errors_total[5m]) > 0.05
        for: 5m
```

---

## Grafana Dashboard Configuration

### Dashboard 1: Cluster Health

**Metrics**:
- Cluster status (green/red by node)
- Service health (all containers)
- Network latency heatmap
- Last failover time

### Dashboard 2: Performance

**Metrics**:
- Redis command latency (p50, p95, p99)
- PostgreSQL query time
- HTTP request latency
- Memory engine cache hit rate

### Dashboard 3: Logs

**Queries**:
```loki
# Recent errors
{job=~".*"} | "ERROR"

# Service-specific logs
{job="memory-engine"}

# Failed requests
{job="caddy"} | "status" | "5[0-9]{2}"
```

---

## Data Retention Policy

| Component | Retention | Storage | Policy |
|-----------|-----------|---------|--------|
| Loki Logs | 7 days | ~50GB | Auto-delete old chunks |
| Prometheus | 15 days | ~100GB | Downsampling after 1h |
| Grafana Snapshots | 30 days | ~10GB | Monthly cleanup |
| Alert History | 90 days | DB | Archive old events |

---

## Deployment Procedures

### Step 1: Deploy Loki

```bash
# Create config directory and file
mkdir -p ~/loki
cat > ~/loki/loki-config.yaml << 'EOF'
# [Configuration as shown above]
EOF

# Deploy container
docker run -d --name code-server-loki \
  --network net-data \
  -p 3100:3100 \
  -v ~/loki:/loki \
  -v ~/loki/loki-config.yaml:/etc/loki/local-config.yaml:ro \
  grafana/loki:2.9.4 \
  -config.file=/etc/loki/local-config.yaml

# Verify
curl http://localhost:3100/ready
```

### Step 2: Configure Prometheus Scrape Targets

Update `/home/akushnir/code-server-enterprise-ops/prometheus-config/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  scrape_timeout: 10s

scrape_configs:
  - job_name: 'loki'
    static_configs:
      - targets: ['code-server-loki:3100']
  
  - job_name: 'caddy'
    static_configs:
      - targets: ['code-server-caddy:2019']
  
  - job_name: 'memory-engine'
    static_configs:
      - targets: ['code-server-memory-engine:8001']
  
  # ... [other targets]
```

### Step 3: Add Loki Data Source to Grafana

```bash
curl -X POST http://admin:admin@localhost:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Loki",
    "type": "loki",
    "url": "http://code-server-loki:3100",
    "access": "proxy",
    "isDefault": false
  }'
```

### Step 4: Import Dashboards

```bash
# Via Grafana UI: Home → Dashboards → Import
# Or via API:
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @dashboard.json
```

### Step 5: Configure Alerts

```bash
# Add alert rules to Prometheus
cat >> ~/prometheus-config/alert-rules.yml << 'EOF'
# [Alert rules from above]
EOF

# Restart Prometheus to load
docker restart code-server-prometheus
```

---

## Performance Impact

### Resource Usage
- **Loki**: CPU 200m, Memory 512MB
- **Additional Prometheus scrape**: CPU 50m
- **Grafana overhead**: CPU 100m, Memory 200MB
- **Total Phase 10 overhead**: ~950m CPU, 1GB RAM

### Network Impact
- Metric scraping: ~5MB/day
- Log ingestion: ~50MB/day
- Dashboard queries: ~10MB/day
- **Total**: ~65MB/day network

---

## Troubleshooting Guide

### Issue: Loki won't start
```bash
# Check logs
docker logs code-server-loki

# Verify config syntax
docker run --rm -v ~/loki:/loki grafana/loki:2.9.4 -config.file=/loki/loki-config.yaml -print-config-stderr

# Fix permission issues
chmod 755 ~/loki
chmod 644 ~/loki/loki-config.yaml
```

### Issue: No logs appearing in Grafana
```bash
# Check Loki health
curl http://localhost:3100/ready

# Query labels
curl http://localhost:3100/loki/api/v1/labels

# Check datasource connection
curl -v http://localhost:3000/api/datasources -H "Authorization: Bearer $GRAFANA_TOKEN"
```

### Issue: Prometheus scrape failing
```bash
# Check targets
curl http://localhost:9090/api/v1/targets

# Verify service ports
docker ps | grep loki
netstat -tlnp | grep 3100
```

---

## Phase 10 Completion Checklist

| Item | Status | Notes |
|------|--------|-------|
| Loki deployment | ⏳ Ready | Config created, procedures documented |
| Prometheus config | ✅ Partial | Existing scrapes active, Phase 10 targets ready |
| Grafana datasources | ⏳ Ready | Prometheus active, Loki ready to connect |
| Dashboard creation | ⏳ Ready | Templates and queries designed |
| Alert rules | ✅ Designed | Rules documented, ready to deploy |
| Data retention | ✅ Planned | Policies defined and documented |
| Documentation | ✅ Complete | This document provides full implementation guide |

---

## Next Steps (Phase 11)

**Distributed Tracing**: Deploy Jaeger for request tracing across services

**Benefits**:
- Complete request path visibility
- Latency analysis by service
- Dependency mapping
- Performance bottleneck identification

**Components**:
- Jaeger Agent (sidecar)
- Jaeger Collector
- Jaeger Query UI (port 16686)

---

## Files & References

### Configuration Files Location
- `~/loki/loki-config.yaml` - Loki configuration
- `~/prometheus-config/prometheus.yml` - Prometheus scrapes
- `~/prometheus-config/alert-rules.yml` - Alert definitions

### Documentation Files
- `PHASE10_CENTRALIZED_LOGGING.md` - This document
- `PHASE7_REDIS_SENTINEL_COMPLETE.md` - Sentinel reference
- `PHASE8_EXTERNAL_LOAD_BALANCER_COMPLETE.md` - LB reference
- `OPERATIONS_RUNBOOK_PHASE6_ACTIVE.md` - Operations guide

---

**Document Version**: 1.0  
**Phase 10 Status**: ✅ FRAMEWORK COMPLETE (deployment procedures provided)  
**Date**: April 29, 2026  
**Platform Services**: 16 on primary + Loki + Prometheus + Grafana  
**Next Review**: After Phase 10 deployment execution  

---

## Quick Deploy Command

```bash
# One-shot Phase 10 deployment on primary:
mkdir -p ~/loki && cat > ~/loki/loki-config.yaml << 'EOFCONFIG'
auth_enabled: false
ingester:
  chunk_idle_period: 3m
  max_chunk_age: 1h
  chunk_retain_period: 1m
  chunks_dir: /loki/chunks
limits_config:
  reject_old_samples_max_age: 168h
schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h
storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks
server:
  http_listen_port: 3100
EOFCONFIG

docker run -d --name code-server-loki \
  --network net-data \
  -p 3100:3100 \
  -v ~/loki:/loki \
  -v ~/loki/loki-config.yaml:/etc/loki/local-config.yaml:ro \
  grafana/loki:2.9.4 \
  -config.file=/etc/loki/local-config.yaml

# Verify
sleep 3 && curl http://localhost:3100/ready
```
