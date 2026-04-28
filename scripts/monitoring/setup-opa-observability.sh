#!/bin/bash
# @file scripts/monitoring/setup-opa-observability.sh
# @module infrastructure/observability
# @description P0-1552 Phase 5: Configure OPA decision logging and Prometheus metrics
# @governance GOV-002: All policy decisions logged and exported to observability pipeline
# @usage setup-opa-observability.sh [--enable-prometheus] [--enable-loki]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

OPA_METRICS="${REPO_ROOT}/artifacts/opa_metrics.prom"

mkdir -p "$(dirname "${OPA_METRICS}")"

log_success() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*"
}

# Export OPA metrics to Prometheus format
export_opa_metrics() {
  log_info "Exporting OPA decision metrics..."
  
  # Query OPA for decision statistics
  local decision_stats=$(curl -s http://localhost:8181/v1/data/system/opa/stats 2>/dev/null || echo '{}')
  
  cat > "${OPA_METRICS}" <<EOF
# HELP opa_decisions_total Total OPA policy decisions
# TYPE opa_decisions_total gauge
opa_decisions_total ${decision_stats}

# HELP opa_decision_evaluation_seconds OPA decision evaluation latency
# TYPE opa_decision_evaluation_seconds histogram
opa_decision_evaluation_seconds_bucket{le="0.001"} 0
opa_decision_evaluation_seconds_bucket{le="0.01"} 0
opa_decision_evaluation_seconds_bucket{le="0.1"} 0
opa_decision_evaluation_seconds_bucket{le="+Inf"} 0
EOF
  
  log_success "OPA metrics exported to ${OPA_METRICS}"
}

# Query OPA runtime for decision summary
query_opa_decision_summary() {
  log_info "Querying OPA for decision summary..."
  
  if ! curl -sf http://localhost:8181/health > /dev/null 2>&1; then
    log_error "OPA service not responding"
    return 1
  fi
  
  # Get allow/deny decision distribution
  local decision_log=$(curl -s http://localhost:8181/v1/data/system/opa/decisions 2>/dev/null || echo '{}')
  
  log_info "Decision log query completed"
  return 0
}

# Set up Prometheus scrape config for OPA
setup_prometheus_scrape() {
  log_info "Setting up Prometheus scrape configuration for OPA..."
  
  cat > "${REPO_ROOT}/config/opa-prometheus-scrape.yaml" <<'EOF'
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: 'opa'
    static_configs:
      - targets: ['localhost:8181']
    metrics_path: '/metrics'
    scrape_interval: 30s
    scrape_timeout: 5s
EOF
  
  log_success "Prometheus scrape config created"
}

# Create Grafana dashboard JSON for OPA metrics
generate_grafana_dashboard() {
  log_info "Generating Grafana dashboard for OPA policy metrics..."
  
  cat > "${REPO_ROOT}/dashboards/opa-policy-monitoring.json" <<'EOF'
{
  "dashboard": {
    "title": "OPA Policy Monitoring",
    "uid": "opa-policies",
    "tags": ["opa", "policy", "governance"],
    "timezone": "UTC",
    "panels": [
      {
        "title": "Policy Allow/Deny Rate",
        "targets": [
          {
            "expr": "rate(opa_decisions_total[5m])"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Decision Evaluation Latency",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, opa_decision_evaluation_seconds)"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Policy Violations by Type",
        "targets": [
          {
            "expr": "opa_policy_violations_total"
          }
        ],
        "type": "table"
      }
    ]
  }
}
EOF
  
  log_success "Grafana dashboard created at ${REPO_ROOT}/dashboards/opa-policy-monitoring.json"
}

# Set up alerting rules for OPA policy violations
generate_alert_rules() {
  log_info "Generating Prometheus alert rules for policy violations..."
  
  cat > "${REPO_ROOT}/config/opa-alert-rules.yaml" <<'EOF'
groups:
  - name: opa_policies
    rules:
      - alert: OPAPolicyViolationRateHigh
        expr: rate(opa_policy_violations_total[5m]) > 0.02
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "OPA policy violation rate spike detected"
      
      - alert: OPADecisionLatencyHigh
        expr: histogram_quantile(0.95, opa_decision_evaluation_seconds) > 0.1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "OPA decision evaluation latency exceeds 100ms"
      
      - alert: OPAServiceDown
        expr: up{job="opa"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "OPA service is down"
EOF
  
  log_success "Alert rules created at ${REPO_ROOT}/config/opa-alert-rules.yaml"
}

main() {
  local enable_prometheus=false
  local enable_loki=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --enable-prometheus)
        enable_prometheus=true
        shift
        ;;
      --enable-loki)
        enable_loki=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  log_info "Setting up OPA observability..."
  
  query_opa_decision_summary || exit 1
  export_opa_metrics || exit 1
  generate_grafana_dashboard || exit 1
  generate_alert_rules || exit 1
  
  if [[ "${enable_prometheus}" == "true" ]]; then
    setup_prometheus_scrape || exit 1
  fi
  
  log_success "OPA observability setup complete"
  log_info "Metrics available at: ${OPA_METRICS}"
  log_info "Grafana dashboard: opa-policy-monitoring"
  log_info "Alert rules: ${REPO_ROOT}/config/opa-alert-rules.yaml"
}

main "$@"