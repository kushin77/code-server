# terraform/phase-8b-renovate-automation.tf
# Renovate Bot — automated dependency updates and vulnerability scanning
# Weekly dependency scanning with digest pinning and auto-merge for security updates

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "null" {}

# ============================================================================
# Renovate Configuration Deployment
# ============================================================================

resource "null_resource" "renovate_config_deploy" {
  triggers = {
    # Re-run if renovate config changes
    config_hash = filemd5("${path.module}/../.renovaterc.json")
  }

  provisioner "file" {
    source      = "${path.module}/../.renovaterc.json"
    destination = "/tmp/.renovaterc.json"

    connection {
      type        = "ssh"
      user        = var.deploy_user
      host        = var.deploy_host
      private_key = file(var.ssh_private_key)
      timeout     = "30s"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Renovate configuration deployed'",
      "# Config will be picked up by Renovate bot on GitHub",
      "echo 'Next: Install Renovate GitHub App at https://github.com/apps/renovate'",
    ]

    connection {
      type        = "ssh"
      user        = var.deploy_user
      host        = var.deploy_host
      private_key = file(var.ssh_private_key)
      timeout     = "30s"
    }
  }
}

# ============================================================================
# Renovate Verification
# ============================================================================

resource "null_resource" "renovate_verification" {
  depends_on = [null_resource.renovate_config_deploy]

  provisioner "remote-exec" {
    inline = [
      "echo '=== RENOVATE CONFIGURATION ==='",
      "cat /tmp/.renovaterc.json | head -20",
      "echo 'Configuration deployed successfully'",
    ]

    connection {
      type        = "ssh"
      user        = var.deploy_user
      host        = var.deploy_host
      private_key = file(var.ssh_private_key)
      timeout     = "30s"
    }
  }
}

# ============================================================================
# Output: Renovate Status
# ============================================================================

output "renovate_status" {
  value       = "Renovate configuration deployed to ${var.deploy_host}"
  description = "Status of Renovate bot deployment"
}

output "renovate_schedule" {
  value = {
    security_patches = "Auto-merge immediately"
    patch_versions   = "Auto-merge if tests pass (Monday 3:00 AM UTC)"
    minor_versions   = "Create PR, require manual review"
    major_versions   = "Create PR, detailed review required"
  }
  description = "Renovate update schedule and automation rules"
}

output "next_steps" {
  value = "1. Install Renovate GitHub App | 2. Authorize app on kushin77/code-server | 3. Renovate will auto-create renovate.json and scan dependencies"
  description = "Post-deployment steps for Renovate activation"
}
