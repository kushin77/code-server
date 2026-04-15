# Phase 9-B: Prometheus SLO Metrics & Analytics
# Issue #365: Metrics Analytics & SLO Reporting
# Immutable version: Prometheus 2.48.0
# NOTE: terraform block and shared variables defined in main.tf and phase-9-variables.tf

variable "prometheus_version" {
  description = "Prometheus version (immutable)"
  type        = string
  default     = "2.48.0"
}

# SLO Rules Configuration
resource "local_file" "slo_rules" {
  filename = "${path.module}/../config/prometheus/slo-rules.yml"
  content  = <<-EOT
groups:
  # Service Level Objectives (SLOs) for all core services
  - name: slo-rules
    interval: 30s
    rules:
      # Code-Server Availability SLO (99.95%)
      - record: slo:code_server_availability:5m
        expr: rate(code_server_up[5m])

      # Code-Server Request Latency SLO (p99 < 100ms)
      - record: slo:code_server_latency:p99
        expr: histogram_quantile(0.99, rate(code_server_request_duration_seconds_bucket[5m]))

      # Code-Server Error Rate SLO (< 0.1%)
      - record: slo:code_server_error_rate:5m
        expr: rate(code_server_http_requests_total{status=~"5.."}[5m]) / rate(code_server_http_requests_total[5m])

      # PostgreSQL Availability SLO (99.99%)
      - record: slo:postgres_availability:5m
        expr: up{job="postgres"} > 0

      # PostgreSQL Replication Lag SLO (< 30s)
      - record: slo:postgres_replication_lag_seconds
        expr: pg_wal_lsn_lag_seconds

      # PostgreSQL Query Performance SLO (p99 < 100ms)
      - record: slo:postgres_query_latency:p99
        expr: histogram_quantile(0.99, rate(pg_stat_statements_mean_time_seconds_bucket[5m]))

      # Redis Availability SLO (99.99%)
      - record: slo:redis_availability:5m
        expr: up{job="redis"} > 0

      # Redis Command Latency SLO (p99 < 10ms)
      - record: slo:redis_command_latency:p99
        expr: histogram_quantile(0.99, rate(redis_command_duration_seconds_bucket[5m]))

      # HAProxy Backend Availability SLO (99.99%)
      - record: slo:haproxy_backend_availability:5m
        expr: rate(haproxy_backend_up[5m])

      # HAProxy Request Latency SLO (p99 < 50ms)
      - record: slo:haproxy_latency:p99
        expr: histogram_quantile(0.99, rate(haproxy_http_request_time_ms_bucket[5m]))

      # HAProxy Error Rate SLO (< 0.1%)
      - record: slo:haproxy_error_rate:5m
        expr: rate(haproxy_frontend_http_responses_total{code=~"5.."}[5m]) / rate(haproxy_frontend_http_responses_total[5m])

      # Container Resource Utilization SLOs
      - record: slo:container_cpu_percent:5m
        expr: (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100

      - record: slo:container_memory_percent:5m
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

      # Disk I/O Utilization SLO (< 70%)
      - record: slo:disk_io_percent:5m
        expr: (rate(node_disk_io_time_seconds_total[5m]) / 5) * 100

      # Network Throughput SLO (< 80% capacity)
      - record: slo:network_throughput_percent:5m
        expr: rate(node_network_transmit_bytes_total[5m]) / 1000000000 * 100

  - name: error-budget-rules
    interval: 60s
    rules:
      # Monthly Error Budget Calculation
      - record: slo:error_budget:month
        expr: (1 - (30 * 24 * 60 * 60) * (1 - 0.9995)) * 100

      # Error Budget Consumed (Code-Server)
      - record: slo:error_budget_consumed:code_server
        expr: (1 - slo:code_server_availability:5m) * 100

      # Error Budget Remaining (Code-Server)
      - record: slo:error_budget_remaining:code_server
        expr: slo:error_budget:month - slo:error_budget_consumed:code_server

      # Burn Rate (code-server)
      - record: slo:burn_rate:code_server:1h
        expr: |
          (
            1 - (
              rate(code_server_up[1h]) and on(instance) up{job="code-server"}
            )
          ) * 100 / 2.592

  - name: operational-metrics
    interval: 30s
    rules:
      # Request Rate by Service
      - record: rate:http_requests:5m:by_service
        expr: sum(rate(http_requests_total[5m])) by (service)

      # P50, P95, P99 Latencies
      - record: latency:p50
        expr: histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))

      - record: latency:p95
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

      - record: latency:p99
        expr: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

      # Error Rate by Status Code
      - record: rate:http_errors:5m:by_status
        expr: sum(rate(http_requests_total{status=~"[45].."}[5m])) by (status)

      # Resource Saturation
      - record: saturation:cpu
        expr: avg(slo:container_cpu_percent:5m)

      - record: saturation:memory
        expr: avg(slo:container_memory_percent:5m)

      - record: saturation:disk_io
        expr: avg(slo:disk_io_percent:5m)

  - name: alerting-rules
    interval: 30s
    rules:
      # SLO Breach Alerts
      - alert: CodeServerSLOBreach
        expr: slo:code_server_availability:5m < 0.9995
        for: 5m
        labels:
          severity: critical
          slo: availability
        annotations:
          summary: "Code-Server SLO breach (availability < 99.95%)"

      - alert: PostgreSLOBreach
        expr: slo:postgres_replication_lag_seconds > 30
        for: 5m
        labels:
          severity: critical
          slo: replication_lag
        annotations:
          summary: "PostgreSQL replication lag SLO breach (> 30s)"

      - alert: HighErrorRate
        expr: slo:code_server_error_rate:5m > 0.001
        for: 5m
        labels:
          severity: warning
          slo: error_rate
        annotations:
          summary: "High error rate detected (> 0.1%)"

      - alert: ErrorBudgetBurnoutWarning
        expr: slo:burn_rate:code_server:1h > 10
        for: 10m
        labels:
          severity: warning
          slo: error_budget
        annotations:
          summary: "Error budget burn rate is high"

      - alert: HighResourceSaturation
        expr: saturation:cpu > 85 or saturation:memory > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Resource saturation is high"
EOT
}

# Grafana SLO Dashboard Configuration
resource "local_file" "grafana_slo_dashboard" {
  filename = "${path.module}/../config/grafana/dashboards/slo-dashboard.json"
  content  = <<-EOT
{
  "annotations": {
    "list": []
  },
  "description": "Service Level Objective (SLO) Dashboard",
  "id": null,
  "links": [],
  "panels": [
    {
      "title": "Availability SLO Status",
      "targets": [
        {
          "expr": "slo:code_server_availability:5m * 100"
        }
      ],
      "type": "gauge",
      "options": {
        "thresholds": {
          "mode": "percentage",
          "steps": [
            {"color": "red", "value": 0},
            {"color": "yellow", "value": 99},
            {"color": "green", "value": 99.95}
          ]
        }
      }
    },
    {
      "title": "Latency P99 (Target: <100ms)",
      "targets": [
        {
          "expr": "slo:code_server_latency:p99 * 1000"
        }
      ],
      "type": "timeseries"
    },
    {
      "title": "Error Rate (Target: <0.1%)",
      "targets": [
        {
          "expr": "slo:code_server_error_rate:5m * 100"
        }
      ],
      "type": "timeseries"
    },
    {
      "title": "Error Budget Remaining",
      "targets": [
        {
          "expr": "slo:error_budget_remaining:code_server"
        }
      ],
      "type": "gauge"
    },
    {
      "title": "Replication Lag (Target: <30s)",
      "targets": [
        {
          "expr": "slo:postgres_replication_lag_seconds"
        }
      ],
      "type": "timeseries"
    },
    {
      "title": "Resource Saturation",
      "targets": [
        {
          "expr": "saturation:cpu",
          "legendFormat": "CPU"
        },
        {
          "expr": "saturation:memory",
          "legendFormat": "Memory"
        }
      ],
      "type": "timeseries"
    }
  ],
  "refresh": "30s",
  "schemaVersion": 37,
  "style": "dark",
  "tags": ["slo", "monitoring"],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-24h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "Service Level Objective (SLO) Dashboard",
  "uid": "slo-dashboard",
  "version": 1
}
EOT
}

# Prometheus Query Optimization Rules
resource "local_file" "prometheus_optimization" {
  filename = "${path.module}/../config/prometheus/recording-rules.yml"
  content  = <<-EOT
groups:
  - name: performance-optimization
    interval: 15s
    rules:
      # Pre-compute frequently used aggregations to reduce query load
      - record: instance:node_cpu_utilisation:rate5m
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

      - record: instance:node_memory_utilisation:percentage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

      - record: instance:node_network_receive_bytes:rate5m
        expr: rate(node_network_receive_bytes_total[5m])

      - record: instance:node_network_transmit_bytes:rate5m
        expr: rate(node_network_transmit_bytes_total[5m])

      - record: instance:node_disk_read_bytes:rate5m
        expr: rate(node_disk_read_bytes_total[5m])

      - record: instance:node_disk_written_bytes:rate5m
        expr: rate(node_disk_written_bytes_total[5m])

      # Service-level aggregations
      - record: service:requests:rate5m
        expr: sum(rate(http_requests_total[5m])) by (service)

      - record: service:errors:rate5m
        expr: sum(rate(http_requests_total{status=~"[45].."}[5m])) by (service)

      - record: service:latency:p95
        expr: histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (service, le))

      # Business metrics
      - record: business:transactions:rate5m
        expr: sum(rate(transaction_total[5m]))

      - record: business:transaction_value:sum5m
        expr: sum(rate(transaction_value_total[5m]))
EOT
}

output "prometheus_slo_rules_url" {
  value = "http://${var.primary_host_ip}:9090/api/v1/rules"
}

output "grafana_slo_dashboard_url" {
  value = "http://${var.primary_host_ip}:3000/d/slo-dashboard"
}

output "slo_targets" {
  value = {
    code_server_availability = "99.95%"
    code_server_latency_p99_ms = 100
    code_server_error_rate = "< 0.1%"
    postgres_availability = "99.99%"
    postgres_replication_lag_seconds = 30
    redis_availability = "99.99%"
    haproxy_availability = "99.99%"
    cpu_saturation_threshold_percent = 85
    memory_saturation_threshold_percent = 85
  }
}

output "prometheus_retention" {
  value = {
    retention_days = 15
    chunk_encoding = "snappy"
    tsdb_directory = "/prometheus/data"
    wal_directory = "/prometheus/wal"
  }
}
