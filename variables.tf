variable "code_server_password" {
  description = "Code-Server authentication password"
  type        = string
  default     = "secure-enterprise-password"
  sensitive   = true
}

variable "config_dir" {
  description = "Configuration directory path"
  type        = string
  default     = "."
}

variable "docker_host" {
  description = "Docker daemon socket"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "enable_https" {
  description = "Enable HTTPS/TLS"
  type        = bool
  default     = true
  
}

variable "code_server_version" {
  description = "Code-Server version tag (use specific version, not latest)"
  type        = string
  default     = "4.19.1"
}

variable "caddy_version" {
  description = "Caddy version tag (use specific version, not latest)"
  type        = string
  default     = "2.7.6"
}

variable "log_level" {
  description = "Logging level (debug, info, warn, error)"
  type        = string
  default     = "info"
  
  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "Log level must be one of: debug, info, warn, error."
  }
}
