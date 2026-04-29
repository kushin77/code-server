#!/bin/bash
# Alertmanager Configuration Setup
# Configure alert routing and notifications

set -e
trap 'echo "❌ Alertmanager setup failed"; exit 1' ERR

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Alertmanager Configuration                                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

CONFIG_DIR="${CONFIG_DIR:-/etc/alertmanager}"
CONFIG_FILE="$CONFIG_DIR/alertmanager.yml"

mkdir -p "$CONFIG_DIR"

echo "Creating Alertmanager configuration..."
echo "  Directory: $CONFIG_DIR"
echo "  File: $CONFIG_FILE"
echo ""

# Create alertmanager configuration
cat > "$CONFIG_FILE" << 'ALERTMANAGER_CONFIG'
global:
  resolve_timeout: 5m
  slack_api_url: '${SLACK_WEBHOOK_URL}'
  pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'

templates:
  - '/etc/alertmanager/templates/*.tmpl'

route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h

  routes:
    # Critical alerts - immediate notification
    - match:
        severity: critical
      receiver: 'critical-group'
      continue: true
      group_wait: 0s
      group_interval: 5m
      repeat_interval: 1h

    # Infrastructure critical - page on-call
    - match:
        severity: critical
        component: infrastructure
      receiver: 'pagerduty-infra'
      continue: true
      group_wait: 0s
      group_interval: 5m

    # Database critical - immediate email
    - match:
        severity: critical
        component: database
      receiver: 'email-critical'
      continue: true

    # Warning alerts - batched notification
    - match:
        severity: warning
      receiver: 'warning-group'
      group_wait: 30s
      group_interval: 15m
      repeat_interval: 24h

receivers:
  - name: 'default'
    email_configs:
      - to: 'ops@kushnir.cloud'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'alerts@kushnir.cloud'
        auth_password: '${SMTP_PASSWORD}'
        from: 'alerts@kushnir.cloud'

  - name: 'critical-group'
    email_configs:
      - to: 'ops@kushnir.cloud,incident@kushnir.cloud'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'alerts@kushnir.cloud'
        auth_password: '${SMTP_PASSWORD}'
        from: 'alerts@kushnir.cloud'
        headers:
          Subject: '🚨 CRITICAL ALERT: {{ .GroupLabels.alertname }}'
        html: |
          <h2>{{ .GroupLabels.alertname }}</h2>
          <p><strong>Component:</strong> {{ .GroupLabels.component }}</p>
          <p><strong>Severity:</strong> CRITICAL</p>
          <hr/>
          {{ range .Alerts.Firing }}
            <h4>{{ .Labels.instance }}</h4>
            <p>{{ .Annotations.description }}</p>
          {{ end }}
    slack_configs:
      - channel: '#critical-alerts'
        title: '🚨 CRITICAL: {{ .GroupLabels.alertname }}'
        text: |
          Component: {{ .GroupLabels.component }}
          {{ range .Alerts.Firing -}}
          • {{ .Labels.instance }}: {{ .Annotations.summary }}
          {{ end }}
        actions:
          - type: button
            text: 'View in Grafana'
            url: 'https://grafana.kushnir.cloud'
          - type: button
            text: 'View in Prometheus'
            url: 'https://prometheus.kushnir.cloud'

  - name: 'pagerduty-infra'
    pagerduty_configs:
      - service_key: '${PAGERDUTY_SERVICE_KEY}'
        description: '{{ .GroupLabels.alertname }} on {{ .Alerts.Firing | len }} hosts'
        details:
          firing: '{{ template "pagerduty.default.instances" .Alerts.Firing }}'

  - name: 'email-critical'
    email_configs:
      - to: 'dba@kushnir.cloud,ops@kushnir.cloud'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'alerts@kushnir.cloud'
        auth_password: '${SMTP_PASSWORD}'
        from: 'alerts@kushnir.cloud'
        headers:
          Subject: '🚨 DATABASE ALERT: {{ .GroupLabels.alertname }}'

  - name: 'warning-group'
    email_configs:
      - to: 'ops@kushnir.cloud'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'alerts@kushnir.cloud'
        auth_password: '${SMTP_PASSWORD}'
        from: 'alerts@kushnir.cloud'
        headers:
          Subject: '⚠️ WARNING: {{ .GroupLabels.alertname }}'
    slack_configs:
      - channel: '#platform-alerts'
        title: '⚠️ {{ .GroupLabels.alertname }}'
        text: |
          {{ range .Alerts.Firing -}}
          • {{ .Labels.instance }}: {{ .Annotations.summary }}
          {{ end }}

inhibit_rules:
  # Inhibit warning if critical exists
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']

  # Inhibit if host is down
  - source_match:
      alertname: 'HostDown'
    target_match_re:
      alertname: '.+'
    equal: ['instance']
ALERTMANAGER_CONFIG

echo "✅ Alertmanager configuration created"
echo ""

# Create notification templates
TEMPLATES_DIR="$CONFIG_DIR/templates"
mkdir -p "$TEMPLATES_DIR"

cat > "$TEMPLATES_DIR/email.tmpl" << 'EMAIL_TEMPLATE'
{{ define "email.default.subject" -}}
[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{end}}] {{ .GroupLabels.alertname }} on {{ if gt (len .GroupLabels) 1 }}{{ delimit (label_names .GroupLabels) ", " }}{{ else }}{{ range .GroupLabels.SortedPairs }}{{ .Value }}{{ end }}{{ end }}
{{- end }}

{{ define "email.default.html" -}}
<html>
<head></head>
<body>
  <h2>{{ .GroupLabels.alertname }}</h2>
  <p><strong>Status:</strong> {{ .Status | toUpper }}</p>
  <p><strong>Component:</strong> {{ .GroupLabels.component }}</p>
  <hr/>
  
  {{ if .Alerts.Firing }}
  <h3>Firing Alerts ({{ .Alerts.Firing | len }})</h3>
  <ul>
  {{ range .Alerts.Firing }}
    <li>
      <strong>{{ .Labels.instance }}</strong><br/>
      {{ .Annotations.summary }}<br/>
      <em>{{ .Annotations.description }}</em>
    </li>
  {{ end }}
  </ul>
  {{ end }}
  
  {{ if .Alerts.Resolved }}
  <h3>Resolved Alerts ({{ .Alerts.Resolved | len }})</h3>
  <ul>
  {{ range .Alerts.Resolved }}
    <li><strong>{{ .Labels.instance }}</strong> - {{ .Annotations.summary }}</li>
  {{ end }}
  </ul>
  {{ end }}
</body>
</html>
{{- end }}
EMAIL_TEMPLATE

echo "✅ Email templates created"
echo ""

# Create environment file template
cat > /tmp/alertmanager.env.template << 'ENV_TEMPLATE'
# Alertmanager Environment Variables
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
SMTP_PASSWORD="your-app-specific-password"
PAGERDUTY_SERVICE_KEY="your-pagerduty-integration-key"
ENV_TEMPLATE

echo "Configuration Template Files:"
echo "  - $CONFIG_FILE"
echo "  - $TEMPLATES_DIR/email.tmpl"
echo "  - /tmp/alertmanager.env.template (template)"
echo ""

echo "Docker Compose Entry:"
cat << 'COMPOSE_ENTRY'

  alertmanager:
    image: prom/alertmanager:latest
    ports:
      - "9093:9093"
    volumes:
      - /etc/alertmanager:/etc/alertmanager
      - alertmanager-storage:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    env_file:
      - .env.alertmanager

volumes:
  alertmanager-storage:
COMPOSE_ENTRY

echo ""
echo "Setup Instructions:"
echo "  1. Set environment variables:"
echo "     export SLACK_WEBHOOK_URL='...'"
echo "     export SMTP_PASSWORD='...'"
echo "     export PAGERDUTY_SERVICE_KEY='...'"
echo ""
echo "  2. Create .env.alertmanager file"
echo ""
echo "  3. Start Alertmanager:"
echo "     docker-compose up -d alertmanager"
echo ""
echo "  4. Test webhook:"
echo "     curl -X POST http://localhost:9093/api/v1/alerts \\..."
echo ""
echo "✅ Alertmanager configuration complete"
echo ""
