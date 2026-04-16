#!/usr/bin/env terraform
# modules/core/variables.tf — Core application services (code-server, Caddy, OAuth2)

variable "host_ip" {
  description = "Host IP address for service binding"
  type        = string
  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.host_ip))
    error_message = "Must be a valid IP address (IPv4)."
  }
}

variable "domain" {
  description = "Primary domain (e.g., ide.kushnir.cloud)"
  type        = string
  validation {
    condition     = can(regex("^([a-z0-9]+(-[a-z0-9]+)*\\.)+[a-z]{2,}$", var.domain))
    error_message = "Must be a valid domain name."
  }
}

variable "code_server_port" {
  description = "Code-server application port"
  type        = number
  default     = 8080
  validation {
    condition     = var.code_server_port > 0 && var.code_server_port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

variable "code_server_version" {
  description = "Code-server Docker image version"
  type        = string
  default     = "4.115.0"
}

variable "code_server_memory_limit" {
  description = "Code-server memory limit"
  type        = string
  default     = "4g"
}

variable "code_server_cpu_limit" {
  description = "Code-server CPU limit (cores)"
  type        = string
  default     = "2.0"
}

variable "caddy_version" {
  description = "Caddy reverse proxy version"
  type        = string
  default     = "2.9.1-alpine"
}

variable "caddy_port_http" {
  description = "Caddy HTTP port"
  type        = number
  default     = 80
}

variable "caddy_port_https" {
  description = "Caddy HTTPS port"
  type        = number
  default     = 443
}

variable "caddy_admin_port" {
  description = "Caddy admin API port (loopback only)"
  type        = number
  default     = 2019
}

variable "caddy_auto_https" {
  description = "Enable automatic HTTPS (on/off/ignore_loaded_certs)"
  type        = string
  default     = "on"
  validation {
    condition     = contains(["on", "off", "ignore_loaded_certs"], var.caddy_auto_https)
    error_message = "Must be one of: on, off, ignore_loaded_certs."
  }
}

variable "caddy_tls_email" {
  description = "Email for Let's Encrypt certificates (if not internal CA)"
  type        = string
  default     = "ops@kushnir.cloud"
}

variable "oauth2_proxy_version" {
  description = "OAuth2-proxy version"
  type        = string
  default     = "7.5.1"
}

variable "oauth2_proxy_port" {
  description = "OAuth2-proxy listen port"
  type        = number
  default     = 4180
}

variable "oauth2_provider" {
  description = "OAuth2 provider (google, github, okta, etc)"
  type        = string
  default     = "google"
  validation {
    condition     = contains(["google", "github", "okta", "azuread"], var.oauth2_provider)
    error_message = "Must be a supported OAuth2 provider."
  }
}

variable "oauth2_callback_url" {
  description = "OAuth2 callback URL (for IDP configuration)"
  type        = string
  default     = "https://ide.kushnir.cloud/oauth2/callback"
}

variable "oauth2_memory_limit" {
  description = "OAuth2-proxy memory limit"
  type        = string
  default     = "256m"
}

variable "oauth2_cpu_limit" {
  description = "OAuth2-proxy CPU limit (cores)"
  type        = string
  default     = "0.25"
}
