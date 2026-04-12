terraform {
  required_version = ">= 1.5.0"
}

locals {
  service_name = "code-server-enterprise"
}

output "deployment_model" {
  description = "How runtime is managed"
  value = {
    runtime_orchestrator = "docker-compose"
    terraform_role       = "metadata-and-outputs"
    service_name         = local.service_name
  }
}

output "code_server_url" {
  description = "Primary IDE URL"
  value       = "https://${var.domain}"
}

output "code_server_password" {
  description = "Optional Terraform-level password output. Runtime uses .env/Compose variables."
  value       = var.code_server_password != null ? var.code_server_password : "managed-via-.env"
  sensitive   = true
}

output "compose_project_name" {
  description = "Compose project label used by operational scripts"
  value       = var.compose_project_name
}
