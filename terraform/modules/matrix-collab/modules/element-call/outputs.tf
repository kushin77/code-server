output "element_call_url" {
  value       = "https://call.${var.apex_domain}"
  description = "URL for Element Call service"
}

output "element_call_container_id" {
  value       = docker_container.element_call.id
  description = "Docker container ID for Element Call"
}
