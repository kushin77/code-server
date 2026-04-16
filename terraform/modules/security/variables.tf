# Security Module - Falco, OPA, Vault, OS Hardening
# P2 #418 Phase 2 Implementation

variable "falco_version" {
  description = "Falco runtime security version"
  type        = string
  default     = "0.36.0"
}

variable "opa_version" {
  description = "OPA/Conftest policy engine version"
  type        = string
  default     = "0.55.0"
}

variable "vault_version" {
  description = "HashiCorp Vault version"
  type        = string
  default     = "1.15.0"
}

variable "vault_storage_size" {
  description = "Vault persistent volume size"
  type        = string
  default     = "10Gi"
}

variable "vault_unseal_keys" {
  description = "Number of Vault unseal keys to generate"
  type        = number
  default     = 5
}

variable "vault_key_threshold" {
  description = "Number of unseal keys required to unseal Vault"
  type        = number
  default     = 3
}

variable "os_hardening_level" {
  description = "OS hardening level (minimal, standard, strict)"
  type        = string
  default     = "standard"
}

variable "selinux_enabled" {
  description = "Enable SELinux enforcement"
  type        = bool
  default     = true
}

variable "auditd_enabled" {
  description = "Enable Linux audit daemon"
  type        = bool
  default     = true
}

variable "file_integrity_scan_interval" {
  description = "File integrity check interval (hours)"
  type        = number
  default     = 24
}

variable "vulnerability_scan_schedule" {
  description = "Vulnerability scan schedule (cron format)"
  type        = string
  default     = "0 2 * * *" # Daily at 2 AM
}

variable "labels" {
  description = "Common labels for all security resources"
  type        = map(string)
  default = {
    module     = "security"
    managed_by = "terraform"
  }
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "security"
}

variable "docker_host" {
  description = "Docker host for non-K8s deployments"
  type        = string
  default     = ""
}
