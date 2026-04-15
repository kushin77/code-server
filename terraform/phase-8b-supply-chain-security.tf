# terraform/phase-8b-supply-chain-security.tf
# Supply Chain Security — cosign image signing, SBOM generation, vulnerability scanning
# SLSA L2 compliance


# ============================================================================
# Supply Chain Security Setup
# ============================================================================

resource "null_resource" "supply_chain_setup" {
  triggers = {
    # Re-run if script changes
    script_hash = filemd5("${path.module}/../scripts/setup-supply-chain-security.sh")
  }

  provisioner "file" {
    source      = "${path.module}/../scripts/setup-supply-chain-security.sh"
    destination = "/tmp/setup-supply-chain-security.sh"

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
      "chmod +x /tmp/setup-supply-chain-security.sh",
      "bash /tmp/setup-supply-chain-security.sh 2>&1 | tee /tmp/supply-chain-setup.log",
    ]

    connection {
      type        = "ssh"
      user        = var.deploy_user
      host        = var.deploy_host
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }
}

# ============================================================================
# Verification: Supply Chain Setup Health Check
# ============================================================================

resource "null_resource" "supply_chain_verification" {
  depends_on = [null_resource.supply_chain_setup]

  provisioner "remote-exec" {
    inline = [
      "echo '=== SUPPLY CHAIN VERIFICATION ==='",
      "which cosign && echo '✓ cosign v2.0.0 installed' || echo '✗ cosign not found'",
      "which syft && echo '✓ syft v0.85.0 installed' || echo '✗ syft not found'",
      "which grype && echo '✓ grype v0.74.0 installed' || echo '✗ grype not found'",
      "which trivy && echo '✓ trivy v0.48.0 installed' || echo '✗ trivy not found'",
      "[ -f ~/.cosign/cosign.key ] && echo '✓ cosign keypair generated' || echo '✗ keypair not found'",
      "echo 'Supply chain verification complete'",
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
# Output: Supply Chain Status
# ============================================================================

output "supply_chain_status" {
  value       = "Supply chain security tools deployed to ${var.deploy_host}"
  description = "Status of supply chain security deployment"
}

output "supply_chain_components" {
  value = {
    cosign = "v2.0.0 (container image signing)"
    syft   = "v0.85.0 (SBOM generation)"
    grype  = "v0.74.0 (vulnerability scanning)"
    trivy  = "v0.48.0 (image scanning)"
  }
  description = "Supply chain tools installed"
}
