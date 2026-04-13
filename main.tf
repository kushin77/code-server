terraform {
  required_version = ">= 1.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# NOTE: Container orchestration is managed entirely by docker-compose.yml.
# This Terraform config handles:
#   1. Rendering Caddyfile.tpl for local development (no TLS challenge)
#   2. Metadata locals used by CI auditing and documentation tooling
# Run:  terraform init && terraform apply
#       → writes caddy/Caddyfile for local dev; no containers are created.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  service_name = "code-server-enterprise"
  environment  = "production"

  code_server_port = 8080
  caddy_http_port  = 80
  caddy_https_port = 443

  code_server_password = var.code_server_password
  data_volume          = "${local.service_name}-data"
  workspace_path       = "/home/coder/project"

  tags = {
    Environment = local.environment
    Service     = local.service_name
    ManagedBy   = "docker-compose"
  }
}

# Render Caddyfile for local development (localhost, no DNS-01 TLS)
resource "null_resource" "caddy_config_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${var.config_dir}/caddy"
  }
}

resource "local_file" "caddyfile" {
  filename = abspath("${var.config_dir}/caddy/Caddyfile")
  content = templatefile("${path.module}/Caddyfile.tpl", {
    code_server_host = "localhost"
    code_server_port = local.code_server_port
  })
}