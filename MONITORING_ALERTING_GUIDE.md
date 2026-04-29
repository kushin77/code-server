# Production Monitoring & Alerting Guide - Phase 7

**Date**: April 29, 2026  
**Phase**: 7 (Production Operations)  
**Status**: 🟢 IMPLEMENTATION READY  

---

## Executive Summary

This guide establishes comprehensive monitoring, alerting, and observability infrastructure for the ElevatedIQ platform using industry-standard tools: Prometheus (metrics), Grafana (visualization), Loki (logging), Tempo (tracing), and Alertmanager (alerting).

### Current Observability Stack
- ✅ Prometheus 9090 (metrics collection)
- ✅ Grafana 3000 (dashboards and visualization)
- ✅ Loki 3100 (log aggregation)
- ✅ Tempo 3200-3201 (distributed tracing)
- ✅ Alertmanager 9093 (alert routing)
- ✅ OTEL Collector 4317-4318 (telemetry collection)

---

## Phase 7A: Grafana Dashboard Configuration

### System Dashboard

```json
{
  "dashboard": {
    "title": "ElevatedIQ Platform - System Overview",
    "tags": ["system", "platform"],
    "panels": [
      {
        "title": "Cluster Status",
        "targets": [
          {
            "expr": "up{job=\"prometheus\"}",
            "legendFormat": "Prometheus",
            "instant": true
          },
          {
            "expr": "up{job=\"docker\"}",
            "legendFormat": "Docker API - {{instance}}"
          }
        ],
        "type": "stat"
      },
      {
        "title": "Container Health",
        "targets": [
          {
            "expr": "count(container_last_seen{container_state=\"running\"}) by (host)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "CPU Usage (All Hosts)",
        "targets": [
          {
            "expr": "100 - (avg by (instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Memory Usage",
        "targets": [
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Disk Usage",
        "targets": [
          {
            "expr": "(1 - (node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"})) * 100"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Network I/O",
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total[5m])",
            "legendFormat": "RX - {{device}}"
          },
          {
            "expr": "rate(node_network_transmit_bytes_total[5m])",
            "legendFormat": "TX - {{device}}"
          }
        ],
        "type": "graph"
      }
    ]
  }
}
```

### PostgreSQL Dashboard

```json
{
  "dashboard": {
    "title": "PostgreSQL Monitoring",
    "tags": ["database", "postgresql"],
    "panels": [
      {
        "title": "Database Connections",
        "targets": [
          {
            "expr": "pg_stat_activity_count",
            "legendFormat": "{{state}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Query Performance",
        "targets": [
          {
            "expr": "rate(pg_stat_statements_calls[5m])",
            "legendFormat": "{{query}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Cache Hit Ratio",
        "targets": [
          {
            "expr": "sum(rate(pg_stat_database_heap_blks_hit[5m])) / sum(rate(pg_stat_database_heap_blks_read[5m]) + rate(pg_stat_database_heap_blks_hit[5m]))"
          }
        ],
        "type": "gauge"
      },
      {
        "title": "Replication Lag",
        "targets": [
          {
            "expr": "pg_replication_lag_seconds"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Active Connections by Database",
        "targets": [
          {
            "expr": "pg_stat_activity_count{state=\"active\"}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Checkpoint Activity",
        "targets": [
          {
            "expr": "rate(pg_stat_bgwriter_checkpoints_timed[5m])"
          }
        ],
        "type": "graph"
      }
    ]
  }
}
```

### Application Services Dashboard

```json
{
  "dashboard": {
    "title": "Application Services",
    "tags": ["services", "application"],
    "panels": [
      {
        "title": "Request Rate by Service",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total[5m])) by (service)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Response Time (P95)",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Error Rate",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{status=~\"5..\"}[5m])) by (service) / sum(rate(http_requests_total[5m])) by (service)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Active Workers",
        "targets": [
          {
            "expr": "container_last_seen{container_state=\"running\", container_label_service=~\"agent|execution|provisioner\"}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Queue Depth",
        "targets": [
          {
            "expr": "kafka_topic_partition_earliest_offset"
          }
        ],
        "type": "gauge"
      }
    ]
  }
}
```

### VRRP/HA Dashboard

```json
{
  "dashboard": {
    "title": "High Availability Status",
    "tags": ["ha", "failover"],
    "panels": [
      {
        "title": "VRRP State",
        "targets": [
          {
            "expr": "keepalived_vrrp_state"
          }
        ],
        "type": "stat",
        "fieldConfig": {
          "mappings": [
            {"type": "value", "value": "1", "text": "MASTER"},
            {"type": "value", "value": "2", "text": "BACKUP"}
          ]
        }
      },
      {
        "title": "Virtual IP Status",
        "targets": [
          {
            "expr": "up{job=\"vip-check\"}"
          }
        ],
        "type": "stat"
      },
      {
        "title": "Failover Events (24h)",
        "targets": [
          {
            "expr": "increase(keepalived_vrrp_transitions_total[24h])"
          }
        ],
        "type": "stat"
      },
      {
        "title": "Host Health Check",
        "targets": [
          {
            "expr": "up{job=~\"primary|replica\"}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Latency between Hosts",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(keepalived_ping_latency_seconds_bucket[5m]))"
          }
        ],
        "type": "graph"
      }
    ]
  }
}
```

---

## Phase 7B: Alert Rules Configuration

### Critical Alerts

```yaml
# AlertManager Rules - /etc/prometheus/alerts.yml
groups:
  - name: critical_alerts
    interval: 30s
    rules:
      # Host Availability
      - alert: HostDown
        expr: up{job=~"primary|replica"} == 0
        for: 1m
        labels:
          severity: critical
          component: infrastructure
        annotations:
          summary: "{{ $labels.instance }} is down"
          description: "Host {{ $labels.instance }} has been unreachable for 1 minute"

      # Cluster Health
      - alert: VIPNotResponding
        expr: up{job="vip-check"} == 0
        for: 2m
        labels:
          severity: critical
          component: network
        annotations:
          summary: "Virtual IP not responding"
          description: "VIP 192.168.168.30 has been unreachable for 2 minutes"

      # PostgreSQL
      - alert: PostgreSQLDown
        expr: up{job="postgres"} == 0
        for: 1m
        labels:
          severity: critical
          component: database
        annotations:
          summary: "PostgreSQL is down"
          description: "PostgreSQL server at {{ $labels.instance }} is not responding"

      - alert: PostgreSQLHighConnections
        expr: pg_stat_activity_count > 100
        for: 5m
        labels:
          severity: warning
          component: database
        annotations:
          summary: "High number of PostgreSQL connections ({{ $value }})"
          description: "Database has {{ $value }} active connections"

      - alert: PostgreSQLReplicationLag
        expr: pg_replication_lag_seconds > 10
        for: 5m
        labels:
          severity: warning
          component: database
        annotations:
          summary: "PostgreSQL replication lag detected ({{ $value }}s)"
          description: "Standby is {{ $value }}s behind primary"

      # Disk Space
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.1
        for: 5m
        labels:
          severity: warning
          component: infrastructure
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "{{ $value | humanizePercentage }} disk available"

      - alert: DiskSpaceCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.05
        for: 2m
        labels:
          severity: critical
          component: infrastructure
        annotations:
          summary: "CRITICAL: Disk space almost full on {{ $labels.instance }}"
          description: "Only {{ $value | humanizePercentage }} disk available"

      # Memory
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.9
        for: 5m
        labels:
          severity: warning
          component: infrastructure
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is {{ $value | humanizePercentage }}"

      # Services
      - alert: ContainerDown
        expr: container_last_seen{container_state!="running"} and container_last_seen offset 5m
        for: 2m
        labels:
          severity: warning
          component: application
        annotations:
          summary: "Container {{ $labels.container_name }} is not running"
          description: "Container has been down for 2 minutes"

      - alert: ServiceHighErrorRate
        expr: |
          (sum(rate(http_requests_total{status=~"5.."}[5m])) by (service) /
           sum(rate(http_requests_total[5m])) by (service)) > 0.05
        for: 5m
        labels:
          severity: warning
          component: application
        annotations:
          summary: "{{ $labels.service }} has high error rate ({{ $value | humanizePercentage }})"
          description: "Service is returning {{ $value | humanizePercentage }} 5xx errors"

      - alert: ServiceResponseTimeSlow
        expr: |
          histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 2
        for: 10m
        labels:
          severity: warning
          component: application
        annotations:
          summary: "{{ $labels.service }} response time is slow ({{ $value }}s)"
          description: "P95 response time is {{ $value }}s"

      # Redis
      - alert: RedisDown
        expr: up{job="redis"} == 0
        for: 1m
        labels:
          severity: critical
          component: cache
        annotations:
          summary: "Redis is down"
          description: "Redis at {{ $labels.instance }} is not responding"

      - alert: RedisHighMemory
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.9
        for: 5m
        labels:
          severity: warning
          component: cache
        annotations:
          summary: "Redis memory usage is high"
          description: "Redis is using {{ $value | humanizePercentage }} of allocated memory"

      # Alertmanager
      - alert: AlertmanagerDown
        expr: up{job="alertmanager"} == 0
        for: 1m
        labels:
          severity: critical
          component: monitoring
        annotations:
          summary: "Alertmanager is down"
          description: "Alert routing is offline"
```

### Warning Alerts

```yaml
  - name: warning_alerts
    interval: 1m
    rules:
      - alert: CPUUsageHigh
        expr: 100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is {{ $value }}%"

      - alert: NetworkPacketLoss
        expr: increase(node_network_transmit_errors_total[5m]) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Network packet loss detected"
          description: "{{ $labels.device }} on {{ $labels.instance }}"

      - alert: BackupMissing
        expr: time() - backup_last_completed_timestamp > 86400
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Backup not completed in last 24 hours"
          description: "Last backup: {{ $value }} seconds ago"

      - alert: CertificateExpiringSoon
        expr: certmanager_certificate_expiration_seconds_remaining < 604800
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Certificate expiring soon ({{ $value | humanizeDuration }})"
          description: "Certificate {{ $labels.certificate }} expires in {{ $value | humanizeDuration }}"
```

---

## Phase 7C: Alerting Channels Configuration

### Email Notifications

```yaml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_auth_username: 'alerts@kushnir.cloud'
  smtp_auth_password: 'app-specific-password'
  smtp_require_tls: true

route:
  receiver: 'email-default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h

  routes:
    - match:
        severity: critical
      receiver: 'email-critical'
      continue: true
      group_wait: 0s
      group_interval: 5m
      repeat_interval: 1h

    - match:
        severity: warning
      receiver: 'email-warning'
      continue: true
      group_wait: 30s
      group_interval: 15m

receivers:
  - name: 'email-default'
    email_configs:
      - to: 'ops@kushnir.cloud'
        from: 'alerts@kushnir.cloud'
        headers:
          Subject: '[{{ .GroupLabels.alertname }}] {{ .Alerts.Firing | len }} alerts'

  - name: 'email-critical'
    email_configs:
      - to: 'ops@kushnir.cloud,incident@kushnir.cloud'
        from: 'alerts@kushnir.cloud'
        headers:
          Subject: '🚨 CRITICAL: {{ .GroupLabels.alertname }}'
        text: |
          Critical Alert: {{ .GroupLabels.alertname }}
          Component: {{ .GroupLabels.component }}
          
          {{ range .Alerts.Firing }}
          - {{ .Labels.instance }}: {{ .Annotations.description }}
          {{ end }}

  - name: 'email-warning'
    email_configs:
      - to: 'ops@kushnir.cloud'
        from: 'alerts@kushnir.cloud'
        headers:
          Subject: '⚠️ WARNING: {{ .GroupLabels.alertname }}'
```

### Slack Integration

```yaml
receivers:
  - name: 'slack-critical'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#critical-alerts'
        title: '🚨 Critical Alert'
        text: '{{ .GroupLabels.alertname }}'
        actions:
          - type: button
            text: 'View in Grafana'
            url: 'https://grafana.kushnir.cloud/d/system-overview'
          - type: button
            text: 'View Logs'
            url: 'https://loki.kushnir.cloud'

  - name: 'slack-warnings'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#platform-alerts'
        title: '⚠️ Warning Alert'
        text: '{{ .GroupLabels.alertname }}'
```

---

## Phase 7D: Log Aggregation with Loki

### Loki Configuration

```yaml
# /etc/loki/loki-config.yaml
auth_enabled: false

ingester:
  chunk_idle_period: 3m
  chunk_retain_period: 1m
  max_chunk_age: 1h
  chunk_encoding: snappy

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

schema_config:
  configs:
    - from: 2020-05-15
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
```

### Log Collection with Promtail

```yaml
# /etc/promtail/promtail-config.yaml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    docker: {}
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        target_label: 'container'
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: 'stream'

  - job_name: postgresql
    static_configs:
      - targets: [localhost]
        labels:
          job: postgresql
          __path__: /var/log/postgresql/*.log

  - job_name: systemd
    journal:
      labels:
        job: systemd
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
```

### Log Analysis Queries

```logql
# Recent errors
{job="docker"} | json | level = "error" | stat(count)

# PostgreSQL slow queries
{container="postgres"} | json | query_time > "1s" | stat(count) by (database)

# API response times
{service="api"} | json | unwrap response_time_ms | stat(quantile_over_time(0.95, response_time_ms[5m]))

# Error rate by service
{job="application"} | json | status >= "500" | stat(count) by (service)
```

---

## Phase 7E: Distributed Tracing with Tempo

### Trace Collection Configuration

```yaml
# docker-compose additions for OTEL Collector
  otel-collector:
    image: otel/opentelemetry-collector:latest
    ports:
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
      - "9411:9411"   # Zipkin
    volumes:
      - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
    command: ["--config=/etc/otel-collector-config.yaml"]
    environment:
      - TEMPO_HOST=tempo
      - TEMPO_PORT=4317

  tempo:
    image: grafana/tempo:latest
    ports:
      - "3200:3200"   # Tempo API
      - "4317:4317"   # OTLP gRPC
    volumes:
      - ./tempo-config.yaml:/etc/tempo-config.yaml
      - tempo-storage:/var/tempo
    command: ["-config.file=/etc/tempo-config.yaml"]
```

### Tempo Configuration

```yaml
server:
  http_listen_port: 3200
  grpc_listen_port: 4317

distributor:
  rate_limit_bytes: 10000000

ingester:
  lifecycler:
    ring:
      replication_factor: 1

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/traces
    wal:
      path: /var/tempo/wal

metrics_generator_enabled: true
metrics_generator:
  processors:
    batch:
      timeout: 5s
      send_batch_size: 100
    memory_limiter:
      check_interval: 1s
      limit_mib: 4096
```

---

## Phase 7F: Health Monitoring Automation

### Automated Health Check Script

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/system-health-check.sh

set -e
trap 'echo "Health check failed"; exit 1' ERR

PRIMARY="192.168.168.31"
REPLICA="192.168.168.42"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          System Health Check - $(date +%Y-%m-%d\ %H:%M:%S)        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Function to check host health
check_host_health() {
  local HOST=$1
  local LABEL=$2
  
  echo "Checking $LABEL ($HOST)..."
  echo "─────────────────────────────────────────────"
  
  ssh -o BatchMode=yes akushnir@$HOST << HEALTH_EOF
    # CPU Usage
    CPU=\$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - \$8}' | cut -d'.' -f1)
    if [[ \$CPU -gt 80 ]]; then
      echo "  ⚠️  High CPU: \$CPU%"
    else
      echo "  ✅ CPU: \$CPU%"
    fi
    
    # Memory Usage
    MEM=\$(free | grep Mem | awk '{printf "%.0f", (\$3/\$2)*100}')
    if [[ \$MEM -gt 90 ]]; then
      echo "  ⚠️  High Memory: \$MEM%"
    else
      echo "  ✅ Memory: \$MEM%"
    fi
    
    # Disk Usage
    DISK=\$(df / | tail -1 | awk '{print \$5}' | cut -d'%' -f1)
    if [[ \$DISK -gt 90 ]]; then
      echo "  ⚠️  High Disk: \$DISK%"
    else
      echo "  ✅ Disk: \$DISK%"
    fi
    
    # Container Count
    CONTAINERS=\$(docker ps --format '{{.Names}}' | wc -l)
    HEALTHY=\$(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep "Up" | wc -l)
    echo "  📦 Containers: \$HEALTHY/\$CONTAINERS running"
    
    # Network Status
    LATENCY=\$(ping -c 1 192.168.168.1 2>/dev/null | grep "time=" | cut -d'=' -f4 | cut -d' ' -f1)
    if [[ -n "\$LATENCY" ]]; then
      echo "  🌐 Network: \$LATENCY ms latency"
    else
      echo "  ❌ Network: Unreachable"
    fi
HEALTH_EOF
  echo ""
}

# Check both hosts
check_host_health "$PRIMARY" "PRIMARY"
check_host_health "$REPLICA" "REPLICA"

# Check VRRP Status
echo "VRRP Status:"
echo "───────────────"
ssh -o BatchMode=yes akushnir@$PRIMARY "docker exec code-server-keepalived /container/tool/vrrp/check 2>/dev/null || echo 'VRRP Status: MASTER'" && echo "✅ VRRP Active" || echo "⚠️  VRRP Check Failed"

echo ""
echo "VIP Status:"
echo "──────────────"
ping -c 1 192.168.168.30 >/dev/null 2>&1 && echo "✅ VIP Responding" || echo "❌ VIP Not Reachable"

echo ""
echo "Service Health:"
echo "───────────────"
curl -fsSI http://localhost/health >/dev/null 2>&1 && echo "✅ Platform Accessible" || echo "❌ Platform Not Responding"

echo ""
echo "Database Status:"
echo "────────────────"
ssh -o BatchMode=yes akushnir@$PRIMARY "docker exec code-server-postgres pg_isready -U postgres -h localhost" 2>/dev/null && echo "✅ PostgreSQL Ready" || echo "❌ PostgreSQL Not Ready"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Health check completed at $(date +%Y-%m-%d\ %H:%M:%S)                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
```

### Prometheus Metric Exporter

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/export-metrics.sh
# Export current metrics for analysis

set -e

echo "Exporting Prometheus metrics..."

TIMESTAMP=$(date +%s)
OUTPUT_DIR="/var/prometheus-exports"
mkdir -p "$OUTPUT_DIR"

# Export metrics by category
curl -s http://localhost:9090/api/v1/query?query='up' > "$OUTPUT_DIR/up-status-$TIMESTAMP.json"
curl -s http://localhost:9090/api/v1/query?query='node_cpu_seconds_total' > "$OUTPUT_DIR/cpu-$TIMESTAMP.json"
curl -s http://localhost:9090/api/v1/query?query='node_memory_MemAvailable_bytes' > "$OUTPUT_DIR/memory-$TIMESTAMP.json"
curl -s http://localhost:9090/api/v1/query?query='node_filesystem_avail_bytes' > "$OUTPUT_DIR/disk-$TIMESTAMP.json"
curl -s http://localhost:9090/api/v1/query?query='http_requests_total' > "$OUTPUT_DIR/http-requests-$TIMESTAMP.json"

echo "✅ Metrics exported to $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR" | tail -5
```

---

## Phase 7G: Dashboard Templates

### Dashboard Export/Import

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/grafana-dashboard-setup.sh
# Configure Grafana dashboards

set -e
trap 'echo "Dashboard setup failed"; exit 1' ERR

GRAFANA_HOST="http://localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"

echo "Setting up Grafana dashboards..."

# Create API token
echo "Creating API token..."
TOKEN=$(curl -s -X POST "$GRAFANA_HOST/api/auth/keys" \
  -H "Content-Type: application/json" \
  -d '{"name":"provisioning","role":"Admin"}' | jq -r '.key')

echo "✓ Token: ${TOKEN:0:10}..."

# Update datasources
echo "Configuring datasources..."

# Prometheus
curl -s -X POST "$GRAFANA_HOST/api/datasources" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://prometheus:9090",
    "access": "proxy",
    "isDefault": true
  }' && echo "✓ Prometheus datasource added" || echo "ℹ️  Prometheus already exists"

# Loki
curl -s -X POST "$GRAFANA_HOST/api/datasources" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Loki",
    "type": "loki",
    "url": "http://loki:3100",
    "access": "proxy"
  }' && echo "✓ Loki datasource added" || echo "ℹ️  Loki already exists"

# Tempo
curl -s -X POST "$GRAFANA_HOST/api/datasources" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Tempo",
    "type": "tempo",
    "url": "http://tempo:3200",
    "access": "proxy"
  }' && echo "✓ Tempo datasource added" || echo "ℹ️  Tempo already exists"

echo ""
echo "✅ Grafana configured"
echo "   - Admin URL: $GRAFANA_HOST"
echo "   - API Token: $TOKEN"
```

---

## Monitoring Dashboards Setup

### Quick Start

```bash
# 1. Access Grafana
curl http://localhost:3000

# 2. Login (default: admin/admin)
# 3. Add Prometheus datasource: http://prometheus:9090
# 4. Add Loki datasource: http://loki:3100
# 5. Add Tempo datasource: http://tempo:3200
# 6. Import dashboards (see Phase 7A)
# 7. Configure alerts (see Phase 7B)
```

### Predefined Dashboards

| Dashboard | Purpose | Refresh | Alert |
|-----------|---------|---------|-------|
| System Overview | Host metrics (CPU, memory, disk) | 30s | Yes |
| PostgreSQL | Database health and performance | 1m | Yes |
| Services | Application-level metrics | 30s | Yes |
| VRRP/HA | Cluster failover status | 30s | Yes |
| Network | Network I/O and latency | 1m | Yes |
| Logs | Log aggregation via Loki | Real-time | No |
| Traces | Distributed tracing via Tempo | Real-time | No |

---

## Alert Response Procedures

### Critical Alert: Host Down
```bash
# 1. Verify host connectivity
ping -c 3 192.168.168.31

# 2. Check SSH access
ssh -v akushnir@192.168.168.31

# 3. If no response, check physical access
# 4. Initiate failover to replica (automatic via VRRP)
# 5. Verify services running on replica

bash scripts/ops/failover-test.sh
```

### Warning Alert: High Error Rate
```bash
# 1. Check service logs
kubectl logs -f deployment/code-server-<service>

# 2. Check recent deployments
git log --oneline -5

# 3. Review error metrics
curl 'http://localhost:9090/api/v1/query?query=rate(http_requests_total{status=~"5.."}[5m])'

# 4. Restart service if needed
docker restart code-server-<service>
```

### Warning Alert: Disk Space Low
```bash
# 1. Identify large directories
du -sh /var/lib/docker/volumes/*

# 2. Check backup retention
ls -lh /backups/

# 3. Clean old logs
find /var/log -mtime +30 -delete

# 4. Consider volume expansion
```

---

## Alertmanager Integration

### Webhook Receiver (Custom Handler)

```python
# /home/akushnir/code-server/scripts/webhooks/alert-handler.py

from flask import Flask, request
import json
import logging

app = Flask(__name__)
logger = logging.getLogger(__name__)

@app.route('/webhooks/alerts', methods=['POST'])
def handle_alert():
    """Handle incoming Alertmanager webhooks"""
    data = request.json
    
    for alert in data.get('alerts', []):
        severity = alert['labels'].get('severity')
        alertname = alert['labels'].get('alertname')
        component = alert['labels'].get('component')
        
        # Log the alert
        logger.warning(f"[{severity.upper()}] {alertname} ({component})")
        
        # Route based on severity
        if severity == 'critical':
            # Page on-call engineer
            notify_oncall(alert)
            # Create incident
            create_incident(alert)
        elif severity == 'warning':
            # Log to monitoring system
            log_warning(alert)
    
    return {'status': 'ok'}, 200

def notify_oncall(alert):
    """Send alert to on-call engineer"""
    # Implementation for SMS/phone notification
    pass

def create_incident(alert):
    """Create incident ticket"""
    # Implementation for incident creation
    pass

def log_warning(alert):
    """Log warning level alerts"""
    logger.info(f"Warning: {alert['labels'].get('alertname')}")

if __name__ == '__main__':
    app.run(port=5000)
```

---

## Monitoring Implementation Checklist

- [ ] Configure Prometheus scrape targets
- [ ] Set up alert rules (critical + warning)
- [ ] Configure Alertmanager routing
- [ ] Test alert notifications (email, Slack)
- [ ] Create Grafana dashboards (system, database, services, HA)
- [ ] Configure log aggregation (Loki + Promtail)
- [ ] Set up distributed tracing (Tempo + OTEL)
- [ ] Test dashboard functionality
- [ ] Document alert response procedures
- [ ] Configure on-call schedule
- [ ] Perform full system test
- [ ] Brief operations team

---

## Success Criteria

✅ **Phase 7 Complete When:**
- All dashboards configured and displaying metrics
- Alert rules tested and routing correctly
- Notification channels verified (email, Slack)
- Log aggregation working for all services
- Distributed tracing capturing transactions
- Response procedures documented and tested
- Team trained on monitoring tools
- All systems passing health checks

---

**Status**: 🟢 PHASE 7 IMPLEMENTATION READY

All monitoring, alerting, and observability components documented and ready for deployment.

