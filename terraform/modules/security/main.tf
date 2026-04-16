// Security Module — Falco, Vault, OPA, OS Hardening
// Provides runtime security, policy enforcement, and secret management

locals {
  falco_config = {
    version      = var.falco_version
    mode         = var.falco_mode
    memory_limit = var.falco_memory_limit
    cpu_limit    = var.falco_cpu_limit
  }

  vault_config = {
    version           = var.vault_version
    port              = var.vault_port
    memory_limit      = var.vault_memory_limit
    cpu_limit         = var.vault_cpu_limit
    max_lease_ttl     = var.vault_max_lease_ttl
    default_lease_ttl = var.vault_default_lease_ttl
  }

  opa_config = {
    version      = var.opa_version
    port         = var.opa_port
    memory_limit = var.opa_memory_limit
    cpu_limit    = var.opa_cpu_limit
  }

  hardening_config = {
    apparmor = var.enable_apparmor
    seccomp  = var.enable_seccomp
    selinux  = var.enable_selinux
  }

  security_features = {
    runtime_monitoring = var.enable_runtime_monitoring
    policy_enforcement = var.enable_policy_enforcement
    secret_management  = var.enable_secret_management
  }

  compliance_config = {
    audit_log_retention = var.audit_log_retention_days
    vuln_scanning       = var.vulnerability_scan_enabled
    image_scanning      = var.container_image_scan_enabled
  }
}

// Note: Falco, Vault, and OPA provisioning via docker-compose.yml
// This module defines security policies, access controls, and monitoring parameters
// Future: Integrate with Kubernetes Pod Security Policies or network policies when scaling
