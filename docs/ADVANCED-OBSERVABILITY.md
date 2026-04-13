# Advanced Observability Stack

## Complete Observability Picture

```
┌─────────────────────────────────────────────────┐
│         Application Requests                    │
├─────────────────────────────────────────────────┤
│ Instrumentation (OpenTelemetry SDKs)            │
├─────────────────────────────────────────────────┤
│ ┌──────────────────┐  ┌──────────────────┐      │
│ │ Metrics          │  │ Traces           │      │
│ │ (Prometheus)     │  │ (Jaeger)         │      │
│ └──────────────────┘  └──────────────────┘      │
│ ┌──────────────────┐                            │
│ │ Logs (Loki)      │                            │
│ └──────────────────┘                            │
│                                                  │
│ ┌──────────────────────────────────────────┐   │
│ │ Grafana Dashboards & Alerts              │   │
│ └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

## 1. Distributed Tracing (Jaeger)

### Installation

```bash
# Add Jaeger Helm repo
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo update

# Install Jaeger
helm install jaeger jaegertracing/jaeger \
  --namespace observability \
  --values - <<EOF
storage:
  type: elasticsearch
  elasticsearch:
    host: elasticsearch.observability.svc.cluster.local
    port: 9200

collector:
  ports:
    otlp:
      enabled: true
      grpc:
        enabled: true
        port: 4317
      http:
        enabled: true
        port: 4318

query:
  service:
    type: LoadBalancer
    port: 16686  # Jaeger UI

agent:
  enabled: true
EOF
```

### Instrumentation

Add to application code (Python example):

```python
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor

# Jaeger exporter
jaeger_exporter = JaegerExporter(
    agent_host_name="jaeger-agent",
    agent_port=6831,
)

# Register exporter
trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(jaeger_exporter)
)

# Auto-instrument libraries
FlaskInstrumentor().instrument()
RequestsInstrumentor().instrument()
SQLAlchemyInstrumentor().instrument()

# Create tracer
tracer = trace.get_tracer(__name__)

# Manual span
with tracer.start_as_current_span("expensive_operation") as span:
    span.set_attribute("user_id", user_id)
    # ... operation code ...
```

### Custom Metrics Collection

```python
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.prometheus import PrometheusMetricReader

# Prometheus reader for Prometheus scraping
prometheus_reader = PrometheusMetricReader()
metrics.set_meter_provider(MeterProvider(metric_readers=[prometheus_reader]))

meter = metrics.get_meter(__name__)

# Counter
request_counter = meter.create_counter(
    "http_requests_total",
    description="Total HTTP requests",
    unit="1"
)

# Histogram
latency_histogram = meter.create_histogram(
    "http_request_duration_seconds",
    description="HTTP request latency",
    unit="s"
)

# Gauge
active_connections = meter.create_observable_gauge(
    "db_connection_pool_active",
    description="Active database connections",
    callbacks=[get_active_connections]
)

# Record metrics
request_counter.add(1, {"endpoint": "/api/users", "status": "200"})
latency_histogram.record(0.35, {"endpoint": "/api/users"})
```

## 2. Log Aggregation (Loki)

### Loki Stack Deployment

```bash
helm install loki grafana/loki-stack \
  --namespace observability \
  --values - <<EOF
loki:
  enabled: true
  persistence:
    enabled: true
    size: 50Gi
  limits_config:
    retention_period: 720h  # 30 days
    max_cache_freshness_per_query: 10m

promtail:
  enabled: true
  config:
    clients:
      - url: http://loki:3100/loki/api/v1/push
    scrape_configs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_name]
            action: replace
            target_label: pod
          - source_labels: [__meta_kubernetes_pod_namespace]
            action: replace
            target_label: namespace
EOF
```

### Application Logging Configuration

```yaml
# kubernetes/overlays/production/patches/logging.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: logging-config
  namespace: code-server
data:
  logging.json: |
    {
      "version": 1,
      "formatters": {
        "json": {
          "class": "pythonjsonlogger.jsonlogger.JsonFormatter",
          "format": "%(timestamp)s %(level)s %(name)s %(message)s"
        }
      },
      "handlers": {
        "console": {
          "class": "logging.StreamHandler",
          "formatter": "json",
          "stream": "ext://sys.stdout"
        }
      },
      "root": {
        "level": "INFO",
        "handlers": ["console"]
      },
      "loggers": {
        "code_server": {
          "level": "DEBUG",
          "handlers": ["console"]
        },
        "database": {
          "level": "INFO",
          "handlers": ["console"]
        },
        "cache": {
          "level": "INFO",
          "handlers": ["console"]
        }
      }
    }
```

### Structured Logging Best Practices

```python
import logging
import json
from datetime import datetime

logger = logging.getLogger(__name__)

class StructuredLogger:
    def __init__(self, logger):
        self.logger = logger
    
    def log_request(self, method, path, status_code, duration_ms, user_id=None):
        """Log HTTP request in structured format"""
        log_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": "INFO",
            "event": "http_request",
            "http_method": method,
            "http_path": path,
            "http_status_code": status_code,
            "duration_ms": duration_ms,
            "user_id": user_id,
        }
        self.logger.info(json.dumps(log_entry))
    
    def log_error(self, error_msg, error_type, context=None):
        """Log errors with full context"""
        log_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": "ERROR",
            "event": "application_error",
            "error_message": error_msg,
            "error_type": error_type,
            "context": context or {},
        }
        self.logger.error(json.dumps(log_entry))
    
    def log_database_query(self, query, duration_ms, rows_affected):
        """Log database operations"""
        log_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": "DEBUG",
            "event": "database_query",
            "query_type": query[:50] + "..." if len(query) > 50 else query,
            "duration_ms": duration_ms,
            "rows_affected": rows_affected,
        }
        self.logger.debug(json.dumps(log_entry))

# Usage
structured = StructuredLogger(logger)
structured.log_request("GET", "/api/users", 200, 45, user_id="user123")
```

### Loki Queries

```promql
# Count errors in last hour
count_over_time({namespace="code-server", stream="stderr"} | `"ERROR"` [1h])

# Latency percentiles
quantile_over_time(0.99, {service="code-server"} | json | duration_ms [5m])

# Error rate by endpoint
sum by (http_path) (count_over_time({namespace="code-server", level="ERROR"} | json | http_path [5m]))

# Logs with context
{namespace="code-server"} | json | latency_ms > 1000

# Alert on high error log volume
count_over_time({namespace="code-server", level="ERROR"} [5m]) > 10
```

## 3. Enhanced Prometheus Configuration

### Recording Rules (Efficient Aggregation)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-rules
  namespace: monitoring
data:
  recording-rules.yaml: |
    groups:
    - name: service-level
      interval: 30s
      rules:
      # Request rates by service
      - record: service:request:rate5m
        expr: rate(http_requests_total[5m]) by (service, method, path)
      
      # Error rates by service
      - record: service:error:rate5m
        expr: rate(http_requests_total{status=~"5.."}[5m]) by (service)
      
      # Latency percentiles (pre-computed)
      - record: service:latency:p50:5m
        expr: histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le))
      
      - record: service:latency:p99:5m
        expr: histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le))
      
      # Availability (SLO tracking)
      - record: service:availability:5m
        expr: |
          (sum(rate(http_requests_total{status=~"2.."}[5m])) by (service))
          /
          (sum(rate(http_requests_total[5m])) by (service))
```

### Prometheus Alerting Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: advanced-alerts
  namespace: monitoring
spec:
  groups:
  - name: slo_alerts
    interval: 30s
    rules:
    # SLO burn rate alerts
    - alert: HighBurnRate
      expr: |
        (1 - (sum(rate(http_requests_total{status=~"2.."}[5m])) by (service))
        / (sum(rate(http_requests_total[5m])) by (service)))
        / (1 - 0.999) > 10  # 10x burn rate
      for: 5m
      annotations:
        summary: "{{ $labels.service }} SLO burn rate {{ $value | humanize }}x"
    
    # Latency SLO alert
    - alert: HighLatency
      expr: |
        histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le))
        > 1  # 1 second
      for: 2m
      annotations:
        summary: "{{ $labels.service }} P99 latency {{ $value | humanize }}s"
    
    # Resource exhaustion
    - alert: HighMemoryUsage
      expr: |
        (container_memory_usage_bytes / container_spec_memory_limit_bytes)
        > 0.85
      annotations:
        summary: "{{ $labels.pod }} memory {{ $value | humanizePercentage }}"
    
    # Anomaly detection
    - alert: UnusualErrorRate
      expr: |
        abs(rate(http_requests_total{status="5xx"}[5m]) - avg_over_time(rate(http_requests_total{status="5xx"}[5m] offset 1w)[1h:5m]))
        > 2 * stddev_over_time(rate(http_requests_total{status="5xx"}[5m] offset 1w)[1h:5m])
      annotations:
        summary: "Unusual error rate spike detected"
```

## 4. Integrating All Three (Metrics + Traces + Logs)

### Correlated Observability

```python
import logging
from opentelemetry import trace

def request_handler(request):
    logger = logging.getLogger(__name__)
    tracer = trace.get_tracer(__name__)
    
    # Get trace ID from OpenTelemetry
    span = trace.get_current_span()
    trace_id = format(span.get_span_context().trace_id, "032x")
    
    # Add trace ID to logs
    log_entry = {
        "timestamp": datetime.utcnow().isoformat(),
        "event": "http_request",
        "trace_id": trace_id,  # Links logs to traces in Grafana
        "path": request.path,
        "method": request.method,
    }
    logger.info(json.dumps(log_entry))
    
    # Record metrics
    meter = metrics.get_meter(__name__)
    counter = meter.create_counter("request_count")
    counter.add(1, {"path": request.path})
    
    # Create span for operation
    with tracer.start_as_current_span("database_query") as span:
        span.set_attribute("db.name", "code_server")
        # Database operation
        result = db.query(...)
        span.set_attribute("db.rows_returned", len(result))
    
    return result
```

### Grafana Dashboard - Trace Explorer

```yaml
# Dashboard to drill from metrics → traces → logs
# 1. User clicks on high latency in metrics graph
# 2. Grafana shows Jaeger traces for that service
# 3. User clicks on slow trace
# 4. Grafana shows Loki logs with matching trace_id
# 5. Root cause identified
```

## 5. Performance Profiling Integration

### Continuous Profiling (optional: Pyroscope)

```bash
helm install pyroscope pyroscope-io/pyroscope \
  --namespace observability \
  --set persistence.enabled=true \
  --set persistence.size=50Gi
```

### Python Application Profiling

```python
import pyroscope

pyroscope.configure(
    application_name="code-server",
    server_address="http://pyroscope:4040",
    sample_rate=100,  # Profile 100% of requests (safe for Python)
)

@pyroscope.profile_function_call
def expensive_operation():
    # This function will be profiled
    ...
```

## 6. Metrics Export for Cost Analysis

### Custom Metrics for Cost Tracking

```python
def track_resource_usage(pod_name, cpu_cores, memory_gb, duration_hours):
    """
    Track resource usage for cost analysis
    On-Prem cost: $X per core-hour, $Y per GB-hour
    """
    meter = metrics.get_meter(__name__)
    
    # Record resource metrics
    cpu_usage_metric = meter.create_counter("pod_cpu_cores_used")
    memory_usage_metric = meter.create_counter("pod_memory_gb_used")
    
    cpu_usage_metric.add(cpu_cores * duration_hours, {"pod": pod_name})
    memory_usage_metric.add(memory_gb * duration_hours, {"pod": pod_name})
    
    # Calculate cost (example: $0.05/core-hour, $0.01/GB-hour)
    estimated_cost = (cpu_cores * duration_hours * 0.05) + (memory_gb * duration_hours * 0.01)
    
    return {
        "pod": pod_name,
        "cpu_hours": cpu_cores * duration_hours,
        "memory_gb_hours": memory_gb * duration_hours,
        "estimated_cost_usd": estimated_cost,
    }
```

## 7. Observability SLO

Target metrics for observability system itself:

| SLI | Target | Alert |
|-----|--------|-------|
| Trace collection latency | < 1 second | > 5s for 5m |
| Log ingestion latency | < 2 seconds | > 10s for 5m |
| Metric scrape success rate | 99.9% | < 99% for 10m |
| Query response time | < 500ms | > 2s for monitoring queries |

---

## Next Step: View Your Traces

1. Deploy Jaeger UI: `kubectl port-forward svc/jaeger-query 16686:16686 -n observability`
2. Open http://localhost:16686
3. Select service and trace:
