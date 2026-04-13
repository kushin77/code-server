# Phase 8: Variables for Verification & Validation

variable "environment" {
  type        = string
  description = "Environment name for labels"
  default     = "production"
}

variable "namespaces_to_verify" {
  type        = list(string)
  description = "Kubernetes namespaces to include in verification checks"
  default = [
    "monitoring",
    "security",
    "backup",
    "code-server",
    "ingress-nginx",
    "cert-manager",
    "kube-system",
    "default"
  ]
}

variable "create_health_check_script" {
  type        = bool
  description = "Create health check verification script"
  default     = true
}

variable "create_compliance_check_script" {
  type        = bool
  description = "Create compliance verification script"
  default     = true
}

variable "create_performance_benchmark" {
  type        = bool
  description = "Create performance benchmark script"
  default     = true
}

variable "create_cleanup_script" {
  type        = bool
  description = "Create cleanup script for test resources"
  default     = true
}

variable "create_verification_checklist" {
  type        = bool
  description = "Create verification checklist ConfigMap"
  default     = true
}

variable "verification_scripts_dir" {
  type        = string
  description = "Directory to store verification scripts"
  default     = "/tmp/k8s-verification"
}

variable "enable_monitoring" {
  type        = bool
  description = "Is monitoring stack enabled (for verification)"
  default     = true
}

variable "enable_code_server" {
  type        = bool
  description = "Is code-server enabled (for verification)"
  default     = true
}

variable "enable_ingress_controller" {
  type        = bool
  description = "Is ingress controller enabled (for verification)"
  default     = true
}
