# terraform/phase-9-host-hardening.tf
# CIS Ubuntu Hardening — Host Security Baseline
# Applies fail2ban, auditd, AIDE, kernel hardening, SSH hardening
# Runs on production host (192.168.168.31) via remote-exec provisioner

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
# CIS Hardening Script Execution
# ============================================================================

resource "null_resource" "cis_hardening" {
  triggers = {
    # Re-run if script changes
    script_hash = filemd5("${path.module}/../scripts/hardening/apply-cis-hardening.sh")
  }

  provisioner "file" {
    source      = "${path.module}/../scripts/hardening/apply-cis-hardening.sh"
    destination = "/tmp/apply-cis-hardening.sh"

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
      "chmod +x /tmp/apply-cis-hardening.sh",
      "sudo /tmp/apply-cis-hardening.sh",
    ]

    connection {
      type        = "ssh"
      user        = var.deploy_user
      host        = var.deploy_host
      private_key = file(var.ssh_private_key)
      timeout     = "5m"
    }
  }

  # Output results after provisioning
  provisioner "local-exec" {
    command = "echo 'CIS hardening applied to ${var.deploy_host}' >> /tmp/cis-hardening-terraform.log"
  }
}

# ============================================================================
# Verification: Post-Hardening Health Check
# ============================================================================

resource "null_resource" "hardening_verification" {
  depends_on = [null_resource.cis_hardening]

  provisioner "remote-exec" {
    inline = [
      "echo '=== HARDENING VERIFICATION ==='",
      "systemctl is-active fail2ban && echo '✓ fail2ban active' || echo '✗ fail2ban inactive'",
      "systemctl is-active auditd && echo '✓ auditd active' || echo '✗ auditd inactive'",
      "test -f /var/lib/aide/aide.db && echo '✓ AIDE database initialized' || echo '⚠ AIDE pending initialization'",
      "sysctl kernel.randomize_va_space | grep -q '2' && echo '✓ ASLR enabled' || echo '✗ ASLR disabled'",
      "sysctl net.ipv4.tcp_syncookies | grep -q '1' && echo '✓ SYN cookies enabled' || echo '✗ SYN cookies disabled'",
      "sshd -T | grep -q 'permitrootlogin no' && echo '✓ SSH root login disabled' || echo '✗ SSH root login enabled'",
      "echo 'Hardening verification complete'",
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
# Output: Hardening Status
# ============================================================================

output "hardening_status" {
  value       = "CIS hardening applied to ${var.deploy_host}"
  description = "Status of CIS Ubuntu hardening deployment"
}

output "hardening_components" {
  value = {
    fail2ban          = "Automated IP banning for SSH and OAuth brute-force"
    auditd            = "Privileged operation audit logging"
    aide              = "File integrity monitoring with daily checks"
    kernel_hardening  = "ASLR, SYN cookies, IP spoofing protection, etc."
    ssh_hardening     = "Root login disabled, strong ciphers, key-only auth"
  }
  description = "Hardening components applied"
}
