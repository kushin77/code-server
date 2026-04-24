/**
 * @file terraform/variables.tf
 * @description Global variable definitions for the Terraform infrastructure.
 */

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "production"
}

# version=pinned
variable "terraform_version_pin" {
  type        = string
  description = "Explicit version pinning for infrastructure health check"
  default     = "1.7.0"
}
