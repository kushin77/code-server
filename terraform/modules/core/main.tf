# @file terraform/modules/core/main.tf
# @description Core networking, DNS, and Caddy reverse proxy
# @governance GOV-002: Deterministic IaC, immutable infrastructure

# ============================================================================
# Caddyfile Configuration (HTTP/S gateway)
# ============================================================================

resource "local_file" "caddyfile" {
  filename = "${path.module}/../../config/caddy/Caddyfile.${var.deployment_mode}"
  content = templatefile("${path.module}/templates/Caddyfile.tpl", {
    apex_domain   = var.apex_domain
    primary_host  = var.primary_host
    admin_email   = var.admin_email
    enable_tls    = var.enable_tls
    log_level     = var.log_level
    deployment_mode = var.deployment_mode
  })
  
  lifecycle {
    ignore_changes = [content]  # Allow manual edits in production
  }
}

# ============================================================================
# DNS Configuration (for reference; actual DNS managed externally)
# ============================================================================

output "dns_configuration" {
  description = "DNS records required for deployment"
  value = {
    apex_domain = var.apex_domain
    a_records = [
      {
        subdomain = "@"
        hostname  = var.primary_host
        note      = "Primary deployment host"
      },
      {
        subdomain = "api"
        hostname  = var.primary_host
      },
      {
        subdomain = "ide"
        hostname  = var.primary_host
      }
    ]
    cname_records = [
      {
        subdomain = "*.inner"
        target    = var.apex_domain
        note      = "Internal service discovery"
      }
    ]
  }
}

# ============================================================================
# Health Check Endpoint
# ============================================================================

output "health_check_url" {
  description = "Cluster health check URL"
  value       = "http://${var.primary_host}/health"
}

output "api_base_url" {
  description = "API base URL"
  value       = "https://${var.apex_domain}/api"
}

# ============================================================================
# Network Architecture (Documentation)
# ============================================================================

output "network_topology" {
  description = "Network topology for reference"
  value = {
    primary_host = var.primary_host
    replica_host = var.replica_host != "" ? var.replica_host : "not configured"
    gateway_port = var.enable_tls ? 443 : 80
    internal_services = [
      "execution-scheduler:8080",
      "opa-service:8181",
      "prompt-gateway:8000",
      "postgres-db:5432",
      "redis-cache:6379",
      "redpanda-broker:9092"
    ]
  }
}
