# @file terraform/environments/air-gapped/variables.tf
# @description Variables for air-gapped (no internet) deployments

variable "local_registry_url" {
  description = "Local container registry URL (required for air-gapped)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9.-]+:[0-9]+$", var.local_registry_url))
    error_message = "local_registry_url must be in format 'host:port'."
  }
}

variable "image_mirror_path" {
  description = "Path where pre-pulled images are stored"
  type        = string
  default     = "/mnt/nas/air-gap/images"
}

variable "bypass_internet_checks" {
  description = "Skip internet connectivity validation"
  type        = bool
  default     = true
}

# Inherit from core
variable "apex_domain" {
  type = string
}

variable "primary_host" {
  type = string
}

variable "admin_email" {
  type = string
}
