#!/bin/bash
# Prometheus Alert Rules and Scrape Configuration Setup
# Configure Prometheus for metric collection and alerting

set -e
trap 'echo "❌ Alert configuration failed"; exit 1' ERR

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Prometheus Alert Rules Configuration                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

PROMETHEUS_CONFIG_DIR="/etc/prometheus"
RULES_FILE="$PROMETHEUS_CONFIG_DIR/alert_rules.yml"

echo "Alert Rules File: $RULES_FILE"
echo ""

# Create alert rules file
cat > "$RULES_FILE" << 'ALERT_RULES'
groups:
  - name: infrastructure_alerts
    interval: 30s
    rules:
      # Host availability
      - alert: HostDown
        expr: up{job=~"primary|replica"} == 0
        for: 1m
        labels:
          severity: critical
          component: infrastructure
        annotations:
          summary: "Host {{ $labels.instance }} is unreachable"
          description: "{{ $labels.instance }} has been down for 1 minute"
          runbook: "https://wiki.kushnir.cloud/host-recovery"

      # CPU alerts
      - alert: HighCPUUsage
        expr: 100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 10m
        labels:
          severity: warning
          component: infrastructure
        annotations:
          summary: "High CPU on {{ $labels.instance }}"
          description: "CPU: {{ $value | humanize }}%"

      # Memory alerts
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.9
        for: 5m
        labels:
          severity: warning
          component: infrastructure
        annotations:
          summary: "High memory on {{ $labels.instance }}"
          description: "Memory: {{ $value | humanizePercentage }}"

      - alert: CriticalMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.95
        for: 2m
        labels:
          severity: critical
          component: infrastructure
        annotations:
          summary: "CRITICAL: Memory almost full on {{ $labels.instance }}"
          description: "Memory: {{ $value | humanizePercentage }}"

      # Disk alerts
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.1
        for: 5m
        labels:
          severity: warning
          component: infrastructure
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Available: {{ $value | humanizePercentage }}"

      - alert: DiskSpaceCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.05
        for: 2m
        labels:
          severity: critical
          component: infrastructure
        annotations:
          summary: "CRITICAL: Disk almost full on {{ $labels.instance }}"
          description: "Available: {{ $value | humanizePercentage }}"

      # VIP/VRRP alerts
      - alert: VIPNotResponding
        expr: up{job="vip-check"} == 0
        for: 2m
        labels:
          severity: critical
          component: network
        annotations:
          summary: "Virtual IP (192.168.168.30) not responding"
          description: "VIP has been unreachable for 2 minutes"

      - alert: VRRPFailoverEvent
        expr: increase(keepalived_vrrp_transitions_total[1m]) > 0
        for: 1m
        labels:
          severity: warning
          component: network
        annotations:
          summary: "VRRP failover event detected"
          description: "{{ $value | humanize }} failover transition(s) in last minute"

  - name: database_alerts
    interval: 30s
    rules:
      # PostgreSQL
      - alert: PostgreSQLDown
        expr: up{job="postgres"} == 0
        for: 1m
        labels:
          severity: critical
          component: database
        annotations:
          summary: "PostgreSQL is down"
          description: "PostgreSQL at {{ $labels.instance }} is not responding"

      - alert: PostgreSQLHighConnections
        expr: pg_stat_activity_count > 100
        for: 5m
        labels:
          severity: warning
          component: database
        annotations:
          summary: "High PostgreSQL connections ({{ $value }})"
          description: "{{ $value }} active connections"

      - alert: PostgreSQLReplicationLag
        expr: pg_replication_lag_seconds > 10
        for: 5m
        labels:
          severity: warning
          component: database
        annotations:
          summary: "PostgreSQL replication lag ({{ $value }}s)"
          description: "Replica is {{ $value }}s behind primary"

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
          summary: "Redis memory usage high ({{ $value | humanizePercentage }})"
          description: "Redis is using {{ $value | humanizePercentage }} of allocated memory"

  - name: application_alerts
    interval: 30s
    rules:
      # Container health
      - alert: ContainerDown
        expr: container_last_seen == 0 and ON() container_last_seen offset 5m
        for: 2m
        labels:
          severity: warning
          component: application
        annotations:
          summary: "Container {{ $labels.container_name }} is not running"
          description: "Container has been down for 2 minutes"

      # Service health
      - alert: ServiceHighErrorRate
        expr: |
          (sum(rate(http_requests_total{status=~"5.."}[5m])) by (service) /
           sum(rate(http_requests_total[5m])) by (service)) > 0.05
        for: 5m
        labels:
          severity: warning
          component: application
        annotations:
          summary: "{{ $labels.service }} high error rate ({{ $value | humanizePercentage }})"
          description: "Service returning {{ $value | humanizePercentage }} 5xx errors"

      - alert: ServiceSlowResponse
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 2
        for: 10m
        labels:
          severity: warning
          component: application
        annotations:
          summary: "{{ $labels.service }} response time slow ({{ $value }}s)"
          description: "P95 response time is {{ $value }}s"

  - name: backup_alerts
    interval: 5m
    rules:
      - alert: BackupMissing
        expr: time() - backup_last_completed_timestamp > 86400
        for: 10m
        labels:
          severity: warning
          component: backup
        annotations:
          summary: "Backup not completed in last 24 hours"
          description: "Last backup: {{ $value | humanizeDuration }} ago"

      - alert: BackupFailed
        expr: backup_last_status != 0
        for: 1m
        labels:
          severity: critical
          component: backup
        annotations:
          summary: "Backup job failed"
          description: "Last backup job returned status {{ $value }}"

  - name: certificate_alerts
    interval: 1h
    rules:
      - alert: CertificateExpiringSoon
        expr: certmanager_certificate_expiration_seconds_remaining < 604800
        for: 1h
        labels:
          severity: warning
          component: security
        annotations:
          summary: "Certificate expiring in {{ $value | humanizeDuration }}"
          description: "Certificate {{ $labels.certificate }} expires soon"

      - alert: CertificateExpiredCritical
        expr: certmanager_certificate_expiration_seconds_remaining < 86400
        for: 10m
        labels:
          severity: critical
          component: security
        annotations:
          summary: "CRITICAL: Certificate expires in {{ $value | humanizeDuration }}"
          description: "Certificate {{ $labels.certificate }} expires in less than 24 hours"
ALERT_RULES

echo "✅ Alert rules created: $RULES_FILE"
echo ""
echo "Alert Rules Summary:"
echo "  - Infrastructure: Host, CPU, Memory, Disk, Network"
echo "  - Database: PostgreSQL, Redis health and performance"
echo "  - Application: Services, containers, error rates"
echo "  - Backup: Backup success and completion checks"
echo "  - Certificates: SSL certificate expiration tracking"
echo ""

echo "Prometheus Scrape Configuration (docker-compose additions):"
echo "─────────────────────────────────────────────────────────"
cat << 'SCRAPE_CONFIG'

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./alert_rules.yml:/etc/prometheus/alert_rules.yml
      - prometheus-storage:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'

  # prometheus.yml configuration:
  global:
    scrape_interval: 30s
    evaluation_interval: 30s
    external_labels:
      cluster: 'elevatediq'

  alerting:
    alertmanagers:
      - static_configs:
          - targets: ['alertmanager:9093']

  rule_files:
    - '/etc/prometheus/alert_rules.yml'

  scrape_configs:
    - job_name: 'prometheus'
      static_configs:
        - targets: ['localhost:9090']

    - job_name: 'docker'
      docker_sd_configs:
        - host: unix:///var/run/docker.sock

    - job_name: 'postgres'
      static_configs:
        - targets: ['postgres-exporter:9187']

    - job_name: 'redis'
      static_configs:
        - targets: ['redis-exporter:9121']

    - job_name: 'vip-check'
      metrics_path: /probe
      static_configs:
        - targets: ['192.168.168.30']

SCRAPE_CONFIG

echo ""
echo "✅ Alert rules and scrape configuration ready"
echo ""
echo "To apply:"
echo "  1. Copy alert_rules.yml to Prometheus config directory"
echo "  2. Update prometheus.yml with rule_files and scrape_configs"
echo "  3. Reload Prometheus: curl -X POST http://localhost:9090/-/reload"
echo ""
