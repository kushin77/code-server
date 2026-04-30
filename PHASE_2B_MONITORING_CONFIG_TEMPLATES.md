# Phase 2b Monitoring Configuration Templates

**Version:** 1.0  
**Purpose:** Ready-to-deploy monitoring configurations for Phase 2b  
**Status:** Production-ready templates  

---

## Overview

This document provides copy-paste ready monitoring configurations for Prometheus, Grafana, and alerting systems.

---

## 1. Prometheus Configuration

### Template: prometheus.yml

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'code-server'
    phase: '2b'
    environment: 'staging'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:
  - '/etc/prometheus/rules/phase2b-alerts.yml'

scrape_configs:
  # PRIMARY GitLab Instance
  - job_name: 'gitlab-primary'
    metrics_path: '/-/metrics'
    scrape_interval: 30s
    static_configs:
      - targets: ['PRIMARY_HOST:8101']
        labels:
          instance: 'primary'
          role: 'primary'
          
  # REPLICA GitLab Instance
  - job_name: 'gitlab-replica'
    metrics_path: '/-/metrics'
    scrape_interval: 30s
    static_configs:
      - targets: ['REPLICA_HOST:8101']
        labels:
          instance: 'replica'
          role: 'replica'

  # PRIMARY PostgreSQL
  - job_name: 'postgres-primary'
    scrape_interval: 30s
    static_configs:
      - targets: ['PRIMARY_HOST:9187']
        labels:
          instance: 'primary'
          database: 'postgresql'
          
  # REPLICA PostgreSQL
  - job_name: 'postgres-replica'
    scrape_interval: 30s
    static_configs:
      - targets: ['REPLICA_HOST:9187']
        labels:
          instance: 'replica'
          database: 'postgresql'

  # PRIMARY Redis
  - job_name: 'redis-primary'
    scrape_interval: 30s
    static_configs:
      - targets: ['PRIMARY_HOST:9121']
        labels:
          instance: 'primary'
          database: 'redis'
          
  # REPLICA Redis
  - job_name: 'redis-replica'
    scrape_interval: 30s
    static_configs:
      - targets: ['REPLICA_HOST:9121']
        labels:
          instance: 'replica'
          database: 'redis'

  # Host Metrics - PRIMARY
  - job_name: 'node-primary'
    scrape_interval: 15s
    static_configs:
      - targets: ['PRIMARY_HOST:9100']
        labels:
          instance: 'primary'
          
  # Host Metrics - REPLICA
  - job_name: 'node-replica'
    scrape_interval: 15s
    static_configs:
      - targets: ['REPLICA_HOST:9100']
        labels:
          instance: 'replica'

  # Docker Metrics
  - job_name: 'docker'
    scrape_interval: 30s
    static_configs:
      - targets: ['PRIMARY_HOST:9323', 'REPLICA_HOST:9323']
```

### Instructions

1. Replace placeholders:
   - `PRIMARY_HOST` - IP or hostname of primary server
   - `REPLICA_HOST` - IP or hostname of replica server

2. Deploy to Prometheus:
   ```bash
   sudo cp prometheus.yml /etc/prometheus/
   sudo systemctl restart prometheus
   ```

3. Verify configuration:
   ```bash
   promtool check config /etc/prometheus/prometheus.yml
   ```

---

## 2. Alert Rules

### Template: phase2b-alerts.yml

```yaml
groups:
  - name: phase2b_alerts
    interval: 30s
    rules:
      
      # ==================== INFRASTRUCTURE ALERTS ====================
      
      - alert: PrimaryHostDown
        expr: up{job=~"gitlab-primary|postgres-primary|redis-primary|node-primary"} == 0
        for: 2m
        labels:
          severity: critical
          phase: '2b'
        annotations:
          summary: "⚠️  PRIMARY host is DOWN"
          description: "PRIMARY host ({{ $labels.instance }}) has been down for > 2 minutes"
          runbook: "PHASE_2B_TROUBLESHOOTING_GUIDE.md#primary-host-down"
          
      - alert: ReplicaHostDown
        expr: up{job=~"gitlab-replica|postgres-replica|redis-replica|node-replica"} == 0
        for: 2m
        labels:
          severity: critical
          phase: '2b'
        annotations:
          summary: "⚠️  REPLICA host is DOWN"
          description: "REPLICA host ({{ $labels.instance }}) has been down for > 2 minutes"
          runbook: "PHASE_2B_TROUBLESHOOTING_GUIDE.md#replica-host-down"
          
      # ==================== DATABASE ALERTS ====================
      
      - alert: DatabaseReplicationLag
        expr: |
          (pg_replication_lag_seconds{job="postgres-primary"} > 10)
          or
          (pg_replication_lag_seconds{job="postgres-replica"} > 10)
        for: 5m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  Database Replication Lag CRITICAL"
          description: "Replication lag is {{ $value }} seconds (threshold: 10s)"
          runbook: "PHASE_2B_TROUBLESHOOTING_GUIDE.md#replication-lag"
          
      - alert: DatabaseConnectionPoolExhausted
        expr: pg_stat_activity_count > 90
        for: 3m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  Database Connection Pool Nearly Full"
          description: "Active connections: {{ $value }} (max: 100)"
          
      - alert: DatabaseLockDetected
        expr: pg_locks_count > 50
        for: 5m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  Database Lock Detected"
          description: "Lock count: {{ $value }}"
          
      # ==================== REPLICATION ALERTS ====================
      
      - alert: RedisReplicationStopped
        expr: redis_connected_slaves{job="redis-primary"} == 0
        for: 2m
        labels:
          severity: critical
          phase: '2b'
        annotations:
          summary: "⚠️  Redis Replication STOPPED"
          description: "PRIMARY Redis has {{ $value }} connected slaves (expected: >= 1)"
          runbook: "PHASE_2B_TROUBLESHOOTING_GUIDE.md#redis-replication-stopped"
          
      - alert: GitlabReplicationLag
        expr: |
          (gitlab_gitaly_replication_lag_bytes{job="gitlab-primary"} > 1073741824) or
          (gitlab_gitaly_replication_lag_bytes{job="gitlab-replica"} > 1073741824)
        for: 10m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  GitLab Replication Lag"
          description: "Lag: {{ humanize $value }}B (1GB threshold)"
          
      # ==================== CONTAINER ALERTS ====================
      
      - alert: ContainerCrashLoop
        expr: increase(container_last_seen{container_state="exited"}[5m]) > 5
        for: 2m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  Container Crash Loop Detected"
          description: "Restarts in last 5m: {{ $value }}"
          
      - alert: ContainerOutOfMemory
        expr: container_memory_usage_bytes / container_memory_max_bytes > 0.95
        for: 2m
        labels:
          severity: critical
          phase: '2b'
        annotations:
          summary: "⚠️  Container Memory CRITICAL"
          description: "Memory usage: {{ humanizePercentage $value }}"
          
      - alert: DiskSpaceRunningOut
        expr: node_filesystem_avail_bytes{device!~'tmpfs|fuse.lxcfs|squashfs|vfat'} / node_filesystem_size_bytes < 0.1
        for: 5m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  Disk Space Running Out"
          description: "Disk free: {{ humanizePercentage $value }} (threshold: 10%)"
          
      # ==================== PARITY GATE ALERTS ====================
      
      - alert: ParityCheckFailed
        expr: gitlab_compose_parity_status == 0
        for: 1m
        labels:
          severity: critical
          phase: '2b'
        annotations:
          summary: "⚠️  PARITY GATE FAILED"
          description: "PRIMARY and REPLICA configurations no longer match"
          runbook: "PHASE_2B_TROUBLESHOOTING_GUIDE.md#parity-gate-failed"
          
      - alert: ConfigurationDriftDetected
        expr: |
          label_replace(
            changes(gitlab_compose_checksum_primary[5m]) > 0, 'type', 'primary', '', ''
          ) or
          label_replace(
            changes(gitlab_compose_checksum_replica[5m]) > 0, 'type', 'replica', '', ''
          )
        for: 2m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  Configuration Drift Detected"
          description: "{{ $labels.type }} configuration changed"
          
      # ==================== RESOURCE ALERTS ====================
      
      - alert: CPUUtilizationHigh
        expr: 100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  CPU Utilization High"
          description: "CPU usage: {{ humanizePercentage (1 - $value / 100) }}"
          
      - alert: MemoryUtilizationHigh
        expr: 1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.85
        for: 5m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  Memory Utilization High"
          description: "Memory usage: {{ humanizePercentage (1 - $value) }}"
          
      - alert: LoadAverageHigh
        expr: node_load5 > node_cpu_count * 2
        for: 10m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  Load Average High"
          description: "Load5: {{ $value }}"
          
      # ==================== GITLAB SERVICE ALERTS ====================
      
      - alert: GitlabServiceDown
        expr: up{job=~"gitlab-primary|gitlab-replica"} == 0
        for: 2m
        labels:
          severity: critical
          phase: '2b'
        annotations:
          summary: "⚠️  GitLab Service DOWN"
          description: "GitLab is not responding on {{ $labels.instance }}"
          runbook: "PHASE_2B_TROUBLESHOOTING_GUIDE.md#gitlab-service-down"
          
      - alert: GitlabHighErrorRate
        expr: rate(gitlab_http_requests_total{status=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  GitLab High Error Rate"
          description: "5xx errors: {{ humanizePercentage $value }}"
          
      - alert: GitlabHighLatency
        expr: gitlab_http_request_duration_seconds{quantile="0.95"} > 5
        for: 10m
        labels:
          severity: warning
          phase: '2b'
        annotations:
          summary: "⚠️  GitLab High Latency"
          description: "P95 latency: {{ $value }}s (threshold: 5s)"
```

### Instructions

1. Deploy to Prometheus:
   ```bash
   sudo cp phase2b-alerts.yml /etc/prometheus/rules/
   sudo systemctl restart prometheus
   ```

2. Verify alerts:
   ```bash
   curl http://localhost:9090/api/v1/rules
   ```

---

## 3. Grafana Dashboard JSON

### Dashboard: Phase 2b Cluster Health

```json
{
  "dashboard": {
    "title": "Phase 2b Cluster Health",
    "tags": ["phase2b", "cluster"],
    "timezone": "UTC",
    "panels": [
      {
        "title": "PRIMARY Host Status",
        "targets": [
          {
            "expr": "up{job=\"node-primary\"}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "thresholds"
            },
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"color": "red", "value": 0},
                {"color": "green", "value": 1}
              ]
            }
          }
        }
      },
      {
        "title": "REPLICA Host Status",
        "targets": [
          {
            "expr": "up{job=\"node-replica\"}",
            "refId": "A"
          }
        ]
      },
      {
        "title": "Container Count (PRIMARY)",
        "targets": [
          {
            "expr": "count(container_state_running{host=\"primary\"})",
            "refId": "A"
          }
        ]
      },
      {
        "title": "Container Count (REPLICA)",
        "targets": [
          {
            "expr": "count(container_state_running{host=\"replica\"})",
            "refId": "A"
          }
        ]
      },
      {
        "title": "Parity Gate Status",
        "targets": [
          {
            "expr": "gitlab_compose_parity_status",
            "refId": "A"
          }
        ]
      },
      {
        "title": "Replication Status",
        "targets": [
          {
            "expr": "pg_replication_lag_seconds",
            "refId": "A"
          }
        ]
      }
    ]
  }
}
```

### Instructions

1. In Grafana UI:
   - Dashboards → New → Import
   - Paste JSON above
   - Configure data source (Prometheus)
   - Save as "Phase 2b Cluster Health"

2. Add to starred dashboards for quick access

---

## 4. AlertManager Configuration

### Template: alertmanager.yml

```yaml
global:
  resolve_timeout: 5m
  slack_api_url: 'SLACK_WEBHOOK_URL'
  pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'

route:
  # Default receiver for all alerts
  receiver: 'slack-phase2b'
  
  # Group alerts
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  
  # Routes for specific alert severities
  routes:
    - match:
        severity: 'critical'
      receiver: 'pagerduty-critical'
      continue: true
      
    - match:
        severity: 'warning'
      receiver: 'slack-warnings'
      group_wait: 30s
      group_interval: 5m

receivers:
  - name: 'slack-phase2b'
    slack_configs:
      - channel: '#phase2b-staging'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        send_resolved: true
        
  - name: 'slack-warnings'
    slack_configs:
      - channel: '#phase2b-warnings'
        title: '⚠️  {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: 'PAGERDUTY_SERVICE_KEY'
        description: '{{ .GroupLabels.alertname }}'
        details:
          alerts: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
```

### Instructions

1. Replace placeholders:
   - `SLACK_WEBHOOK_URL` - Slack incoming webhook
   - `PAGERDUTY_SERVICE_KEY` - PagerDuty integration key

2. Deploy:
   ```bash
   sudo cp alertmanager.yml /etc/alertmanager/
   sudo systemctl restart alertmanager
   ```

3. Test:
   ```bash
   curl -XPOST http://localhost:9093/api/v1/alerts -d '[{
     "labels": {"alertname": "TestAlert", "severity": "critical"},
     "annotations": {"summary": "Test alert"}
   }]'
   ```

---

## 5. Environment Variables for Configuration

### Template: monitoring.env

```bash
# Prometheus Configuration
PROMETHEUS_SCRAPE_INTERVAL=15s
PROMETHEUS_EVALUATION_INTERVAL=15s
PROMETHEUS_RETENTION=30d

# Alert Thresholds
ALERT_REPLICATION_LAG_THRESHOLD=10s
ALERT_CPU_THRESHOLD=80%
ALERT_MEMORY_THRESHOLD=85%
ALERT_DISK_THRESHOLD=10%

# Slack Configuration
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
SLACK_CHANNEL="#phase2b-staging"

# PagerDuty Configuration
PAGERDUTY_SERVICE_KEY="YOUR_PAGERDUTY_KEY"
PAGERDUTY_INTEGRATION_URL="https://events.pagerduty.com/v2/enqueue"

# Grafana Configuration
GRAFANA_ADMIN_PASSWORD="secure_password"
GRAFANA_ALERT_NOTIFICATION_ENABLED=true

# Infrastructure Hosts
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
VIP_HOST="192.168.168.50"

# Monitoring Retention
METRICS_RETENTION_DAYS=30
LOG_RETENTION_DAYS=14
```

### Instructions

1. Source configuration:
   ```bash
   source monitoring.env
   envsubst < prometheus.yml.template > prometheus.yml
   ```

---

## 6. Health Check Scripts

### Script: check-monitoring-health.sh

```bash
#!/bin/bash

echo "=== Phase 2b Monitoring Health Check ==="
echo ""

# Check Prometheus
echo "Checking Prometheus..."
curl -s http://localhost:9090/-/healthy || echo "❌ Prometheus not responding"
echo ""

# Check AlertManager
echo "Checking AlertManager..."
curl -s http://localhost:9093/-/healthy || echo "❌ AlertManager not responding"
echo ""

# Check Grafana
echo "Checking Grafana..."
curl -s http://localhost:3000/api/health || echo "❌ Grafana not responding"
echo ""

# Check alert rules loaded
echo "Alert Rules:"
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups | length' 2>/dev/null || echo "❌ Could not fetch rules"
echo ""

# Check targets
echo "Prometheus Targets:"
curl -s http://localhost:9090/api/v1/targets | jq '.data | {active: length}' 2>/dev/null || echo "❌ Could not fetch targets"
```

### Instructions

```bash
chmod +x check-monitoring-health.sh
./check-monitoring-health.sh
```

---

## Deployment Checklist

- [ ] Prometheus configuration deployed
- [ ] Alert rules configured
- [ ] Grafana dashboards imported
- [ ] AlertManager configured
- [ ] Slack/PagerDuty channels created
- [ ] Test alert sent successfully
- [ ] Monitoring health check passed
- [ ] All metrics collecting data
- [ ] Dashboard displaying values
- [ ] Alerts firing on threshold

---

## Quick Reference Commands

```bash
# Reload Prometheus configuration
curl -X POST http://localhost:9090/-/reload

# Query alert status
curl http://localhost:9090/api/v1/alerts

# List all metrics
curl 'http://localhost:9090/api/v1/label/__name__/values'

# View specific alert
curl 'http://localhost:9090/api/v1/query?query=ALERT_PrimaryHostDown'

# Check AlertManager status
curl http://localhost:9093/api/v1/alerts

# View Grafana dashboards
curl http://localhost:3000/api/dashboards/db/phase-2b-cluster-health
```

---

**Version:** 1.0  
**Status:** Ready for deployment  
**Created:** April 30, 2026

