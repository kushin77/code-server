variable "domain" {
  description = "Public domain used by Caddy and oauth2-proxy"
  type        = string
  default     = "ide.kushnir.cloud"

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+$", var.domain))
    error_message = "domain must be a valid hostname string."
  }
}

variable "compose_project_name" {
  description = "Logical project name for Compose-managed runtime"
  type        = string
  default     = "code-server-enterprise"
}

variable "code_server_password" {
  description = "Optional password output for Terraform. Prefer setting CODE_SERVER_PASSWORD in .env instead of tfvars."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true

  validation {
    condition     = var.code_server_password == null || length(var.code_server_password) >= 16
    error_message = "If set, code_server_password must be at least 16 characters."
  }
}
