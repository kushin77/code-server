output "oidc_config_path" {
  value       = local_file.synapse_oidc_config.filename
  description = "Path to Synapse OIDC configuration file"
}

output "oidc_patch_path" {
  value       = local_file.synapse_oidc_patch.filename
  description = "Path to homeserver.yaml OIDC configuration patch"
}

output "provisioning_script_path" {
  value       = local_file.user_provisioning_script.filename
  description = "Path to user provisioning script"
}

output "domain_restriction_config_path" {
  value       = local_file.domain_restriction_config.filename
  description = "Path to domain restriction configuration"
}

output "health_check_script_path" {
  value       = local_file.health_check.filename
  description = "Path to OIDC integration health check script"
}

output "sso_setup_guide_path" {
  value       = local_file.sso_setup_guide.filename
  description = "Path to SSO setup guide documentation"
}

output "oidc_provider_id" {
  value       = local.oidc_provider_id
  description = "OIDC provider identifier"
}

output "oidc_issuer" {
  value       = local.oidc_issuer
  description = "Google OIDC issuer URL"
}

output "allowed_domain" {
  value       = var.allowed_email_domain
  description = "Allowed email domain for SSO login"
}

output "auto_provisioning_enabled" {
  value       = var.auto_provision_users
  description = "Whether automatic user provisioning is enabled"
}

output "integration_status" {
  value       = "ready"
  description = "OIDC integration status (ready for deployment)"
}
