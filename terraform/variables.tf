/**
 * @file terraform/variables.tf
 * @description Global variable definitions for the Terraform infrastructure.
 */

variable "environment" {
  type        = string
  description = "Deployment environment (production/staging/development)"
  default     = "production"
  
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be production, staging, or development."
  }
}


variable "kubeconfig_path" {
  type        = string
  description = "Path to Kubernetes configuration file"
  default     = "~/.kube/config"
}

variable "common_tags" {
  type        = map(string)
  description = "Common tags applied to Terraform-managed resources"
  default     = {}
}

# version=pinned
variable "terraform_version_pin" {
  type        = string
  description = "Explicit version pinning for infrastructure health check"
  default     = "1.7.0"
}
