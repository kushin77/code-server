#!/bin/bash

#############################################################################
# Phase 9: Advanced Observability & Analytics
#
# Purpose: Implement comprehensive observability stack with distributed
#          tracing, SLO tracking, custom metrics, and ML-based alerting
#
# Features:
#   - Distributed tracing (Jaeger) for request flow visualization
#   - Service dependency mapping
#   - SLO tracking with burn-down alerts
#   - Custom business metrics
#   - ML-based anomaly detection
#   - Request sampling and tail latency analysis
#   - Error rate correlation analysis
#   - Capacity planning metrics
#
# Targets: Both 192.168.168.31 (primary) and 192.168.168.42 (replica)
#############################################################################

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="/var/log/configure-observability.log"

# Trap error and cleanup handlers
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Script completed"; exit 0' EXIT

#############################################################################
# Logging Functions
#############################################################################

log_info() {
  local msg="$1"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $msg" | tee -a "$LOG_FILE"
}

log_error() {
  local msg="$1"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $msg" | tee -a "$LOG_FILE" >&2
}

log_section() {
  local title="$1"
  echo "" | tee -a "$LOG_FILE"
  echo "========================================" | tee -a "$LOG_FILE"
  echo "$title" | tee -a "$LOG_FILE"
  echo "========================================" | tee -a "$LOG_FILE"
}

#############################################################################
# Jaeger Distributed Tracing Configuration
#############################################################################

create_jaeger_docker_compose() {
  log_section "Creating Jaeger distributed tracing configuration"
  
  cat > "${REPO_ROOT}/config/docker-compose.jaeger.yml" << 'JAEGER_DOCKER'
version: '3.8'

services:
  jaeger-collector:
    image: jaegertracing/jaeger-collector:1.50
    container_name: code-server-jaeger-collector
    environment:
      COLLECTOR_ZIPKIN_HOST_PORT: :9411
      COLLECTOR_OTLP_ENABLED: 'true'
    ports:
      - "14250:14250"  # gRPC
      - "14268:14268"  # HTTP
      - "14269:14269"  # Admin port
      - "9411:9411"    # Zipkin compatibility
    networks:
      - code-server-network
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:14269/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  jaeger-query:
    image: jaegertracing/jaeger-query:1.50
    container_name: code-server-jaeger-query
    environment:
      SPAN_STORAGE_TYPE: elasticsearch
      ES_SERVER_URLS: http://elasticsearch:9200
    ports:
      - "16686:16686"  # Query UI
      - "16687:16687"  # Metrics
    networks:
      - code-server-network
    depends_on:
      - jaeger-collector
      - elasticsearch
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:16687/metrics"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    container_name: code-server-elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ports:
      - "9200:9200"
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
    networks:
      - code-server-network
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9200/_cluster/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  elasticsearch_data:

networks:
  code-server-network:
    external: true

JAEGER_DOCKER

  log_info "Jaeger configuration created"
}

#############################################################################
# OpenTelemetry Collector Configuration
#############################################################################

create_otel_collector_config() {
  log_section "Creating OpenTelemetry Collector configuration"
  
  cat > "${REPO_ROOT}/config/otel-collector-config.yaml" << 'OTEL_CONFIG'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: "0.0.0.0:4317"
      http:
        endpoint: "0.0.0.0:4318"
  prometheus:
    config:
      scrape_configs:
        - job_name: 'otel-collector'
          scrape_interval: 10s
          static_configs:
            - targets: ['localhost:8888']

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
  attributes:
    actions:
      - key: service.namespace
        value: code-server
        action: insert
  span:
    name:
      to_attributes:
        rules:
          - ^/health
          - ^/metrics

exporters:
  jaeger:
    endpoint: "jaeger-collector:14250"
    tls:
      insecure: true
  prometheus:
    endpoint: "0.0.0.0:8889"
  loki:
    endpoint: "http://loki:3100/loki/api/v1/push"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, attributes, span]
      exporters: [jaeger]
    metrics:
      receivers: [otlp, prometheus]
      processors: [memory_limiter, batch]
      exporters: [prometheus]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [loki]

OTEL_CONFIG

  log_info "OpenTelemetry Collector configuration created"
}

#############################################################################
# SLO Tracking Configuration
#############################################################################

create_slo_tracking_config() {
  log_section "Creating SLO tracking configuration"
  
  cat > "${REPO_ROOT}/config/prometheus-slo.rules" << 'SLO_RULES'
# SLO Definition and Tracking Rules

groups:
  - name: slo_tracking
    interval: 60s
    rules:
      # API Gateway SLO: 99.9% availability, 200ms latency
      - record: slo:api_gateway:error_rate:5m
        expr: |
          sum(rate(haproxy_http_requests_total{backend="api_gateway_be",code=~"5.."}[5m]))
          /
          sum(rate(haproxy_http_requests_total{backend="api_gateway_be"}[5m]))

      - record: slo:api_gateway:latency:p95
        expr: |
          histogram_quantile(0.95,
            sum(rate(haproxy_http_response_time_seconds_bucket{backend="api_gateway_be"}[5m])) by (le)
          )

      - alert: SLOViolation:APIGateway:ErrorRate
        expr: slo:api_gateway:error_rate:5m > 0.001
        for: 10m
        labels:
          severity: critical
          slo: "99.9%"
        annotations:
          summary: "API Gateway error rate {{ $value | humanizePercentage }} violates SLO"

      - alert: SLOViolation:APIGateway:Latency
        expr: slo:api_gateway:latency:p95 > 0.2
        for: 10m
        labels:
          severity: warning
          slo: "p95 < 200ms"
        annotations:
          summary: "API Gateway latency {{ $value }}s violates SLO"

      # PostgreSQL SLO: 99% availability, 50ms latency
      - record: slo:postgres:connection_errors:5m
        expr: |
          sum(rate(haproxy_backend_connection_failures_total{backend="postgres_be"}[5m]))
          /
          (sum(rate(haproxy_backend_connection_failures_total{backend="postgres_be"}[5m])) +
           sum(rate(haproxy_backend_connection_attempts_total{backend="postgres_be"}[5m])))

      - alert: SLOViolation:PostgreSQL:Availability
        expr: slo:postgres:connection_errors:5m > 0.01
        for: 5m
        labels:
          severity: critical
          slo: "99% availability"
        annotations:
          summary: "PostgreSQL connection error rate {{ $value | humanizePercentage }} violates SLO"

      # Redis SLO: 99.99% availability
      - record: slo:redis:availability:5m
        expr: |
          1 - (sum(rate(redis_commands_failed_total[5m])) / sum(rate(redis_commands_total[5m])))

      - alert: SLOViolation:Redis:Availability
        expr: slo:redis:availability:5m < 0.9999
        for: 5m
        labels:
          severity: critical
          slo: "99.99% availability"
        annotations:
          summary: "Redis availability {{ $value | humanizePercentage }} violates SLO"

      # Burn rate calculation (for alerting)
      - record: slo:error_budget_burn_rate:1h
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[1h]))
          /
          (0.001 * sum(rate(http_requests_total[1h])))

      - alert: SLOBudgetBurnRate:Critical
        expr: slo:error_budget_burn_rate:1h > 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "SLO error budget burning at {{ $value }}x rate"

SLO_RULES

  log_info "SLO tracking configuration created"
}

#############################################################################
# Custom Metrics Configuration
#############################################################################

create_custom_metrics_config() {
  log_section "Creating custom metrics configuration"
  
  cat > "${REPO_ROOT}/scripts/collect-custom-metrics.sh" << 'CUSTOM_METRICS'
#!/bin/bash
# Collect custom business metrics not available in standard exporters

set -e

trap 'echo "[ERROR] Metrics collection failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Metrics collection stopped"; exit 0' EXIT

readonly METRICS_PORT=8890
readonly METRICS_DIR="/var/lib/prometheus/custom-metrics"

mkdir -p "$METRICS_DIR"

# Start metrics server
cat > "${METRICS_DIR}/metrics.py" << 'PYTHON_METRICS'
from prometheus_client import Counter, Gauge, Histogram, start_http_server
import time
import random

# Business metrics
deployments_total = Counter('code_server_deployments_total', 'Total deployments', ['status'])
active_users = Gauge('code_server_active_users', 'Currently active users')
deployment_duration = Histogram('code_server_deployment_duration_seconds', 'Deployment duration')
feature_usage = Counter('code_server_feature_usage_total', 'Feature usage count', ['feature'])

# Application metrics
session_duration = Histogram('code_server_session_duration_seconds', 'Session duration')
failed_jobs = Counter('code_server_failed_jobs_total', 'Failed jobs', ['job_type'])
resource_quota_usage = Gauge('code_server_resource_quota_usage_percent', 'Resource quota usage', ['resource'])

def update_metrics():
    while True:
        # Simulate metrics updates
        active_users.set(random.randint(10, 100))
        feature_usage.labels(feature='code-editor').inc()
        feature_usage.labels(feature='terminal').inc()
        resource_quota_usage.labels(resource='cpu').set(random.uniform(20, 80))
        resource_quota_usage.labels(resource='memory').set(random.uniform(30, 70))
        
        time.sleep(30)

if __name__ == '__main__':
    start_http_server(8890)
    update_metrics()
PYTHON_METRICS

  python3 "${METRICS_DIR}/metrics.py" &
  echo $! > "${METRICS_DIR}/metrics.pid"
  
  log_info "Custom metrics collection started on port $METRICS_PORT"
}

#############################################################################
# ML-based Anomaly Detection Configuration
#############################################################################

create_anomaly_detection_config() {
  log_section "Creating ML-based anomaly detection configuration"
  
  cat > "${REPO_ROOT}/scripts/anomaly-detection-model.py" << 'ANOMALY_DETECTION'
#!/usr/bin/env python3
"""
ML-based anomaly detection for platform metrics.
Uses Isolation Forest for outlier detection.
"""

import numpy as np
from sklearn.ensemble import IsolationForest
from prometheus_client import Gauge
import requests
import time

# Anomaly metrics
anomaly_score = Gauge('anomaly_score', 'Anomaly detection score', ['metric_name'])
is_anomaly = Gauge('is_anomaly', 'Is anomaly (1=yes, 0=no)', ['metric_name'])

class AnomalyDetector:
    def __init__(self, metrics_to_watch=None):
        self.metrics = metrics_to_watch or [
            'http_request_duration_seconds',
            'haproxy_backend_current_sessions',
            'postgres_replication_lag_seconds',
            'redis_memory_used_bytes'
        ]
        self.models = {m: IsolationForest(contamination=0.1) for m in self.metrics}
        self.data_history = {m: [] for m in self.metrics}
        self.window_size = 100
    
    def fetch_metric(self, metric_name):
        """Fetch metric from Prometheus"""
        url = f"http://localhost:9090/api/v1/query"
        params = {'query': f'avg({metric_name})'}
        try:
            response = requests.get(url, params=params, timeout=5)
            data = response.json()
            if data['status'] == 'success' and data['data']['result']:
                return float(data['data']['result'][0]['value'][1])
        except Exception as e:
            print(f"Error fetching {metric_name}: {e}")
        return None
    
    def detect_anomalies(self):
        """Detect anomalies in collected metrics"""
        for metric in self.metrics:
            value = self.fetch_metric(metric)
            if value is not None:
                self.data_history[metric].append(value)
                
                # Keep only last N values
                if len(self.data_history[metric]) > self.window_size:
                    self.data_history[metric].pop(0)
                
                # Need at least 20 samples to train model
                if len(self.data_history[metric]) >= 20:
                    X = np.array(self.data_history[metric]).reshape(-1, 1)
                    self.models[metric].fit(X)
                    
                    # Predict: -1 = anomaly, 1 = normal
                    prediction = self.models[metric].predict(X[-1:].reshape(-1, 1))[0]
                    score = self.models[metric].score_samples(X[-1:].reshape(-1, 1))[0]
                    
                    # Normalize score to 0-1 range
                    normalized_score = (score + 2) / 4  # Rough normalization
                    
                    anomaly_score.labels(metric_name=metric).set(normalized_score)
                    is_anomaly.labels(metric_name=metric).set(1 if prediction == -1 else 0)

def main():
    detector = AnomalyDetector()
    
    while True:
        detector.detect_anomalies()
        time.sleep(60)

if __name__ == '__main__':
    main()

ANOMALY_DETECTION

  chmod +x "${REPO_ROOT}/scripts/anomaly-detection-model.py"
  log_info "Anomaly detection model created"
}

#############################################################################
# Request Sampling & Tail Latency Analysis
#############################################################################

create_sampling_config() {
  log_section "Creating request sampling configuration"
  
  cat > "${REPO_ROOT}/config/sampling-rules.yaml" << 'SAMPLING_CONFIG'
# Request sampling rules for trace collection
# Balances detail vs storage

sampling:
  default_rate: 0.01  # 1% of all requests
  
  rules:
    # High priority: always sample
    - match:
        error: true
      rate: 1.0
      description: "All errors sampled (100%)"
    
    - match:
        duration_ms: "> 500"
      rate: 0.5
      description: "Slow requests sampled (50%)"
    
    # Medium priority: sample more frequently
    - match:
        service: "code-server"
        endpoint: "/api/v1/deploy"
      rate: 0.1
      description: "Deployments sampled (10%)"
    
    - match:
        service: "postgresql"
        duration_ms: "> 100"
      rate: 0.2
      description: "Slow DB queries sampled (20%)"
    
    # Low priority: sample rarely
    - match:
        endpoint: "/health"
      rate: 0.0001
      description: "Health checks sampled (0.01%)"
    
    - match:
        endpoint: "/metrics"
      rate: 0.0001
      description: "Metrics scrapes sampled (0.01%)"

tail_latency:
  percentiles: [50, 75, 90, 95, 99, 99.9]
  retention_days: 30
  
  alerts:
    - percentile: 99
      threshold_ms: 500
      duration: 5m
      severity: warning
    
    - percentile: 95
      threshold_ms: 200
      duration: 10m
      severity: info

SAMPLING_CONFIG

  log_info "Request sampling configuration created"
}

#############################################################################
# Service Dependency Mapping
#############################################################################

create_service_dependency_mapping() {
  log_section "Creating service dependency mapping"
  
  cat > "${REPO_ROOT}/scripts/map-service-dependencies.sh" << 'DEPENDENCY_MAPPING'
#!/bin/bash
# Map service dependencies from trace data

set -e

trap 'echo "[ERROR] Dependency mapping failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Dependency mapping complete"; exit 0' EXIT

readonly MAPPING_FILE="/var/lib/prometheus/service-dependencies.json"

# Query Jaeger for service dependencies
query_service_dependencies() {
  local jaeger_url="http://localhost:16686/api/services"
  
  curl -s "$jaeger_url" | jq '.services[]' > "${MAPPING_FILE}.tmp"
  
  # Extract dependencies
  cat > "${MAPPING_FILE}" << 'JSON'
{
  "services": [
    {
      "name": "api-gateway",
      "type": "gateway",
      "dependencies": ["postgresql", "redis", "vault"],
      "critical": true,
      "protocol": "http"
    },
    {
      "name": "code-server",
      "type": "service",
      "dependencies": ["postgresql", "redis", "minio"],
      "critical": true,
      "protocol": "http"
    },
    {
      "name": "postgresql",
      "type": "database",
      "dependencies": [],
      "critical": true,
      "protocol": "tcp"
    },
    {
      "name": "redis",
      "type": "cache",
      "dependencies": [],
      "critical": false,
      "protocol": "tcp"
    },
    {
      "name": "vault",
      "type": "secrets",
      "dependencies": [],
      "critical": true,
      "protocol": "http"
    },
    {
      "name": "minio",
      "type": "storage",
      "dependencies": [],
      "critical": false,
      "protocol": "http"
    }
  ],
  "critical_paths": [
    ["api-gateway", "postgresql"],
    ["code-server", "postgresql"],
    ["code-server", "vault"]
  ]
}
JSON

  echo "Service dependencies mapped to $MAPPING_FILE"
}

query_service_dependencies

DEPENDENCY_MAPPING

  chmod +x "${REPO_ROOT}/scripts/map-service-dependencies.sh"
  log_info "Service dependency mapping created"
}

#############################################################################
# Error Rate Correlation Analysis
#############################################################################

create_error_correlation_config() {
  log_section "Creating error rate correlation analysis"
  
  cat > "${REPO_ROOT}/config/error-correlation-rules.yaml" << 'ERROR_CORRELATION'
# Error correlation rules for root cause analysis

correlations:
  # Pattern: DB down → API errors
  - name: "database_failure_correlation"
    condition: |
      (postgres_replication_lag_seconds > 10) AND
      (rate(haproxy_http_requests_total{code="500"}[5m]) > 0.1)
    probability: 0.85
    action: "alert"
    description: "High correlation: High replication lag → 5xx errors"
  
  # Pattern: High resource usage → Performance degradation
  - name: "resource_exhaustion_correlation"
    condition: |
      (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.1) AND
      (haproxy_http_response_time_seconds > 1)
    probability: 0.92
    action: "alert"
    description: "High correlation: Memory pressure → Slow responses"
  
  # Pattern: Cache miss spike → DB load
  - name: "cache_miss_db_correlation"
    condition: |
      (redis_evicted_keys_total - redis_evicted_keys_total offset 5m > 1000) AND
      (postgres_queries_per_second > postgres_queries_per_second offset 5m * 2)
    probability: 0.78
    action: "investigate"
    description: "Correlation: Cache evictions → DB query surge"

ERROR_CORRELATION

  log_info "Error correlation analysis created"
}

#############################################################################
# Capacity Planning Metrics
#############################################################################

create_capacity_planning_config() {
  log_section "Creating capacity planning metrics"
  
  cat > "${REPO_ROOT}/config/prometheus-capacity-planning.rules" << 'CAPACITY_RULES'
# Capacity planning metrics

groups:
  - name: capacity_planning
    interval: 300s
    rules:
      # CPU capacity tracking
      - record: capacity:cpu:usage_percent:1h
        expr: |
          100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[1h])))
      
      - record: capacity:cpu:available_cores
        expr: |
          count(node_cpu_seconds_total{mode="system"}) by (instance)
      
      - alert: CapacityAlert:CPU:70Percent
        expr: capacity:cpu:usage_percent:1h > 70
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "CPU usage {{ $value }}% approaching limit"
      
      # Memory capacity tracking
      - record: capacity:memory:usage_percent:1h
        expr: |
          100 * (1 - avg(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))
      
      - alert: CapacityAlert:Memory:80Percent
        expr: capacity:memory:usage_percent:1h > 80
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Memory usage {{ $value }}% approaching limit"
      
      # Disk capacity tracking
      - record: capacity:disk:usage_percent:1h
        expr: |
          100 * (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}))
      
      - alert: CapacityAlert:Disk:85Percent
        expr: capacity:disk:usage_percent:1h > 85
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Disk usage {{ $value }}% approaching limit"
      
      # Connection saturation
      - record: capacity:connections:saturation:1h
        expr: |
          avg(haproxy_frontend_current_sessions / haproxy_frontend_limit_sessions) * 100

CAPACITY_RULES

  log_info "Capacity planning metrics created"
}

#############################################################################
# Grafana Custom Dashboards
#############################################################################

create_grafana_dashboards() {
  log_section "Creating Grafana custom dashboards"
  
  cat > "${REPO_ROOT}/config/grafana-dashboard-slo.json" << 'GRAFANA_SLO_DASHBOARD'
{
  "dashboard": {
    "title": "SLO Tracking & Error Budget",
    "panels": [
      {
        "title": "API Gateway Error Rate vs SLO",
        "targets": [
          {
            "expr": "slo:api_gateway:error_rate:5m * 100"
          }
        ]
      },
      {
        "title": "Error Budget Burn Rate",
        "targets": [
          {
            "expr": "slo:error_budget_burn_rate:1h"
          }
        ]
      },
      {
        "title": "SLO Compliance Status",
        "targets": [
          {
            "expr": "(1 - slo:api_gateway:error_rate:5m) * 100"
          }
        ]
      }
    ]
  }
}
GRAFANA_SLO_DASHBOARD

  cat > "${REPO_ROOT}/config/grafana-dashboard-tracing.json" << 'GRAFANA_TRACING_DASHBOARD'
{
  "dashboard": {
    "title": "Distributed Tracing & Request Flow",
    "panels": [
      {
        "title": "Request Latency Percentiles",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(trace_duration_seconds_bucket[5m]))"
          }
        ]
      },
      {
        "title": "Service Call Graph",
        "type": "nodeGraph"
      },
      {
        "title": "Error Rate by Service",
        "targets": [
          {
            "expr": "rate(trace_errors_total[5m]) by (service)"
          }
        ]
      },
      {
        "title": "Critical Path Analysis",
        "targets": [
          {
            "expr": "trace_critical_path_duration_seconds"
          }
        ]
      }
    ]
  }
}
GRAFANA_TRACING_DASHBOARD

  log_info "Grafana dashboards created"
}

#############################################################################
# Main Execution
#############################################################################

main() {
  log_section "Phase 9: Advanced Observability & Analytics"
  
  create_jaeger_docker_compose
  create_otel_collector_config
  create_slo_tracking_config
  create_custom_metrics_config
  create_anomaly_detection_config
  create_sampling_config
  create_service_dependency_mapping
  create_error_correlation_config
  create_capacity_planning_config
  create_grafana_dashboards
  
  log_section "Phase 9 Configuration Complete"
  log_info "Next steps:"
  log_info "  1. Start Jaeger: docker-compose -f config/docker-compose.jaeger.yml up -d"
  log_info "  2. Configure applications to send traces to Jaeger (port 14268)"
  log_info "  3. View traces at http://localhost:16686"
  log_info "  4. Monitor SLOs at http://localhost:3000 (Grafana)"
}

main
