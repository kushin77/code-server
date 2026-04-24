# Monitoring Module Outputs

output "prometheus_endpoint" {
  description = "Prometheus HTTP endpoint"
  value       = var.docker_host == "" ? "http://prometheus.${var.namespace}.svc.cluster.local:9090" : "http://localhost:9090"
}

output "grafana_endpoint" {
  description = "Grafana HTTP endpoint"
  value       = var.docker_host == "" ? "http://grafana.${var.namespace}.svc.cluster.local:3000" : "http://localhost:3000"
}

output "grafana_admin_user" {
  description = "Grafana admin username"
  value       = "admin"
}

output "alertmanager_endpoint" {
  description = "AlertManager HTTP endpoint"
  value       = var.docker_host == "" ? "http://alertmanager.${var.namespace}.svc.cluster.local:9093" : "http://localhost:9093"
}

output "prometheus_pvc_name" {
  description = "Prometheus PVC name"
  value       = try(kubernetes_persistent_volume_claim.prometheus[0].metadata[0].name, "")
}

output "grafana_pvc_name" {
  description = "Grafana PVC name"
  value       = try(kubernetes_persistent_volume_claim.grafana[0].metadata[0].name, "")
}

output "monitoring_namespace" {
  description = "Monitoring namespace"
  value       = var.namespace
}

output "slo_error_budget_percentage" {
  description = "SLO error budget percentage"
  value       = var.slo_error_budget_percentage
}

output "prometheus_version" {
  description = "Prometheus version deployed"
  value       = var.prometheus_version
}

output "grafana_version" {
  description = "Grafana version deployed"
  value       = var.grafana_version
}

output "alertmanager_version" {
  description = "AlertManager version deployed"
  value       = var.alertmanager_version
}
