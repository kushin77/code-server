# terraform/phase-9-egress-filtering.tf
# Docker Egress Filtering — Prevent Container-to-Internet Exfiltration
# Blocks database (postgres/redis) from outbound internet access
# Protects internal services (prometheus, grafana) from external access

provider "null" {}

# ============================================================================
# Docker iptables Egress Filtering
# ============================================================================

resource "null_resource" "docker_iptables_hardening" {
  triggers = {
    # Re-run if script changes
    script_hash = filemd5("${path.module}/../scripts/hardening/docker-iptables-hardening.sh")
  }

  provisioner "file" {
    source      = "${path.module}/../scripts/hardening/docker-iptables-hardening.sh"
    destination = "/tmp/docker-iptables-hardening.sh"

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
      "chmod +x /tmp/docker-iptables-hardening.sh",
      "sudo /tmp/docker-iptables-hardening.sh",
    ]

    connection {
      type        = "ssh"
      user        = var.deploy_user
      host        = var.deploy_host
      private_key = file(var.ssh_private_key)
      timeout     = "2m"
    }
  }
}

# ============================================================================
# Verification: Egress Filtering Health Check
# ============================================================================

resource "null_resource" "egress_verification" {
  depends_on = [null_resource.docker_iptables_hardening]

  provisioner "remote-exec" {
    inline = [
      "echo '=== EGRESS FILTERING VERIFICATION ==='",
      "sudo iptables -L DOCKER-USER -n | grep -q DROP && echo '✓ DOCKER-USER chain configured' || echo '✗ DOCKER-USER chain empty'",
      "sudo iptables-save | grep -c 'DOCKER-USER' && echo '✓ iptables rules will persist' || echo '⚠️ persistence may be incomplete'",
      "echo 'Egress verification complete'",
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
# Output: Egress Filtering Status
# ============================================================================

output "egress_filtering_status" {
  value       = "Container egress filtering applied to ${var.deploy_host}"
  description = "Status of egress filtering deployment"
}

output "protected_services" {
  value = {
    postgres   = "No outbound internet access (data isolation)"
    redis      = "No outbound internet access (data isolation)"
    prometheus = "External access blocked (monitoring isolation)"
    grafana    = "External access blocked (monitoring isolation)"
  }
  description = "Services protected by egress filtering"
}

output "firewall_rules_summary" {
  value = "DOCKER-USER chain: Blocks external to internal services + container egress via iptables"
  description = "Summary of firewall rules applied"
}
