variable "falco_version" {
  description = "Falco runtime security engine version"
  type        = string
  default     = "0.37.1"
}

variable "falco_mode" {
  description = "Falco execution mode (modern-bpf/legacy)"
  type        = string
  default     = "modern-bpf"
}

variable "falco_memory_limit" {
  description = "Falco container memory limit"
  type        = string
  default     = "512m"
}

variable "falco_cpu_limit" {
  description = "Falco container CPU limit"
  type        = string
  default     = "0.5"
}

variable "vault_version" {
  description = "HashiCorp Vault version"
  type        = string
  default     = "1.15.0"
}

variable "vault_port" {
  description = "Vault HTTP port"
  type        = number
  default     = 8200
}

variable "vault_memory_limit" {
  description = "Vault container memory limit"
  type        = string
  default     = "512m"
}

variable "vault_cpu_limit" {
  description = "Vault container CPU limit"
  type        = string
  default     = "0.5"
}

variable "vault_max_lease_ttl" {
  description = "Vault max lease TTL (hours)"
  type        = number
  default     = 168
}

variable "vault_default_lease_ttl" {
  description = "Vault default lease TTL (hours)"
  type        = number
  default     = 24
}

variable "opa_version" {
  description = "Open Policy Agent version"
  type        = string
  default     = "0.58.0"
}

variable "opa_port" {
  description = "OPA HTTP port"
  type        = number
  default     = 8181
}

variable "opa_memory_limit" {
  description = "OPA container memory limit"
  type        = string
  default     = "256m"
}

variable "opa_cpu_limit" {
  description = "OPA container CPU limit"
  type        = string
  default     = "0.25"
}

variable "enable_apparmor" {
  description = "Enable AppArmor security profiles"
  type        = bool
  default     = true
}

variable "enable_seccomp" {
  description = "Enable seccomp system call filtering"
  type        = bool
  default     = true
}

variable "enable_selinux" {
  description = "Enable SELinux (if available on OS)"
  type        = bool
  default     = false
}

variable "enable_runtime_monitoring" {
  description = "Enable Falco runtime security monitoring"
  type        = bool
  default     = true
}

variable "enable_policy_enforcement" {
  description = "Enable OPA policy enforcement"
  type        = bool
  default     = true
}

variable "enable_secret_management" {
  description = "Enable Vault secret management"
  type        = bool
  default     = true
}

variable "audit_log_retention_days" {
  description = "Security audit log retention (days)"
  type        = number
  default     = 90
}

variable "vulnerability_scan_enabled" {
  description = "Enable automated vulnerability scanning"
  type        = bool
  default     = true
}

variable "container_image_scan_enabled" {
  description = "Enable container image scanning"
  type        = bool
  default     = true
}
