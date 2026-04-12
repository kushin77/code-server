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
    Environment = local.environment
    Service     = local.service_name
    ManagedBy   = "Terraform"
  }
}

# Docker Network
resource "docker_network" "enterprise" {
  name = local.network_name
  driver = "bridge"
  
  labels = {
    name = local.network_name
  }
}

# Docker Volume for persistent data
resource "docker_volume" "code_server_data" {
  name = local.data_volume
  
  labels = {
    service = local.service_name
  }
}

# Code-Server Container
resource "docker_image" "code_server" {
  name          = "codercom/code-server:latest"
  keep_locally  = true
  pull_triggers = ["*"]
}

resource "docker_container" "code_server" {
  name             = "${local.service_name}-app"
  image            = docker_image.code_server.image_id
  restart_policy   = "unless-stopped"
  must_run         = true
  
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
  
  # Expose internal port
  expose = [local.code_server_port]
  
  # Health check
  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:${local.code_server_port}/health || exit 1"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
  }
  
  labels = merge(
    local.tags,
    {
      "service.port" = local.code_server_port
    }
  )
  
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
  provisioners "local-exec" {
    command = "mkdir -p ${var.config_dir}/caddy"
  }
}

# Write Caddyfile
resource "local_file" "caddyfile" {
  filename = "${var.config_dir}/caddy/Caddyfile"
  content  = templatefile("${path.module}/Caddyfile.tpl", {
    code_server_host = "code-server-enterprise-app"
    code_server_port = local.code_server_port
  })
}

# Caddy Container  
resource "docker_container" "caddy" {
  name             = "${local.service_name}-proxy"
  image            = docker_image.caddy.image_id
  restart_policy   = "unless-stopped"
  must_run         = true
  
  # Port mappings
  ports {
    internal = 80
    external = local.caddy_http_port
  }
  
  ports {
    internal = 443
    external = local.caddy_https_port
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
  
  labels = merge(
    local.tags,
    {
      "service.type" = "reverse-proxy"
    }
  )
  
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
  description = "Container Status"
  value = {
    code_server = docker_container.code_server.state
    caddy       = docker_container.caddy.state
  }
}

output "network_info" {
  description = "Network Configuration"
  value = {
    network_id = docker_network.enterprise.id
    code_server_ip = docker_container.code_server.network_data[0].ip_address
    caddy_ip       = docker_container.caddy.network_data[0].ip_address
  }
}
