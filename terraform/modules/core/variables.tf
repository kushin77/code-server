# @file terraform/modules/core/variables.tf
# @description Variables for core networking, DNS, and gateway module
# @governance GOV-002: Parameterized IaC, zero hardcoding

variable "apex_domain" {
  description = "Organization's apex domain"
  type        = string
}

variable "primary_host" {
  description = "Primary host IP/hostname"
  type        = string
}

variable "replica_host" {
  description = "Replica host IP/hostname"
  type        = string
  default     = ""
}

variable "admin_email" {
  description = "Administrator email for Let's Encrypt"
  type        = string
}

variable "enable_tls" {
  description = "Enable TLS with Let's Encrypt"
  type        = bool
  default     = false
}

variable "caddy_image" {
  description = "Caddy container image"
  type        = string
  default     = "caddy:2.7.4-alpine"
}

variable "deployment_mode" {
  description = "Deployment mode: private | air-gapped | federated"
  type        = string
  default     = "private"
}

variable "log_level" {
  description = "Caddy log level"
  type        = string
  default     = "info"
}

variable "tags" {
  description = "Common tags for resources"
  type        = map(string)
  default     = {}
}
