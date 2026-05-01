#!/bin/bash
#
# @file deploy-monitoring-automation.sh
# @module ops
# @description Automates deployment of monitoring stack and alert configuration
# @author Operations Team
# @version 1.0
# @date 2026-04-30
#

set -euo pipefail

# ============================================================================
# ERROR HANDLING
# ============================================================================

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
ENV_FILE="${PROJECT_ROOT}/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Timeouts (seconds)
SERVICE_STARTUP_TIMEOUT=60
HEALTH_CHECK_TIMEOUT=120

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

# Check if service is running
is_service_running() {
  local service=$1
  docker-compose ps "$service" | grep -q "Up" && return 0 || return 1
}

# Wait for service to be healthy
wait_for_service() {
  local service=$1
  local timeout=$2
  local elapsed=0

  log_info "Waiting for $service to be healthy (timeout: ${timeout}s)..."

  while [ $elapsed -lt $timeout ]; do
    if is_service_running "$service"; then
      # Additional health check based on service type
      case "$service" in
        prometheus)
          if curl -sf http://localhost:9090/-/healthy >/dev/null 2>&1; then
            log_success "$service is healthy"
            return 0
          fi
          ;;
        grafana)
          if curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
            log_success "$service is healthy"
            return 0
          fi
          ;;
        alertmanager)
          if amtool config routes >/dev/null 2>&1; then
            log_success "$service is healthy"
            return 0
          fi
          ;;
        loki)
          if curl -sf http://localhost:3100/ready >/dev/null 2>&1; then
            log_success "$service is healthy"
            return 0
          fi
          ;;
        alert-relay)
          if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
            log_success "$service is healthy"
            return 0
          fi
          ;;
        *)
          log_success "$service is running"
          return 0
          ;;
      esac
    fi

    echo -n "."
    sleep 5
    ((elapsed += 5))
  done

  log_error "$service failed to become healthy within ${timeout}s"
  return 1
}

# ============================================================================
# PHASE 3.0: VALIDATION
# ============================================================================

phase_validate() {
  log_info "=== PHASE 3.0: VALIDATING PREREQUISITES ==="

  # Check Docker availability
  if ! command -v docker &>/dev/null; then
    log_error "Docker is not installed"
    exit 1
  fi
  log_success "Docker is available"

  # Check docker-compose availability
  if ! command -v docker-compose &>/dev/null; then
    log_error "docker-compose is not installed"
    exit 1
  fi
  log_success "docker-compose is available"

  # Check .env file
  if [ ! -f "$ENV_FILE" ]; then
    log_error ".env file not found at $ENV_FILE"
    exit 1
  fi
  log_success ".env file found"

  # Validate docker-compose syntax
  if ! docker-compose config >/dev/null 2>&1; then
    log_error "docker-compose.yml has syntax errors"
    exit 1
  fi
  log_success "docker-compose.yml syntax is valid"

  # Check monitoring config files
  local config_files=(
    "config/monitoring/prometheus/prometheus.yml"
    "config/monitoring/alertmanager.yml"
    "config/monitoring/alerts/prometheus-rules.yml"
    "config/monitoring/loki/loki-config.yaml"
    "config/monitoring/tempo/tempo-config.yaml"
  )

  for config_file in "${config_files[@]}"; do
    if [ ! -f "$config_file" ]; then
      log_warning "Configuration file missing: $config_file"
    else
      log_success "Found: $config_file"
    fi
  done

  # Verify required ports are available
  local required_ports=(9090 3000 9093 3100 8080)
  for port in "${required_ports[@]}"; do
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
      log_warning "Port $port is already in use (may be OK if same service)"
    fi
  done

  log_success "Phase 3.0 validation complete"
}

# ============================================================================
# PHASE 3.1: DEPLOY MONITORING SERVICES
# ============================================================================

phase_deploy_monitoring() {
  log_info "=== PHASE 3.1: DEPLOYING MONITORING SERVICES ==="

  # Deploy monitoring services
  log_info "Starting monitoring services..."
  docker-compose up -d \
    prometheus-init prometheus \
    grafana-init grafana \
    loki-init loki \
    alertmanager-init alertmanager \
    tempo-init tempo

  log_success "Monitoring services started"

  # Wait for each service
  local monitoring_services=("prometheus" "grafana" "alertmanager" "loki" "tempo")
  for service in "${monitoring_services[@]}"; do
    wait_for_service "$service" $HEALTH_CHECK_TIMEOUT || {
      log_error "Service $service failed to start"
      docker-compose logs "$service"
      exit 1
    }
  done

  log_success "Phase 3.1 deployment complete"
}

# ============================================================================
# PHASE 3.2: DEPLOY ALERT RELAY
# ============================================================================

phase_deploy_alert_relay() {
  log_info "=== PHASE 3.2: DEPLOYING ALERT RELAY SERVICE ==="

  # Deploy alert relay
  log_info "Starting alert-relay service..."
  docker-compose up -d alert-relay

  log_success "Alert relay started"

  # Wait for alert relay
  wait_for_service "alert-relay" $HEALTH_CHECK_TIMEOUT || {
    log_error "alert-relay failed to start"
    docker-compose logs alert-relay
    exit 1
  }

  log_success "Phase 3.2 alert relay deployment complete"
}

# ============================================================================
# PHASE 3.3: VERIFY PROMETHEUS SCRAPE TARGETS
# ============================================================================

phase_verify_scrape_targets() {
  log_info "=== PHASE 3.3: VERIFYING PROMETHEUS SCRAPE TARGETS ==="

  # Give Prometheus time to start scraping
  log_info "Waiting 30s for Prometheus to begin scraping..."
  sleep 30

  # Get scrape targets
  local targets_json=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null || echo "{}")
  local active_count=$(echo "$targets_json" | jq '.data.activeTargets | length' 2>/dev/null || echo 0)
  local dropped_count=$(echo "$targets_json" | jq '.data.droppedTargets | length' 2>/dev/null || echo 0)

  log_info "Prometheus scrape targets:"
  echo "$targets_json" | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}' 2>/dev/null | head -20

  log_info "Active targets: $active_count"
  log_info "Dropped targets: $dropped_count"

  if [ "$active_count" -lt 5 ]; then
    log_warning "Expected at least 5 active targets, found $active_count"
  else
    log_success "Prometheus is scraping $active_count targets"
  fi

  log_success "Phase 3.3 verification complete"
}

# ============================================================================
# PHASE 3.4: PROVISION GRAFANA DATASOURCES
# ============================================================================

phase_provision_grafana() {
  log_info "=== PHASE 3.4: PROVISIONING GRAFANA DATASOURCES ==="

  local grafana_url="http://localhost:3000"
  local grafana_user="admin"
  local grafana_pass="admin"
  local grafana_auth=$(echo -n "$grafana_user:$grafana_pass" | base64)

  # Provision Prometheus datasource
  log_info "Provisioning Prometheus datasource..."
  curl -X POST "$grafana_url/api/datasources" \
    -H "Authorization: Basic $grafana_auth" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Prometheus",
      "type": "prometheus",
      "url": "http://prometheus:9090",
      "access": "proxy",
      "isDefault": true,
      "jsonData": {
        "timeInterval": "15s"
      }
    }' 2>/dev/null

  log_success "Prometheus datasource provisioned"

  # Provision Loki datasource
  log_info "Provisioning Loki datasource..."
  curl -X POST "$grafana_url/api/datasources" \
    -H "Authorization: Basic $grafana_auth" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Loki",
      "type": "loki",
      "url": "http://loki:3100",
      "access": "proxy",
      "jsonData": {}
    }' 2>/dev/null

  log_success "Loki datasource provisioned"

  # Provision Tempo datasource
  log_info "Provisioning Tempo datasource..."
  curl -X POST "$grafana_url/api/datasources" \
    -H "Authorization: Basic $grafana_auth" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Tempo",
      "type": "tempo",
      "url": "http://tempo:3100",
      "access": "proxy",
      "jsonData": {}
    }' 2>/dev/null

  log_success "Tempo datasource provisioned"

  # Suggest password change
  log_warning "IMPORTANT: Change default Grafana password immediately"
  log_warning "Access at: http://localhost:3000 (or https://kushnir.cloud/grafana)"
  log_warning "Default user: admin / admin"

  log_success "Phase 3.4 Grafana provisioning complete"
}

# ============================================================================
# PHASE 3.5: TEST ALERT ROUTING
# ============================================================================

phase_test_alert_routing() {
  log_info "=== PHASE 3.5: TESTING ALERT ROUTING ==="

  # Send test alert to each receiver
  log_info "Sending test alert to critical-webhook..."
  curl -X POST http://localhost:8080/api/alerts/critical \
    -H "Content-Type: application/json" \
    -d '{
      "alerts": [
        {
          "status": "firing",
          "labels": {
            "alertname": "TestAlertCritical",
            "severity": "critical",
            "service": "test"
          },
          "annotations": {
            "summary": "This is a test critical alert",
            "description": "Testing alert relay functionality"
          },
          "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
          "endsAt": "0001-01-01T00:00:00Z"
        }
      ]
    }' 2>/dev/null

  log_success "Test alert sent to critical receiver"

  # Test warning alert
  log_info "Sending test alert to warning receiver..."
  curl -X POST http://localhost:8080/api/alerts/warning \
    -H "Content-Type: application/json" \
    -d '{
      "alerts": [
        {
          "status": "firing",
          "labels": {
            "alertname": "TestAlertWarning",
            "severity": "warning",
            "service": "test"
          },
          "annotations": {
            "summary": "This is a test warning alert",
            "description": "Testing alert routing"
          },
          "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
          "endsAt": "0001-01-01T00:00:00Z"
        }
      ]
    }' 2>/dev/null

  log_success "Test alert sent to warning receiver"

  log_info "Check logs for alert processing:"
  log_info "  docker-compose logs alert-relay | tail -20"

  log_success "Phase 3.5 alert routing test complete"
}

# ============================================================================
# PHASE 3.6: VERIFICATION & SUMMARY
# ============================================================================

phase_summary() {
  log_info "=== PHASE 3.6: VERIFICATION & SUMMARY ==="

  log_info "Verifying all services are healthy..."
  docker-compose ps | grep -E "prometheus|grafana|alertmanager|loki|tempo|alert-relay"

  log_info "=== MONITORING STACK DEPLOYMENT COMPLETE ==="
  echo ""
  echo "┌─────────────────────────────────────────────────────────────┐"
  echo "│ MONITORING & ALERTING AUTOMATION DEPLOYED                   │"
  echo "├─────────────────────────────────────────────────────────────┤"
  echo "│                                                             │"
  echo "│ Services:                                                   │"
  echo "│   • Prometheus (metrics):     http://localhost:9090         │"
  echo "│   • Grafana (dashboards):     http://localhost:3000         │"
  echo "│   • AlertManager:             http://localhost:9093         │"
  echo "│   • Loki (logs):              http://localhost:3100         │"
  echo "│   • Tempo (traces):           http://localhost:3100/tempo   │"
  echo "│   • Alert Relay (webhooks):   http://localhost:8080         │"
  echo "│                                                             │"
  echo "│ External Access (via Caddy/HTTPS):                          │"
  echo "│   • https://kushnir.cloud/grafana                           │"
  echo "│   • https://kushnir.cloud/prometheus                        │"
  echo "│   • https://kushnir.cloud/alertmanager                      │"
  echo "│                                                             │"
  echo "│ Next Steps:                                                 │"
  echo "│   1. Change Grafana default password (admin/admin)          │"
  echo "│   2. Configure email/Slack receivers in alertmanager.yml    │"
  echo "│   3. Create custom Grafana dashboards                       │"
  echo "│   4. Set up on-call rotation                                │"
  echo "│   5. Train operations team on alert procedures              │"
  echo "│                                                             │"
  echo "│ Documentation:                                              │"
  echo "│   • MONITORING_ALERTING_SETUP.md (comprehensive guide)      │"
  echo "│   • config/monitoring/ (all configuration files)            │"
  echo "│                                                             │"
  echo "└─────────────────────────────────────────────────────────────┘"
  echo ""

  log_success "Phase 3 monitoring automation deployment complete"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  log_info "Starting Phase 3 Monitoring Automation Deployment"
  log_info "Timestamp: $(date)"
  echo ""

  # Execute phases in order
  phase_validate
  echo ""

  phase_deploy_monitoring
  echo ""

  phase_deploy_alert_relay
  echo ""

  phase_verify_scrape_targets
  echo ""

  phase_provision_grafana
  echo ""

  phase_test_alert_routing
  echo ""

  phase_summary

  log_success "All phases complete - monitoring automation ready for production"
}

# ============================================================================
# EXECUTION
# ============================================================================

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  main "$@"
fi
