# ==============================================================================
# alertmanager.tpl - Terraform Template for AlertManager Configuration
# CONSOLIDATED from: alertmanager-base.yml + alertmanager.default.yml + alertmanager-production.yml
# This template is processed by Terraform to generate config/alertmanager.yml
# Version: 2.0 (SSOT Consolidated Template)
# ==============================================================================

global:
  resolve_timeout: 5m
  slack_api_url: '${alertmanager_slack_webhook}'
  pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'

# ==============================================================================
# ROUTING RULES - Severity-Based Alert Distribution (Base + Production Merged)
# ==============================================================================

templates:
  - '/etc/alertmanager/templates/*.tmpl'

route:
  receiver: '${default_receiver}'
  group_by: ['alertname', 'cluster', 'service', 'environment', 'severity']
  group_wait: ${group_wait_default}s
  group_interval: ${group_interval_default}m
  repeat_interval: ${repeat_interval_default}h

  routes:
    # CRITICAL ALERTS (P1) - Immediate Page to On-Call
    - match:
        severity: critical
      receiver: 'pagerduty-critical'
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 1h
      continue: true

    # HIGH SEVERITY (P2) - Urgent Response
    - match:
        severity: high
      receiver: 'slack-incidents'
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      continue: true

    # MEDIUM SEVERITY (P3) - Standard Response
    - match:
        severity: medium
      receiver: 'slack-warnings'
      group_wait: 5m
      group_interval: 10m
      repeat_interval: 12h
      continue: true

    # LOW SEVERITY (P4) - Daily Digest
    - match:
        severity: low
      receiver: 'email-digest'
      group_wait: 1h
      group_interval: 1h
      repeat_interval: 24h
      continue: false

    # Info/Debug alerts - Silenced (null receiver)
    - match:
        severity: info
      receiver: 'null'
      continue: false

# ==============================================================================
# ALERT DEDUPLICATION & SUPPRESSION RULES (Base + Production Merged)
# ==============================================================================

inhibit_rules:
  # Suppress warning/high/medium if critical is already firing for same service
  - source_match:
      severity: critical
    target_match_re:
      severity: 'warning|high|medium'
    equal: ['alertname', 'cluster', 'service']

  # Suppress low if medium/high is firing for same service
  - source_match_re:
      severity: 'medium|high'
    target_match:
      severity: low
    equal: ['alertname', 'service']

  # If cluster is down, suppress node-level alerts
  - source_match:
      severity: critical
      alertname: ClusterDown
    target_match_re:
      severity: 'warning|high|medium'
    equal: ['cluster']

  # If service is down, suppress endpoint/performance alerts
  - source_match:
      severity: critical
      alertname: ServiceDown
    target_match_re:
      severity: 'warning|high|medium'
      alertname: 'ServiceLatency|ServiceMemory|ServiceCPU|ServiceDiskUsage|HighErrorRate'
    equal: ['service', 'instance']

  # Suppress duplicate alerts from cascading failures
  - source_match:
      alertname: ServiceDown
    target_match:
      alertname: ServiceUnavailable
    equal: ['service']

# ==============================================================================
# RECEIVERS - Alert Notification Channels (All Variants Consolidated)
# ==============================================================================

receivers:
  # Null receiver - silences alerts
  - name: null

  # Critical alerts (P1) - PagerDuty + Slack
  - name: pagerduty-critical
    slack_configs:
      - api_url: '${alertmanager_slack_webhook}'
        channel: '${slack_channel_critical}'
        title: '🚨 CRITICAL: {{ .GroupLabels.alertname }}'
        text: |
          {{ range .Alerts.Firing }}
          *Alert:* {{ .Labels.alertname }}
          *Severity:* {{ .Labels.severity }}
          *Instance:* {{ .Labels.instance }}
          *Summary:* {{ .Annotations.summary }}
          {{ end }}
        color: 'danger'
        send_resolved: true
        actions:
          - type: button
            text: 'View Dashboard'
            url: '{{ .CommonAnnotations.dashboard_url }}'
          - type: button
            text: 'View Runbook'
            url: '{{ .CommonAnnotations.runbook_url }}'
    
    pagerduty_configs:
      - service_key: '${pagerduty_service_key}'
        description: '{{ .GroupLabels.alertname }} on {{ .GroupLabels.instance }}'
        details:
          firing: '{{ range .Alerts.Firing }}{{ .Labels.instance }} ({{ .Labels.severity }}) {{ end }}'
          resolved: '{{ range .Alerts.Resolved }}{{ .Labels.instance }} {{ end }}'
          summary: '{{ .CommonAnnotations.summary }}'
          runbook: '{{ .CommonAnnotations.runbook_url }}'

  # High severity (P2) - Slack incidents channel
  - name: slack-incidents
    slack_configs:
      - api_url: '${alertmanager_slack_webhook}'
        channel: '${slack_channel_incidents}'
        title: '⚠️  HIGH: {{ .GroupLabels.alertname }}'
        text: |
          {{ range .Alerts.Firing }}
          *Alert:* {{ .Labels.alertname }}
          *Instance:* {{ .Labels.instance }}
          *Summary:* {{ .Annotations.summary }}
          {{ end }}
        color: 'warning'
        send_resolved: true

  # Medium severity (P3) - Slack warnings channel
  - name: slack-warnings
    slack_configs:
      - api_url: '${alertmanager_slack_webhook}'
        channel: '${slack_channel_warnings}'
        title: 'MEDIUM: {{ .GroupLabels.alertname }}'
        text: |
          {{ range .Alerts.Firing }}
          {{ .Labels.alertname }} on {{ .Labels.instance }}
          {{ end }}
        color: '#439FE0'
        send_resolved: true

  # Low severity (P4) - Email daily digest
  - name: email-digest
    email_configs:
      - to: '${email_recipient_low}'
        from: 'alertmanager@kushnir.cloud'
        smarthost: '${email_smtp_host}:${email_smtp_port}'
        auth_username: '${email_smtp_user}'
        auth_password: '${email_smtp_password}'
        headers:
          Subject: 'Low Priority Alerts - Daily Digest'
        html: |
          <html>
            <body>
              <h2>Low Priority Alerts - Daily Digest</h2>
              {{ range .Alerts }}
                <p><strong>{{ .Labels.alertname }}</strong></p>
                <p>Instance: {{ .Labels.instance }}</p>
                <p>{{ .Annotations.summary }}</p>
              {{ end }}
            </body>
          </html>
        send_resolved: true

  # Default fallback receiver
  - name: '${default_receiver}'
    slack_configs:
      - api_url: '${alertmanager_slack_webhook}'
        channel: '${slack_channel_default}'
        title: 'Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
        send_resolved: true

# ==============================================================================
# TERRAFORM VARIABLES FOR TEMPLATE SUBSTITUTION
# ==============================================================================
# This template is processed by Terraform with the following variables:
#
# Required:
#   - alertmanager_slack_webhook: Slack webhook URL (from Vault)
#   - pagerduty_service_key: PagerDuty integration key (from Vault/GSM)
#   - slack_channel_critical: Critical alerts channel (e.g., #critical-alerts)
#   - slack_channel_incidents: High severity channel (e.g., #incidents)
#   - slack_channel_warnings: Medium severity channel (e.g., #warnings)
#   - slack_channel_default: Default fallback channel (e.g., #alerts)
#   - email_recipient_low: Email address for low-severity digest
#   - email_smtp_host: SMTP server hostname
#   - email_smtp_port: SMTP server port (25, 465, 587)
#   - email_smtp_user: SMTP authentication username
#   - email_smtp_password: SMTP authentication password (from Vault)
#
# Optional (Defaults Provided):
#   - default_receiver: Default fallback receiver (default: "slack-incidents")
#   - group_wait_default: Initial grouping wait time in seconds (prod: 10, dev: 30)
#   - group_interval_default: Grouping interval in minutes (prod: 5, dev: 10)
#   - repeat_interval_default: Repeat notification interval in hours (prod: 4, dev: 1)
#
# Usage:
#   terraform apply -var-file=terraform.dev.tfvars
#   terraform apply -var-file=terraform.prod.tfvars
#   Generates: config/alertmanager.yml
#
# Consolidation Source:
#   ✅ alertmanager-base.yml (routing, inhibit_rules, shared structure)
#   ✅ alertmanager.default.yml (Slack multi-channel receivers)
#   ✅ alertmanager-production.yml (PagerDuty + email integration)
# ==============================================================================
