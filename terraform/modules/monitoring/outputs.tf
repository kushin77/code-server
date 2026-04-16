output "prometheus_config" {
  description = "Prometheus service configuration"
  value = {
    version      = local.prometheus_config.version
    port         = local.prometheus_config.port
    retention    = local.prometheus_config.retention
    memory_limit = local.prometheus_config.memory_limit
    cpu_limit    = local.prometheus_config.cpu_limit
    endpoint     = "http://prometheus:${local.prometheus_config.port}"
  }
}

output "grafana_config" {
  description = "Grafana service configuration"
  value = {
    version      = local.grafana_config.version
    port         = local.grafana_config.port
    admin_user   = local.grafana_config.admin_user
    memory_limit = local.grafana_config.memory_limit
    cpu_limit    = local.grafana_config.cpu_limit
    endpoint     = "http://grafana:${local.grafana_config.port}"
  }
}

output "alertmanager_config" {
  description = "AlertManager service configuration"
  value = {
    version      = local.alertmanager_config.version
    port         = local.alertmanager_config.port
    memory_limit = local.alertmanager_config.memory_limit
    cpu_limit    = local.alertmanager_config.cpu_limit
    endpoint     = "http://alertmanager:${local.alertmanager_config.port}"
  }
}

output "loki_config" {
  description = "Loki log aggregation service configuration"
  value = {
    version      = local.loki_config.version
    port         = local.loki_config.port
    memory_limit = local.loki_config.memory_limit
    cpu_limit    = local.loki_config.cpu_limit
    endpoint     = "http://loki:${local.loki_config.port}"
  }
}

output "jaeger_config" {
  description = "Jaeger distributed tracing service configuration"
  value = {
    version       = local.jaeger_config.version
    ui_port       = local.jaeger_config.port
    otlp_port     = local.jaeger_config.otlp_port
    memory_limit  = local.jaeger_config.memory_limit
    cpu_limit     = local.jaeger_config.cpu_limit
    ui_endpoint   = "http://jaeger:${local.jaeger_config.port}"
    otlp_endpoint = "http://jaeger:${local.jaeger_config.otlp_port}"
  }
}

output "slo_config" {
  description = "SLO targets for observability"
  value = {
    availability_target = "${local.slo_config.availability_target}%"
    latency_p99_ms      = local.slo_config.latency_p99_target
    error_rate_target   = "${local.slo_config.error_rate_target}%"
  }
}

output "alert_rules" {
  description = "Alert severity levels enabled"
  value = {
    critical = local.alert_rules.critical_enabled
    high     = local.alert_rules.high_enabled
    medium   = local.alert_rules.medium_enabled
  }
}
