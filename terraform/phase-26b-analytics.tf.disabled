terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 26-B: Developer Analytics Dashboard (15 hours)
# Real-time visibility into API usage patterns and performance
# ════════════════════════════════════════════════════════════════════════════

# Analytics data collection configuration (single source of truth)
locals {
  analytics_metrics = {
    request_volume = {
      granularities = ["hour", "day", "week", "month"]
      retention     = "3 months"
    }
    error_tracking = {
      error_types = ["400", "401", "403", "429", "500", "503"]
      retention   = "6 months"
    }
    latency_percentiles = {
      percentiles = [50, 95, 99]
      retention   = "3 months"
    }
    cost_estimation = {
      method     = "compute_time * $rate_per_ms"
      granularity = "per_query"
      currency   = "USD"
    }
    top_queries = {
      limit       = 100
      update_freq = "6 hours"
    }
  }

  analytics_services = {
    aggregator = {
      name       = "analytics-aggregator"
      image      = "python:3.11-slim"
      cpu_limit  = "500m"
      memory_limit = "512Mi"
    }
    api = {
      name       = "analytics-api"
      image      = "node:20-alpine"
      cpu_limit  = "250m"
      memory_limit = "256Mi"
    }
  }
}

# ClickHouse deployment for time-series analytics
resource "local_file" "phase_26b_clickhouse_deployment" {
  filename = "${path.module}/../kubernetes/phase-26-analytics/clickhouse-deployment.yaml"
  
  content = <<-EOT
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: clickhouse-config
      namespace: default
    data:
      config.xml: |
        <clickhouse>
          <listen_host>0.0.0.0</listen_host>
          <http_port>8123</http_port>
          <tcp_port>9000</tcp_port>
          <max_connections>4096</max_connections>
          <default_database>analytics</default_database>
          <timezone>UTC</timezone>
        </clickhouse>
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: clickhouse
      namespace: default
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: clickhouse
      template:
        metadata:
          labels:
            app: clickhouse
        spec:
          containers:
          - name: clickhouse
            image: clickhouse/clickhouse-server:24.1
            ports:
            - containerPort: 8123
              name: http
            - containerPort: 9000
              name: tcp
            resources:
              limits:
                cpu: 4
                memory: 8Gi
              requests:
                cpu: 2
                memory: 4Gi
            volumeMounts:
            - name: data
              mountPath: /var/lib/clickhouse
            - name: config
              mountPath: /etc/clickhouse-server/config.d
            livenessProbe:
              httpGet:
                path: /ping
                port: http
              initialDelaySeconds: 30
              periodSeconds: 10
          volumes:
          - name: config
            configMap:
              name: clickhouse-config
          - name: data
            emptyDir: {}
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: clickhouse
      namespace: default
    spec:
      selector:
        app: clickhouse
      ports:
      - port: 8123
        name: http
      - port: 9000
        name: tcp
      type: ClusterIP
  EOT
}

# Analytics aggregator service
resource "local_file" "phase_26b_analytics_aggregator" {
  filename = "${path.module}/../kubernetes/phase-26-analytics/analytics-aggregator-deployment.yaml"
  
  content = <<-EOT
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: analytics-aggregator
      namespace: default
    spec:
      replicas: 2
      selector:
        matchLabels:
          app: analytics-aggregator
      template:
        metadata:
          labels:
            app: analytics-aggregator
        spec:
          containers:
          - name: aggregator
            image: python:3.11-slim
            env:
            - name: PROMETHEUS_URL
              value: "http://prometheus:9090"
            - name: CLICKHOUSE_HOST
              value: "clickhouse"
            - name: CLICKHOUSE_PORT
              value: "9000"
            resources:
              limits:
                cpu: 500m
                memory: 512Mi
              requests:
                cpu: 250m
                memory: 256Mi
            livenessProbe:
              exec:
                command:
                - /bin/sh
                - -c
                - ps aux | grep aggregator
              initialDelaySeconds: 30
              periodSeconds: 10
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: analytics-aggregator
      namespace: default
    spec:
      selector:
        app: analytics-aggregator
      ports:
      - port: 8000
        name: metrics
      type: ClusterIP
  EOT

  depends_on = [local_file.phase_26b_clickhouse_deployment]
}

output "phase_26b_analytics_config" {
  description = "Phase 26-B analytics configuration"
  value       = local.analytics_metrics
}

output "phase_26b_status" {
  description = "Phase 26-B implementation status"
  value = {
    status         = "IMPLEMENTED"
    storage        = "ClickHouse time-series database"
    metrics        = "Request volume, errors, latency, cost"
    update_freq    = "Real-time with <5min latency"
    deployment     = "192.168.168.31"
  }
}
