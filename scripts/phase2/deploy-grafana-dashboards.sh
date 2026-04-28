#!/usr/bin/env bash
###############################################################################
# Phase 2: SLOG Observability Stack - Grafana Dashboard Provisioning
#
# @file scripts/phase2/deploy-grafana-dashboards.sh
# @module phase2/observability
# @description Deploy Grafana with pre-configured dashboards
# @governance GOV-001: Dashboards must be version-controlled and reproducible
# @usage ./deploy-grafana-dashboards.sh
###############################################################################

set -euo pipefail

# Error handling
trap 'log_error "Grafana deployment failed at line $LINENO"; exit 1' ERR
trap 'log_info "Grafana deployment session ending..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

log_info() { echo "[INFO]    | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }
log_success() { echo "[SUCCESS] | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }
log_error() { echo "[ERROR]   | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }

# ============================================================================
# GRAFANA DATASOURCES
# ============================================================================

generate_grafana_datasources() {
    cat > /tmp/datasources.yaml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true

  - name: OpenSearch
    type: elasticsearch
    access: proxy
    url: http://opensearch:9200
    database: logs-*
    isDefault: false
    editable: true
    jsonData:
      timeField: "@timestamp"
      esVersion: 8

  - name: PostgreSQL
    type: postgres
    access: proxy
    url: postgres:5432
    database: services
    user: postgres
    isDefault: false
    editable: true

  - name: Redis
    type: redis-datasource
    access: proxy
    url: redis://redis:6379
    isDefault: false
    editable: true
EOF

    log_success "✓ Grafana datasources configured"
}

# ============================================================================
# GRAFANA DASHBOARDS
# ============================================================================

generate_grafana_dashboards() {
    # System Overview Dashboard
    cat > /tmp/dashboard-system-overview.json << 'EOF'
{
  "dashboard": {
    "title": "System Overview - Elite Enterprise",
    "panels": [
      {
        "title": "CPU Usage",
        "targets": [
          {
            "expr": "100 - (avg(irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
          }
        ]
      },
      {
        "title": "Memory Usage",
        "targets": [
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100"
          }
        ]
      },
      {
        "title": "Disk Usage",
        "targets": [
          {
            "expr": "(node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes * 100"
          }
        ]
      },
      {
        "title": "Network I/O",
        "targets": [
          {
            "expr": "rate(node_network_transmit_bytes_total[5m])"
          }
        ]
      }
    ]
  }
}
EOF

    # Service Health Dashboard
    cat > /tmp/dashboard-service-health.json << 'EOF'
{
  "dashboard": {
    "title": "Service Health - Elite Enterprise",
    "panels": [
      {
        "title": "Service Up Status",
        "targets": [
          {
            "expr": "up"
          }
        ]
      },
      {
        "title": "Container Count",
        "targets": [
          {
            "expr": "count(container_info)"
          }
        ]
      },
      {
        "title": "Request Rate",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])"
          }
        ]
      },
      {
        "title": "Error Rate",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~\"5..\"}[5m])"
          }
        ]
      }
    ]
  }
}
EOF

    # Database Performance Dashboard
    cat > /tmp/dashboard-db-performance.json << 'EOF'
{
  "dashboard": {
    "title": "Database Performance - PostgreSQL",
    "panels": [
      {
        "title": "Active Connections",
        "targets": [
          {
            "expr": "pg_stat_activity_count"
          }
        ]
      },
      {
        "title": "Replication Lag",
        "targets": [
          {
            "expr": "pg_replication_lag_seconds"
          }
        ]
      },
      {
        "title": "Query Performance",
        "targets": [
          {
            "expr": "rate(pg_stat_statements_mean_exec_time[5m])"
          }
        ]
      },
      {
        "title": "Cache Hit Ratio",
        "targets": [
          {
            "expr": "pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read)"
          }
        ]
      }
    ]
  }
}
EOF

    log_success "✓ Grafana dashboards provisioned"
}

# ============================================================================
# DOCKER COMPOSE ADDITION
# ============================================================================

generate_grafana_compose() {
    cat > /tmp/grafana-compose.yml << 'EOF'
version: '3.8'
services:
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: changeme
      GF_INSTALL_PLUGINS: grafana-piechart-panel,grafana-clock-panel
      GF_PATHS_PROVISIONING: /etc/grafana/provisioning
    volumes:
      - /tmp/datasources.yaml:/etc/grafana/provisioning/datasources/datasources.yaml:ro
      - /tmp/dashboard-system-overview.json:/etc/grafana/provisioning/dashboards/system-overview.json:ro
      - /tmp/dashboard-service-health.json:/etc/grafana/provisioning/dashboards/service-health.json:ro
      - /tmp/dashboard-db-performance.json:/etc/grafana/provisioning/dashboards/db-performance.json:ro
      - grafana-storage:/var/lib/grafana
    networks:
      - observability
    restart: unless-stopped
    depends_on:
      - prometheus
      - opensearch

volumes:
  grafana-storage:

networks:
  observability:
    driver: bridge
EOF

    log_success "✓ Grafana docker-compose addition generated"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║ PHASE 2: GRAFANA DASHBOARD PROVISIONING                  ║"
    log_info "║ Real-time visualization and alerting                     ║"
    log_info "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    generate_grafana_datasources
    generate_grafana_dashboards
    generate_grafana_compose
    
    echo ""
    log_info "Grafana configurations ready:"
    log_info "  - Datasources: /tmp/datasources.yaml"
    log_info "  - Dashboards: 3 pre-configured"
    log_info "  - Compose: /tmp/grafana-compose.yml"
    log_info ""
    log_info "Access Grafana at: http://primary-host:3000"
    log_info "Default credentials: admin / changeme"
    log_info "Next: Configure alerting and notification channels"
}

main "$@"
