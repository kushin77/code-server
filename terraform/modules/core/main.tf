#!/usr/bin/env terraform
# modules/core/main.tf — Core application services provisioning
# Currently, core services are Docker-managed via docker-compose.yml
# This module serves as a placeholder for future native Terraform deployment

# For now, this module outputs service configuration that can be referenced
# by other modules. When migrating to Terraform-managed Docker, resources would be added here:
# - docker_image (for code-server, caddy, oauth2-proxy)
# - docker_container (for service provisioning)
# - docker_network (for service networking)

# Placeholder: Future implementation
# resource "docker_image" "code_server" {
#   name = "codercom/code-server:${var.code_server_version}"
# }

# resource "docker_container" "code_server" {
#   name    = "code-server"
#   image   = docker_image.code_server.id
#   ports {
#     internal = var.code_server_port
#     external = var.code_server_port
#   }
#   memory = var.code_server_memory_limit
# }

# For now, simply reference the docker-compose configuration
locals {
  core_services = {
    code_server = {
      name    = "code-server"
      port    = var.code_server_port
      version = var.code_server_version
      memory  = var.code_server_memory_limit
      cpu     = var.code_server_cpu_limit
    }
    caddy = {
      name    = "caddy"
      version = var.caddy_version
      http_port  = var.caddy_port_http
      https_port = var.caddy_port_https
      admin_port = var.caddy_admin_port
    }
    oauth2_proxy = {
      name    = "oauth2-proxy"
      version = var.oauth2_proxy_version
      port    = var.oauth2_proxy_port
      provider = var.oauth2_provider
    }
  }
}
