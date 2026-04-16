// ════════════════════════════════════════════════════════════════════════════
// Terraform Module Outputs — Information exported for consumers
// ════════════════════════════════════════════════════════════════════════════

// Code-Server Access Information
output "code_server_url" {
  description = "URL to access code-server via oauth2-proxy with HTTPS and authentication"
  value       = "https://${var.domain}"
}

output "deployment_host_ip" {
  description = "IP address of the primary deployment host for SSH access and direct operations"
  value       = var.deployment_host
}

output "deployment_user" {
  description = "SSH user for accessing deployment host"
  value       = var.deployment_user
}

// Service URLs for Operator Access
output "prometheus_url" {
  description = "URL to Prometheus metrics dashboard (internal network, no HTTPS)"
  value       = "http://${var.deployment_host}:9090"
}

output "grafana_url" {
  description = "URL to Grafana observability dashboard (internal network, no HTTPS, default: admin/admin123)"
  value       = "http://${var.deployment_host}:3000"
}

output "alertmanager_url" {
  description = "URL to AlertManager alerts dashboard (internal network, no HTTPS)"
  value       = "http://${var.deployment_host}:9093"
}

output "jaeger_url" {
  description = "URL to Jaeger distributed tracing (internal network, no HTTPS)"
  value       = "http://${var.deployment_host}:16686"
}

// Database Access Information
output "postgresql_host" {
  description = "PostgreSQL hostname (internal Docker network reference)"
  value       = "postgresql:5432"
}

output "redis_host" {
  description = "Redis hostname (internal Docker network reference)"
  value       = "redis:6379"
}

// Configuration References
output "config_directory" {
  description = "Configuration directory containing docker-compose.yml and configs"
  value       = var.config_dir
}

output "domain_name" {
  description = "Primary domain used for oauth2-proxy OIDC redirect URIs and certificate provisioning"
  value       = var.domain
}

// Deployment Information
output "deployment_summary" {
  description = "Summary of deployment endpoints and access points"
  value = {
    code_server  = "https://${var.domain}"
    prometheus   = "http://${var.deployment_host}:9090"
    grafana      = "http://${var.deployment_host}:3000"
    alertmanager = "http://${var.deployment_host}:9093"
    jaeger       = "http://${var.deployment_host}:16686"
    ssh_host     = "${var.deployment_user}@${var.deployment_host}"
    postgresql   = "postgresql:5432"
    redis        = "redis:6379"
  }
}
