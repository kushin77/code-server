// Monitoring Module — Prometheus, Grafana, AlertManager, Loki, Jaeger
// Provides observability stack for SLO tracking and distributed tracing

locals {
  prometheus_config = {
    version      = var.prometheus_version
    port         = var.prometheus_port
    retention    = var.prometheus_retention
    memory_limit = var.prometheus_memory_limit
    cpu_limit    = var.prometheus_cpu_limit
  }

  grafana_config = {
    version      = var.grafana_version
    port         = var.grafana_port
    admin_user   = var.grafana_admin_user
    memory_limit = var.grafana_memory_limit
    cpu_limit    = var.grafana_cpu_limit
  }

  alertmanager_config = {
    version      = var.alertmanager_version
    port         = var.alertmanager_port
    memory_limit = var.alertmanager_memory_limit
    cpu_limit    = var.alertmanager_cpu_limit
  }

  loki_config = {
    version      = var.loki_version
    port         = var.loki_port
    memory_limit = var.loki_memory_limit
    cpu_limit    = var.loki_cpu_limit
  }

  jaeger_config = {
    version      = var.jaeger_version
    port         = var.jaeger_port
    otlp_port    = var.jaeger_otlp_port
    memory_limit = var.jaeger_memory_limit
    cpu_limit    = var.jaeger_cpu_limit
  }

  slo_config = {
    availability_target = var.slo_target_availability
    latency_p99_target  = var.slo_target_latency_p99
    error_rate_target   = var.slo_target_error_rate
  }

  alert_rules = {
    critical_enabled = var.alert_severity_critical_enabled
    high_enabled     = var.alert_severity_high_enabled
    medium_enabled   = var.alert_severity_medium_enabled
  }
}

// Note: Actual Prometheus, Grafana, AlertManager, Loki, Jaeger provisioning
// is currently managed via docker-compose.yml
// This module defines configuration parameters and exports service metadata
// Future: Migrate to Kubernetes operators or Terraform Docker provider when scaling beyond single-host deployment
