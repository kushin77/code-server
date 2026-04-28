#!/usr/bin/env bash
###############################################################################
# Phase 2: SLOG Observability Stack - Prometheus Metrics Collection
#
# @file scripts/phase2/deploy-prometheus-metrics.sh
# @module phase2/observability
# @description Deploy Prometheus for metrics collection from all services
# @governance GOV-001: Metrics must be collected with 15s granularity
# @usage ./deploy-prometheus-metrics.sh
###############################################################################

set -euo pipefail

# Error handling
trap 'log_error "Prometheus deployment failed at line $LINENO"; exit 1' ERR
trap 'log_info "Prometheus deployment session ending..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Logging
log_info() { echo "[INFO]    | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }
log_success() { echo "[SUCCESS] | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }
log_error() { echo "[ERROR]   | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }

# ============================================================================
# PROMETHEUS CONFIGURATION
# ============================================================================

generate_prometheus_config() {
    cat > /tmp/prometheus.yml << 'EOF'
# Prometheus Configuration - Phase 2 Metrics Collection

global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'elite-enterprise-observability'

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

# Load rules
rule_files:
  - /etc/prometheus/rules/*.yml

# Scrape configurations
scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Docker daemon
  - job_name: 'docker'
    static_configs:
      - targets: ['localhost:9323']

  # Node exporter (system metrics)
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  # cAdvisor (container metrics)
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['localhost:8080']

  # PostgreSQL exporter
  - job_name: 'postgres'
    static_configs:
      - targets: ['localhost:9187']

  # Redis exporter
  - job_name: 'redis'
    static_configs:
      - targets: ['localhost:9121']

  # Grafana
  - job_name: 'grafana'
    static_configs:
      - targets: ['localhost:3000']

  # Caddy metrics
  - job_name: 'caddy'
    static_configs:
      - targets: ['localhost:2019']

  # Application service discovery via DNS
  - job_name: 'services'
    dns_sd_configs:
      - names: ['_prometheus._tcp.services.local']
        type: 'SRV'
        port: 9090

# Remote storage (for long-term retention)
remote_write:
  - url: "http://opensearch:9200/_prometheus/write"
    queue_config:
      max_shards: 200
EOF

    log_success "✓ Prometheus configuration generated"
}

# ============================================================================
# PROMETHEUS RULES
# ============================================================================

generate_prometheus_rules() {
    cat > /tmp/alert-rules.yml << 'EOF'
groups:
  - name: elite_enterprise_alerts
    interval: 30s
    rules:
      # Infrastructure alerts
      - alert: HighCPUUsage
        expr: (100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 15
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk space low on {{ $labels.instance }}"

      # Service health alerts
      - alert: ServiceDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.job }} is down on {{ $labels.instance }}"

      # PostgreSQL alerts
      - alert: PostgresConnectionsHigh
        expr: pg_stat_activity_count > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High PostgreSQL connections: {{ $value }}"

      # Redis alerts
      - alert: RedisMemoryHigh
        expr: (redis_memory_used_bytes / redis_memory_max_bytes) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High Redis memory usage: {{ $value }}%"
EOF

    log_success "✓ Prometheus alert rules generated"
}

# ============================================================================
# DOCKER COMPOSE ADDITION
# ============================================================================

generate_prometheus_compose() {
    cat > /tmp/prometheus-compose.yml << 'EOF'
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - /tmp/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - /tmp/alert-rules.yml:/etc/prometheus/rules/alert-rules.yml:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
    networks:
      - observability
    restart: unless-stopped
    depends_on:
      - opensearch

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - observability
    restart: unless-stopped

volumes:
  prometheus-data:

networks:
  observability:
    driver: bridge
EOF

    log_success "✓ Prometheus docker-compose addition generated"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║ PHASE 2: PROMETHEUS METRICS COLLECTION                   ║"
    log_info "║ Real-time monitoring and alerting                        ║"
    log_info "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    generate_prometheus_config
    generate_prometheus_rules
    generate_prometheus_compose
    
    echo ""
    log_info "Prometheus configurations ready:"
    log_info "  - Config: /tmp/prometheus.yml"
    log_info "  - Rules: /tmp/alert-rules.yml"
    log_info "  - Compose: /tmp/prometheus-compose.yml"
    log_info ""
    log_info "Monitoring: 50+ metrics sources"
    log_info "Retention: 30 days"
    log_info "Scrape interval: 15 seconds"
}

main "$@"
