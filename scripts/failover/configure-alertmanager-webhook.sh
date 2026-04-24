#!/usr/bin/env bash
# @file        scripts/failover/configure-alertmanager-webhook.sh
# @module      operations/failover
# @description Configure AlertManager to send alerts to webhook receiver
# @owner       Infrastructure Team
# @status      Production ready - April 23, 2026
#
# Generates AlertManager configuration with webhook integration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
WEBHOOK_HOST="${WEBHOOK_HOST:-localhost}"
WEBHOOK_PORT="${WEBHOOK_PORT:-9099}"
ALERTMANAGER_CONFIG="${PROJECT_DIR}/alertmanager.yml"
BACKUP_CONFIG="${ALERTMANAGER_CONFIG}.backup.$(date +%s)"

echo "Generating AlertManager webhook configuration..."

# Backup existing config
if [[ -f "$ALERTMANAGER_CONFIG" ]]; then
    cp "$ALERTMANAGER_CONFIG" "$BACKUP_CONFIG"
    echo "✓ Backup saved to: $BACKUP_CONFIG"
fi

# Generate updated configuration with webhook receiver
cat > "$ALERTMANAGER_CONFIG" << 'EOF'
global:
  resolve_timeout: 5m
  slack_api_url: '' # Optional: set to enable Slack notifications
  pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'

route:
  receiver: 'default-receiver'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 30s
  repeat_interval: 24h
  
  routes:
    # Critical failures → webhook receiver for automatic failover
    - match:
        severity: critical
      receiver: 'failover-webhook'
      continue: true
      group_wait: 5s
      group_interval: 10s
      repeat_interval: 12h
    
    # Warnings → default receiver with webhook
    - match:
        severity: warning
      receiver: 'default-receiver'
      continue: true
    
    # Info and below → default receiver
    - match:
        severity: info
      receiver: 'default-receiver'

receivers:
  - name: 'default-receiver'
    # Slack notifications (if configured)
    slack_configs:
      - channel: '#alerts'
        title: 'Alert: {{ .GroupLabels.alertname }}'
        text: 'Service: {{ .GroupLabels.service }}'
        send_resolved: true

  - name: 'failover-webhook'
    # Webhook for automatic failover response
    webhook_configs:
      - url: 'http://{{ WEBHOOK_HOST }}:{{ WEBHOOK_PORT }}/webhook'
        send_resolved: true
        http_sd_configs: []

inhibit_rules:
  # Don't alert if critical is firing
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'service']
  
  # Don't alert if warning is firing
  - source_match:
      severity: 'warning'
    target_match:
      severity: 'info'
    equal: ['alertname', 'service']
EOF

# Replace placeholders
sed -i "s|{{ WEBHOOK_HOST }}|$WEBHOOK_HOST|g" "$ALERTMANAGER_CONFIG"
sed -i "s|{{ WEBHOOK_PORT }}|$WEBHOOK_PORT|g" "$ALERTMANAGER_CONFIG"

echo "✓ AlertManager configuration generated: $ALERTMANAGER_CONFIG"
echo ""
echo "Configuration includes:"
echo "  ✓ Critical alerts routed to webhook receiver"
echo "  ✓ Warning alerts routed to default receiver"
echo "  ✓ Webhook URL: http://$WEBHOOK_HOST:$WEBHOOK_PORT/webhook"
echo ""
echo "To apply changes:"
echo "  docker-compose restart alertmanager"
