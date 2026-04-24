terraform {
  required_version = ">= 1.6.0"
}

variable "apex_domain" {
  type        = string
  description = "Primary domain for the deployment"
}

variable "primary_host" {
  type        = string
  description = "Primary application host"
}

variable "replica_host" {
  type        = string
  description = "Replica application host"
}

variable "nas_host" {
  type        = string
  description = "NAS host for persistent data"
}

variable "registry_url" {
  type        = string
  description = "Internal registry URL"
}

variable "admin_email" {
  type        = string
  description = "Admin contact email"
}

variable "deployment_mode" {
  type        = string
  description = "Deployment mode"

  validation {
    condition     = contains(["private", "air-gapped", "federated"], var.deployment_mode)
    error_message = "deployment_mode must be private, air-gapped, or federated"
  }
}

locals {
  deployment_profile = {
    private = {
      mode = "private"
    }
    "air-gapped" = {
      mode = "air-gapped"
    }
    federated = {
      mode = "federated"
    }
  }
}

output "deployment_mode" {
  value = var.deployment_mode
}

output "apex_domain" {
  value = var.apex_domain
}
