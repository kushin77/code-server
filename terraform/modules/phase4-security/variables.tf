# Phase 4: Variables for Security & RBAC

variable "namespace_monitoring" {
  type        = string
  description = "Kubernetes namespace for monitoring stack"
  default     = "monitoring"
}

variable "namespace_security" {
  type        = string
  description = "Kubernetes namespace for security tools"
  default     = "security"
}

variable "namespace_code_server" {
  type        = string
  description = "Kubernetes namespace for code-server"
  default     = "code-server"
}

variable "namespace_backup" {
  type        = string
  description = "Kubernetes namespace for backup/Velero"
  default     = "backup"
}

variable "environment" {
  type        = string
  description = "Environment name for labels"
  default     = "production"
}

variable "create_read_only_role" {
  type        = bool
  description = "Create read-only ClusterRole for monitoring/observation"
  default     = true
}

variable "create_developer_role" {
  type        = bool
  description = "Create developer ClusterRole for team access"
  default     = true
}

variable "create_admin_role" {
  type        = bool
  description = "Create admin ClusterRole for privileged operations"
  default     = true
}

variable "create_monitoring_sa" {
  type        = bool
  description = "Create ServiceAccount for monitoring"
  default     = true
}

variable "create_code_server_sa" {
  type        = bool
  description = "Create ServiceAccount for code-server"
  default     = true
}

variable "create_backup_sa" {
  type        = bool
  description = "Create ServiceAccount for backup/Velero"
  default     = true
}

variable "enable_network_policies" {
  type        = bool
  description = "Enable Kubernetes Network Policies for default-deny security"
  default     = true
}
