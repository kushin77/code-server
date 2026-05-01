# terraform/environments/private/variables.tf
# @description Private deployment variables - supplementary to main.tf
# Note: Core variables (apex_domain, primary_host, replica_host, nas_host, admin_email) 
# are defined in main.tf to prevent duplication

variable "ssh_user" {
  type        = string
  default     = "akushnir"
  description = "SSH user for remote deployment"
}

variable "ssh_key" {
  type        = string
  default     = ""
  description = "SSH private key path for remote deployment (uses agent if empty)"
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port for remote hosts (1-65535)"

  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1 and 65535"
  }
}

variable "enable_tls" {
  type        = bool
  default     = false
  description = "Enable TLS with Let's Encrypt"
}

variable "log_level" {
  type        = string
  default     = "info"
  description = "Log level: debug, info, warn, error"

  validation {
    condition     = contains(["debug", "info", "warn", "error"], lower(var.log_level))
    error_message = "log_level must be one of: debug, info, warn, error"
  }
}

variable "oauth2_cookie_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "OAuth2-proxy cookie secret (auto-generated if empty)"
}

variable "metrics_retention_days" {
  type        = number
  default     = 30
  description = "Prometheus metrics retention (1-365 days)"

  validation {
    condition     = var.metrics_retention_days >= 1 && var.metrics_retention_days <= 365
    error_message = "metrics_retention_days must be between 1 and 365"
  }
}

# SERVICE VERSIONS (from terraform.tfvars)
variable "caddy_version" {
  type        = string
  default     = "2.7.4"
  description = "Caddy version to deploy"
}

variable "postgres_version" {
  type        = string
  default     = "16-alpine"
  description = "PostgreSQL version to deploy"
}

variable "redis_version" {
  type        = string
  default     = "7-alpine"
  description = "Redis version to deploy"
}

variable "redpanda_version" {
  type        = string
  default     = "v24.1.1"
  description = "Redpanda version to deploy"
}

variable "opa_version" {
  type        = string
  default     = "0.58.0"
  description = "OPA version to deploy"
}

variable "ollama_version" {
  type        = string
  default     = "0.1.16"
  description = "Ollama version to deploy"
}

variable "qdrant_version" {
  type        = string
  default     = "1.7.0"
  description = "Qdrant version to deploy"
}

variable "prometheus_version" {
  type        = string
  default     = "v2.50.0"
  description = "Prometheus version to deploy"
}

variable "grafana_version" {
  type        = string
  default     = "10.2.0"
  description = "Grafana version to deploy"
}

variable "loki_version" {
  type        = string
  default     = "2.9.1"
  description = "Loki version to deploy"
}

variable "oauth2_proxy_version" {
  type        = string
  default     = "7.5.1"
  description = "OAuth2-proxy version to deploy"
}

variable "tempo_version" {
  type        = string
  default     = "2.4.1"
  description = "Tempo version to deploy"
}

# FEATURE FLAGS
variable "enable_metrics" {
  type        = bool
  default     = true
  description = "Enable Prometheus metrics collection"
}

variable "enable_tracing" {
  type        = bool
  default     = false
  description = "Enable distributed tracing with Tempo"
}

variable "enable_debug_endpoints" {
  type        = bool
  default     = false
  description = "Enable debug endpoints for troubleshooting"
}

variable "enable_deployment_validation" {
  type        = bool
  default     = true
  description = "Run deployment validation and health checks"
}

variable "enable_deployment_simulation" {
  type        = bool
  default     = false
  description = "Run dry-run simulation before actual deployment"
}

# PERSISTENCE & OBSERVABILITY
variable "postgres_pool_size" {
  type        = number
  default     = 10
  description = "PostgreSQL connection pool size"
}

variable "postgres_max_overflow" {
  type        = number
  default     = 20
  description = "PostgreSQL max overflow connections"
}

variable "redis_max_memory" {
  type        = string
  default     = "512mb"
  description = "Redis max memory setting"
}

variable "prometheus_retention_days" {
  type        = number
  default     = 30
  description = "Prometheus metrics retention (days)"
}

variable "loki_retention_days" {
  type        = number
  default     = 7
  description = "Loki logs retention (days)"
}

variable "force_recreate" {
  type        = bool
  default     = false
  description = "Force recreate all containers on deployment"
}

variable "auto_rollback_on_failure" {
  type        = bool
  default     = true
  description = "Automatically rollback deployment on failure"
}

variable "rollback_failure_threshold" {
  type        = number
  default     = 3
  description = "Number of failed deployments before auto-rollback triggers"
}

# ============================================================================
# CONTAINER STACK VARIABLES (added for docker_container resource approach)
# ============================================================================

# Host repo paths
variable "primary_repo_path" {
  type        = string
  default     = "/home/akushnir/code-server-enterprise"
  description = "Absolute path of repo checkout on the primary host"
}

variable "replica_repo_path" {
  type        = string
  default     = "/home/akushnir/code-server-enterprise"
  description = "Absolute path of repo checkout on the replica host"
}

# App image tag
variable "app_image_tag" {
  type        = string
  default     = "latest"
  description = "Tag for all custom-built app images in the internal registry"
}

# Database
variable "db_user" {
  type        = string
  default     = "postgres"
  description = "PostgreSQL superuser name"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "PostgreSQL superuser password (set via TF_VAR_db_password)"
}

variable "db_name" {
  type        = string
  default     = "code_server"
  description = "PostgreSQL database name"
}

# Redis
variable "redis_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Redis AUTH password (set via TF_VAR_redis_password)"
}

# Grafana
variable "grafana_admin_user" {
  type        = string
  default     = "admin"
  description = "Grafana admin username"
}

variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  description = "Grafana admin password (set via TF_VAR_grafana_admin_password)"
}

# Qdrant
variable "qdrant_api_key" {
  type        = string
  sensitive   = true
  description = "Qdrant REST API key (set via TF_VAR_qdrant_api_key)"
}

# Scheduler
variable "scheduler_api_key" {
  type        = string
  sensitive   = true
  description = "Execution Scheduler API key (set via TF_VAR_scheduler_api_key)"
}

# OAuth2
variable "oauth2_client_id" {
  type        = string
  default     = ""
  description = "OAuth2 client ID"
}

variable "oauth2_client_secret" {
  type        = string
  sensitive   = true
  default     = ""
  description = "OAuth2 client secret (set via TF_VAR_oauth2_client_secret)"
}

# ── App-tier services ─────────────────────────────────────────────────────────
variable "code_server_password" {
  type        = string
  sensitive   = true
  default     = "password123"
  description = "Password for the code-server IDE web UI"
}

variable "minio_root_user" {
  type        = string
  default     = "minioadmin"
  description = "MinIO root/admin username"
}

variable "minio_root_password" {
  type        = string
  sensitive   = true
  default     = "minioadmin"
  description = "MinIO root/admin password"
}

variable "vault_token" {
  type        = string
  sensitive   = true
  default     = "devtoken"
  description = "Vault dev root token ID"
}

variable "gitlab_runner_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "GitLab runner registration token"
}
