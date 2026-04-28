/**
 * @file terraform/modules/deployment-orchestration.tf
 * @description Phase 3: Deployment orchestration using script-based approach
 * @governance OPS-002: Infrastructure deployments managed via version-controlled scripts
 * @note This module replaces raw remote-exec provisioners with a script-based approach
 */

# Deploy services using script-based orchestration (Phase 3 improvement)
resource "null_resource" "deployment_orchestration" {
  triggers = {
    deployment_script   = filemd5("${path.module}/../../scripts/ops/deploy-via-ssh.sh")
    docker_compose_hash = filemd5("${path.module}/../../docker-compose.yml")
    override_hash       = filemd5("${path.module}/../../docker-compose.override.yml")
    config_hash         = filemd5("${path.module}/../../scripts/_common/config.env")
    primary_host        = var.primary_host
  }

  # Local execution of deployment script (can be executed from anywhere)
  provisioner "local-exec" {
    working_dir = "${path.module}/../.."
    
    command = "${path.module}/../../scripts/ops/deploy-via-ssh.sh ."
    
    environment = {
      PRIMARY_HOST    = var.primary_host
      REPLICA_HOST    = var.replica_host != "" ? var.replica_host : ""
      SSH_USER        = var.ssh_user
      SSH_KEY         = var.ssh_key != "" ? var.ssh_key : ""
      SSH_PORT        = var.ssh_port
      FORCE_RECREATE  = var.force_recreate ? "true" : "false"
      PROFILES        = "ai governance infrastructure all"
      DRY_RUN         = "false"
    }
  }

  lifecycle {
    ignore_changes = all
  }

  depends_on = [
    var.primary_host,
    var.replica_host
  ]
}

# Dry-run simulation (for validation)
resource "null_resource" "deployment_simulation" {
  count = var.enable_deployment_simulation ? 1 : 0

  triggers = {
    deployment_script = filemd5("${path.module}/../../scripts/ops/deploy-via-ssh.sh")
  }

  # Local dry-run to validate deployment
  provisioner "local-exec" {
    working_dir = "${path.module}/../.."
    
    command = "${path.module}/../../scripts/ops/deploy-via-ssh.sh . 2>&1 | tee /tmp/deployment-simulation.log"
    
    environment = {
      PRIMARY_HOST    = var.primary_host
      REPLICA_HOST    = var.replica_host != "" ? var.replica_host : ""
      SSH_USER        = var.ssh_user
      SSH_KEY         = var.ssh_key != "" ? var.ssh_key : ""
      SSH_PORT        = var.ssh_port
      FORCE_RECREATE  = "false"
      PROFILES        = "ai governance infrastructure all"
      DRY_RUN         = "true"  # Dry run for simulation
    }
  }

  lifecycle {
    ignore_changes = all
  }
}

# Output deployment status
output "deployment_status" {
  value = {
    orchestration_method = "Script-based (local-exec + SSH)"
    deployment_script    = abspath("${path.module}/../../scripts/ops/deploy-via-ssh.sh")
    primary_host         = var.primary_host
    replica_host         = var.replica_host != "" ? var.replica_host : "Not configured"
    deployment_user      = var.ssh_user
    deployment_port      = var.ssh_port
    force_recreate       = var.force_recreate
    profiles             = "ai governance infrastructure all"
    status               = "DEPLOYED via script-based orchestration"
  }
  description = "Deployment orchestration status and configuration"
}

# Output deployment log location
output "deployment_log_location" {
  value = "artifacts/deployment-*.log"
  description = "Location of deployment logs (created after execution)"
}
