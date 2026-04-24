#!/usr/bin/env hcl
# @file        terraform/modules/whitelabel-customer/main.tf
# @module      terraform/whitelabel
# @description Terraform module for per-customer whitelabel deployment

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

variable "customer_id" {
  type        = string
  description = "Unique customer identifier"
}

variable "apex_domain" {
  type        = string
  description = "Apex domain (e.g., acme-corp.com)"
}

variable "email_domain" {
  type        = string
  description = "Email domain for OAuth access control"
}

variable "oauth_provider" {
  type        = string
  description = "OAuth provider (google, okta, azure-ad)"
  default     = "google"
}

variable "nas_path" {
  type        = string
  description = "NAS storage path for customer data"
  default     = "/nas/persistent"
}

variable "database_name" {
  type        = string
  description = "PostgreSQL database name"
}

variable "replicas" {
  type        = number
  description = "Number of deployment replicas"
  default     = 2
}

variable "ha_enabled" {
  type        = bool
  description = "Enable high availability mode"
  default     = true
}

variable "environment" {
  type        = string
  description = "Environment (staging, production)"
  default     = "production"
}

# Output values
output "customer_id" {
  value       = var.customer_id
  description = "Customer identifier"
}

output "apex_domain" {
  value       = var.apex_domain
  description = "Apex domain"
}

output "ide_domain" {
  value       = "ide.${var.apex_domain}"
  description = "IDE subdomain"
}

output "auth_domain" {
  value       = "auth.${var.apex_domain}"
  description = "Auth subdomain"
}

output "api_domain" {
  value       = "api.${var.apex_domain}"
  description = "API subdomain"
}

output "database_name" {
  value       = var.database_name
  description = "PostgreSQL database"
}

output "nas_path" {
  value       = "${var.nas_path}/${var.customer_id}"
  description = "NAS path for customer data"
}

# Local values for templating
locals {
  deployment_name = "elevatediq-${var.customer_id}"
  
  tags = {
    Customer    = var.customer_id
    Environment = var.environment
    ManagedBy   = "Terraform"
    Module      = "whitelabel-customer"
  }

  docker_compose_override = templatefile("${path.module}/docker-compose.override.yml.tpl", {
    customer_id       = var.customer_id
    apex_domain       = var.apex_domain
    database_name     = var.database_name
    oauth_provider    = var.oauth_provider
    email_domain      = var.email_domain
  })

  caddyfile_config = templatefile("${path.module}/Caddyfile.tpl", {
    apex_domain      = var.apex_domain
    customer_id      = var.customer_id
  })

  env_vars = templatefile("${path.module}/.env.tpl", {
    customer_id      = var.customer_id
    apex_domain      = var.apex_domain
    email_domain     = var.email_domain
    oauth_provider   = var.oauth_provider
    database_name    = var.database_name
  })
}

# Store generated configs in outputs for manual deployment
output "docker_compose_config" {
  value       = local.docker_compose_override
  description = "Generated docker-compose.override.yml"
  sensitive   = false
}

output "caddyfile_config" {
  value       = local.caddyfile_config
  description = "Generated Caddyfile"
  sensitive   = false
}

output "env_vars" {
  value       = local.env_vars
  description = "Generated .env variables"
  sensitive   = true
}

# Optional: Create DNS records in Route53 or Cloud DNS
output "dns_records_required" {
  value = [
    {
      name    = var.apex_domain
      type    = "A"
      value   = "Load Balancer IP"
      comment = "Apex domain"
    },
    {
      name    = "ide.${var.apex_domain}"
      type    = "A"
      value   = "Load Balancer IP"
      comment = "IDE"
    },
    {
      name    = "auth.${var.apex_domain}"
      type    = "A"
      value   = "Load Balancer IP"
      comment = "OAuth2 proxy"
    },
    {
      name    = "api.${var.apex_domain}"
      type    = "A"
      value   = "Load Balancer IP"
      comment = "API"
    },
  ]
  description = "DNS records to create for customer deployment"
}

# Output data isolation summary
output "data_isolation_summary" {
  value = {
    customer_id     = var.customer_id
    database        = var.database_name
    nas_path        = "${var.nas_path}/${var.customer_id}"
    redis_prefix    = "elevatediq:${var.customer_id}:"
    kafka_prefix    = "elevatediq-${var.customer_id}-"
    replicas        = var.replicas
    ha_enabled      = var.ha_enabled
  }
  description = "Data isolation configuration"
}
