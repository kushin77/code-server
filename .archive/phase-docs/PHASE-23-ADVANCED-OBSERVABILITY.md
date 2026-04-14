# Phase 23: Advanced Observability - Metrics Correlation & Trace Synthesis

**Status**: 🟢 PLANNING & SPECIFICATION  
**Priority**: P1 - High (critical for SRE operational excellence)  
**Target Date**: April 15-30, 2026  
**Duration**: ~40 hours (5 days, 8 hours/day )  
**Type**: Observability infrastructure  
**Owner**: @kushin77 (DevOps/Platform Lead)

---

## Executive Vision

Transition from basic infrastructure monitoring (Phase 21) to enterprise-grade observability with:

- **Distributed Tracing**: Full request lifecycle tracking (code-server → ollama → cache → DB)
- **Metrics Correlation**: Automatic linking of related signals (CPU ↔ latencyincidents, error_rate ↔ failed_requests)
- **Anomaly Detection**: ML-based baseline learning + automatic alerts
- **Root Cause Analysis**: One-click drill-down from symptom → root cause
- **SLA Tracking**: Real-time SLI & SLO monitoring with burn-down tracking

**Business Outcome**: < 3 minute MTTR (Mean Time To Resolution) vs current ~15 minutes

---

## Phase 23-A: Distributed Tracing Architecture (12 hours)

### Objective
Implement OpenTelemetry (OTel) instrumentation across all services with Jaeger as the backend.

### Architecture

```
┌────────────────┐
│  code-server   │ ──┐ OTel SDK (auto-instrument)
└────────────────┘   │
                      │
┌────────────────┐   │    ┌──────────────┐
│    ollama      │ ──┼─→  │ OTel Collector│ ──→ ┌─────────────────┐
└────────────────┘   │    └──────────────┘     │  Jaeger Backend │
                     │                         │  (ElasticSearch)│
┌────────────────┐   │                         └─────────────────┘
│   Caddy        │ ──┘
└────────────────┘

Trace Flow:
  code-server request ─→ caddy ──→ code-server app ──→ ollama
  └─ Span 1: http.request.in
     └─ Span 2: http.request.out (caddy → app)
        └─ Span 3: rpc.call (app → ollama)
           └─ Span 4: ollama.inference
        └─ Span 5: db.query (if applicable)
```

### Tasks

**A1: OpenTelemetry Collector Deployment (3 hours)**

```bash
# Deploy OTel Collector as bridge container
docker run -d \
  --name otel-collector \
  --restart unless-stopped \
  -p 4317:4317  #gRPC receiver (from apps)
  -p 4318:4318  # HTTP receiver (HTTP exporters)
  -p 14250:14250 # Jaeger gRPC receiver
  -v ./otel-config.yml:/etc/otel/config.yml \
  otel/opentelemetry-collector-contrib:latest

# Configuration (otel-config.yml)
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
  jaeger:
    protocols:
      grpc:
        endpoint: 0.0.0.0:14250

processors:
  batch:
    send_batch_size: 1024
    timeout: 10s
  memory_limiter:
    check_interval: 5s
    limit_mib: 512

exporters:
  jaeger:
    endpoint: jaeger-backend:14250
    tls:
      insecure: true
  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: otel_

service:
  pipelines:
    traces:
      receivers: [otlp, jaeger]
      processors: [memory_limiter, batch]
      exporters: [jaeger, prometheus]
```

**A2: Jaeger Backend (3 hours)**

```bash
# Deploy Jaeger all-in-one (dev) or production cluster (prod)
docker run -d \
  --name jaeger \
  --restart unless-stopped \
  -e COLLECTOR_ZIPKIN_HOST_PORT=:9411 \
  -p 6831:6831/udp # Jaeger compact thrift
  -p 6832:6832/udp # Jaeger binary thrift
  -p 5778:5778    # Jaeger serve frontends
  -p 16686:16686  # Jaeger UI
  -p 14268:14268  # Jaeger collector HTTP
  -p 14250:14250  # Jaeger collector gRPC
  -p 9411:9411    # Zipkin compatible endpoint
  -v jaeger-data:/badger \
  jaegertracing/all-in-one:latest

# UI: http://192.168.168.31:16686
```

**A3: Application Instrumentation - Code-Server (3 hours)**

```javascript
// SDK setup in code-server (if Node.js based)
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { JaegerExporter } = require('@opentelemetry/exporter-jaeger');

const sdk = new NodeSDK({
  instrumentations: [getNodeAutoInstrumentations()],
  traceExporter: new JaegerExporter({
    host: 'otel-collector',
    port: 14250,
  }),
});

sdk.start();

// Standard Express middleware automatically traced:
// - HTTP requests (method, URL, status)
// - Database queries
// - External API calls
```

**A4: Application Instrumentation - Ollama (3 hours)**

```python
# Python instrumentation for Ollama (if Python-based parts)
from opentelemetry import trace, metrics
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

jaeger_exporter = JaegerExporter(
    agent_host_name='otel-collector',
    agent_port=6831,
)
trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(jaeger_exporter)
)

FastAPIInstrumentor.instrument_app(app)  # Auto-trace all FastAPI endpoints
RequestsInstrumentor().instrument()  # Auto-trace HTTP calls
```

---

## Phase 23-B: Metrics Correlation Engine (10 hours)

### Objective
Link related Prometheus metrics into correlated signal groups.

### Implementation

**B1: PromQL Rule Creation (4 hours)**

```yaml
# prometheus-rules-phase-23.yml

groups:
  - name: correlations
    rules:
      # Correlation Group 1: Request → Response Time
      - name: request_latency_spike
        expr: |
          (rate(http_requests_total[5m]) > 100)
          and
          (histogram_quantile(0.99, http_request_duration_seconds_bucket) > 0.5)
        annotations:
          summary: "High request rate causing latency spike"
          correlation: "traffic↑ → latency↑"

      # Correlation Group 2: CPU → Malloc Failures
      - name: resource_pressure
        expr: |
          (rate(process_cpu_seconds_total[5m]) > 0.8)
          and
          (malloc_failures_total > 0)
        annotations:
          summary: "High CPU utilization linked to memory failures"
          correlation: "cpu↑ → malloc_fail↑"

      # Correlation Group 3: Model Inference → Database Load
      - name: inference_db_pressure
        expr: |
          (rate(ollama_inference_requests_total[5m]) > 10)
          and
          (pg_stat_activity_count > 50)
        annotations:
          summary: "Model inference load correlates with DB connection pool saturation"
          correlation: "inference↑ → db_connections↑"

      # Correlation Group 4: Error Rate → User Impact
      - name: error_cascade
        expr: |
          (rate(http_requests_total{status=~"5.."}[5m]) > 0.05)
          and
          (rate(user_session_timeouts_total[5m]) > 0.1)
        annotations:
          summary: "Errors causing session timeouts (user-visible SLA impact)"
          correlation: "errors↑ → timeouts↑"
```

**B2: AlertManager Correlation Rules (3 hours)**

```yaml
# alertmanager-production.yml
route:
  group_by: ['correlation_group', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  
  routes:
    - match_labels:
        correlation: "traffic↑ → latency↑"
      receiver: on-call-escalation
      continue: true
      routes:
        - match_labels:
            severity: critical
          receiver: pagerduty
          
    - match_labels:
        correlation: "cpu↑ → malloc_fail↑"
      receiver: scaling-automation
      actions:
        - trigger: scale-horizontally
          target_cpu: 70%

receivers:
  scaling-automation:
    webhook_configs:
      - url: http://autoscaler:8080/scale-up
        send_resolved: false
```

**B3: Grafana Correlation Dashboard (3 hours)**

```json
{
  "dashboard": {
    "title": "Phase 23: Advanced Observability - Correlation Dashboard",
    "panels": [
      {
        "title": "Request Rate vs Latency (Correlation 1)",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "Requests/sec"
          },
          {
            "expr": "histogram_quantile(0.99, http_request_duration_seconds_bucket)",
            "legendFormat": "p99 latency (s)",
            "yaxis": "right"
          }
        ],
        "alert": "traffic_latency_correlation"
      },
      {
        "title": "Model Inference vs DB Connections",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(ollama_inference_requests_total[5m])",
            "legendFormat": "Inference calls/sec"
          },
          {
            "expr": "pg_stat_activity_count",
            "legendFormat": "DB connections",
            "yaxis": "right"
          }
        ],
        "alert": "inference_db_correlation"
      },
      {
        "title": "Error Rate vs Session Timeouts",
        "type": "heatmap",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~'5..'}[5m])",
            "legendFormat": "5xx errors/sec"
          },
          {
            "expr": "rate(user_session_timeouts_total[5m])",
            "legendFormat": "Timeouts/sec",
            "yaxis": "right"
          }
        ]
      }
    ]
  }
}
```

---

## Phase 23-C: Anomaly Detection (10 hours)

### Objective
ML-based anomaly detection with automatic baseline learning.

### Implementation

**C1: Prometheus Operator + ML (4 hours)**

```yaml
# Install: Prometheus + Thanos (long-term storage) + ML plugin
helm install prometheus prometheus-community/kube-prometheus-stack \
  --set prometheus.prometheusSpec.remoteWrite[0].url=http://thanos-receive:19291/api/v1/receive \
  --set alertmanager.enabled=true
```

**C2: Prophet Anomaly Detection (3 hours)**

```python
#!/usr/bin/env python3
# anomaly_detector.py - Runs as sidecar to Prometheus

import requests
from prophet import Prophet
import pandas as pd
from datetime import datetime, timedelta

def detect_anomalies():
    # Query Prometheus for 30-day historical data
    query = 'rate(http_requests_total[5m])'
    
    # Fetch data
    response = requests.get('http://prometheus:9090/api/v1/query_range', params={
        'query': query,
        'start': (datetime.now() - timedelta(days=30)).timestamp(),
        'end': datetime.now().timestamp(),
        'step': '5m'
    })
    
    # Convert to Prophet format
    data = []
    for timestamp, value in response.json()['data']['result'][0]['values']:
        data.append({
            'ds': datetime.fromtimestamp(timestamp),
            'y': float(value)
        })
    
    df = pd.DataFrame(data)
    
    # Fit Prophet model
    model = Prophet(yearly_seasonality=True, weekly_seasonality=True)
    model.fit(df)
    
    # Generate forecast + confidence intervals
    future = model.make_future_dataframe(periods=1, freq='5min')
    forecast = model.predict(future)
    
    # Detect anomalies (values outside 95% confidence interval)
    latest = df.iloc[-1]
    forecast_latest = forecast.iloc[-1]
    
    if not (forecast_latest['yhat_lower'] < latest['y'] < forecast_latest['yhat_upper']):
        anomaly_score = abs(latest['y'] - forecast_latest['yhat']) / (forecast_latest['yhat_upper'] - forecast_latest['yhat_lower'])
        
        # Report as Prometheus metric
        requests.post('http://prometheus:9090/metrics', data=f"""
# HELP anomaly_score Current anomaly score (0-1)
# TYPE anomaly_score gauge
anomaly_score{query="{query}"} {anomaly_score}
        """)

# Run every 5 minutes
while True:
    detect_anomalies()
    time.sleep(300)
```

**C3: Grafana Recorded Rules (3 hours)**

```yaml
# Record baseline metrics for future comparison
groups:
  - name: anomaly_baselines
    interval: 5m
    rules:
      # Daily baseline: mean + stddev of past 7 days at same hour
      - record: http_requests:baseline:daily
        expr: |
          avg(avg_over_time(rate(http_requests_total[5m])[7d:5m] offset 24h))

      # Peak vs baseline ratio
      - record: http_requests:anomaly_ratio
        expr: |
          rate(http_requests_total[5m]) / http_requests:baseline:daily
```

**C4: AutoML Alerting (2 hours)**

```yaml
# alerts-phase-23.yml
- alert: AnomalyDetected
  expr: anomaly_score > 2
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Anomaly detected: {{ $labels.query }}"
    description: "Anomaly score: {{ $value }}"
    runbook: "https://runbooks.example.com/anomaly-detection"
```

---

## Phase 23-D: SLA/SLI/SLO Tracking (8 hours)

### Objective
Real-time SLI measurement with SLO burn-down tracking.

### Implementation

**D1: SLI Definitions (2 hours)**

```yaml
# sli-definitions.yml
slis:
  availability:
    description: "% of successful requests (5xx errors count as failures)"
    query: |
      (sum(rate(http_requests_total{status=~"2.."}[5m]))) /
      (sum(rate(http_requests_total[5m])))
    target: 0.9995  # 99.95% availability

  latency:
    description: "% of requests faster than 100ms"
    query: |
      (sum(rate(http_request_duration_seconds_bucket{le="0.1"}[5m]))) /
      (sum(rate(http_requests_total[5m])))
    target: 0.95  # 95% of requests < 100ms

  completeness:
    description: "% of inference requests completed (not timed out)"
    query: |
      (sum(rate(ollama_inference_complete_total[5m]))) /
      (sum(rate(ollama_inference_requests_total[5m])))
    target: 0.99  # 99% completion rate
```

**D2: SLO Calculation (2 hours)**

```yaml
# slos-phase-23.yml
groups:
  - name: slo_tracking
    interval: 1m
    rules:
      # Availability SLO: 99.95% over 30 days
      - record: slo:availability:current
        expr: |
          availability_sli{job="code-server"}

      - record: slo:availability:error_budget_minutes
        expr: |
          (1 - slo:availability:current) * 30 * 24 * 60
        annotations:
          description: "Minutes remaining in 30-day error budget (if SLI constant)"

      - alert: SLOBurnRateHigh
        expr: |
          (1 - slo:availability:current) > 0.0005  # 50% of budget burned in 1 day
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "SLO burn rate is {{ $value | humanizePercentage }}"
          description: "At current rate, monthly error budget will be exhausted in {{ $value / 0.0005 | humanizeDuration }}"
```

**D3: Grafana SLO Dashboard (2 hours)**

```json
{
  "dashboard": {
    "title": "Phase 23: SLA/SLI/SLO Tracking",
    "panels": [
      {
        "title": "30-Day Error Budget (Availability)",
        "type": "gauge",
        "targets": [
          {
            "expr": "slo:availability:error_budget_minutes"
          }
        ],
        "max": 1296,  // 30 days * 43.2 minutes error budget for 99.95%
        "thresholds": [0, 648, 1296],  // Red < 50% / Yellow < 100%
        "alert": true
      },
      {
        "title": "SLI Trending (30-day)",
        "type": "graph",
        "targets": [
          {
            "expr": "slo:availability:current",
            "legendFormat": "Actual"
          },
          {
            "expr": "slo:availability:target",
            "legendFormat": "Target (99.95%)"
          }
        ]
      },
      {
        "title": "Latency SLI (% < 100ms)",
        "type": "gauge",
        "targets": [
          {
            "expr": "slo:latency:current"
          }
        ],
        "max": 1.0,
        "alert": true
      }
    ]
  }
}
```

---

## Phase 23-E: Root Cause Analysis (RCA) Automation (2 hours)

### Objective
One-click drill-down from symptom → root cause

### Implementation

```python
#!/usr/bin/env python3
# rca-engine.py - Automated root cause analysis

def analyze_incident(alert):
    """
    Given an alert, find correlated metrics to identify root cause
    """
    incident = {
        'alert': alert.name,
        'triggered_at': datetime.now(),
        'severity': alert.labels.severity,
        'metrics': [],
        'hypothesis': None,
        'root_cause': None,
    }
    
    # Query correlated metrics
    correlations = query_correlation_rules(alert.name)
    
    for correlation in correlations:
        metric_value = query_prometheus(correlation['expr'])
        if metric_value['threshold_exceeded']:
            incident['metrics'].append({
                'name': correlation['name'],
                'value': metric_value['value'],
                'threshold': metric_value['threshold'],
                'timestamps': metric_value['timestamps']
            })
    
    # Perform causality analysis
    if alert.name == 'HighLatency':
        if incident['metrics']['cpu_utilization'] > 80:
            incident['hypothesis'] = 'High CPU causing latency'
        elif incident['metrics']['memory_usage'] > 90:
            incident['hypothesis'] = 'Memory pressure causing GC pauses'
        elif incident['metrics']['disk_io'] > 95:
            incident['hypothesis'] = 'Disk I/O bottleneck'
        else:
            incident['hypothesis'] = 'External dependency slow (database/API)'
    
    # Generate RCA report with remediation
    incident['recommended_action'] = get_remediation(incident['hypothesis'])
    
    return incident
```

---

## Phase 23 Success Criteria

- ✅ OpenTelemetry SDK integrated in all services
- ✅ Jaeger traces fully populated (request → response)
- ✅ Metric correlation dashboard showing relationships
- ✅ Anomaly detection running with < 2% false positive rate
- ✅ SLI/SLO dashboards showing error budget tracking
- ✅ RCA engine working for top 3 alert types
- ✅ MTTR reduced from ~15 min to < 3 min
- ✅ Team trained on new observability tools
- ✅ Runbooks updated with trace analysis procedures

---

## Files Reference

- Spec: `PHASE-23-ADVANCED-OBSERVABILITY.md` (this file)
- Terraform: `phase-23-observability.tf` (container deployments)
- Prometheus: `prometheus-rules-phase-23.yml`, `alerts-phase-23.yml`
- Jaeger: `otel-config.yml`, `jaeger-config.yml`
- Python: `anomaly_detector.py`, `rca_engine.py`
- Monitoring: Grafana dashboards (JSON export)

---

## Deployment Checklist

- [ ] Phase 21 (monitoring stack) operational
- [ ] OTel Collector running
- [ ] Jaeger backend running (UI accessible)
- [ ] Application SDKs integrated
- [ ] First traces appearing in Jaeger
- [ ] Prometheus correlation rules deployed
- [ ] Anomaly detection model trained
- [ ] SLO dashboards created
- [ ] Team trained on tools
- [ ] Production deployment (gradual rollout)

---

## Timeline

| Week | Tasks | Hours | Status |
|------|-------|-------|--------|
| 1 (Apr 15-19) | A: Tracing architecture | 12 | ⏳ READY |
| 1 (Apr 15-19) | B: Metrics correlation | 10 | ⏳ READY |
| 2 (Apr 22-26) | C: Anomaly detection | 10 | QUEUED |
| 2 (Apr 22-26) | D: SLO tracking | 8 | QUEUED |
| 3 (Apr 29-30) | E: RCA automation | 2 | QUEUED |
| **TOTAL** | — | **40 hours** | — |

---

## Acceptance Criteria

✅ **Phase 23-A: Tracing Deployed**
- Jaeger UI shows traces from > 90% of requests
- Trace latency < 1 second end-to-end (collection → UI)
- Error traces captured with stack traces

✅ **Phase 23-B: Correlation Active**
- Correlation dashboard shows linked signals
- AlertManager routes to correlation-aware handlers
- Auto-scaling triggered by inferred causality

✅ **Phase 23-C: Anomalies Detected**
- Prophet model running with < 2% false positives
- Anomalies appear in metrics < 5 minutes after occurrence
- Baseline learning accurate after 7 days

✅ **Phase 23-D: SLO Tracked**
- Real-time SLI measurement accurate
- Error budget burn-down visible
- Alerts trigger before SLO breach

✅ **Phase 23-E: RCA Working**
- Top 3 alerts have RCA coverage
- Hypothesis accuracy > 80%
- Recommended actions tested and validated

---

**Phase 23 Status**: 🟢 SPECIFICATION COMPLETE, READY FOR DEPLOYMENT  
**Owner**: @kushin77  
**Next**: Execute Phase 23-A starting April 15, 2026

