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
  type        = string
  description = "Primary domain for the deployment"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.apex_domain))
    error_message = "apex_domain must be a valid domain name (e.g., internal.local)"
  }
}

variable "primary_host" {
  type        = string
  description = "Primary application host (IPv4 or FQDN)"

  validation {
    condition     = can(regex("^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}|([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]*[a-z0-9])?)$", var.primary_host))
    error_message = "primary_host must be a valid IPv4 address (e.g., 10.0.0.10) or FQDN (e.g., primary.local)"
  }
}

variable "admin_email" {
  type        = string
  description = "Admin contact email"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "admin_email must be a valid email address (e.g., admin@internal.local)"
  }
}
