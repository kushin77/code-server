# Security Module Outputs

output "falco_endpoint" {
  description = "Falco runtime security status"
  value       = "Daemonset deployed on all nodes"
}

output "opa_endpoint" {
  description = "OPA policy engine endpoint"
  value       = var.docker_host == "" ? "http://opa.${var.namespace}.svc.cluster.local:8181" : "http://localhost:8181"
}

output "vault_endpoint" {
  description = "Vault secret management endpoint"
  value       = var.docker_host == "" ? "http://vault.${var.namespace}.svc.cluster.local:8200" : "http://localhost:8200"
}

output "security_namespace" {
  description = "Security namespace"
  value       = var.namespace
}

output "falco_version" {
  description = "Falco version deployed"
  value       = var.falco_version
}

output "opa_version" {
  description = "OPA version deployed"
  value       = var.opa_version
}

output "vault_version" {
  description = "Vault version deployed"
  value       = var.vault_version
}

output "vault_mode" {
  description = "Vault runtime mode"
  value       = var.vault_mode
}

output "vault_unseal_keys_count" {
  description = "Number of Vault unseal keys"
  value       = var.vault_unseal_keys
}

output "vault_key_threshold" {
  description = "Keys required to unseal Vault"
  value       = var.vault_key_threshold
}

output "os_hardening_level" {
  description = "OS hardening level applied"
  value       = var.os_hardening_level
}

output "selinux_enabled" {
  description = "SELinux enforcement status"
  value       = var.selinux_enabled
}
