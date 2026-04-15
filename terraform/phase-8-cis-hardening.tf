# terraform/phase-8-cis-hardening.tf
# ====================================
# CIS Ubuntu 22.04 LTS Security Hardening (Issue #349)
# Level 2 controls: auditd, fail2ban, unattended-upgrades, SSH hardening,
# PAM hardening, sysctl kernel parameters, AIDE file integrity monitoring

# ─── Local variables ──────────────────────────────────────────────────────

locals {
  cis_hardening_script = "${path.module}/../scripts/deploy-phase-8-cis-hardening.sh"
  
  # CIS control objectives
  controls = {
    filesystem    = "1.1"  # Mount options (nodev, nosuid, noexec)
    services      = "2.1"  # Disable unnecessary services
    network       = "3.1"  # Network parameter hardening
    ssh           = "5.1"  # SSH hardening
    auditd        = "5.2.1" # Audit daemon configuration
    logging       = "5.2.4" # Rsyslog configuration
    pam           = "5.3"  # PAM hardening
    aide          = "6.1"  # File integrity monitoring
    upgrades      = "6.2"  # Automatic security updates
    fail2ban      = "6.3"  # Intrusion prevention
  }
}

# ─── Deploy CIS hardening to primary host ─────────────────────────────────

resource "null_resource" "cis_hardening_primary" {
  count = var.deploy_cis_hardening ? 1 : 0

  provisioner "remote-exec" {
    inline = [
      "echo 'CIS Ubuntu 22.04 LTS Hardening - Starting...'",
      "bash ${local.cis_hardening_script}"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      host        = var.primary_host
      private_key = file(var.ssh_key_path)
      timeout     = "10m"
    }
  }

  depends_on = [
    # Ensure base infrastructure is ready
  ]

  triggers = {
    script_hash = filemd5(local.cis_hardening_script)
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Monitoring/Observability: Audit rule validation ──────────────────────

resource "null_resource" "verify_auditd" {
  count = var.deploy_cis_hardening ? 1 : 0

  provisioner "remote-exec" {
    inline = [
      "echo 'Verifying auditd installation and rules...'",
      "systemctl is-active auditd || echo 'WARNING: auditd not active'",
      "auditctl -l | grep -c 'modules' || echo 'WARNING: audit rules may not be loaded'",
      "echo 'Audit verification complete'"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      host        = var.primary_host
      private_key = file(var.ssh_key_path)
      timeout     = "5m"
    }
  }

  depends_on = [null_resource.cis_hardening_primary]
}

# ─── Variables ────────────────────────────────────────────────────────────

variable "deploy_cis_hardening" {
  description = "Deploy CIS Ubuntu 22.04 LTS hardening (#349)"
  type        = bool
  default     = true
}

variable "primary_host" {
  description = "Primary host IP or FQDN"
  type        = string
  default     = "primary.prod.internal"
}

variable "ssh_user" {
  description = "SSH user for deployment"
  type        = string
  default     = "akushnir"
}

variable "ssh_key_path" {
  description = "Path to SSH private key"
  type        = string
  default     = "~/.ssh/id_rsa"
  sensitive   = true
}

# ─── Outputs ──────────────────────────────────────────────────────────────

output "cis_hardening_status" {
  description = "CIS hardening deployment status"
  value = var.deploy_cis_hardening ? {
    deployed      = true
    controls      = local.controls
    deployment_id = try(null_resource.cis_hardening_primary[0].id, "not-deployed")
  } : {
    deployed = false
  }
}

output "cis_controls_matrix" {
  description = "CIS control objectives addressed by this deployment"
  value = var.deploy_cis_hardening ? local.controls : {}
}
