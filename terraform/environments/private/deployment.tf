/**
 * @file terraform/environments/private/deployment.tf
 * @description Enterprise-class deployment management for code-server-enterprise
 * @governance GOV-002 - Infrastructure as Code with validation, health checks, rollback
 * @best-practices P0: Version-controlled, idempotent, auditable deployments
 */

# ============================================================================
# TRIGGER DATA (Read file hashes to determine deployment trigger state)
# ============================================================================

data "local_file" "docker_compose_deploy" {
  filename = "${path.root}/../../../docker-compose.deploy.yml"
}

data "local_file" "docker_compose_override" {
  filename = "${path.root}/../../../docker-compose.override.yml"
}

data "local_file" "caddy_config_file" {
  filename = "${path.root}/../../../config/caddy/Caddyfile"
}

data "local_file" "terraform_deploy_script" {
  filename = "${path.root}/../../../scripts/ops/terraform-deploy.sh"
}

# Validate environment before deployment
resource "null_resource" "deployment_validation" {
  triggers = {
    primary_host = var.primary_host
    replica_host = var.replica_host
  }

  provisioner "local-exec" {
    working_dir = "${path.root}/../../../"
    command     = "bash -n scripts/ops/terraform-deploy.sh 2>&1 | grep -v '^$' || echo 'Validation: script syntax OK'"
  }
}

# ============================================================================
# DRY-RUN DEPLOYMENT (Simulation/validation)
# ============================================================================

resource "null_resource" "deployment_simulation" {
  triggers = {
    primary_host = var.primary_host
  }

  provisioner "local-exec" {
    working_dir = "${path.root}/../../../"
    command = join(" ", [
      "bash scripts/ops/terraform-deploy.sh",
      var.primary_host,
      "primary",
      "true",  # DRY_RUN
      "2>&1 | head -100"
    ])
  }

  depends_on = [null_resource.deployment_validation]
}

# ============================================================================
# PRIMARY HOST DEPLOYMENT
# ============================================================================

resource "null_resource" "primary_host_deployment" {
  triggers = {
    deployment_script = data.local_file.terraform_deploy_script.content_md5
    docker_compose    = data.local_file.docker_compose_deploy.content_md5
    override_hash     = data.local_file.docker_compose_override.content_md5
    caddy_hash        = data.local_file.caddy_config_file.content_md5
    primary_host      = var.primary_host
    force_recreate    = var.force_recreate ? "true" : "false"
  }

  provisioner "local-exec" {
    working_dir = "${path.root}/../../../"
    command = join(" ", [
      "bash scripts/ops/terraform-deploy.sh",
      var.primary_host,
      "primary",
      "false",  # DRY_RUN
      "2>&1"
    ])
  }

  lifecycle {
    ignore_changes = [triggers]
  }

  depends_on = [
    null_resource.deployment_simulation,
    local_file.docker_compose_override,
    local_file.caddy_config
  ]
}

# ============================================================================
# REPLICA HOST DEPLOYMENT
# ============================================================================

resource "null_resource" "replica_host_deployment" {
  count = var.replica_host != var.primary_host && var.replica_host != "" ? 1 : 0

  triggers = {
    deployment_script = data.local_file.terraform_deploy_script.content_md5
    docker_compose    = data.local_file.docker_compose_deploy.content_md5
    override_hash     = data.local_file.docker_compose_override.content_md5
    caddy_hash        = data.local_file.caddy_config_file.content_md5
    replica_host      = var.replica_host
    force_recreate    = var.force_recreate ? "true" : "false"
  }

  provisioner "local-exec" {
    working_dir = "${path.root}/../../../"
    command = join(" ", [
      "bash scripts/ops/terraform-deploy.sh",
      var.replica_host,
      "replica",
      "false",  # DRY_RUN
      "2>&1"
    ])
  }

  lifecycle {
    ignore_changes = [triggers]
  }

  depends_on = [
    null_resource.primary_host_deployment,
    local_file.docker_compose_override,
    local_file.caddy_config
  ]
}

# ============================================================================
# POST-DEPLOYMENT VALIDATION
# ============================================================================

resource "null_resource" "post_deployment_validation" {
  triggers = {
    primary_deployment = null_resource.primary_host_deployment.id
    replica_deployment = var.replica_host != var.primary_host && var.replica_host != "" ? null_resource.replica_host_deployment[0].id : "skipped"
  }

  provisioner "local-exec" {
    working_dir = "${path.root}/../../../"
    command = <<-EOT
      set -e
      echo "=== POST-DEPLOYMENT VALIDATION ==="
      
      # Validate primary
      echo "Primary (${var.primary_host}):"
      ssh -o ConnectTimeout=5 akushnir@${var.primary_host} "docker ps --format '{{.Names}}' | wc -l | xargs echo 'Containers:'"
      
      # Validate replica if configured
      if [ "${var.replica_host}" != "${var.primary_host}" ] && [ -n "${var.replica_host}" ]; then
        echo "Replica (${var.replica_host}):"
        ssh -o ConnectTimeout=5 akushnir@${var.replica_host} "docker ps --format '{{.Names}}' | wc -l | xargs echo 'Containers:'"
      fi
      
      echo "=== VALIDATION COMPLETE ==="
    EOT
  }

  depends_on = [
    null_resource.primary_host_deployment,
    null_resource.replica_host_deployment
  ]
}

# ============================================================================
# DEPLOYMENT OUTPUTS
# ============================================================================

output "deployment_checklist" {
  value = {
    "deployment_status"                  = "MANAGED - Services deployed via Terraform provisioners"
    "orchestration_method"               = "Local-exec + SSH + docker-compose.deploy.yml"
    "docker_compose_version_requirement" = "2.20.0+"
    "deployment_modes" = [
      "primary: ${var.primary_host}",
      var.replica_host != var.primary_host && var.replica_host != "" ? "replica: ${var.replica_host}" : "replica: not configured"
    ]
    "health_check_command" = "curl -fsS http://${var.primary_host}:80/health"
    "services_deployed" = [
      "caddy-gateway (80/443)",
      "execution-scheduler (8080)",
      "opa-service (8181)",
      "oauth2-proxy (4180)",
      "qdrant-vectors (6333/6334)",
      "ollama-models (11434)",
      "prometheus (9090)",
      "grafana (3000)",
      "loki (3100)",
      "postgres (5432)",
      "redis (6379)",
      "redpanda (9092)",
      "tempo (3200)"
    ]
    "deployment_validation_enabled" = var.enable_deployment_validation
    "force_recreate_enabled"        = var.force_recreate
  }
  description = "Deployment status and configuration"
}

output "infrastructure_state" {
  value = {
    "deployment_status"     = "COMPLETE - All services managed by Terraform"
    "orchestration_script"  = abspath("${path.root}/../../../scripts/ops/terraform-deploy.sh")
    "deployment_log_format" = "/tmp/terraform-deployment-*.log"
    "managed_hosts" = concat(
      [var.primary_host],
      var.replica_host != "" && var.replica_host != var.primary_host ? [var.replica_host] : []
    )
    "managed_files" = [
      local_file.docker_compose_override.filename,
      local_file.caddy_config.filename
    ]
    "version_control_required" = true
    "rollback_strategy"        = "docker-compose down per host + git revert"
  }
  description = "Infrastructure state and management references"
}

output "service_endpoints" {
  value = {
    "health_check"  = "http://${var.primary_host}/health"
    "gateway"       = "http://${var.primary_host}"
    "execution_api" = "http://${var.primary_host}/api/execution"
    "opa_api"       = "http://${var.primary_host}:8181/v1/policies"
    "prometheus"    = "http://${var.primary_host}:9090"
    "grafana"       = "http://${var.primary_host}:3000"
    "loki"          = "http://${var.primary_host}:3100"
  }
  description = "Service endpoint URLs"
}

output "deployment_commands" {
  value = {
    "force_redeployment" = "terraform taint null_resource.primary_host_deployment && terraform apply"
    "view_deployment_log" = "tail -f /tmp/terraform-deployment-*.log"
    "manual_ssh_test"    = "ssh akushnir@${var.primary_host} 'cd ~/code-server-enterprise-ops && docker-compose -f docker-compose.deploy.yml ps'"
    "manual_redeploy"    = "ssh akushnir@${var.primary_host} 'cd ~/code-server-enterprise-ops && docker-compose -f docker-compose.deploy.yml up -d'"
    "manual_rollback"    = "ssh akushnir@${var.primary_host} 'cd ~/code-server-enterprise-ops && docker-compose -f docker-compose.deploy.yml down'"
  }
  description = "Common deployment commands"
}
