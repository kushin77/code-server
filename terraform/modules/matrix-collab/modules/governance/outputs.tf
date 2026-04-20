# Outputs for Matrix Governance Module

output "admin_bot_id" {
  value       = try(docker_container.matrix_admin_bot[0].id, null)
  description = "Container ID of the Matrix admin bot"
}

output "admin_bot_status" {
  value       = try(docker_container.matrix_admin_bot[0].state[0].status, null)
  description = "Current status of the admin bot container"
}

output "audit_schema_name" {
  value       = try(postgresql_schema.audit_logging[0].name, null)
  description = "PostgreSQL schema name for audit logging"
}

output "space_templates_config_path" {
  value       = try(local_file.space_templates[0].filename, null)
  description = "Path to space templates configuration file"
}

output "moderation_config_path" {
  value       = try(local_file.moderation_config[0].filename, null)
  description = "Path to moderation configuration file"
}

output "retention_purge_container_id" {
  value       = try(docker_container.retention_purge_job[0].id, null)
  description = "Container ID of the retention purge job (if Docker-based)"
}

output "governance_module_summary" {
  value = {
    admin_bot_enabled           = var.enable_admin_bot
    retention_enabled           = var.enable_retention_policies
    space_templates_enabled     = var.enable_space_templates
    audit_logging_enabled       = var.enable_audit_logging
    moderation_enabled          = var.enable_moderation
    retention_purge_enabled     = var.enable_retention_purge_job
    default_retention_lifetime  = var.retention_default_max_lifetime
    audit_retention_days        = var.audit_retention_days
    rate_limit_messages_per_min = var.rate_limit_messages_per_minute
  }
  description = "Summary of governance module configuration"
}
