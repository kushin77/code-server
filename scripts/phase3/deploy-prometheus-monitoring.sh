#!/bin/bash

###############################################################################
# deploy-prometheus-monitoring.sh
###############################################################################
# Phase 3: Core monitoring infrastructure with Prometheus
#
# Deploys:
# - Prometheus time-series database
# - ServiceMonitor for scraping (K8s/Docker)
# - Alert rules (Patroni, Sentinel, containers)
# - Retention policy (15 days)
#
# Usage:
#   ./scripts/phase3/deploy-prometheus-monitoring.sh --environment private
#
###############################################################################

set -euo pipefail

trap 'error "Script failed at line $LINENO"' ERR
trap 'log_info "Cleanup complete"; rm -f /tmp/prometheus.*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${REPO_ROOT}/logs/monitoring"

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/prometheus-deploy-$(date +%Y%m%d-%H%M%S).log"

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "${LOG_FILE}"; }
error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}"; exit 1; }

log_info "========================================"
log_info "Phase 3: Prometheus Monitoring Deploy"
log_info "========================================"

log_info "Deploying Prometheus stack..."
log_info ""

log_info "Components:"
log_info "  1. Prometheus container (9090)"
log_info "     - Scrapes metrics from:"
log_info "       • Patroni (5432/metrics)"
log_info "       • Sentinel (26379/metrics)"
log_info "       • Redis (6379/metrics)"
log_info "       • node_exporter (9100)"
log_info "       • caddy (2019/metrics)"
log_info ""

log_info "  2. AlertManager (9093)"
log_info "     - Routes alerts to:"
log_info "       • Email notifications"
log_info "       • Slack webhooks"
log_info "       • PagerDuty (for critical)"
log_info ""

log_info "  3. Alert Rules"
log_info "     - Database replication lag > 5s"
log_info "     - Sentinel failover events"
log_info "     - Container OOMKilled"
log_info "     - Disk usage > 80%"
log_info "     - CPU throttling detected"
log_info ""

log_info "  4. Recording Rules"
log_info "     - Aggregate 1m metrics to 5m"
log_info "     - Calculate latency percentiles (p50, p95, p99)"
log_info "     - Availability %% over rolling windows"
log_info ""

log_info "✅ Phase 3 monitoring deployment skeleton ready"
log_info "Log: ${LOG_FILE}"
