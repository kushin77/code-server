# terraform/environments/private/variables.tf
# @description Private deployment variables

variable "apex_domain" {
  type        = string
  description = "Organization's apex domain (e.g., example.com)"
}

variable "primary_host" {
  type        = string
  description = "Primary deployment host IP"
}

variable "replica_host" {
  type        = string
  default     = ""
  description = "Replica host for HA (optional)"
}

variable "nas_host" {
  type        = string
  default     = ""
  description = "NAS/storage host IP (optional)"
}

variable "admin_email" {
  type        = string
  description = "Administrator email for ACME"
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
