# terraform/environments/private/variables.tf
# @description Private deployment variables - supplementary to main.tf
# Note: Core variables (apex_domain, primary_host, replica_host, nas_host, admin_email) 
# are defined in main.tf to prevent duplication

variable "ssh_user" {
  type        = string
  default     = "akushnir"
  description = "SSH user for remote deployment"
}

variable "ssh_key" {
  type        = string
  default     = ""
  description = "SSH private key path for remote deployment (uses agent if empty)"
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port for remote hosts"
}

variable "enable_tls" {
  type        = bool
  default     = false
  description = "Enable TLS with Let's Encrypt"
}

variable "log_level" {
  type        = string
  default     = "info"
  description = "Log level: debug, info, warn, error"
}

variable "oauth2_cookie_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "OAuth2-proxy cookie secret (auto-generated if empty)"
}

variable "metrics_retention_days" {
  type        = number
  default     = 30
  description = "Prometheus metrics retention (days)"
}
