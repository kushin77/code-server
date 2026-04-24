output "element_url" {
  value       = "https://element.${var.apex_domain}"
  description = "URL of the Element web client"
}

output "element_container_id" {
  value       = docker_container.element.id
  description = "Docker container ID for Element"
}
