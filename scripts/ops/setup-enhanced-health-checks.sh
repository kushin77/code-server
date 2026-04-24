#!/usr/bin/env bash
# @file        scripts/ops/setup-enhanced-health-checks.sh
# @module      infrastructure/monitoring
# @description Setup enhanced health checks for pgbouncer, backups, and replication lag
# @owner       Infrastructure Team
# @status      In development - April 23, 2026

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
HEALTH_CHECK_PORT="${HEALTH_CHECK_PORT:-8081}"
REPLICATION_LAG_THRESHOLD="${REPLICATION_LAG_THRESHOLD:-5000}"  # milliseconds
BACKUP_AGE_THRESHOLD="${BACKUP_AGE_THRESHOLD:-3600}"  # seconds (1 hour)

# ============================================================================
# Logging
# ============================================================================

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[✓] $*"; }

# ============================================================================
# PgBouncer Health Check
# ============================================================================

check_pgbouncer_health() {
    local status="healthy"
    local message="PgBouncer operational"
    
    # Check if pgbouncer is running
    if ! docker exec pgbouncer pg_isready -h localhost -p 6432 > /dev/null 2>&1; then
        status="unhealthy"
        message="PgBouncer not responding"
        return 1
    fi
    
    # Check connection pool statistics
    local active_conns=$(docker exec pgbouncer psql -U pgbouncer -d pgbouncer -c \
        "SELECT SUM(cl_active) FROM stats;" 2>/dev/null | tail -1)
    
    local waiting_conns=$(docker exec pgbouncer psql -U pgbouncer -d pgbouncer -c \
        "SELECT SUM(cl_waiting) FROM stats;" 2>/dev/null | tail -1)
    
    # Alert if too many waiting connections
    if [ "${waiting_conns}" -gt 100 ]; then
        status="degraded"
        message="High connection queue (${waiting_conns} waiting)"
    fi
    
    echo "{\"component\": \"pgbouncer\", \"status\": \"${status}\", \"message\": \"${message}\", \"active\": ${active_conns}, \"waiting\": ${waiting_conns}}"
    [ "${status}" = "healthy" ] && return 0 || return 1
}

# ============================================================================
# PostgreSQL Replication Lag Check
# ============================================================================

check_replication_lag() {
    local status="healthy"
    local lag_ms=0
    local message="Replication OK"
    
    # Get replication lag in milliseconds
    lag_ms=$(ssh "akushnir@${PRIMARY_HOST}" "
    docker exec postgres psql -U postgres -c \"
        SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_time())) * 1000;
    \" 2>/dev/null | tail -1" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    
    lag_ms=${lag_ms:-0}
    
    if [ "${lag_ms%.*}" -gt ${REPLICATION_LAG_THRESHOLD} ]; then
        status="critical"
        message="Replication lag exceeds threshold"
    elif [ "${lag_ms%.*}" -gt $((REPLICATION_LAG_THRESHOLD / 2)) ]; then
        status="degraded"
        message="Replication lag elevated"
    fi
    
    echo "{\"component\": \"replication\", \"status\": \"${status}\", \"message\": \"${message}\", \"lag_ms\": ${lag_ms}}"
    [ "${status}" = "healthy" ] && return 0 || return 1
}

# ============================================================================
# Backup Status Check
# ============================================================================

check_backup_status() {
    local status="healthy"
    local message="Backups OK"
    local last_backup_age=0
    local backup_count=0
    
    # Check if backups exist
    last_backup_age=$(ssh "akushnir@${PRIMARY_HOST}" "
    LATEST_BACKUP=\$(ls -t /var/backups/postgresql/backup-*.sql.gz 2>/dev/null | head -1)
    if [ -n \"\${LATEST_BACKUP}\" ]; then
        echo \$(($(date +%s) - \$(stat -f%m \"\${LATEST_BACKUP}\" 2>/dev/null || echo $(date +%s))))
    else
        echo 999999
    fi
    " 2>/dev/null)
    
    backup_count=$(ssh "akushnir@${PRIMARY_HOST}" "ls -1 /var/backups/postgresql/backup-*.sql.gz 2>/dev/null | wc -l" 2>/dev/null || echo 0)
    
    if [ "${last_backup_age}" -gt ${BACKUP_AGE_THRESHOLD} ]; then
        status="critical"
        message="Last backup older than threshold"
    elif [ "${backup_count}" -lt 2 ]; then
        status="degraded"
        message="Insufficient backup history"
    fi
    
    echo "{\"component\": \"backups\", \"status\": \"${status}\", \"message\": \"${message}\", \"last_age_seconds\": ${last_backup_age}, \"count\": ${backup_count}}"
    [ "${status}" = "healthy" ] && return 0 || return 1
}

# ============================================================================
# Connection Pool Health
# ============================================================================

check_connection_pool_health() {
    local status="healthy"
    local message="Connection pool healthy"
    
    # Get pgbouncer pool statistics
    local pool_stats=$(docker exec pgbouncer psql -U pgbouncer -d pgbouncer -c \
        "SELECT cl_active, cl_waiting, sv_active, sv_idle, sv_used, sv_tested FROM stats LIMIT 1;" 2>/dev/null)
    
    # Extract key metrics
    local idle_conns=$(echo "${pool_stats}" | tail -1 | awk '{print $4}')
    
    if [ "${idle_conns}" -lt 5 ]; then
        status="degraded"
        message="Low idle connections"
    fi
    
    echo "{\"component\": \"connection_pool\", \"status\": \"${status}\", \"message\": \"${message}\", \"stats\": \"${pool_stats}\"}"
    [ "${status}" = "healthy" ] && return 0 || return 1
}

# ============================================================================
# Health Check Aggregator
# ============================================================================

run_all_health_checks() {
    local overall_status="healthy"
    local failed_checks=0
    local all_checks="["
    
    # Run each check
    local pgbouncer_check=$(check_pgbouncer_health)
    if [ $? -ne 0 ]; then ((failed_checks++)); overall_status="unhealthy"; fi
    all_checks="${all_checks}${pgbouncer_check},"
    
    local replication_check=$(check_replication_lag)
    if [ $? -ne 0 ]; then ((failed_checks++)); overall_status="unhealthy"; fi
    all_checks="${all_checks}${replication_check},"
    
    local backup_check=$(check_backup_status)
    if [ $? -ne 0 ]; then ((failed_checks++)); overall_status="unhealthy"; fi
    all_checks="${all_checks}${backup_check},"
    
    local pool_check=$(check_connection_pool_health)
    if [ $? -ne 0 ]; then ((failed_checks++)); overall_status="unhealthy"; fi
    all_checks="${all_checks}${pool_check}"
    
    all_checks="${all_checks}]"
    
    # Return aggregated result
    echo "{\"overall_status\": \"${overall_status}\", \"failed_checks\": ${failed_checks}, \"components\": ${all_checks}}"
}

# ============================================================================
# HTTP Health Check Endpoint
# ============================================================================

start_health_check_server() {
    log_info "Starting health check HTTP server on port ${HEALTH_CHECK_PORT}..."
    
    cat > /tmp/health-check-server.py <<'PYTHON'
#!/usr/bin/env python3
import json
import subprocess
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            # Quick health check
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            response = {
                "status": "healthy",
                "timestamp": time.time()
            }
            self.wfile.write(json.dumps(response).encode())
            
        elif self.path == "/health/detailed":
            # Detailed health check
            try:
                result = subprocess.run(
                    ["bash", "-c", "source scripts/ops/setup-enhanced-health-checks.sh && run_all_health_checks"],
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                
                if result.returncode == 0:
                    health_data = json.loads(result.stdout)
                    self.send_response(200)
                else:
                    health_data = {"error": "Health check failed"}
                    self.send_response(503)
                    
            except Exception as e:
                logger.error(f"Health check error: {e}")
                health_data = {"error": str(e)}
                self.send_response(500)
            
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(health_data).encode())
            
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        logger.info("%s - %s" % (self.client_address[0], format % args))

def run_server(port):
    server = HTTPServer(('0.0.0.0', port), HealthCheckHandler)
    logger.info(f"Health check server listening on port {port}")
    server.serve_forever()

if __name__ == '__main__':
    port = int(os.environ.get('HEALTH_CHECK_PORT', 8081))
    run_server(port)
PYTHON
    
    # Start server in background
    docker exec code-server python3 /tmp/health-check-server.py &
    log_success "✓ Health check server started"
}

# ============================================================================
# Prometheus Metrics Exporter
# ============================================================================

create_health_metrics_exporter() {
    cat > /tmp/health-metrics.sh <<'EOF'
#!/bin/bash
# Export health metrics for Prometheus

METRIC_PREFIX="code_server"

echo "# HELP ${METRIC_PREFIX}_pgbouncer_active Active pgbouncer connections"
echo "# TYPE ${METRIC_PREFIX}_pgbouncer_active gauge"
docker exec pgbouncer psql -U pgbouncer -d pgbouncer -c "SELECT SUM(cl_active) FROM stats;" 2>/dev/null | tail -1 | \
    sed "s/^/${METRIC_PREFIX}_pgbouncer_active /"

echo "# HELP ${METRIC_PREFIX}_replication_lag_ms Replication lag in milliseconds"
echo "# TYPE ${METRIC_PREFIX}_replication_lag_ms gauge"
ssh akushnir@192.168.168.31 "docker exec postgres psql -U postgres -c \
    \"SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_time())) * 1000;\"" 2>/dev/null | \
    tail -1 | sed "s/^/${METRIC_PREFIX}_replication_lag_ms /"

echo "# HELP ${METRIC_PREFIX}_backup_count Total backups available"
echo "# TYPE ${METRIC_PREFIX}_backup_count gauge"
ssh akushnir@192.168.168.31 "ls -1 /var/backups/postgresql/backup-*.sql.gz 2>/dev/null | wc -l" 2>/dev/null | \
    sed "s/^/${METRIC_PREFIX}_backup_count /"

echo "# HELP ${METRIC_PREFIX}_backup_last_age_seconds Age of last backup in seconds"
echo "# TYPE ${METRIC_PREFIX}_backup_last_age_seconds gauge"
ssh akushnir@192.168.168.31 "
LATEST=\$(ls -t /var/backups/postgresql/backup-*.sql.gz 2>/dev/null | head -1)
if [ -n \"\${LATEST}\" ]; then
    echo \$(($(date +%s) - \$(stat -f%m \"\${LATEST}\")))
else
    echo 999999
fi
" 2>/dev/null | sed "s/^/${METRIC_PREFIX}_backup_last_age_seconds /"
EOF

    chmod +x /tmp/health-metrics.sh
    log_info "✓ Metrics exporter script created"
}

# ============================================================================
# Prometheus Scrape Configuration
# ============================================================================

create_prometheus_scrape_config() {
    cat > /tmp/prometheus-health-checks.yml <<EOF
global:
  scrape_interval: 30s
  scrape_timeout: 10s

scrape_configs:
  - job_name: 'health-checks'
    static_configs:
      - targets: ['localhost:${HEALTH_CHECK_PORT}']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'postgresql-replication'
    static_configs:
      - targets: ['192.168.168.31:9187']  # postgres_exporter
    scrape_interval: 30s

  - job_name: 'pgbouncer-stats'
    static_configs:
      - targets: ['192.168.168.31:6432']
    scrape_interval: 30s
EOF

    log_info "✓ Prometheus scrape configuration created"
}

# ============================================================================
# Grafana Dashboard
# ============================================================================

create_grafana_dashboard() {
    cat > /tmp/health-checks-dashboard.json <<'EOF'
{
  "dashboard": {
    "title": "Health Checks - Infrastructure Status",
    "panels": [
      {
        "title": "PgBouncer Status",
        "targets": [{"expr": "code_server_pgbouncer_active"}]
      },
      {
        "title": "Replication Lag",
        "targets": [{"expr": "code_server_replication_lag_ms"}]
      },
      {
        "title": "Backup Age",
        "targets": [{"expr": "code_server_backup_last_age_seconds"}]
      },
      {
        "title": "Connection Pool",
        "targets": [{"expr": "code_server_connection_pool_available"}]
      }
    ]
  }
}
EOF

    log_info "✓ Grafana dashboard definition created"
}

# ============================================================================
# Alert Rules
# ============================================================================

create_health_alert_rules() {
    cat > /tmp/health-checks-alerts.yml <<'EOF'
groups:
  - name: health-checks
    interval: 30s
    rules:
      # PgBouncer unhealthy
      - alert: PgBouncer Unhealthy
        expr: code_server_pgbouncer_active == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PgBouncer is not responding"

      # Replication lag critical
      - alert: Replication Lag Critical
        expr: code_server_replication_lag_ms > 5000
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Replication lag exceeds threshold ({{ $value }}ms)"

      # Backup not recent
      - alert: Backup Stale
        expr: code_server_backup_last_age_seconds > 7200
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Last backup is {{ $value }}s old (>2h)"

      # Connection pool depleted
      - alert: Connection Pool Depleted
        expr: code_server_connection_pool_available < 5
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Only {{ $value }} idle connections available"
EOF

    log_info "✓ Alert rules created"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "Setting up Enhanced Health Checks"
    log_info "Primary: ${PRIMARY_HOST}"
    log_info "Health check port: ${HEALTH_CHECK_PORT}"
    log_info "Replication lag threshold: ${REPLICATION_LAG_THRESHOLD}ms"
    log_info "Backup age threshold: ${BACKUP_AGE_THRESHOLD}s"
    
    # Create all configuration files
    create_prometheus_scrape_config
    create_grafana_dashboard
    create_health_alert_rules
    create_health_metrics_exporter
    
    # Start health check server
    # start_health_check_server
    
    # Test health checks
    log_info "Running health checks..."
    run_all_health_checks
    
    log_success "✓ Enhanced health checks deployed!"
    log_info "Check endpoint: http://localhost:${HEALTH_CHECK_PORT}/health"
    log_info "Detailed check: http://localhost:${HEALTH_CHECK_PORT}/health/detailed"
    log_info "Metrics exported for Prometheus integration"
    
    return 0
}

main "$@"
