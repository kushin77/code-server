#!/usr/bin/env terraform
# modules/core/outputs.tf — Core module outputs

output "code_server_config" {
  description = "Code-server service configuration"
  value = {
    name    = "code-server"
    port    = var.code_server_port
    version = var.code_server_version
    memory  = var.code_server_memory_limit
    cpu     = var.code_server_cpu_limit
    url     = "http://${var.host_ip}:${var.code_server_port}"
  }
}

output "caddy_config" {
  description = "Caddy reverse proxy configuration"
  value = {
    name       = "caddy"
    version    = var.caddy_version
    http_port  = var.caddy_port_http
    https_port = var.caddy_port_https
    admin_port = var.caddy_admin_port
    auto_https = var.caddy_auto_https
    domain     = var.domain
    admin_url  = "http://127.0.0.1:${var.caddy_admin_port}"
  }
}

output "oauth2_config" {
  description = "OAuth2-proxy service configuration"
  value = {
    name         = "oauth2-proxy"
    version      = var.oauth2_proxy_version
    port         = var.oauth2_proxy_port
    provider     = var.oauth2_provider
    callback_url = var.oauth2_callback_url
    url          = "http://127.0.0.1:${var.oauth2_proxy_port}"
  }
}
