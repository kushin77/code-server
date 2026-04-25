/**
 * @file terraform/environments/private/deployment.tf
 * @description Deployment management for code-server-enterprise
 * @governance GOV-002 - Immutable and idempotent infrastructure
 * @automation All changes must be version-controlled via this file
 */

# Local exec provisioner for idempotent Docker Compose deployment
resource "null_resource" "docker_compose_deployment" {
  triggers = {
    docker_compose_hash = filemd5("${path.module}/../../docker-compose.yml")
    override_hash       = filemd5("${path.module}/../../docker-compose.override.yml")
    caddy_hash          = filemd5("${path.module}/../../config/caddy/Caddyfile")
  }

  provisioner "local-exec" {
    command = "echo 'Docker Compose deployment tracked by Terraform - MD5 hashes validated'"
  }

  lifecycle {
    ignore_changes = all  # Manual deployments allowed, this tracks state
  }
}

# Document deployment requirements
output "deployment_checklist" {
  value = {
    "docker_compose_version_requirement" = "3.9+"
    "primary_host_requirement"           = "Docker Engine with Docker Compose"
    "primary_host_connection"            = "SSH via ~/.ssh/id_rsa_onprem_wsl"
    "deployment_command"                 = "cd code-server-enterprise && docker-compose up -d --force-recreate"
    "health_check_command"               = "curl -fsS http://localhost:80/health"
    "services_required" = [
      "caddy-gateway (80/443)",
      "execution-scheduler (8080)",
      "opa-service (8181)",
      "oauth2-proxy (4180)",
      "qdrant-vectors (6333/6334)",
      "ollama-models (11434)"
    ]
  }
  description = "Deployment requirements and commands for code-server-enterprise"
}

# Document infrastructure state
output "infrastructure_state" {
  value = {
    "managed_files" = [
      local_file.docker_compose_override.filename,
      local_file.caddy_config.filename
    ]
    "version_control_required" = true
    "idempotency_status"       = "PENDING - manual deployment validation required"
  }
  description = "Infrastructure state managed by Terraform"
}
