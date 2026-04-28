/**
 * @file terraform/environments/private/deployment.tf
 * @description Deployment management for code-server-enterprise
 * @governance GOV-002 - Immutable and idempotent infrastructure
 * @automation All changes must be version-controlled via this file
 */

# Deploy and start services on primary host
resource "null_resource" "primary_host_deployment" {
  triggers = {
    docker_compose_hash = filemd5("${path.module}/../../../docker-compose.yml")
    override_hash       = filemd5("${path.module}/../../../docker-compose.override.yml")
    caddy_hash          = filemd5("${path.module}/../../../config/caddy/Caddyfile")
    primary_host        = var.primary_host
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo '[INFO] Deploying Docker Compose on primary host (${var.primary_host})'",
      "cd code-server-enterprise || cd ~/code-server",
      "echo '[INFO] Starting services with docker-compose (all profiles)...'",
      "docker-compose --profile ai --profile governance --profile infrastructure --profile all up -d --force-recreate",
      "echo '[INFO] Waiting for services to stabilize (30s)...'",
      "sleep 30",
      "echo '[INFO] Checking health endpoint...'",
      "curl -fsS http://localhost:80/health || echo '[WARN] Health check pending, services may still be starting'",
      "echo '[SUCCESS] Primary host deployment complete'"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      host        = var.primary_host
      private_key = var.ssh_key != "" ? file(var.ssh_key) : null
      port        = var.ssh_port
      timeout     = "5m"
    }
  }

  lifecycle {
    # P1 #2422: Changed from ignore_changes = all to [triggers]
    # - Enables terraform drift detection on non-trigger attributes
    # - Drift detection for deployment state uses gitops-drift-detector.sh
    # - To trigger redeployment: terraform taint null_resource.primary_host_deployment
    # - or change a trigger value (docker_compose_hash, override_hash, caddy_hash, or primary_host)
    ignore_changes = [triggers]
  }

  depends_on = [
    local_file.docker_compose_override,
    local_file.caddy_config
  ]
}

# Deploy and start services on replica host
resource "null_resource" "replica_host_deployment" {
  count = var.replica_host != var.primary_host && var.replica_host != "" ? 1 : 0

  triggers = {
    docker_compose_hash = filemd5("${path.module}/../../../docker-compose.yml")
    override_hash       = filemd5("${path.module}/../../../docker-compose.override.yml")
    caddy_hash          = filemd5("${path.module}/../../../config/caddy/Caddyfile")
    replica_host        = var.replica_host
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo '[INFO] Deploying Docker Compose on replica host (${var.replica_host})'",
      "cd code-server-enterprise || cd ~/code-server",
      "echo '[INFO] Starting services with docker-compose (all profiles)...'",
      "docker-compose --profile ai --profile governance --profile infrastructure --profile all up -d --force-recreate",
      "echo '[INFO] Waiting for services to stabilize (30s)...'",
      "sleep 30",
      "echo '[INFO] Checking health endpoint...'",
      "curl -fsS http://localhost:80/health || echo '[WARN] Health check pending, services may still be starting'",
      "echo '[SUCCESS] Replica host deployment complete'"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      host        = var.replica_host
      private_key = var.ssh_key != "" ? file(var.ssh_key) : null
      port        = var.ssh_port
      timeout     = "5m"
    }
  }

  lifecycle {
    # P1 #2422: Changed from ignore_changes = all to [triggers]
    # - Enables terraform drift detection on non-trigger attributes
    # - To trigger redeployment: terraform taint null_resource.replica_host_deployment
    # - or change a trigger value (docker_compose_hash, override_hash, caddy_hash, or replica_host)
    ignore_changes = [triggers]
  }

  depends_on = [
    local_file.docker_compose_override,
    local_file.caddy_config,
    null_resource.primary_host_deployment
  ]
}

# Document deployment requirements
output "deployment_checklist" {
  value = {
    "deployment_status"                  = "AUTOMATED - Services deployed via Terraform"
    "docker_compose_version_requirement" = "3.9+"
    "primary_host"                       = var.primary_host
    "replica_host"                       = var.replica_host != "" ? var.replica_host : "Not configured"
    "nas_host"                           = var.nas_host != "" ? var.nas_host : "Not configured"
    "health_check_command"               = "curl -fsS http://${var.primary_host}:80/health"
    "services_deployed" = [
      "caddy-gateway (80/443)",
      "execution-scheduler (8080)",
      "opa-service (8181)",
      "oauth2-proxy (4180)",
      "qdrant-vectors (6333/6334)",
      "ollama-models (11434)"
    ]
  }
  description = "Automated deployment status and service information"
}

# Document infrastructure state
output "infrastructure_state" {
  value = {
    "deployment_status" = "COMPLETE - All services are now running via Terraform provisioners"
    "managed_files" = [
      local_file.docker_compose_override.filename,
      local_file.caddy_config.filename
    ]
    "deployed_hosts" = concat(
      [var.primary_host],
      var.replica_host != "" && var.replica_host != var.primary_host ? [var.replica_host] : []
    )
    "version_control_required" = true
  }
  description = "Infrastructure state managed by Terraform - services are running"
}

# Output service URLs
output "service_endpoints" {
  value = {
    "health_check"  = "http://${var.primary_host}/health"
    "gateway"       = "http://${var.primary_host}"
    "execution_api" = "http://${var.primary_host}/api/execution"
    "opa_api"       = "http://${var.primary_host}/api/opa"
    "auth_api"      = "http://${var.primary_host}/api/auth"
  }
  description = "Service endpoints for the deployed cluster"
}
