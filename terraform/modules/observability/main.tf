# @file terraform/modules/observability/main.tf
# @description Observability infrastructure configuration

resource "random_password" "grafana_admin" {
  count  = var.grafana_admin_password == "" ? 1 : 0
  length = 16
}

output "observability_endpoints" {
  description = "Observability service endpoints"
  value = {
    prometheus = "http://prometheus:9090"
    grafana    = "http://grafana:3000"
    loki       = "http://loki:3100"
  }
}

output "observability_config" {
  description = "Observability configuration"
  value = {
    metrics_retention_days = var.metrics_retention_days
    logs_retention_days    = var.logs_retention_days
    grafana_admin_set      = var.grafana_admin_password != ""
  }
}
