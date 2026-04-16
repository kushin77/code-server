// Networking Module — Kong, CoreDNS, Caddy
// Provides API gateway, service discovery, and reverse proxy

locals {
  kong_config = {
    version           = var.kong_version
    proxy_port        = var.kong_proxy_port
    proxy_ssl_port    = var.kong_proxy_ssl_port
    admin_port        = var.kong_admin_port
    admin_listen      = "127.0.0.1:${var.kong_admin_port}" // Loopback only
    memory_limit      = var.kong_memory_limit
    cpu_limit         = var.kong_cpu_limit
    rate_limit_minute = var.kong_rate_limit_minute
    rate_limit_hour   = var.kong_rate_limit_hour
    rate_limit_auth   = var.kong_rate_limit_auth_minute
  }

  coredns_config = {
    version      = var.coredns_version
    port         = var.coredns_port
    memory_limit = var.coredns_memory_limit
    cpu_limit    = var.coredns_cpu_limit
  }

  caddy_config = {
    version      = var.caddy_version
    http_port    = var.caddy_http_port
    https_port   = var.caddy_https_port
    admin_port   = var.caddy_admin_port
    auto_https   = var.caddy_auto_https
    memory_limit = var.caddy_memory_limit
    cpu_limit    = var.caddy_cpu_limit
  }

  features = {
    tls_termination   = var.enable_tls_termination
    rate_limiting     = var.enable_rate_limiting
    service_discovery = var.enable_service_discovery
  }

  routing_config = {
    load_balancing = var.load_balancing_algorithm
  }
}

// Note: Kong, CoreDNS, and Caddy provisioning is currently via docker-compose.yml
// This module defines configuration parameters, security rules, and routing policies
// Future: Integrate with Terraform Docker provider or Kubernetes when scaling
