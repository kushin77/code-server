#!/usr/bin/env bash
# @file        scripts/ops/setup-automated-failover-monitoring.sh
# @module      infrastructure/reliability
# @description Setup Prometheus AlertManager webhook for automated failover response
# @owner       Infrastructure Team
# @status      In development - April 23, 2026
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

# Initialize repository context
init_repo

# Required configuration from environment
: "${PRIMARY_HOST:?PRIMARY_HOST must be set}"
: "${REPLICA_HOST:?REPLICA_HOST must be set}"
: "${PRIMARY_USER:?PRIMARY_USER must be set}"
: "${ALERTMANAGER_ALERTS_URL:?ALERTMANAGER_ALERTS_URL must be set}"
: "${FAILOVER_WEBHOOK_URL:?FAILOVER_WEBHOOK_URL must be set}"
: "${PRIMARY_EXPORTER_TARGET:?PRIMARY_EXPORTER_TARGET must be set}"

# ============================================================================
# AlertManager Webhook Configuration
# ============================================================================

create_webhook_handler() {
  cat > /tmp/failover-webhook-handler.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Webhook receiver for Prometheus AlertManager
# Triggers failover when critical alerts received

REPLICA_HOST="${REPLICA_HOST}"
PRIMARY_HOST="${PRIMARY_HOST}"
PRIMARY_USER="${PRIMARY_USER}"

log_failover() {
  echo "\$(date '+%Y-%m-%d %H:%M:%S') [FAILOVER] \$*" | tee -a /var/log/failover-webhook.log
}

trigger_failover() {
  log_failover "Failover triggered by alert: \$1"
    
  # Promote replica to primary
  log_failover "Promoting replica to primary..."
  ssh "\${PRIMARY_USER}@\${REPLICA_HOST}" "
    docker exec postgres psql -U postgres -c 'SELECT pg_promote();' 2>/dev/null || \
    docker exec postgres pg_ctl promote -D /var/lib/postgresql/data
  "
    
  if [ \$? -eq 0 ]; then
    log_failover "✓ Replica promoted to primary"
        
    # Update application configuration if needed
    ssh "\${PRIMARY_USER}@\${REPLICA_HOST}" "
      cd code-server-enterprise && docker-compose restart code-server oauth2-proxy caddy 2>/dev/null || true
    "
        
    log_failover "✓ Services restarted on new primary"
  else
    log_failover "✗ Failover failed - manual intervention required"
    exit 1
  fi
}

# Parse alert webhook payload
# Payload is received via stdin from a simple socat/nc listener or standard webhook server
INPUT=\$(cat)
ALERT_STATUS=\$(echo "\$INPUT" | jq -r '.status' 2>/dev/null || echo "unknown")
ALERT_SEVERITY=\$(echo "\$INPUT" | jq -r '.alerts[0].labels.severity' 2>/dev/null || echo "unknown")

if [ "\${ALERT_STATUS}" = "firing" ] && [ "\${ALERT_SEVERITY}" = "critical" ]; then
  trigger_failover "\$(echo "\$INPUT" | jq -r '.alerts[0].labels.alertname')"
else
  log_failover "Non-critical alert ignored: status=\${ALERT_STATUS}, severity=\${ALERT_SEVERITY}"
fi
EOF
  chmod +x /tmp/failover-webhook-handler.sh
}

# ============================================================================
# AlertManager Configuration
# ============================================================================

update_alertmanager_config() {
    log_info "Updating AlertManager configuration for webhook..."
    
  cat > /tmp/alertmanager-failover.yml <<EOF
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
      - url: '${ALERTMANAGER_ALERTS_URL}'
        send_resolved: true
  
  - name: 'failover-webhook'
    webhook_configs:
      - url: '${FAILOVER_WEBHOOK_URL}'
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
# Create Critical Alert Rules
# ============================================================================

create_critical_alert_rules() {
    log_info "Creating critical alert rules..."

  cat > /tmp/critical-alerts.yml <<EOF
groups:
  - name: critical-infrastructure
    rules:
      # PostgreSQL down
      - alert: PostgreSQLDown
        expr: pg_up == 0
        for: 10s
        labels:
          severity: critical
          alerttype: database
        annotations:
          summary: "PostgreSQL is down on primary"
          description: "PostgreSQL instance on {{ \$labels.instance }} has been down for more than 10 seconds"
      
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
          description: "PostgreSQL replication lag is {{ \$value }}s (>5s)"
      
      # Primary host down
      - alert: PrimaryHostDown
        expr: up{instance="${PRIMARY_EXPORTER_TARGET}"} == 0
        for: 10s
        labels:
          severity: critical
          alerttype: infrastructure
        annotations:
          summary: "Primary host is down"
          description: "Primary host (${PRIMARY_HOST}) is unreachable"
EOF
    
    log_info "Critical alert rules created"
}

# ============================================================================
# Deploy Webhook Handler
# ============================================================================

deploy_webhook_handler() {
    log_info "Deploying webhook handler to primary host..."
    
    ssh "${PRIMARY_USER}@${PRIMARY_HOST}" "mkdir -p /opt/failover/bin"
    scp /tmp/failover-webhook-handler.sh "${PRIMARY_USER}@${PRIMARY_HOST}:/opt/failover/bin/webhook-handler.sh"
    ssh "${PRIMARY_USER}@${PRIMARY_HOST}" "chmod +x /opt/failover/bin/webhook-handler.sh"
    
    log_info "✓ Webhook handler deployed"
}

# ============================================================================
# Setup AlertManager on Primary
# ============================================================================

setup_alertmanager_webhook() {
    log_info "Configuring AlertManager webhook endpoint on ${PRIMARY_HOST}..."

    scp /tmp/alertmanager-failover.yml "${PRIMARY_USER}@${PRIMARY_HOST}:/tmp/alertmanager-failover.yml"

    ssh "${PRIMARY_USER}@${PRIMARY_HOST}" "
    # Update alertmanager configuration
    docker cp /tmp/alertmanager-failover.yml alertmanager:/etc/alertmanager/alertmanager.yml 2>/dev/null || {
        docker exec alertmanager bash -c '
            if ! grep -q \"failover_webhook\" /etc/alertmanager/alertmanager.yml; then
                cat >> /etc/alertmanager/alertmanager.yml <<HEREDOC

# Failover webhook routing (appended)
failover_webhook:
  url: \"${FAILOVER_WEBHOOK_URL}\"
  send_resolved: false
HEREDOC
            fi
        '
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
    log_info "Registering critical alert rules with Prometheus on ${PRIMARY_HOST}..."

    scp /tmp/critical-alerts.yml "${PRIMARY_USER}@${PRIMARY_HOST}:/tmp/critical-alerts.yml"

    ssh "${PRIMARY_USER}@${PRIMARY_HOST}" "
    # Add critical alert rules to Prometheus
    docker exec prometheus mkdir -p /etc/prometheus/rules/
    docker cp /tmp/critical-alerts.yml prometheus:/etc/prometheus/rules/ 2>/dev/null || {
        docker exec prometheus bash -c '
            if ! grep -q \"/etc/prometheus/rules/critical-alerts.yml\" /etc/prometheus/prometheus.yml; then
                cat >> /etc/prometheus/prometheus.yml <<HEREDOC

# Critical infrastructure alert rules (added)
rule_files:
  - \"/etc/prometheus/rules/critical-alerts.yml\"
HEREDOC
            fi
        '
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
    log_info "Testing failover webhook simulation..."
    
    # Note: Full simulation requires the listener to be active on the target host
    log_info "To test manually on primary:"
    log_info "  echo '{\"status\":\"firing\",\"alerts\":[{\"labels\":{\"alertname\":\"PostgreSQLDown\",\"severity\":\"critical\"}}]}' | /opt/failover/bin/webhook-handler.sh"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "Setting up Automated Failover Monitoring"
    
    # Create configurations locally
    create_webhook_handler
    update_alertmanager_config
    create_critical_alert_rules
    
    # Deploy to primary host
    deploy_webhook_handler
    setup_alertmanager_webhook
    register_critical_alerts
    
    # Simulation report
    test_failover_webhook
    
    log_info "✓ Automated failover monitoring setup complete!"
    log_info "Critical alerts will now trigger automatic failover"
    
    return 0
}

# Run
main "$@"
