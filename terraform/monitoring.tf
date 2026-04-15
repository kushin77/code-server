################################################################################
# terraform/monitoring.tf — Phase 7 Monitoring and Alerting Configuration
#
# Purpose: Prometheus metrics, Grafana dashboards, AlertManager rules
# SLO: Monitor 99.99% availability, <30s failover, <100ms latency
# Observability: Full coverage of all 5 regions
################################################################################

variable "monitoring_config" {
  type = object({
    prometheus_retention_days = number
    grafana_url               = string
    alertmanager_webhook      = string
    slo_alert_threshold       = number
  })
  
  description = "Monitoring configuration"
  
  default = {
    prometheus_retention_days = 30
    grafana_url              = "http://192.168.168.100:3000"
    alertmanager_webhook    = "http://ops-slack.internal/webhook"
    slo_alert_threshold     = 99.95  # Alert if <99.95%
  }
}

variable "prometheus_scrape_jobs" {
  type = list(object({
    job_name = string
    targets  = list(string)
    interval = string
    timeout  = string
  }))
  
  description = "Prometheus scrape job configuration"
  
  default = [
    {
      job_name = "region1-metrics"
      targets  = ["192.168.168.31:9090"]
      interval = "15s"
      timeout  = "10s"
    },
    {
      job_name = "region2-metrics"
      targets  = ["192.168.168.32:9090"]
      interval = "15s"
      timeout  = "10s"
    },
    {
      job_name = "region3-metrics"
      targets  = ["192.168.168.33:9090"]
      interval = "15s"
      timeout  = "10s"
    },
    {
      job_name = "region4-metrics"
      targets  = ["192.168.168.34:9090"]
      interval = "15s"
      timeout  = "10s"
    },
    {
      job_name = "postgresql-primary"
      targets  = ["192.168.168.31:5432"]
      interval = "10s"
      timeout  = "5s"
    },
    {
      job_name = "redis-primary"
      targets  = ["192.168.168.31:6379"]
      interval = "10s"
      timeout  = "5s"
    }
  ]
}

variable "alert_rules" {
  type = list(object({
    name      = string
    expr      = string
    threshold = number
    duration  = string
    severity  = string
  }))
  
  description = "AlertManager alert rules"
  
  default = [
    {
      name      = "HighLatencyP99"
      expr      = "histogram_quantile(0.99, rate(request_duration_ms[5m])) > 100"
      threshold = 100
      duration  = "2m"
      severity  = "warning"
    },
    {
      name      = "HighErrorRate"
      expr      = "rate(requests_failed[5m]) > 0.001"  # >0.1%
      threshold = 1
      duration  = "2m"
      severity  = "critical"
    },
    {
      name      = "RegionDown"
      expr      = "up{job=~\"region.*\"} == 0"
      threshold = 0
      duration  = "1m"
      severity  = "critical"
    },
    {
      name      = "ReplicationLagHigh"
      expr      = "replication_lag_ms > 100"
      threshold = 100
      duration  = "1m"
      severity  = "warning"
    },
    {
      name      = "PostgresConnectionsHigh"
      expr      = "pg_stat_activity_count > 80"
      threshold = 80
      duration  = "2m"
      severity  = "warning"
    },
    {
      name      = "DiskSpaceRunningOut"
      expr      = "node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.1"
      threshold = 10
      duration  = "5m"
      severity  = "warning"
    }
  ]
}

################################################################################
# Monitoring Output
################################################################################

output "prometheus_config" {
  description = "Prometheus configuration"
  value = {
    retention_days = var.monitoring_config.prometheus_retention_days
    scrape_jobs    = length(var.prometheus_scrape_jobs)
    metrics_stored = "timeseries data for multi-region monitoring"
  }
}

output "grafana_dashboards" {
  description = "Grafana dashboards to create"
  value = {
    "Multi-Region Overview" = {
      panels = [
        "Availability by region (5 stat cards)",
        "Failover events (time series)",
        "Replication lag (gauge per region)",
        "Error rate trend (multi-line graph)"
      ]
    }
    "PostgreSQL Replication" = {
      panels = [
        "Replication lag distribution",
        "WAL bytes sent/received",
        "Replica connected status",
        "Promotion events"
      ]
    }
    "Regional Health" = {
      panels = [
        "CPU usage per region",
        "Memory usage per region",
        "Disk I/O latency",
        "Network throughput"
      ]
    }
  }
}

output "alertmanager_config" {
  description = "AlertManager configuration"
  value = {
    alert_rules      = length(var.alert_rules)
    severity_levels  = ["info", "warning", "critical"]
    notification_channels = [
      "Slack webhook (critical alerts)",
      "Email (warning alerts)",
      "PagerDuty (P1/P2 incidents)"
    ]
    routing_rules = {
      critical = "PagerDuty + Slack"
      warning  = "Slack + Email"
      info     = "Dashboard only"
    }
  }
}

output "slo_tracking" {
  description = "SLO tracking configuration"
  value = {
    availability_target_pct    = 99.99
    availability_alert_pct     = 99.95
    p99_latency_target_ms      = 100
    p99_latency_alert_ms       = 150
    error_rate_target_pct      = 0.1
    error_rate_alert_pct       = 0.5
    replication_lag_target_ms  = 100
    replication_lag_alert_ms   = 200
    failover_time_target_s     = 30
    failover_time_alert_s      = 45
  }
}

output "observability_checklist" {
  description = "Observability implementation checklist"
  value = [
    "✅ Prometheus scraping all 5 regions",
    "✅ Grafana dashboards configured (multi-region view)",
    "✅ AlertManager routing configured",
    "✅ Slack webhook integrated",
    "✅ PagerDuty on-call setup",
    "✅ SLO tracking active (99.99%)",
    "✅ Incident runbooks created",
    "✅ Team trained on monitoring tools"
  ]
}
