/**
 * Code-Server Infrastructure-as-Code Deployment
 * 
 * SHARED CLUSTER NAMESPACE CONSTRAINT:
 * This Terraform configuration manages ONLY code-server namespaced resources.
 * All containers are prefixed with "code-server-".
 * All networks created are isolated to this deployment.
 * No management of shared cluster workloads (e.g., hermes, other services).
 * 
 * Namespace Isolation:
 * - Networks: ingress, services, database (code-server only)
 * - Containers: code-server-* prefix (40+ services per host)
 * - No cross-namespace resource dependencies
 * - No management of external workloads
 */

terraform {
  required_version = ">= 1.6.0, < 1.15.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "= 3.0.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "= 2.4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "= 3.2.1"
    }
  }
}

variable "apex_domain" {
  type        = string
  description = "Primary domain for the deployment"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.apex_domain))
    error_message = "apex_domain must be a valid domain name (e.g., kushnir.cloud, internal.local)"
  }
}

variable "primary_host" {
  type        = string
  description = "Primary application host (IPv4 or FQDN)"

  validation {
    condition     = can(regex("^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}|([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]*[a-z0-9])?)$", var.primary_host))
    error_message = "primary_host must be a valid IPv4 address (e.g., 192.168.168.31) or FQDN (e.g., primary.local)"
  }
}

variable "replica_host" {
  type        = string
  description = "Replica application host (IPv4 or FQDN)"

  validation {
    condition     = can(regex("^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}|([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]*[a-z0-9])?)$", var.replica_host))
    error_message = "replica_host must be a valid IPv4 address (e.g., 192.168.168.42) or FQDN (e.g., replica.local)"
  }
}

variable "nas_host" {
  type        = string
  description = "NAS host for persistent data (IPv4 or FQDN)"

  validation {
    condition     = can(regex("^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}|([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]*[a-z0-9])?)$", var.nas_host))
    error_message = "nas_host must be a valid IPv4 address (e.g., 192.168.168.56) or FQDN (e.g., nas.local)"
  }
}

variable "registry_url" {
  type        = string
  description = "Internal registry URL"

  validation {
    condition     = can(regex("^(https?://)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]*[a-z0-9])?(:\\d+)?(/.*)?$", var.registry_url))
    error_message = "registry_url must be a valid URL (e.g., https://registry.local:5000 or registry.local:5000)"
  }
}

variable "admin_email" {
  type        = string
  description = "Admin contact email"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "admin_email must be a valid email address (e.g., admin@kushnir.cloud)"
  }
}

variable "deployment_mode" {
  type        = string
  description = "Deployment mode"

  validation {
    condition     = contains(["private", "air-gapped", "federated"], var.deployment_mode)
    error_message = "deployment_mode must be private, air-gapped, or federated"
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for remote state and infrastructure"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Environment name for tagging"
  default     = "production"
}

variable "kubeconfig_path" {
  type        = string
  description = "Path to Kubernetes configuration file"
  default     = "~/.kube/config"
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

# ============================================================================
# FULL STACK — PRIMARY HOST (192.168.168.31)
# All 40 containers declared as Terraform resources on the primary host.
# terraform plan  → shows every container diff
# terraform apply → creates/updates/destroys containers declaratively
# ============================================================================

module "primary" {
  source = "./modules/stack"

  providers = {
    docker = docker.primary
  }

  host_role        = "primary"
  remote_repo_path = var.primary_repo_path
  deployment_mode  = var.deployment_mode

  # Domain
  apex_domain = var.apex_domain
  tls_email   = var.admin_email
  auth_domain = "auth.${var.apex_domain}"
  log_level   = var.log_level

  # Registry
  registry_url  = var.registry_url
  app_image_tag = var.app_image_tag

  # Secrets
  db_user                = var.db_user
  db_password            = var.db_password
  db_name                = var.db_name
  redis_password         = var.redis_password
  grafana_admin_user     = var.grafana_admin_user
  grafana_admin_password = var.grafana_admin_password
  qdrant_api_key         = var.qdrant_api_key
  scheduler_api_key      = var.scheduler_api_key
  oauth2_client_id       = var.oauth2_client_id
  oauth2_client_secret   = var.oauth2_client_secret
  oauth2_cookie_secret   = var.oauth2_cookie_secret

  # Observability
  prometheus_retention_days = var.prometheus_retention_days

  # App-tier
  code_server_password = var.code_server_password
  minio_root_user      = var.minio_root_user
  minio_root_password  = var.minio_root_password
  vault_token          = var.vault_token
  gitlab_runner_token  = var.gitlab_runner_token
}

# ============================================================================
# FULL STACK — REPLICA HOST (192.168.168.42)
# Identical stack on the replica. Edge agent gets a different ID.
# ============================================================================

module "replica" {
  source = "./modules/stack"

  providers = {
    docker = docker.replica
  }

  host_role        = "replica"
  remote_repo_path = var.replica_repo_path
  deployment_mode  = var.deployment_mode

  # Domain
  apex_domain = var.apex_domain
  tls_email   = var.admin_email
  auth_domain = "auth.${var.apex_domain}"
  log_level   = var.log_level

  # Registry
  registry_url  = var.registry_url
  app_image_tag = var.app_image_tag

  # Secrets
  db_user                = var.db_user
  db_password            = var.db_password
  db_name                = var.db_name
  redis_password         = var.redis_password
  grafana_admin_user     = var.grafana_admin_user
  grafana_admin_password = var.grafana_admin_password
  qdrant_api_key         = var.qdrant_api_key
  scheduler_api_key      = var.scheduler_api_key
  oauth2_client_id       = var.oauth2_client_id
  oauth2_client_secret   = var.oauth2_client_secret
  oauth2_cookie_secret   = var.oauth2_cookie_secret

  # Observability
  prometheus_retention_days = var.prometheus_retention_days

  # App-tier
  code_server_password = var.code_server_password
  minio_root_user      = var.minio_root_user
  minio_root_password  = var.minio_root_password
  vault_token          = var.vault_token
  gitlab_runner_token  = var.gitlab_runner_token
}
