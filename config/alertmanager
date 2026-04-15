# ==============================================================================
# alertmanager.tpl - Terraform Template for AlertManager Configuration
# Consolidated from: alertmanager-base.yml + alertmanager.yml + alertmanager-production.yml
# This template is processed by Terraform to generate config/alertmanager.yml
# Version: 2.0 (SSOT Template - April 15, 2026)
# ==============================================================================

# ==============================================================================
# GLOBAL CONFIGURATION
# ==============================================================================

global:
  resolve_timeout: 5m
  
  # Slack integration (optional - configure via environment)
  slack_api_url: '${ALERTMANAGER_SLACK_WEBHOOK:}'
  
  # PagerDuty integration (optional - configure via environment)
  pagerduty_url: '${ALERTMANAGER_PAGERDUTY_URL:}'
  
  # Hipchat integration (optional - configure via environment)
  hipchat_api_url: '${ALERTMANAGER_HIPCHAT_URL:}'
  hipchat_auth_token: '${ALERTMANAGER_HIPCHAT_TOKEN:}'

# ==============================================================================
# ALERT ROUTING RULES (Priority-Based)
# ==============================================================================

route:
  # Root route configuration
  receiver: 'default-null'
  group_by: ['alertname', 'cluster', 'service', 'severity']
  
  # Timing (varies by environment)
  group_wait: ${alert_group_wait}          # 10s (dev) | 30s (prod)
  group_interval: ${alert_group_interval}  # 10s (dev) | 5m (prod)
  repeat_interval: ${alert_repeat_interval}# 12h (all)

  routes:
    # =========================================================================
    # CRITICAL ALERTS (P0) - Immediate escalation
    # =========================================================================
    - match:
        severity: critical
      receiver: 'critical-team'
      group_wait: 0s              # Send immediately
      group_interval: 5m
      repeat_interval: 1h         # Repeat hourly
      continue: true
      
      # Critical sub-routes
      routes:
        # Production down
        - match:
            alertname: 'ServiceDown'
          receiver: 'pagerduty-critical'
          group_wait: 0s
          repeat_interval: 30m

        # Database issues
        - match:
            alertname: 'PostgreSQLDown|RedisDown|DatabaseError'
          receiver: 'pagerduty-critical'
          group_wait: 0s
          repeat_interval: 30m

    # =========================================================================
    # HIGH ALERTS (P1) - Urgent attention
    # =========================================================================
    - match:
        severity: high
      receiver: 'high-team'
      group_wait: 30s
      group_interval: 10m
      repeat_interval: 4h
      continue: true

    # =========================================================================
    # MEDIUM ALERTS (P2) - Standard timeline
    # =========================================================================
    - match:
        severity: medium
      receiver: 'medium-team'
      group_wait: 5m
      group_interval: 15m
      repeat_interval: 8h
      continue: true

    # =========================================================================
    # LOW ALERTS (P3) - Batch/daily
    # =========================================================================
    - match:
        severity: low
      receiver: 'low-team'
      group_wait: 1h
      group_interval: 4h
      repeat_interval: 24h
      continue: true

# ==============================================================================
# RECEIVERS (Notification Targets)
# ==============================================================================

receivers:
  # Default receiver (null - no notifications)
  - name: 'default-null'
    # Null receiver: alerts stored but not forwarded anywhere

  # ========================================================================
  # CRITICAL ALERT RECEIVERS
  # ========================================================================
  - name: 'critical-team'
    # Sends to multiple channels (continued below)
    slack_configs:
      - api_url: '${ALERTMANAGER_SLACK_WEBHOOK}'
        channel: '${ALERTMANAGER_SLACK_CRITICAL_CHANNEL:#critical-alerts}'
        title: 'Critical Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        send_resolved: true
        color: 'danger'
    pagerduty_configs:
      - service_key: '${ALERTMANAGER_PAGERDUTY_SERVICE_KEY:}'
        description: '{{ .GroupLabels.alertname }} ({{ .GroupLabels.severity }})'
        details:
          firing: '{{ range .Alerts.Firing }}{{ .Labels.instance }}{{ end }}'

  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: '${ALERTMANAGER_PAGERDUTY_SERVICE_KEY:}'
        description: 'CRITICAL: {{ .GroupLabels.alertname }}'
        client: 'AlertManager (on-prem 192.168.168.31)'

  # ========================================================================
  # HIGH ALERT RECEIVERS
  # ========================================================================
  - name: 'high-team'
    slack_configs:
      - api_url: '${ALERTMANAGER_SLACK_WEBHOOK}'
        channel: '${ALERTMANAGER_SLACK_HIGH_CHANNEL:#alerts-high}'
        title: 'High Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  # ========================================================================
  # MEDIUM ALERT RECEIVERS
  # ========================================================================
  - name: 'medium-team'
    slack_configs:
      - api_url: '${ALERTMANAGER_SLACK_WEBHOOK}'
        channel: '${ALERTMANAGER_SLACK_MEDIUM_CHANNEL:#alerts}'
        title: 'Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  # ========================================================================
  # LOW ALERT RECEIVERS (Digest)
  # ========================================================================
  - name: 'low-team'
    slack_configs:
      - api_url: '${ALERTMANAGER_SLACK_WEBHOOK}'
        channel: '${ALERTMANAGER_SLACK_LOW_CHANNEL:#alerts-digest}'
        title: 'Daily Digest: {{ len .Alerts }} alerts'
        text: '{{ range .Alerts }}• {{ .Labels.alertname }}\n{{ end }}'
        send_resolved: false

# ==============================================================================
# ALERT DEDUPLICATION & SUPPRESSION
# ==============================================================================

inhibit_rules:
  # Suppress warnings if critical is firing
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: ['alertname', 'cluster', 'service']

  # Suppress high if critical is firing
  - source_match:
      severity: critical
    target_match:
      severity: high
    equal: ['alertname', 'service']

  # Suppress medium if high is firing
  - source_match:
      severity: high
    target_match:
      severity: medium
    equal: ['alertname', 'service']

  # Suppress low if medium+ is firing
  - source_match:
      severity: medium
    target_match:
      severity: low
    equal: ['alertname', 'service']

  # Suppress all if service is down
  - source_match:
      alertname: 'ServiceDown'
    target_match_re:
      alertname: '.*'
    equal: ['service', 'cluster']

  # Suppress memory alerts if host is down
  - source_match:
      alertname: 'HostDown'
    target_match_re:
      alertname: 'Memory.*|CPU.*|Disk.*'
    equal: ['instance']

# ==============================================================================
# TEMPLATES
# ==============================================================================

templates:
  - '/etc/alertmanager/templates/*.tmpl'
  - '/etc/alertmanager/slack-messages.tmpl'
  - '/etc/alertmanager/pagerduty-messages.tmpl'
  - '/etc/alertmanager/email-messages.tmpl'

# ==============================================================================
# END OF ALERTMANAGER TEMPLATE
# ==============================================================================
# Terraform substitutes these variables at apply time:
# - alert_group_wait: 10s (dev) | 30s (prod)
# - alert_group_interval: 10s (dev) | 5m (prod)
# - alert_repeat_interval: 12h (all environments)
#
# Consolidates:
# - alertmanager-base.yml (routing structure)
# - alertmanager.yml (default config)
# - alertmanager-production.yml (receivers + enterprise integration)
# ==============================================================================
