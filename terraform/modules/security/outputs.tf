output "falco_config" {
  description = "Falco runtime security engine configuration"
  value = {
    version      = local.falco_config.version
    mode         = local.falco_config.mode
    memory_limit = local.falco_config.memory_limit
    cpu_limit    = local.falco_config.cpu_limit
  }
}

output "vault_config" {
  description = "HashiCorp Vault secret management configuration"
  value = {
    version           = local.vault_config.version
    port              = local.vault_config.port
    memory_limit      = local.vault_config.memory_limit
    cpu_limit         = local.vault_config.cpu_limit
    max_lease_ttl     = "${local.vault_config.max_lease_ttl}h"
    default_lease_ttl = "${local.vault_config.default_lease_ttl}h"
    endpoint          = "http://vault:${local.vault_config.port}"
  }
}

output "opa_config" {
  description = "Open Policy Agent configuration"
  value = {
    version      = local.opa_config.version
    port         = local.opa_config.port
    memory_limit = local.opa_config.memory_limit
    cpu_limit    = local.opa_config.cpu_limit
    endpoint     = "http://opa:${local.opa_config.port}"
  }
}

output "hardening_controls" {
  description = "OS-level hardening controls enabled"
  value = {
    apparmor = local.hardening_config.apparmor
    seccomp  = local.hardening_config.seccomp
    selinux  = local.hardening_config.selinux
  }
}

output "security_features" {
  description = "Security features enabled"
  value = {
    runtime_monitoring = local.security_features.runtime_monitoring
    policy_enforcement = local.security_features.policy_enforcement
    secret_management  = local.security_features.secret_management
  }
}

output "compliance_posture" {
  description = "Compliance and audit configuration"
  value = {
    audit_log_retention_days = local.compliance_config.audit_log_retention
    vulnerability_scanning   = local.compliance_config.vuln_scanning
    container_image_scanning = local.compliance_config.image_scanning
  }
}
