variable "namespace_monitoring" {
  type        = string
  description = "Monitoring namespace"
  default     = "monitoring"
}

variable "namespace_security" {
  type        = string
  description = "Security namespace"
  default     = "security"
}

variable "namespace_backup" {
  type        = string
  description = "Backup namespace"
  default     = "backup-system"
}

variable "namespace_code_server" {
  type        = string
  description = "code-server namespace"
  default     = "code-server"
}

variable "namespace_ingress" {
  type        = string
  description = "Ingress namespace"
  default     = "ingress-nginx"
}

variable "namespace_cert_manager" {
  type        = string
  description = "Cert-manager namespace"
  default     = "cert-manager"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "production"
}

variable "enable_monitoring" {
  type        = bool
  description = "Enable monitoring namespace"
  default     = true
}

variable "enable_security" {
  type        = bool
  description = "Enable security namespace"
  default     = true
}

variable "enable_backup" {
  type        = bool
  description = "Enable backup namespace"
  default     = true
}

variable "enable_code_server" {
  type        = bool
  description = "Enable code-server namespace"
  default     = true
}

variable "enable_ingress" {
  type        = bool
  description = "Enable ingress namespace"
  default     = true
}
