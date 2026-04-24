output "presence_sidecar_url" {
  value       = "http://presence-sidecar:9000"
  description = "Presence sidecar service URL"
}

output "presence_sidecar_container_id" {
  value       = docker_container.presence_sidecar.id
  description = "Docker container ID for presence sidecar"
}
