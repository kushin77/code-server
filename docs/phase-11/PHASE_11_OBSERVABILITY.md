# Phase 11: Advanced Observability

**Document**: Observability strategy for production systems
**Date**: April 13, 2026

## Overview

Phase 11 observability enables operators to understand system behavior at scale through:
- **Distributed Tracing**: End-to-end request tracking
- **Metrics Correlation**: Link metrics to business impact
- **Anomaly Detection**: ML-driven issue identification
- **Observability Dashboards**: Real-time system health
- **Cost Attribution**: Understand resource usage per service

## Observability Stack

### Components

```
┌──────────────────────────────────────────────────────────┐
│              Application (code-server)                    │
│ - OpenTelemetry SDK for tracing                          │
│ - Prometheus client for metrics                          │
│ - Structured logging (JSON)                              │
└──────────────┬───────────────────────────────────────────┘
               │
     ┌─────────┼─────────┐
     │         │         │
     ▼         ▼         ▼
┌────────┐ ┌────────┐ ┌──────┐
│ Jaeger │ │Prometh │ │ Loki │
│(Traces)│ │eus    │ │(Logs)│
│        │ │(Metrics)
└────────┘ └────────┘ └──────┘
     │         │         │
     └─────────┼─────────┘
               │
               ▼
          ┌─────────────┐
          │   Grafana   │
          │ (Dashboards │
          │ & Alerting) │
          └─────────────┘
```

### Technology Stack

| Component | Purpose | Deployment |
|-----------|---------|------------|
| **Jaeger** | Distributed tracing | 1 collector + 1 UI (all-in-one) |
| **Prometheus** | Metrics collection | 1 primary + 1 sidecar (HA) |
| **Loki** | Log aggregation | 1 distributor + 3 queriers |
| **Grafana** | Visualization & alerting | 2 instances (HA) |
| **AlertManager** | Alert routing | 2 instances (HA) |
| **OpenTelemetry SDK** | Instrumentation | On all code-server instances |

## Distributed Tracing (Jaeger)

### Span Structure

Every request generates a trace with spans:

```
Trace: http-request-12345
├─ Span: api-gateway (10ms)
│  └─ Parent Span: code-server (8ms)
│     ├─ Span: auth-check (1ms)
│     │  └─ Tag: user-id=usr_xyz
│     │  └─ Tag: permission=admin
│     ├─ Span: database-query (4ms)
│     │  └─ Tag: query=SELECT...
│     │  └─ Log: rows=142
│     ├─ Span: cache-lookup (0.5ms)
│     │  └─ Tag: cache-hit=true
│     └─ Span: response-generation (2ms)
└─ Span: load-balancer (2ms)
```

### OpenTelemetry Integration

```typescript
// Instrumentation
import { NodeTracer } from '@opentelemetry/tracing';
import { JaegerExporter } from '@opentelemetry/exporter-jaeger';

const jaegerExporter = new JaegerExporter({
  endpoint: 'http://jaeger-collector:14268/api/traces',
});

const tracer = new NodeTracer({
  exporter: jaegerExporter,
  sampler: {
    shouldSample: (context) => {
      // Sample 10% of requests
      // Sample 100% of errors
      return context.traceFlags === 0 ? Math.random() < 0.1 : true;
    },
  },
});

// Automatic span creation
const span = tracer.startSpan('database-query', {
  attributes: {
    'db.system': 'postgresql',
    'db.statement': 'SELECT * FROM users WHERE id=?',
    'db.user': 'app_user',
  },
});

try {
  const result = await db.query('SELECT * FROM users WHERE id = ?', [id]);
  span.addEvent('query-complete', { 'rows': result.length });
} catch (error) {
  span.recordException(error);
} finally {
  span.end();
}
```

### Jaeger Deployment

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: jaeger-config
data:
  sampler.json: |
    {
      "default_strategy": {
        "type": "probabilistic",
        "param": 0.1
      },
      "service_strategies": [
        {
          "service": "code-server",
          "type": "probabilistic",
          "param": 0.5
        },
        {
          "service": "postgresql",
          "type": "const",
          "param": 1
        }
      ]
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jaeger
  template:
    metadata:
      labels:
        app: jaeger
    spec:
      containers:
      - name: jaeger
        image: jaegertracing/all-in-one:1.57.0
        ports:
        - containerPort: 6831
          protocol: UDP
        - containerPort: 16686
          protocol: TCP
        env:
        - name: COLLECTOR_ZIPKIN_HTTP_PORT
          value: "9411"
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
```

### Trace Analysis Queries

**Find slow operations**:
```sql
SELECT operation, AVG(duration) as avg_duration
  FROM spans
 WHERE duration > 100ms
 GROUP BY operation
 ORDER BY avg_duration DESC
```

**Find errors by service**:
```sql
SELECT service, COUNT(*)
  FROM spans
 WHERE error = true
 GROUP BY service
```

**Database query latency distribution**:
```sql
SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration)
  FROM spans
 WHERE operation = 'database-query'
```

## Metrics (Prometheus)

### Metric Types

| Type | Purpose | Example |
|------|---------|---------|
| **Counter** | Monotonically increasing | `http_requests_total` |
| **Gauge** | Point-in-time value | `memory_usage_bytes` |
| **Histogram** | Value distribution | `request_duration_seconds` |
| **Summary** | Quantile tracking | `query_latency_percentiles` |

### Key Metrics

```
# Application Metrics
http_requests_total{method="GET",path="/api/data",status="200"}
http_requests_duration_seconds{method="GET",path="/api/data",percentile="0.95"}
http_errors_total{method="GET",path="/api/data",status="500"}

# Database Metrics
db_connections_active{host="primary"}
db_query_duration_seconds{operation="SELECT",percentile="0.99"}
db_replication_lag_bytes{replica="standby-1"}

# Cache Metrics
redis_commands_processed{command="GET",status="hit"}
redis_memory_used_bytes{node="redis-0"}
redis_evictions_total{reason="lru"}

# Infrastructure Metrics
node_cpu_usage_percent
node_memory_usage_bytes
node_disk_io_reads_total
network_bandwidth_bytes{direction="in"}
```

### Prometheus Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        cluster: 'code-server-prod'
        environment: 'production'

    scrape_configs:
    - job_name: 'code-server'
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - default
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: code-server
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: node

    - job_name: 'postgresql'
      static_configs:
      - targets: ['postgres-primary:9187']
      - targets: ['postgres-replica-1:9187']
      - targets: ['postgres-replica-2:9187']

    - job_name: 'redis'
      static_configs:
      - targets: ['redis-0:9121']
      - targets: ['redis-1:9121']
      - targets: ['redis-2:9121']

    - job_name: 'kubernetes-nodes'
      kubernetes_sd_configs:
      - role: node
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
```

## Logs (Loki)

### Structured Logging

```json
{
  "timestamp": "2026-04-13T10:15:00Z",
  "level": "ERROR",
  "service": "code-server",
  "pod": "code-server-1",
  "node": "node-1",
  "request_id": "req_abc123",
  "user_id": "usr_xyz",
  "message": "Database query failed",
  "error": "connection refused",
  "query": "SELECT * FROM users WHERE id = ?",
  "duration_ms": 5000,
  "retry_attempt": 2
}
```

### Loki Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
data:
  loki-config.yaml: |
    auth_enabled: false

    ingester:
      chunk_idle_period: 3m
      chunk_retain_period: 1m
      max_chunk_age: 1h
      max_streams_matching_max_bytes: 6291456
      max_streams_without_limits: 10000

    limits_config:
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h

    schema_config:
      configs:
      - from: 2020-10-24
        store: boltdb-shipper
        object_store: s3
        schema: v11
        index:
          prefix: index_
          period: 24h

    server:
      http_listen_port: 3100
      log_level: info

    storage_config:
      boltdb_shipper:
        active_index_directory: /tmp/loki/boltdb-shipper-active
        cache_location: /tmp/loki/boltdb-shipper-cache
        shared_store: s3
      s3:
        s3: null
        endpoint: s3.amazonaws.com
        region: us-east-1
        bucket_name: loki-logs
        access_key_id: ${AWS_ACCESS_KEY_ID}
        secret_access_key: ${AWS_SECRET_ACCESS_KEY}
```

### Log Query Examples

```sql
-- Find all errors in past hour
{job="code-server"} | json | level="ERROR"

-- Find slow queries
{job="code-server"} | json | duration_ms > 1000

-- Find user errors
{job="code-server"} | json | user_id="usr_xyz"

-- Count errors by service
sum by (service) (count(({level="ERROR"))))
```

## Anomaly Detection

### ML-Based Detection

```python
# Anomaly detection using Prometheus metrics

import numpy as np
from sklearn.ensemble import IsolationForest

def detect_anomalies(metric_data, contamination=0.01):
    """
    Detect anomalies in metric time series

    Args:
        metric_data: N x M array (N time points, M features)
        contamination: Expected fraction of anomalies (1%)

    Returns:
        Indices of anomalous points
    """

    # Train isolation forest
    if_model = IsolationForest(contamination=contamination, random_state=42)
    predictions = if_model.fit_predict(metric_data)

    # Return anomaly indices
    return np.where(predictions == -1)[0]

# Example: Detect latency anomaly
latency_percentiles = [
    [95.0, 102.0, 98.0],  # [p50, p99, max]
    [96.0, 105.0, 101.0],
    [94.0, 103.0, 99.0],
    [150.0, 250.0, 300.0],  # ANOMALY - spike
    [95.0, 100.0, 97.0],
]

anomalies = detect_anomalies(np.array(latency_percentiles))
print(f"Anomalous points: {anomalies}")  # [3]
```

### Alert Rules with Anomaly Detection

```yaml
groups:
- name: anomaly-alerts
  rules:
  - alert: LatencyAnomaly
    expr: |
      rate(http_requests_duration_seconds_sum[5m])
      / rate(http_requests_duration_seconds_count[5m])
      > quantile_over_time(0.99, rate(http_requests_duration_seconds[5m])[7d:1m])
    for: 5m
    annotations:
      summary: "Latency above 99th percentile for 5 minutes"

  - alert: ErrorRateAnomaly
    expr: |
      rate(http_errors_total[5m])
      > rate(http_errors_total[7d:1m]) + 2 * stddev_over_time(rate(http_errors_total[7d:1m]))
    for: 5m
    annotations:
      summary: "Error rate 2 standard deviations above weekly average"

  - alert: MemoryLeak
    expr: |
      predict_linear(container_memory_usage_bytes[1h], 3600)
      > 3.5e9  # 3.5GB limit
    for: 10m
    annotations:
      summary: "Memory usage projected to exceed limit in 1 hour"
```

## Dashboards

### Key Dashboards

1. **System Health Overview**
   - Uptime, availability SLI
   - Request latency (p50, p95, p99)
   - Error rate by endpoint
   - Active connections

2. **Database Health**
   - Primary/replica lag
   - Active connections
   - Query latency distribution
   - Replication status

3. **Resource Utilization**
   - CPU per node
   - Memory per node
   - Disk I/O
   - Network throughput

4. **Business Metrics**
   - Requests per second
   - Revenue per request (cost attribution)
   - User sessions
   - API usage by client

---

**Status**: Complete
**Last Updated**: April 13, 2026
