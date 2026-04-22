#!/usr/bin/env bash
# @file        scripts/observability/comprehensive-log-pipeline-setup.sh
# @module      observability/setup
# @description Sets up complete logging pipeline: collection → aggregation → GitHub issues.
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════
# Comprehensive Log Pipeline Setup (Phase 22+)
#
# Purpose:
#   - One-shot setup for entire logging infrastructure
#   - Validates all components (Loki, Prometheus, GitHub)
#   - Starts all log collectors in daemon mode
#   - Creates systemd services for persistence
#
# Usage:
#   sudo bash scripts/observability/comprehensive-log-pipeline-setup.sh --install
#   sudo systemctl status logging-pipeline.service
#
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${PROJECT_ROOT}/scripts/_common/init.sh" || { echo "FATAL: Cannot source init.sh"; exit 1; }

# Configuration
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://localhost:3100}"
PROMETHEUS_ENDPOINT="${PROMETHEUS_ENDPOINT:-http://localhost:9090}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
INSTALL_MODE=false
DRY_RUN=false
SYSTEMD_USER="${SYSTEMD_USER:-root}"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL_MODE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --systemd-user)
      SYSTEMD_USER="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ════════════════════════════════════════════════════════════════════════════════════════════
# VALIDATION CHECKS
# ════════════════════════════════════════════════════════════════════════════════════════════

validate_components() {
  log_info "Validating logging pipeline components..."
  
  local all_valid=true
  
  # Check Loki connectivity
  log_info "  Checking Loki connectivity..."
  if curl -s "${LOKI_ENDPOINT}/ready" >/dev/null 2>&1; then
    log_success "    ✅ Loki is accessible"
  else
    log_error "    ❌ Loki not accessible at ${LOKI_ENDPOINT}"
    all_valid=false
  fi
  
  # Check Prometheus connectivity
  log_info "  Checking Prometheus connectivity..."
  if curl -s "${PROMETHEUS_ENDPOINT}/-/healthy" >/dev/null 2>&1; then
    log_success "    ✅ Prometheus is accessible"
  else
    log_warn "    ⚠️  Prometheus not accessible at ${PROMETHEUS_ENDPOINT}"
  fi
  
  # Check GitHub token
  if [[ -n "${GITHUB_TOKEN}" ]]; then
    log_info "  Checking GitHub token..."
    if curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
      "https://api.github.com/user" >/dev/null 2>&1; then
      log_success "    ✅ GitHub token is valid"
    else
      log_error "    ❌ GitHub token is invalid"
      all_valid=false
    fi
  else
    log_warn "    ⚠️  GITHUB_TOKEN not set - issue creation disabled"
  fi
  
  # Check required tools
  log_info "  Checking required tools..."
  for tool in bash jq curl docker docker-compose; do
    if command -v "${tool}" &>/dev/null; then
      log_success "    ✅ ${tool} available"
    else
      if [[ "${tool}" == "docker" ]] || [[ "${tool}" == "docker-compose" ]]; then
        log_warn "    ⚠️  ${tool} not found (optional)"
      else
        log_error "    ❌ ${tool} required but not found"
        all_valid=false
      fi
    fi
  done
  
  if [[ "${all_valid}" == "false" ]]; then
    log_fatal "Component validation failed"
    return 1
  fi
  
  log_success "All components validated"
  return 0
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# SYSTEMD SERVICE INSTALLATION
# ════════════════════════════════════════════════════════════════════════════════════════════

install_systemd_services() {
  log_info "Installing systemd services..."
  
  local service_dir="/etc/systemd/system"
  
  if [[ ! -d "${service_dir}" ]]; then
    log_error "Systemd not available"
    return 1
  fi
  
  # Error Triage Engine service
  local error_triage_service="${service_dir}/error-triage.service"
  log_info "  Creating error-triage.service..."
  
  if [[ "${DRY_RUN}" == "false" ]]; then
    sudo tee "${error_triage_service}" >/dev/null <<EOF
[Unit]
Description=Automated Error Triage Engine
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
User=${SYSTEMD_USER}
WorkingDirectory=${PROJECT_ROOT}
ExecStart=/bin/bash ${SCRIPT_DIR}/error-triage-engine.sh --daemon
Restart=always
RestartSec=30

Environment="LOKI_ENDPOINT=${LOKI_ENDPOINT}"
Environment="PROMETHEUS_ENDPOINT=${PROMETHEUS_ENDPOINT}"
Environment="GITHUB_TOKEN=${GITHUB_TOKEN}"
Environment="GITHUB_REPO=${GITHUB_REPO}"

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  else
    log_info "    [DRY-RUN] Would create error-triage.service"
  fi
  
  # HAProxy Failover Logger service
  local failover_service="${service_dir}/haproxy-failover.service"
  log_info "  Creating haproxy-failover.service..."
  
  if [[ "${DRY_RUN}" == "false" ]]; then
    sudo tee "${failover_service}" >/dev/null <<EOF
[Unit]
Description=HAProxy Failover Event Logger
After=network.target docker.service

[Service]
Type=simple
User=${SYSTEMD_USER}
WorkingDirectory=${PROJECT_ROOT}
ExecStart=/bin/bash ${SCRIPT_DIR}/haproxy-failover-event-logger.sh --daemon --interval 10
Restart=always
RestartSec=30

Environment="LOKI_ENDPOINT=${LOKI_ENDPOINT}"
Environment="GITHUB_TOKEN=${GITHUB_TOKEN}"
Environment="GITHUB_REPO=${GITHUB_REPO}"
Environment="HAPROXY_STATS_URL=http://localhost:8404/haproxy-stats;csv"
Environment="HAPROXY_USER=admin"
Environment="HAPROXY_PASSWORD=admin123"

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  else
    log_info "    [DRY-RUN] Would create haproxy-failover.service"
  fi
  
  # System Log Shipper service
  local syslog_service="${service_dir}/system-log-shipper.service"
  log_info "  Creating system-log-shipper.service..."
  
  if [[ "${DRY_RUN}" == "false" ]]; then
    sudo tee "${syslog_service}" >/dev/null <<EOF
[Unit]
Description=System Log Shipper to Loki
After=network.target

[Service]
Type=oneshot
User=${SYSTEMD_USER}
WorkingDirectory=${PROJECT_ROOT}
ExecStart=/bin/bash ${SCRIPT_DIR}/system-log-shipper.sh
StandardOutput=journal
StandardError=journal

# Run every 5 minutes
ExecStartPost=/usr/bin/systemctl start system-log-shipper.timer

[Install]
WantedBy=multi-user.target
EOF
  else
    log_info "    [DRY-RUN] Would create system-log-shipper.service"
  fi
  
  # Log-to-GitHub Bridge service
  local bridge_service="${service_dir}/log-github-bridge.service"
  log_info "  Creating log-github-bridge.service..."
  
  if [[ "${DRY_RUN}" == "false" ]]; then
    sudo tee "${bridge_service}" >/dev/null <<EOF
[Unit]
Description=Log-to-GitHub Bridge (Automated Issue Creation)
After=network.target docker.service

[Service]
Type=simple
User=${SYSTEMD_USER}
WorkingDirectory=${PROJECT_ROOT}
ExecStart=/bin/bash ${SCRIPT_DIR}/log-to-github-bridge.sh --daemon --interval 600
Restart=always
RestartSec=60

Environment="LOKI_ENDPOINT=${LOKI_ENDPOINT}"
Environment="GITHUB_TOKEN=${GITHUB_TOKEN}"
Environment="GITHUB_REPO=${GITHUB_REPO}"

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  else
    log_info "    [DRY-RUN] Would create log-github-bridge.service"
  fi
  
  # Reload systemd and enable services
  if [[ "${DRY_RUN}" == "false" ]]; then
    log_info "  Enabling and starting services..."
    sudo systemctl daemon-reload
    sudo systemctl enable error-triage.service
    sudo systemctl enable haproxy-failover.service
    sudo systemctl enable log-github-bridge.service
    
    log_success "Systemd services installed and enabled"
  else
    log_info "  [DRY-RUN] Would enable and start services"
  fi
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# PROMTAIL CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════════════════════

install_promtail_config() {
  log_info "Setting up Promtail for log collection..."
  
  local promtail_config="${PROJECT_ROOT}/config/promtail-docker-logging.yaml"
  
  if [[ -f "${promtail_config}" ]]; then
    log_success "Promtail config already exists"
    return 0
  fi
  
  log_info "  Creating Docker logging driver config..."
  
  if [[ "${DRY_RUN}" == "false" ]]; then
    mkdir -p "$(dirname "${promtail_config}")"
    cat > "${promtail_config}" <<'EOF'
# Docker daemon.json logging configuration for Loki
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "labels": "job,instance"
  }
}

# Note: For native Loki support, consider using:
# docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions
# Then update daemon.json with:
# "log-driver": "loki",
# "log-opts": {
#   "loki-url": "http://loki:3100/loki/api/v1/push",
#   "loki-batch-size": "400"
# }
EOF
    log_success "Promtail config created"
  else
    log_info "  [DRY-RUN] Would create Promtail config"
  fi
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN INSTALLATION FLOW
# ════════════════════════════════════════════════════════════════════════════════════════════

run_installation() {
  log_info "════════════════════════════════════════════════════════════════════════════════════"
  log_info "Comprehensive Logging Pipeline Installation"
  log_info "════════════════════════════════════════════════════════════════════════════════════"
  
  # Validate components
  validate_components || return 1
  
  # Install Promtail config
  install_promtail_config || true
  
  # Install systemd services
  install_systemd_services || return 1
  
  log_success "════════════════════════════════════════════════════════════════════════════════════"
  log_success "Logging Pipeline Installation Complete!"
  log_success "════════════════════════════════════════════════════════════════════════════════════"
  
  echo ""
  echo "Next Steps:"
  echo "  1. Verify services: sudo systemctl status error-triage haproxy-failover log-github-bridge"
  echo "  2. View logs: sudo journalctl -u error-triage -f"
  echo "  3. Check GitHub issues: https://github.com/${GITHUB_REPO}/issues"
  echo ""
  echo "Environment Variables Set:"
  echo "  LOKI_ENDPOINT: ${LOKI_ENDPOINT}"
  echo "  PROMETHEUS_ENDPOINT: ${PROMETHEUS_ENDPOINT}"
  echo "  GITHUB_REPO: ${GITHUB_REPO}"
  echo "  GITHUB_TOKEN: $([ -n "${GITHUB_TOKEN}" ] && echo 'SET' || echo 'NOT SET')"
  echo ""
  
  return 0
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════════════════════

main() {
  if [[ "${INSTALL_MODE}" == "false" ]]; then
    log_error "Installation mode not specified"
    echo ""
    echo "Usage: $0 --install [--dry-run]"
    echo ""
    echo "Options:"
    echo "  --install     Execute installation"
    echo "  --dry-run     Show what would be installed without making changes"
    exit 1
  fi
  
  run_installation
}

main "$@"
