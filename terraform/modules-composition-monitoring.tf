# Terraform Module: Monitoring Stack (Prometheus, Grafana, AlertManager, Loki, Jaeger)
# Module Version: 1.0.0 | Last Updated: 2026-04-22

module "monitoring" {
  source = "./modules/monitoring"

  # General configuration
  environment     = var.environment
  deployment_host = var.deployment_host
  domain          = var.domain
  namespace       = "monitoring"

  # Prometheus Configuration
  prometheus_enabled  = true
  prometheus_image    = "prom/prometheus:v${var.prometheus_version}"
  prometheus_port     = var.prometheus_port
  prometheus_memory   = "2Gi"
  prometheus_cpu      = "1000m"
  prometheus_retention_days = var.prometheus_retention_days

  # Prometheus scrape targets
  prometheus_scrape_configs = {
    code_server = {
      targets = ["localhost:8080"]
      interval = "15s"
    }
    caddy = {
      targets = ["localhost:2019"]
      interval = "30s"
    }
    postgres = {
      targets = ["postgres-exporter:9187"]
      interval = "30s"
    }
    redis = {
      targets = ["redis-exporter:9121"]
      interval = "30s"
    }
    kong = {
      targets = ["kong:8001"]
      interval = "30s"
    }
  }

  # Grafana Configuration
  grafana_enabled     = true
  grafana_image       = "grafana/grafana:${var.grafana_version}"
  grafana_port        = var.grafana_port
  grafana_admin_user  = var.grafana_admin_user
  grafana_admin_password = var.grafana_admin_password
  grafana_memory      = "512Mi"
  grafana_cpu         = "250m"

  # Grafana datasources
  grafana_datasources = [
    {
      name   = "Prometheus"
      type   = "prometheus"
      url    = "http://localhost:${var.prometheus_port}"
      access = "proxy"
    },
    {
      name   = "Loki"
      type   = "loki"
      url    = "http://localhost:${var.loki_port}"
      access = "proxy"
    },
    {
      name   = "Jaeger"
      type   = "jaeger"
      url    = "http://localhost:${var.jaeger_port}"
      access = "proxy"
    }
  ]

  # Grafana provisioned dashboards
  grafana_dashboards_enabled = true
  grafana_dashboards_dir     = "${path.module}/../config/grafana/dashboards"

  # AlertManager Configuration
  alertmanager_enabled = true
  alertmanager_image   = "prom/alertmanager:v${var.alertmanager_version}"
  alertmanager_port    = var.alertmanager_port
  alertmanager_memory  = "256Mi"
  alertmanager_cpu     = "100m"

  # AlertManager routing
  alertmanager_routes = {
    slack = {
      receiver = "slack-notifications"
      group_by = ["alertname", "cluster", "service"]
      group_wait = "30s"
      group_interval = "5m"
      repeat_interval = "4h"
      matchers = ["severity=~warning|critical"]
    }
    pagerduty = {
      receiver = "pagerduty-incidents"
      group_by = ["alertname"]
      group_wait = "10s"
      group_interval = "10s"
      repeat_interval = "30m"
      matchers = ["severity=critical"]
    }
  }

  # Loki Configuration
  loki_enabled     = true
  loki_image       = "grafana/loki:${var.loki_version}"
  loki_port        = var.loki_port
  loki_memory      = "512Mi"
  loki_cpu         = "250m"
  loki_retention_days = var.loki_retention_days

  # Loki scrape configs
  loki_scrape_configs = {
    docker = {
      job_name = "docker"
      static_configs = [{
        targets = ["localhost"]
        labels = {
          job      = "docker-logs"
          hostname = var.deployment_host
        }
      }]
    }
  }

  # Jaeger Configuration
  jaeger_enabled  = true
  jaeger_image    = "jaegertracing/all-in-one:${var.jaeger_version}"
  jaeger_port     = var.jaeger_port
  jaeger_memory   = "1Gi"
  jaeger_cpu      = "500m"
  jaeger_retention_days = var.jaeger_retention_days
  jaeger_sampling_rate  = 0.1  # Sample 10% of traces

  # Resource limits
  resource_limits = {
    memory = "6Gi"
    cpu    = "3000m"
  }

  # Storage configuration
  storage = {
    type = "local"  # Can be: local, s3, gcs
    path = "/mnt/monitoring-data"
    backup_enabled = true
    backup_interval = "daily"
  }

  # Networking
  network_mode = "bridge"
  expose_ports = {
    prometheus    = var.prometheus_port
    grafana       = var.grafana_port
    alertmanager  = var.alertmanager_port
    loki          = var.loki_port
    jaeger        = var.jaeger_port
  }

  # High availability
  replicas = {
    alertmanager = 3  # HA cluster
    prometheus   = 1  # Single instance (or 2 for remote storage)
  }

  # SLO Tracking
  slo_tracking = {
    enabled = true
    slo_targets = {
      code_server_availability = 0.99  # 99% uptime
      api_latency_p99          = 100   # 100ms p99 latency
      error_rate               = 0.001 # <0.1% error rate
    }
    alert_thresholds = {
      warning  = 0.95  # Alert if below 95%
      critical = 0.90  # Critical if below 90%
    }
  }

  # Observability
  observability = {
    metrics_enabled = true
    logs_enabled    = true
    traces_enabled  = true
  }

  # Tags
  tags = merge(var.tags, {
    Module = "monitoring"
    Purpose = "Prometheus, Grafana, AlertManager, Loki, Jaeger"
  })
}

# Output monitoring URLs for configuration
output "monitoring_urls" {
  value = {
    prometheus   = "http://localhost:${module.monitoring.prometheus_port}"
    grafana      = "http://localhost:${module.monitoring.grafana_port}"
    alertmanager = "http://localhost:${module.monitoring.alertmanager_port}"
    loki         = "http://localhost:${module.monitoring.loki_port}"
    jaeger       = "http://localhost:${module.monitoring.jaeger_port}"
  }
}

# Output Prometheus scrape configs for other modules
output "prometheus_scrape_targets" {
  value = module.monitoring.scrape_targets
}

# Output Grafana datasources for other modules
output "grafana_datasources" {
  value = module.monitoring.datasources
}
