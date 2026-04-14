#!/bin/bash

################################################################################
# Phase 16 Monitoring & SLO Configuration
# Purpose: Deploy Phase 16-specific Prometheus/Grafana configuration
# Timeline: April 21-27, 2026
# 
# Usage: bash scripts/phase-16-monitoring-setup.sh
#
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="${ROOT_DIR}/config/phase-16"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}"
}

log_error() {
    echo -e "${RED}❌ ERROR: $*${NC}"
}

# ============================================================================
# PROMETHEUS CONFIGURATION
# ============================================================================

create_prometheus_rules() {
    log "Creating Prometheus alert rules for Phase 16..."
    
    mkdir -p "${CONFIG_DIR}/prometheus"
    
    cat > "${CONFIG_DIR}/prometheus/phase-16-rules.yml" << 'EOF'
groups:
  - name: phase_16_slo_alerts
    interval: 30s
    rules:
      # p99 Latency Alert
      - alert: Phase16_P99LatencyExceeded
        expr: histogram_quantile(0.99, rate(http_request_duration_ms_bucket[5m])) > 150
        for: 5m
        labels:
          severity: critical
          phase: 16
        annotations:
          summary: "p99 Latency exceeds 150ms"
          description: "Phase 16 p99 latency is {{ $value }}ms (target: <100ms)"
          dashboard: "http://localhost:3000/d/phase-16-slo"
          runbook: "wiki/runbooks/phase-16-latency.md"

      # Error Rate Alert
      - alert: Phase16_ErrorRateExceeded
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.001
        for: 2m
        labels:
          severity: high
          phase: 16
        annotations:
          summary: "Error rate exceeds 0.1%"
          description: "Phase 16 error rate is {{ $value }} (target: <0.001)"
          dashboard: "http://localhost:3000/d/phase-16-slo"

      # Availability Alert
      - alert: Phase16_AvailabilityExceeded
        expr: (1 - (increase(http_requests_total{status=~"5.."}[5m]) / increase(http_requests_total[5m]))) < 0.999
        for: 10m
        labels:
          severity: critical
          phase: 16
        annotations:
          summary: "Availability drops below 99.9%"
          description: "Phase 16 availability is {{ $value }}% (target: >99.9%)"

      # Developer Active Sessions
      - alert: Phase16_LowDeveloperActivity
        expr: count(active_developer_sessions) < (day_of_month * 7 - 1)
        for: 15m
        labels:
          severity: warning
          phase: 16
        annotations:
          summary: "Developer active sessions below expected"
          description: "Only {{ $value }} developers active (expected: ~{{ day_of_month * 7 }})"

      # Redis Cache Issues
      - alert: Phase16_RedisCacheDown
        expr: up{job="redis"} == 0
        for: 1m
        labels:
          severity: high
          phase: 16
        annotations:
          summary: "Redis cache is down"
          description: "Phase 15 Redis cache (used in Phase 16) became unavailable"
          runbook: "wiki/runbooks/redis-failure.md"

      # Pod Restart Detection
      - alert: Phase16_PodRestarting
        expr: rate(kube_pod_container_status_restarts_total{pod=~"code-server.*"}[1h]) > 0
        labels:
          severity: medium
          phase: 16
        annotations:
          summary: "code-server pod restarting"
          description: "Pod {{ $labels.pod_name }} restarted in last hour"

EOF
    
    log_success "Prometheus rules created"
}

# ============================================================================
# GRAFANA DASHBOARDS
# ============================================================================

create_grafana_dashboards() {
    log "Creating Grafana dashboards for Phase 16..."
    
    mkdir -p "${CONFIG_DIR}/grafana/dashboards"
    
    # Dashboard 1: Phase 16 SLO Overview
    cat > "${CONFIG_DIR}/grafana/dashboards/phase-16-slo.json" << 'EOF'
{
  "dashboard": {
    "title": "Phase 16 - SLO Overview",
    "tags": ["phase-16", "slo", "production"],
    "timezone": "browser",
    "panels": [
      {
        "title": "p99 Latency (target: <100ms)",
        "targets": [
          {
            "expr": "histogram_quantile(0.99, rate(http_request_duration_ms_bucket[5m]))"
          }
        ],
        "alert": {
          "conditions": [{"evaluator": {"params": [150], "type": "gt"}}]
        }
      },
      {
        "title": "Error Rate (target: <0.1%)",
        "targets": [
          {
            "expr": "rate(http_requests_total{status=~\"5..\"}[5m])"
          }
        ]
      },
      {
        "title": "Availability (target: >99.9%)",
        "targets": [
          {
            "expr": "(1 - (increase(http_requests_total{status=~\"5..\"}[5m]) / increase(http_requests_total[5m])))"
          }
        ]
      },
      {
        "title": "Throughput (req/s)",
        "targets": [
          {
            "expr": "rate(http_requests_total[1m])"
          }
        ]
      },
      {
        "title": "Active Developers",
        "targets": [
          {
            "expr": "count(active_developer_sessions)"
          }
        ]
      },
      {
        "title": "Request Distribution (by day)",
        "targets": [
          {
            "expr": "sum by (day) (rate(http_requests_total[5m]))"
          }
        ]
      }
    ]
  }
}
EOF

    # Dashboard 2: Developer Onboarding Progress
    cat > "${CONFIG_DIR}/grafana/dashboards/phase-16-developer-activity.json" << 'EOF'
{
  "dashboard": {
    "title": "Phase 16 - Developer Activity & Onboarding",
    "tags": ["phase-16", "developers", "onboarding"],
    "panels": [
      {
        "title": "Developers Onboarded (by day)",
        "targets": [
          {
            "expr": "count(developer_first_session_time) by (day)"
          }
        ]
      },
      {
        "title": "Developer Productivity (commits/day)",
        "targets": [
          {
            "expr": "sum(rate(git_commits_total[1d])) by (day)"
          }
        ]
      },
      {
        "title": "Session Duration by Developer",
        "targets": [
          {
            "expr": "avg(developer_session_duration_minutes) by (email)"
          }
        ]
      },
      {
        "title": "Developer Satisfaction (feedback)",
        "targets": [
          {
            "expr": "avg(developer_satisfaction_score) by (day)"
          }
        ]
      },
      {
        "title": "Support Requests (by day)",
        "targets": [
          {
            "expr": "sum(support_requests_total) by (day, severity)"
          }
        ]
      },
      {
        "title": "IDE Accessibility Score",
        "targets": [
          {
            "expr": "ide_accessibility_score * 100"
          }
        ]
      }
    ]
  }
}
EOF

    # Dashboard 3: Infrastructure Health
    cat > "${CONFIG_DIR}/grafana/dashboards/phase-16-infrastructure.json" << 'EOF'
{
  "dashboard": {
    "title": "Phase 16 - Infrastructure Health",
    "tags": ["phase-16", "infrastructure", "ops"],
    "panels": [
      {
        "title": "Pod Replica Status",
        "targets": [
          {
            "expr": "kube_deployment_status_replicas{deployment=~\"code-server.*\"}"
          }
        ]
      },
      {
        "title": "Memory Usage (by pod)",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{pod=~\"code-server.*\"}"
          }
        ]
      },
      {
        "title": "CPU Usage (by pod)",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{pod=~\"code-server.*\"}[5m])"
          }
        ]
      },
      {
        "title": "Network I/O (ingress/egress)",
        "targets": [
          {
            "expr": "rate(container_network_transmit_bytes[5m])"
          }
        ]
      },
      {
        "title": "Disk Space Available",
        "targets": [
          {
            "expr": "node_filesystem_avail_bytes"
          }
        ]
      },
      {
        "title": "Redis Memory Usage",
        "targets": [
          {
            "expr": "redis_memory_used_bytes"
          }
        ]
      }
    ]
  }
}
EOF

    log_success "Grafana dashboards created"
}

# ============================================================================
# ALERTMANAGER CONFIGURATION
# ============================================================================

create_alertmanager_config() {
    log "Creating AlertManager configuration for Phase 16..."
    
    mkdir -p "${CONFIG_DIR}/alertmanager"
    
    cat > "${CONFIG_DIR}/alertmanager/phase-16-routes.yml" << 'EOF'
route:
  receiver: 'phase-16-critical'
  group_by: ['phase', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 5m
  routes:
    # Critical alerts: Page SRE immediately
    - match:
        severity: critical
        phase: 16
      receiver: 'phase-16-critical'
      group_wait: 0s
      repeat_interval: 5m

    # High alerts: Alert to team
    - match:
        severity: high
        phase: 16
      receiver: 'phase-16-high'
      repeat_interval: 15m

    # Medium alerts: Log to operations
    - match:
        severity: medium
        phase: 16
      receiver: 'phase-16-medium'
      repeat_interval: 30m

receivers:
  # Critical: Page on-call + Slack + Email + Status page
  - name: 'phase-16-critical'
    slack_configs:
      - api_url: 'SLACK_WEBHOOK_URL'
        channel: '#incident-response'
        title: '🚨 CRITICAL - Phase 16: {{ .GroupLabels.alertname }}'
        text: 'Severity: {{ .GroupLabels.severity }}\nDetailed info: {{ .Alerts.Firing | len }} firing'
        send_resolved: true
    email_configs:
      - to: 'sre-oncall@company.com'
        from: 'phase-16-alerts@company.com'
        smarthost: 'smtp.company.com:587'
    pagerduty_configs:
      - service_key: 'PD_SERVICE_KEY'

  # High: Alert to team Slack
  - name: 'phase-16-high'
    slack_configs:
      - api_url: 'SLACK_WEBHOOK_URL'
        channel: '#code-server-ops'
        title: '⚠️  HIGH - Phase 16: {{ .GroupLabels.alertname }}'
        send_resolved: true

  # Medium: Operations channel
  - name: 'phase-16-medium'
    slack_configs:
      - api_url: 'SLACK_WEBHOOK_URL'
        channel: '#operations'
        title: '📊 Phase 16: {{ .GroupLabels.alertname }}'
        send_resolved: false

grouping_labels:
  - phase
  - severity
  - alertname

EOF
    
    log_success "AlertManager configuration created"
}

# ============================================================================
# SLO RECORDING RULES
# ============================================================================

create_slo_recording_rules() {
    log "Creating SLO recording rules..."
    
    cat > "${CONFIG_DIR}/prometheus/phase-16-slo-rules.yml" << 'EOF'
groups:
  - name: phase_16_slo_recording
    interval: 30s
    rules:
      # SLI: Request latency (p99)
      - record: phase16:sli_request_latency:p99
        expr: histogram_quantile(0.99, rate(http_request_duration_ms_bucket[5m]))

      # SLI: Error rate
      - record: phase16:sli_error_rate:ratio
        expr: sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

      # SLI: Availability
      - record: phase16:sli_availability:ratio
        expr: sum(rate(http_requests_total{status=~"2.."}[5m])) / sum(rate(http_requests_total[5m]))

      # SLO: Is latency SLO met?
      - record: phase16:slo_latency_met:bool
        expr: phase16:sli_request_latency:p99 < 100

      # SLO: Is error rate SLO met?
      - record: phase16:slo_error_rate_met:bool
        expr: phase16:sli_error_rate:ratio < 0.001

      # SLO: Is availability SLO met?
      - record: phase16:slo_availability_met:bool
        expr: phase16:sli_availability:ratio > 0.999

      # SLO: Days until SLO burndown (error budget exhaustion)
      - record: phase16:slo_error_budget_remaining:days
        expr: |
          (1 - 0.001) - (sum_over_time(phase16:sli_error_rate:ratio[30d]))
          /
          30

EOF
    
    log_success "SLO recording rules created"
}

# ============================================================================
# NOTIFICATION TEMPLATES
# ============================================================================

create_notification_templates() {
    log "Creating notification templates..."
    
    mkdir -p "${CONFIG_DIR}/templates"
    
    cat > "${CONFIG_DIR}/templates/phase-16-alert.tmpl" << 'EOF'
{{define "phase16_alert"}}
Phase 16 Production Rollout Alert
{{.Status|toUpper}}

Alert: {{.GroupLabels.alertname}}
Severity: {{.GroupLabels.severity}}
Phase: {{.GroupLabels.phase}}

{{range .Alerts.Firing}}
Instance: {{.Labels.instance}}
Value: {{.Value}}
Description: {{.Annotations.description}}
Runbook: {{.Annotations.runbook}}
{{end}}

Dashboard: http://localhost:3000/d/phase-16-slo
{{end}}
EOF
    
    log_success "Notification templates created"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo -e "${BLUE}=== Phase 16 Monitoring Setup ===${NC}"
    echo "Creating comprehensive monitoring configuration for Phase 16..."
    
    mkdir -p "$CONFIG_DIR"
    
    create_prometheus_rules
    create_grafana_dashboards
    create_alertmanager_config
    create_slo_recording_rules
    create_notification_templates
    
    echo -e "\n${GREEN}✅ Phase 16 Monitoring Setup Complete${NC}"
    echo "Configuration files created in: $CONFIG_DIR"
    echo ""
    echo "Next steps:"
    echo "1. Copy Prometheus rules: cp ${CONFIG_DIR}/prometheus/*.yml /etc/prometheus/"
    echo "2. Copy Grafana dashboards: Copy to /etc/grafana/provisioning/dashboards/"
    echo "3. Update AlertManager config: Update webhook URLs in ${CONFIG_DIR}/alertmanager/"
    echo "4. Reload Prometheus: systemctl reload prometheus"
    echo "5. Reload AlertManager: systemctl reload alertmanager"
    echo ""
    echo "Verify dashboards at: http://localhost:3000/d/phase-16-slo"
}

main "$@"
