output "homeserver_url" {
  value       = module.homeserver.homeserver_url
  description = "URL of the Matrix homeserver"
}

output "element_url" {
  value       = module.element.element_url
  description = "URL of the Element web client"
}

output "synapse_admin_token" {
  value       = module.homeserver.synapse_admin_token
  description = "Admin token for Synapse server"
  sensitive   = true
}

output "postgres_host" {
  value       = module.homeserver.postgres_host
  description = "PostgreSQL host for Synapse"
}

output "postgres_port" {
  value       = module.homeserver.postgres_port
  description = "PostgreSQL port for Synapse"
}

output "redis_url" {
  value       = var.redis_url
  description = "Redis connection URL"
}

output "bridges_enabled" {
  value = {
    slack       = var.enable_slack_bridge
    teams       = var.enable_teams_bridge
    google_chat = var.enable_google_chat_bridge
  }
  description = "Status of enabled bridges"
}

output "presence_sidecar_enabled" {
  value       = var.enable_presence_sidecar
  description = "Whether presence sidecar is enabled"
}

output "element_call_enabled" {
  value       = var.enable_element_call
  description = "Whether Element Call is enabled"
}

output "all_service_urls" {
  value = {
    homeserver = module.homeserver.homeserver_url
    element    = module.element.element_url
    matrix_api = "${module.homeserver.homeserver_url}/_matrix"
  }
  description = "All service URLs"
}
