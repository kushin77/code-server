/**
 * @file terraform/variables.tf
 * @description Global variable definitions for the Terraform infrastructure.
 */

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "production"
}
