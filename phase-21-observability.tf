# ════════════════════════════════════════════════════════════════════════════
# PHASE 21: OPERATIONAL EXCELLENCE & OBSERVABILITY
# Date: April 14, 2026
# Purpose: Deploy production-grade monitoring, observability, incident response
# Status: PRODUCTION - Ready for immediate execution
# ════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 21: OBSERVABILITY & OPERATIONAL EXCELLENCE
# ─────────────────────────────────────────────────────────────────────────────

variable "phase_21_enabled" {
  description = "Enable Phase 21 Observability & Operational Excellence"
  type        = bool
  default     = true
}

variable "prometheus_enabled" {
  description = "Deploy Prometheus metrics collector"
  type        = bool
  default     = true
}

variable "grafana_enabled" {
  description = "Deploy Grafana visualization & dashboards"
  type        = bool
  default     = true
}

variable "alertmanager_enabled" {
  description = "Deploy AlertManager for incident triggering"
  type        = bool
  default     = true
}

variable "slo_targets" {
  description = "SLO targets for observability"
  type = object({
    availability_target_percent      = number  # 99.9% = 9 hours downtime/year
    latency_p99_target_ms           = number  # <100ms
    error_rate_target_percent       = number  # <0.1%
    apdex_threshold_ms              = number  # Application Performance Index threshold
  })
  default = {
    availability_target_percent      = 99.9
    latency_p99_target_ms           = 100
    error_rate_target_percent       = 0.1
    apdex_threshold_ms              = 50
  }
}

variable "alert_channels" {
  description = "Alert notification channels"
  type = object({
    slack_webhook_url          = string  # Slack #incidents channel
    pagerduty_integration_key  = string  # PagerDuty on-call escalation
    email_alerts               = list(string)
  })
  default = {
    slack_webhook_url          = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
    pagerduty_integration_key  = "YOUR_PAGERDUTY_KEY"
    email_alerts               = ["devops@example.com"]
  }
  sensitive = true
}

# ─────────────────────────────────────────────────────────────────────────────
# PROMETHEUS DOCKER IMAGE & CONTAINER
# ─────────────────────────────────────────────────────────────────────────────

resource "docker_image" "prometheus" {
  count         = var.phase_21_enabled && var.prometheus_enabled ? 1 : 0
  name          = "prom/prometheus"
  pull_triggers = ["v2.48.0"]
}

resource "docker_container" "prometheus" {
  count         = var.phase_21_enabled && var.prometheus_enabled ? 1 : 0
  name          = "prometheus-operator"
  image         = "prom/prometheus:v2.48.0"

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=90d",
    "--web.console.libraries=/usr/share/prometheus/console_libraries",
    "--web.console.templates=/usr/share/prometheus/consoles",
    "--web.enable-lifecycle",
  ]

  ports {
    internal = 9090
    external = 9090
    protocol = "tcp"
  }

  volumes {
    host_path      = "/home/akushnir/.config/prometheus"
    container_path = "/etc/prometheus"
    read_only      = false
  }

  volumes {
    host_path      = "/home/akushnir/.docker-volumes/prometheus"
    container_path = "/prometheus"
    read_only      = false
  }

  healthcheck {
    test         = ["CMD", "wget", "-q", "--spider", "http://localhost:9090/-/healthy"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }

  depends_on = [docker_image.prometheus]

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# GRAFANA DOCKER IMAGE & CONTAINER
# ─────────────────────────────────────────────────────────────────────────────

resource "docker_image" "grafana" {
  count         = var.phase_21_enabled && var.grafana_enabled ? 1 : 0
  name          = "grafana/grafana"
  pull_triggers = ["10.2.3"]
}

resource "docker_container" "grafana" {
  count         = var.phase_21_enabled && var.grafana_enabled ? 1 : 0
  name          = "grafana-dashboards"
  image         = "grafana/grafana:10.2.3"

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=admin123",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_INSTALL_PLUGINS=piechart",
    "GF_SECURITY_COOKIE_SECURE=true",
    "GF_SECURITY_COOKIE_HTTPONLY=true",
  ]

  ports {
    internal = 3000
    external = 3000
    protocol = "tcp"
  }

  volumes {
    host_path      = "/home/akushnir/.docker-volumes/grafana"
    container_path = "/var/lib/grafana"
    read_only      = false
  }

  volumes {
    host_path      = "/etc/grafana/provisioning"
    container_path = "/etc/grafana/provisioning"
    read_only      = true
  }

  healthcheck {
    test         = ["CMD", "wget", "-q", "--spider", "http://localhost:3000/api/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }

  depends_on = [
    docker_image.grafana,
    docker_container.prometheus,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ALERTMANAGER FOR INCIDENT TRIGGERING
# ─────────────────────────────────────────────────────────────────────────────

resource "docker_image" "alertmanager" {
  count         = var.phase_21_enabled && var.alertmanager_enabled ? 1 : 0
  name          = "prom/alertmanager"
  pull_triggers = ["v0.26.0"]
}

resource "docker_container" "alertmanager" {
  count         = var.phase_21_enabled && var.alertmanager_enabled ? 1 : 0
  name          = "alertmanager-incidents"
  image         = "prom/alertmanager:v0.26.0"

  command = [
    "--config.file=/etc/alertmanager/config.yml",
    "--storage.path=/alertmanager",
    "--log.level=info",
  ]

  ports {
    internal = 9093
    external = 9093
    protocol = "tcp"
  }

  volumes {
    host_path      = "/home/akushnir/.config/alertmanager"
    container_path = "/etc/alertmanager"
    read_only      = true
  }

  volumes {
    host_path      = "/home/akushnir/.docker-volumes/alertmanager"
    container_path = "/alertmanager"
    read_only      = false
  }

  # healthcheck disabled due to terraform docker provider issues
  # test         = ["CMD", "wget", "-q", "--spider", "http://localhost:9093"]

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# PROMETHEUS CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

locals {
  prometheus_config = yamlencode({
    global = {
      scrape_interval      = "15s"
      scrape_timeout       = "10s"
      evaluation_interval  = "15s"
      external_labels = {
        cluster = "production"
        env     = "prod"
      }
    }

    alerting = {
      alertmanagers = [
        {
          static_configs = [
            {
              targets = ["localhost:9093"]
            }
          ]
        }
      ]
    }

    rule_files = [
      "/etc/prometheus/rules/*.yml"
    ]

    scrape_configs = [
      {
        job_name = "prometheus"
        metrics_path = "/metrics"
        static_configs = [
          {
            targets = ["localhost:9090"]
          }
        ]
      },
      {
        job_name = "postgres"
        static_configs = [
          {
            targets = ["localhost:9187"]
          }
        ]
      },
      {
        job_name = "caddy"
        static_configs = [
          {
            targets = ["localhost:2019"]
          }
        ]
      },
      {
        job_name = "node"
        static_configs = [
          {
            targets = ["localhost:9100"]
          }
        ]
      },
    ]
  })
}

resource "local_file" "prometheus_config" {
  count           = var.phase_21_enabled && var.prometheus_enabled ? 1 : 0
  filename        = "/etc/prometheus/prometheus.yml"
  content         = local.prometheus_config
  file_permission = "0644"
  depends_on      = [docker_image.prometheus]
}

# ─────────────────────────────────────────────────────────────────────────────
# PROMETHEUS ALERT RULES
# ─────────────────────────────────────────────────────────────────────────────

locals {
  alert_rules = {
    "database-failover" = {
      alert = "DatabaseFailoverDetected"
      expr  = "pg_replication_lag_seconds > 60"
      for   = "1m"
      annotations = {
        summary     = "PostgreSQL replication lag critical"
        description = "Replication lag {{ $value }}s - failover may be triggered"
      }
      labels = {
        severity = "critical"
        page     = "true"
      }
    },
    "latency-spike" = {
      alert = "LatencySpike"
      expr  = "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 0.2"
      for   = "5m"
      annotations = {
        summary     = "High latency detected"
        description = "p99 latency {{ $value }}s (target: <0.1s)"
      }
      labels = {
        severity = "high"
        page     = "false"
      }
    },
    "error-rate-high" = {
      alert = "ErrorRateHigh"
      expr  = "rate(http_requests_total{status=~'5..'}[5m]) > 0.001"
      for   = "5m"
      annotations = {
        summary     = "Error rate above threshold"
        description = "Error rate {{ $value }} (target: <0.1%)"
      }
      labels = {
        severity = "medium"
        page     = "false"
      }
    },
  }
}

resource "local_file" "alert_rules" {
  count           = var.phase_21_enabled && var.prometheus_enabled ? 1 : 0
  filename        = "/etc/prometheus/rules/alerts.yml"
  content         = yamlencode({ groups = [{ name = "alerts", rules = [for k, v in local.alert_rules : v] }] })
  file_permission = "0644"
  depends_on      = [docker_image.prometheus]
}

# ─────────────────────────────────────────────────────────────────────────────
# ALERTMANAGER CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

locals {
  alertmanager_config = yamlencode({
    global = {
      resolve_timeout = "5m"
    }

    route = {
      group_by       = ["alertname", "cluster", "service"]
      group_wait     = "30s"
      group_interval = "5m"
      repeat_interval = "1h"
      receiver        = "default"
      routes = [
        {
          match = {
            page = "true"
          }
          receiver = "pagerduty"
          continue = true
        }
      ]
    }

    receivers = [
      {
        name = "default"
        slack_configs = [
          {
            api_url = var.alert_channels.slack_webhook_url
            channel = "#incidents"
            title   = "{{ .AlertGroupLabels.alertname }}"
            text    = "{{ range .Alerts }}{{ .Annotations.description }}\n{{ end }}"
          }
        ]
      },
    ]
  })
}

resource "local_file" "alertmanager_config" {
  count           = var.phase_21_enabled && var.alertmanager_enabled ? 1 : 0
  filename        = "/etc/alertmanager/config.yml"
  content         = local.alertmanager_config
  file_permission = "0644"
  depends_on      = [docker_image.alertmanager]
}

# ─────────────────────────────────────────────────────────────────────────────
# SLO & ERROR BUDGET TRACKING
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "slo_definitions" {
  count   = var.phase_21_enabled ? 1 : 0
  filename = "/etc/prometheus/slo-definitions.yml"
  content = yamlencode({
    slos = {
      availability = {
        target        = var.slo_targets.availability_target_percent
        error_budget  = 100 - var.slo_targets.availability_target_percent
        measurement   = "uptime_percent"
        description   = "System availability (9 hours downtime allowed per year)"
      },
      latency = {
        target        = var.slo_targets.latency_p99_target_ms
        measurement   = "http_request_duration_seconds_bucket{le=\"${var.slo_targets.latency_p99_target_ms / 1000}\"}"
        percentile    = 99
        description   = "99th percentile latency < 100ms"
      },
      error_rate = {
        target        = var.slo_targets.error_rate_target_percent
        error_budget  = var.slo_targets.error_rate_target_percent
        measurement   = "http_requests_total{status=~'5..'}"
        description   = "Error rate < 0.1% (99.9% success rate)"
      },
    }
  })
  file_permission = "0644"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 21 STATUS OUTPUT
# ─────────────────────────────────────────────────────────────────────────────

output "phase_21_observability_status" {
  description = "Phase 21 Observability deployment status"
  value = {
    prometheus_enabled  = var.phase_21_enabled && var.prometheus_enabled
    grafana_enabled     = var.phase_21_enabled && var.grafana_enabled
    alertmanager_enabled = var.phase_21_enabled && var.alertmanager_enabled
    prometheus_url     = "http://localhost:9090"
    grafana_url        = "http://localhost:3000"
    alertmanager_url   = "http://localhost:9093"
    slo_targets        = var.slo_targets
    deployment_timestamp = timestamp()
  }
}
