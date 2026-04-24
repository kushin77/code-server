output "homeserver_url" {
  value       = "https://${var.matrix_domain}"
  description = "URL of the Matrix homeserver"
}

output "postgres_host" {
  value       = docker_container.postgres.name
  description = "PostgreSQL hostname"
}

output "postgres_port" {
  value       = 5432
  description = "PostgreSQL port"
}

output "synapse_admin_token" {
  value       = var.synapse_admin_token
  description = "Admin token for server administration"
  sensitive   = true
}

output "synapse_container_id" {
  value       = docker_container.synapse.id
  description = "Docker container ID for Synapse"
}
