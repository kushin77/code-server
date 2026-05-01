/**
 * @file modules/stack/variables.tf
 * @description Input variables for the full container stack module.
 *              Called once per host (primary + replica) with different docker provider aliases.
 */

variable "host_role" {
  type        = string
  description = "Host role: primary or replica"
  validation {
    condition     = contains(["primary", "replica"], var.host_role)
    error_message = "host_role must be primary or replica"
  }
}

variable "remote_repo_path" {
  type        = string
  description = "Absolute path where this repo is checked out on the remote host"
  default     = "/home/akushnir/code-server"
}

variable "deployment_mode" {
  type        = string
  description = "Deployment mode used for resource tagging"
  default     = "private"

  validation {
    condition     = contains(["private", "air-gapped", "federated"], var.deployment_mode)
    error_message = "deployment_mode must be private, air-gapped, or federated"
  }
}

variable "registry_url" {
  type        = string
  description = "Internal container registry for custom-built app images"
  default     = "registry.kushnir.cloud:5000"
}

variable "app_image_tag" {
  type        = string
  description = "Tag for all custom-built application images"
  default     = "latest"
}

# ── Domain & TLS ─────────────────────────────────────────────────────────────
variable "apex_domain" {
  type    = string
  default = "kushnir.cloud"
}

variable "tls_email" {
  type    = string
  default = "ops@kushnir.cloud"
}

variable "auth_domain" {
  type    = string
  default = "auth.kushnir.cloud"
}

variable "log_level" {
  type    = string
  default = "info"
}

# ── Database ──────────────────────────────────────────────────────────────────
variable "db_user" {
  type      = string
  sensitive = false
  default   = "postgres"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_name" {
  type    = string
  default = "code_server"
}

# ── Redis ─────────────────────────────────────────────────────────────────────
variable "redis_password" {
  type      = string
  sensitive = true
  default   = ""
}

# ── Observability ─────────────────────────────────────────────────────────────
variable "grafana_admin_user" {
  type    = string
  default = "admin"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "prometheus_retention_days" {
  type    = number
  default = 30
}

# ── API keys / Secrets ────────────────────────────────────────────────────────
variable "qdrant_api_key" {
  type      = string
  sensitive = true
}

variable "scheduler_api_key" {
  type      = string
  sensitive = true
}

variable "oauth2_client_id" {
  type    = string
  default = ""
}

variable "oauth2_client_secret" {
  type      = string
  sensitive = true
  default   = ""
}

variable "oauth2_cookie_secret" {
  type      = string
  sensitive = true
}

# ── Edge Agent ────────────────────────────────────────────────────────────────
variable "edge_agent_id" {
  type    = string
  default = ""  # Computed from host_role below in locals
}

# ── Alert Relay ───────────────────────────────────────────────────────────────
variable "slack_webhook" {
  type      = string
  sensitive = true
  default   = "https://hooks.slack.com/services/PLACEHOLDER"
}

variable "smtp_host" {
  type    = string
  default = "smtp.kushnir.cloud"
}

variable "smtp_port" {
  type    = string
  default = "587"
}

variable "smtp_user" {
  type    = string
  default = "alertmanager@kushnir.cloud"
}

variable "smtp_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "smtp_from" {
  type    = string
  default = "alertmanager@kushnir.cloud"
}

variable "pagerduty_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "custom_webhook_url" {
  type    = string
  default = ""
}

# ── App-tier services ─────────────────────────────────────────────────────────
variable "code_server_password" {
  type      = string
  sensitive = true
  default   = "password123"
}

variable "minio_root_user" {
  type    = string
  default = "minioadmin"
}

variable "minio_root_password" {
  type      = string
  sensitive = true
  default   = "minioadmin"
}

variable "vault_token" {
  type      = string
  sensitive = true
  default   = "devtoken"
}

variable "gitlab_runner_token" {
  type      = string
  sensitive = true
  default   = ""
}
