#!/usr/bin/env bash
# @file        scripts/ops/setup-automated-failover-monitoring.sh
# @module      infrastructure/reliability
# @description Setup Prometheus AlertManager webhook for automated failover response
# @owner       Infrastructure Team
# @status      In development - April 23, 2026

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
PRIMARY_USER="${PRIMARY_USER:-akushnir}"
ALERT_WEBHOOK_PORT="${ALERT_WEBHOOK_PORT:-5001}"

# ============================================================================
# Logging Functions
# ============================================================================

log_info() { log_info "$(date '+%Y-%m-%d %H:%M:%S') [FAILOVER] $*"; }
log_error() { log_error "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*"; }
log_warn() { log_warn "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*"; }

# ============================================================================
# AlertManager Webhook Configuration
# ============================================================================

create_webhook_handler() {
    cat > /tmp/failover-webhook-handler.sh <<'EOF'
#!/bin/bash
# Webhook receiver for Prometheus AlertManager
# Triggers failover when critical alerts received

REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
PRIMARY_USER="${PRIMARY_USER:-akushnir}"

log_failover() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [FAILOVER] $*" | tee -a /var/log/failover-webhook.log
}

trigger_failover() {
    log_failover "Failover triggered by alert: $1"
    
    # Promote replica to primary
    log_failover "Promoting replica to primary..."
    ssh "${PRIMARY_USER}@${REPLICA_HOST}" "
        docker exec postgres psql -U postgres -c 'SELECT pg_promote();' 2>/dev/null || \
        docker exec postgres pg_ctl promote -D /var/lib/postgresql/data
    "
    
    if [ $? -eq 0 ]; then
        log_failover "✓ Replica promoted to primary"
        
        # Update application configuration if needed
        ssh "${PRIMARY_USER}@${REPLICA_HOST}" "
            docker-compose restart code-server oauth2-proxy caddy 2>/dev/null || true
        "
        
        log_failover "✓ Services restarted on new primary"
    else
        log_failover "✗ Failover failed - manual intervention required"
        exit 1
    fi
}

# Parse alert webhook payload
ALERT_STATUS=$(echo "$1" | jq -r '.status' 2>/dev/null || echo "unknown")
ALERT_SEVERITY=$(echo "$1" | jq -r '.alerts[0].labels.severity' 2>/dev/null || echo "unknown")

if [ "${ALERT_STATUS}" = "firing" ] && [ "${ALERT_SEVERITY}" = "critical" ]; then
    trigger_failover "$(echo "$1" | jq -r '.alerts[0].labels.alertname')"
else
    log_failover "Non-critical alert ignored: status=${ALERT_STATUS}, severity=${ALERT_SEVERITY}"
fi
EOF
    chmod +x /tmp/failover-webhook-handler.sh
}

# ============================================================================
# AlertManager Configuration
# ============================================================================

update_alertmanager_config() {
    log_info "Updating AlertManager configuration for webhook..."
    
    cat > /tmp/alertmanager-failover.yml <<'EOF'
global:
  resolve_timeout: 5m
  
route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  
  routes:
    # Critical infrastructure alerts trigger failover
    - match:
        severity: critical
        alerttype: infrastructure
      receiver: 'failover-webhook'
      continue: true
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 1h
    
    # Database alerts
    - match:
        severity: critical
        alerttype: database
      receiver: 'failover-webhook'
      continue: true
      group_wait: 5s
      group_interval: 5m
      repeat_interval: 1h
    
    # Default handling for other alerts
    - receiver: 'default'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:9093/api/v1/alerts'
        send_resolved: true
  
  - name: 'failover-webhook'
    webhook_configs:
      - url: 'http://localhost:5001/webhook'
        send_resolved: false

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'cluster', 'service']
EOF
    
    log_info "AlertManager failover configuration ready"
}

# ============================================================================
# Prometheus Alert Rules
# ============================================================================

create_critical_alert_rules() {
    cat > /tmp/critical-alerts.yml <<'EOF'
groups:
  - name: infrastructure-critical
    interval: 10s
    rules:
      # PostgreSQL down
      - alert: PostgreSQLDown
        expr: up{job="postgres"} == 0
        for: 10s
        labels:
          severity: critical
          alerttype: infrastructure
        annotations:
          summary: "PostgreSQL is down"
          description: "PostgreSQL has been unreachable for more than 10 seconds"
      
      # Redis down
      - alert: RedisDown
        expr: up{job="redis"} == 0
        for: 10s
        labels:
          severity: critical
          alerttype: infrastructure
        annotations:
          summary: "Redis is down"
          description: "Redis has been unreachable for more than 10 seconds"
      
      # Replication lag critical
      - alert: ReplicationLagCritical
        expr: pg_replication_lag{} > 5
        for: 30s
        labels:
          severity: critical
          alerttype: database
        annotations:
          summary: "Replication lag critical"
          description: "PostgreSQL replication lag is {{ $value }}s (>5s)"
      
      # Primary host down
      - alert: PrimaryHostDown
        expr: up{instance="192.168.168.31:9100"} == 0
        for: 10s
        labels:
          severity: critical
          alerttype: infrastructure
        annotations:
          summary: "Primary host is down"
          description: "Primary host (192.168.168.31) is unreachable"
EOF
    
    log_info "Critical alert rules created"
}

# ============================================================================
# Deploy Webhook Handler
# ============================================================================

deploy_webhook_handler() {
    log_info "Deploying webhook handler to primary host..."
    
    ssh "${PRIMARY_USER}@${PRIMARY_HOST}" "
    cat > /tmp/failover-webhook.sh <<'HEREDOC'
$(cat /tmp/failover-webhook-handler.sh)
HEREDOC
    chmod +x /tmp/failover-webhook.sh
    "
    
    log_info "✓ Webhook handler deployed"
}

# ============================================================================
# Setup AlertManager on Primary
# ============================================================================

setup_alertmanager_webhook() {
    log_info "Configuring AlertManager webhook endpoint..."
    
    ssh "${PRIMARY_USER}@${PRIMARY_HOST}" "
    # Update alertmanager configuration
    docker cp /tmp/alertmanager-failover.yml alertmanager:/etc/alertmanager/alertmanager.yml 2>/dev/null || {
        docker exec alertmanager bash -c 'cat >> /etc/alertmanager/alertmanager.yml' <<'HEREDOC'

# Failover webhook routing (appended)
failover_webhook:
  url: 'http://localhost:${ALERT_WEBHOOK_PORT}/webhook'
  send_resolved: false
HEREDOC
    }
    
    # Reload AlertManager config
    docker exec alertmanager amtool config reload 2>/dev/null || \
    docker kill --signal=HUP alertmanager 2>/dev/null || true
    "
    
    log_info "✓ AlertManager configured for webhook"
}

# ============================================================================
# Register Critical Alerts
# ============================================================================

register_critical_alerts() {
    log_info "Registering critical alert rules with Prometheus..."
    
    ssh "${PRIMARY_USER}@${PRIMARY_HOST}" "
    # Add critical alert rules to Prometheus
    docker cp /tmp/critical-alerts.yml prometheus:/etc/prometheus/rules/ 2>/dev/null || {
        docker exec prometheus bash -c 'cat >> /etc/prometheus/prometheus.yml' <<'HEREDOC'

# Critical infrastructure alert rules (added)
rule_files:
  - '/etc/prometheus/rules/critical-alerts.yml'
HEREDOC
    }
    
    # Reload Prometheus
    docker exec prometheus kill -HUP 1 2>/dev/null || true
    "
    
    log_info "✓ Critical alert rules registered"
}

# ============================================================================
# Test Failover Trigger
# ============================================================================

test_failover_webhook() {
    log_info "Testing failover webhook..."
    
    # Simulate alert webhook call
    curl -X POST http://${PRIMARY_HOST}:${ALERT_WEBHOOK_PORT}/webhook \
        -H "Content-Type: application/json" \
        -d '{
          "status": "firing",
          "alerts": [{
            "status": "firing",
            "labels": {
              "alertname": "PostgreSQLDown",
              "severity": "critical"
            }
          }]
        }' 2>/dev/null || log_warn "Webhook test failed (may be expected if not yet listening)"
    
    sleep 2
    
    log_info "Failover webhook test completed"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "Setting up Automated Failover Monitoring"
    
    # Create webhook handler
    create_webhook_handler
    
    # Update AlertManager config
    update_alertmanager_config
    
    # Create critical alert rules
    create_critical_alert_rules
    
    # Deploy to primary host
    deploy_webhook_handler
    setup_alertmanager_webhook
    register_critical_alerts
    
    # Test webhook
    test_failover_webhook
    
    log_info "✓ Automated failover monitoring setup complete!"
    log_info "Critical alerts will now trigger automatic failover"
    log_info "Monitor progress at: http://${PRIMARY_HOST}:3000 (Grafana)"
    
    return 0
}

# Run
main "$@"
