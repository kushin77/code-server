terraform {
  required_version = ">= 1.0"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# Semantic local values for configuration
locals {
  service_name = "code-server-enterprise"
  environment  = "production"

  # Network configuration
  network_name = "${local.service_name}-network"

  # Container configuration
  code_server_port   = 8080
  caddy_http_port    = 80
  caddy_https_port   = 443

  # Credentials (use variables in production)
  code_server_password = var.code_server_password

  # Volume paths
  data_volume = "${local.service_name}-data"
  workspace_path = "/home/coder/project"

  tags = {
    Environment = local.environmen
    Service     = local.service_name
    ManagedBy   = "Terraform"
  }
}

# Docker Network
resource "docker_network" "enterprise" {
  name   = local.network_name
  driver = "bridge"
}

# Docker Volume for persistent data
resource "docker_volume" "code_server_data" {
  name = local.data_volume
}

# Code-Server Container
resource "docker_image" "code_server" {
  name          = "codercom/code-server:latest"
  keep_locally  = true
  pull_triggers = ["*"]
}

resource "docker_container" "code_server" {
  name     = "${local.service_name}-app"
  image    = docker_image.code_server.image_id
  must_run = true

  env = [
    "PASSWORD=${local.code_server_password}",
    "SUDO_PASSWORD=${local.code_server_password}",
    "SERVICE_URL=https://open-vsx.org/vscode/gallery",
    "ITEM_URL=https://open-vsx.org/vscode/item"
  ]

  volumes {
    volume_name    = docker_volume.code_server_data.name
    container_path = "/home/coder"
  }

  # Network configuration
  networks_advanced {
    name         = docker_network.enterprise.name
    ipv4_address = "172.20.0.2"
  }

  # Port mapping (internal only, mapped by Caddy)
  ports {
    internal = local.code_server_por
    external = local.code_server_por
  }

  depends_on = [docker_network.enterprise]
}

# Caddy Image
resource "docker_image" "caddy" {
  name          = "caddy:latest"
  keep_locally  = true
  pull_triggers = ["*"]
}

# Self-signed certificate helper
resource "null_resource" "caddy_config" {
  provisioner "local-exec" {
    command = "mkdir -p ${var.config_dir}/caddy"
  }
}

# Write Caddyfile
resource "local_file" "caddyfile" {
  filename = abspath("${var.config_dir}/caddy/Caddyfile")
  content  = templatefile("${path.module}/Caddyfile.tpl", {
    code_server_host = "code-server-enterprise-app"
    code_server_port = local.code_server_por
  })
}

# Caddy Container
resource "docker_container" "caddy" {
  name     = "${local.service_name}-proxy"
  image    = docker_image.caddy.image_id
  must_run = true

  # Port mappings
  ports {
    internal = 80
    external = local.caddy_http_por
  }

  ports {
    internal = 443
    external = local.caddy_https_por
  }

  volumes {
    host_path      = local_file.caddyfile.filename
    container_path = "/etc/caddy/Caddyfile"
  }

  volumes {
    volume_name    = "${local.service_name}-caddy-data"
    container_path = "/data"
  }

  volumes {
    volume_name    = "${local.service_name}-caddy-config"
    container_path = "/config"
  }

  # Network
  networks_advanced {
    name         = docker_network.enterprise.name
    ipv4_address = "172.20.0.3"
  }

  env = [
    "ACME_AGREE=true"
  ]

  depends_on = [docker_network.enterprise, docker_container.code_server, local_file.caddyfile]
}

# Output access details
output "code_server_url" {
  description = "Code-Server Access URL"
  value       = "http://localhost:${local.caddy_http_port}"
}

output "code_server_password" {
  description = "Code-Server Password"
  value       = local.code_server_password
  sensitive   = true
}

output "container_status" {
  description = "Container IDs"
  value = {
    code_server = docker_container.code_server.id
    caddy       = docker_container.caddy.id
  }
}

output "network_info" {
  description = "Network Configuration"
  value = {
    network_id = docker_network.enterprise.id
  }
}
