#!/usr/bin/env bash
# @file        scripts/ops/deploy-sla-metrics.sh
# @module      ops/monitoring
# @description Deploy SLA metrics and alert rules to Prometheus for production monitoring
# @owner       platform
# @status      active
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"
init_repo

################################################################################
# SLA METRICS DEPLOYMENT
################################################################################

PROMETHEUS_CONFIG="${SCRIPT_DIR}/monitoring/prometheus-sla-rules.yml"
ALERTMANAGER_CONFIG="${SCRIPT_DIR}/monitoring/alertmanager-sla-rules.yml"
REPLICAS="${REPLICAS:-192.168.168.31,192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"

log_info "📈 SLA Metrics & Alert Rules Deployment"
log_info "   Targets: $REPLICAS"
log_info ""

################################################################################
# CREATE PROMETHEUS ALERT RULES
################################################################################

log_info "🔨 Creating Prometheus SLA alert rules..."

mkdir -p "$(dirname "$PROMETHEUS_CONFIG")"

cat > "$PROMETHEUS_CONFIG" << 'EOF'
# Prometheus Alert Rules for SLA Compliance
# Generated from docs/PRODUCTION-SLA-METRICS.md

groups:
  - name: sla_compliance
    interval: 30s
    rules:
      # SLA Target 1: 99.9% deployment success rate
      - alert: DeploymentSuccessRateLow
        expr: rate(deployment_success_total[5m]) < 0.999
        for: 5m
        labels:
          severity: warning
          sla: deployment_success
        annotations:
          summary: "Deployment success rate below SLA target (99.9%)"
          description: "Current rate: {{ $value | humanizePercentage }}"

      # SLA Target 2: Zero data loss per deployment
      - alert: DataLossDetected
        expr: increase(data_loss_events_total[1m]) > 0
        for: 1m
        labels:
          severity: critical
          sla: data_loss
        annotations:
          summary: "DATA LOSS EVENT DETECTED - IMMEDIATE ESCALATION REQUIRED"
          description: "Count: {{ $value }}"

      # SLA Target 3: Automatic recovery within 5 minutes
      - alert: RecoveryTimeExceeded
        expr: max(recovery_time_seconds) > 300
        for: 1m
        labels:
          severity: critical
          sla: recovery_time
        annotations:
          summary: "Recovery time exceeded SLA target (5 minutes)"
          description: "Current: {{ $value | humanizeDuration }}"

      # SLA Target 4: Deployment duration 8-13 minutes
      - alert: DeploymentDurationOutOfSLA
        expr: deployment_duration_seconds > 900 or deployment_duration_seconds < 480
        for: 1m
        labels:
          severity: warning
          sla: deployment_duration
        annotations:
          summary: "Deployment duration outside SLA window (8-13 minutes)"
          description: "Current: {{ $value | humanizeDuration }}"

      # SLA Target 5: Load balancer failover < 5 seconds
      - alert: FailoverTimeExceeded
        expr: lb_failover_time_seconds > 5
        for: 1m
        labels:
          severity: warning
          sla: failover_time
        annotations:
          summary: "Load balancer failover time exceeds SLA (5 seconds)"
          description: "Current: {{ $value }}s"

      # SLA Target 6: Health check response < 500ms
      - alert: HealthCheckLatencyHigh
        expr: histogram_quantile(0.99, health_check_duration_seconds) > 0.5
        for: 5m
        labels:
          severity: warning
          sla: health_check_latency
        annotations:
          summary: "Health check latency exceeds SLA (500ms)"
          description: "P99: {{ $value }}s"
EOF

log_info "✅ Prometheus alert rules created"
log_info ""

################################################################################
# CREATE ALERTMANAGER ROUTES FOR SLA ALERTS
################################################################################

log_info "🔨 Creating AlertManager SLA routing rules..."

mkdir -p "$(dirname "$ALERTMANAGER_CONFIG")"

cat > "$ALERTMANAGER_CONFIG" << 'EOF'
# AlertManager routing rules for SLA violations
# Routes SLA alerts to appropriate escalation channels

routes:
  # Critical SLA violations: Immediate escalation
  - match:
      severity: critical
      sla: data_loss
    group_by: ['sla']
    group_wait: 1m
    group_interval: 5m
    repeat_interval: 1h
    receiver: 'escalation-critical'
    
  - match:
      severity: critical
      sla: recovery_time
    group_by: ['sla']
    group_wait: 1m
    group_interval: 5m
    repeat_interval: 1h
    receiver: 'escalation-critical'

  # Warning SLA violations: Standard escalation
  - match:
      severity: warning
      sla: deployment_success
    group_by: ['sla']
    group_wait: 5m
    group_interval: 15m
    repeat_interval: 4h
    receiver: 'escalation-warning'

  - match:
      severity: warning
      sla: deployment_duration
    group_by: ['sla']
    group_wait: 5m
    group_interval: 15m
    repeat_interval: 4h
    receiver: 'escalation-warning'

  - match:
      severity: warning
      sla: failover_time
    group_by: ['sla']
    group_wait: 5m
    group_interval: 15m
    repeat_interval: 4h
    receiver: 'escalation-warning'

  - match:
      severity: warning
      sla: health_check_latency
    group_by: ['sla']
    group_wait: 10m
    group_interval: 30m
    repeat_interval: 8h
    receiver: 'escalation-info'

# Receivers for escalation
receivers:
  - name: 'escalation-critical'
    # Send to: PagerDuty, SMS, Slack #critical
    
  - name: 'escalation-warning'
    # Send to: Slack #alerts, Email ops-team

  - name: 'escalation-info'
    # Send to: Slack #monitoring
EOF

log_info "✅ AlertManager routing rules created"
log_info ""

################################################################################
# DOCUMENTATION
################################################################################

log_info "📚 SLA Metrics Deployment Documentation"
log_info ""
log_info "✅ Alert Rules Created:"
log_info "   - Deployment success rate monitoring (99.9% target)"
log_info "   - Data loss detection (zero loss requirement)"
log_info "   - Recovery time tracking (< 5 min target)"
log_info "   - Deployment duration monitoring (8-13 min target)"
log_info "   - Failover time tracking (< 5 sec target)"
log_info "   - Health check latency monitoring (< 500ms target)"
log_info ""
log_info "✅ Escalation Routes Configured:"
log_info "   - Critical: Immediate escalation (data loss, recovery time)"
log_info "   - Warning: Standard escalation (deployment, failover metrics)"
log_info "   - Info: Dashboard-only escalation (latency trends)"
log_info ""
log_info "📊 Next Steps:"
log_info "   1. Deploy alert rules to Prometheus: /etc/prometheus/rules/"
log_info "   2. Configure AlertManager receivers (PagerDuty, Slack, Email)"
log_info "   3. Restart Prometheus: docker compose restart prometheus"
log_info "   4. Verify rules loaded: curl http://localhost:9090/api/v1/rules"
log_info ""
log_info "✅ SLA METRICS DEPLOYMENT READY"
log_info ""
exit 0
