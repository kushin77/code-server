# Phase 8: OS Hardening (#349)
# CIS Linux Benchmarks, fail2ban, auditd, AIDE, kernel hardening
# Immutable (pinned versions), Idempotent (safe to apply multiple times)
# On-prem deployment to 192.168.168.31

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

variable "primary_host_ip" {
  description = "Primary production host IP (on-prem)"
  type        = string
  default     = "192.168.168.31"
}

variable "enable_cis_hardening" {
  description = "Enable CIS Linux hardening"
  type        = bool
  default     = true
}

variable "enable_fail2ban" {
  description = "Enable fail2ban intrusion detection"
  type        = bool
  default     = true
}

variable "enable_auditd" {
  description = "Enable auditd audit logging"
  type        = bool
  default     = true
}

variable "enable_aide" {
  description = "Enable AIDE file integrity monitoring"
  type        = bool
  default     = true
}

# ============================================================================
# OS Hardening Scripts
# ============================================================================

# CIS Linux Hardening Script
resource "local_file" "cis_hardening_script" {
  filename = "${path.module}/../scripts/cis-linux-hardening.sh"
  content  = file("${path.module}/../scripts/cis-linux-hardening.sh")
}

# fail2ban Configuration
resource "local_file" "fail2ban_config" {
  filename = "${path.module}/../config/fail2ban-local.conf"
  content = templatefile("${path.module}/../templates/fail2ban-local.conf.tpl", {
    ssh_port        = 22
    http_port       = 80
    https_port      = 443
    max_retry       = 5
    find_time       = 600
    ban_time        = 3600
    code_server_port = 8080
  })
}

# auditd Rules Configuration
resource "local_file" "auditd_rules" {
  filename = "${path.module}/../config/audit.rules"
  content = templatefile("${path.module}/../templates/audit.rules.tpl", {
    watch_dirs = ["/etc", "/home", "/root", "/opt/code-server"]
    watch_files = ["/etc/sudoers", "/etc/shadow", "/etc/passwd"]
  })
}

# AIDE Configuration
resource "local_file" "aide_config" {
  filename = "${path.module}/../config/aide.conf.d-aide-hardened"
  content = templatefile("${path.module}/../templates/aide.conf.tpl", {
    monitored_dirs = [
      "/usr/bin",
      "/usr/sbin",
      "/bin",
      "/sbin",
      "/usr/lib",
      "/etc"
    ]
  })
}

# ============================================================================
# Deployment Script (idempotent, safe to run multiple times)
# ============================================================================

resource "local_file" "deploy_os_hardening" {
  filename = "${path.module}/../scripts/deploy-os-hardening.sh"
  content  = templatefile("${path.module}/../templates/deploy-os-hardening.sh.tpl", {
    primary_host     = var.primary_host_ip
    enable_cis       = var.enable_cis_hardening
    enable_fail2ban  = var.enable_fail2ban
    enable_auditd    = var.enable_auditd
    enable_aide      = var.enable_aide
  })
}

# ============================================================================
# Outputs
# ============================================================================

output "phase_8_os_hardening_status" {
  description = "Phase 8 OS Hardening deployment status"
  value = {
    cis_hardening    = var.enable_cis_hardening ? "ENABLED" : "DISABLED"
    fail2ban         = var.enable_fail2ban ? "ENABLED" : "DISABLED"
    auditd           = var.enable_auditd ? "ENABLED" : "DISABLED"
    aide             = var.enable_aide ? "ENABLED" : "DISABLED"
    target_host      = var.primary_host_ip
    deployment_ready = true
    immutable        = true
    idempotent       = true
  }
}

output "deployment_script" {
  description = "Path to deployment script"
  value       = local_file.deploy_os_hardening.filename
}
