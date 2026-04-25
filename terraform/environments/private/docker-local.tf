/**
 * @file terraform/environments/private/docker-local.tf
 * @description Local Docker Compose management for development/private deployments
 * @governance GOV-002 - Infrastructure as Code for idempotent deployments
 */

# Local file resources for configuration management
resource "local_file" "docker_compose_override" {
  filename        = "${path.module}/../../docker-compose.override.yml"
  content         = file("${path.module}/../../docker-compose.override.yml")
  file_permission = "0644"

  lifecycle {
    ignore_changes = [content]  # Managed by docker-compose.override.yml file
  }
}

resource "local_file" "caddy_config" {
  filename        = "${path.module}/../../config/caddy/Caddyfile"
  content         = file("${path.module}/../../config/caddy/Caddyfile.http-prod")
  file_permission = "0644"

  lifecycle {
    ignore_changes = [content]  # Allow manual updates when needed
  }
}

# Output local file paths for reference
output "docker_compose_override_path" {
  value = local_file.docker_compose_override.filename
  description = "Path to docker-compose.override.yml"
}

output "caddy_config_path" {
  value = local_file.caddy_config.filename
  description = "Path to active Caddyfile"
}
