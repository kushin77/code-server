// ════════════════════════════════════════════════════════════════════════════
// IaC Deployment Variables — All infrastructure config flows through here
// These are the ONLY configuration inputs; everything else is derived
// ════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// Service Configuration
// ─────────────────────────────────────────────────────────────────────────────

variable "code_server_password" {
  description = "Code-Server authentication password (immutable after deployment; change via docker exec)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.code_server_password) >= 8
    error_message = "code_server_password must be at least 8 characters."
  }
}

variable "domain" {
  description = "Root domain for deployment (e.g., kushnir.cloud). OAuth2 callbacks are derived from this domain and IDE_DOMAIN."
  type        = string
  default     = "kushnir.cloud"
  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain))
    error_message = "domain must be a valid FQDN (e.g., kushnir.cloud)"
  }
}

variable "config_dir" {
  description = "Configuration directory (by default, project root)"
  type        = string
  default     = "."
}

// ─────────────────────────────────────────────────────────────────────────────
// Authentication & Secrets (from Google Secret Manager)
// Populate via: scripts/fetch-gsm-secrets.sh OR terraform.tfvars
// ─────────────────────────────────────────────────────────────────────────────

variable "google_client_id" {
  description = "Google OAuth2 Client ID (from GCP Console OAuth2.0 credentials)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "google_client_secret" {
  description = "Google OAuth2 Client Secret (from GCP Console OAuth2.0 credentials)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "redis_password" {
  description = "Redis authentication password (from GSM or vault-backed env)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redis_password) >= 12
    error_message = "redis_password must be at least 12 characters."
  }
}

variable "oauth2_proxy_cookie_secret" {
  description = "Random cookie encryption secret for oauth2-proxy (generate: openssl rand -base64 32)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.oauth2_proxy_cookie_secret) > 0
    error_message = "oauth2_proxy_cookie_secret is required; generate: openssl rand -base64 32"
  }
}

variable "synapse_admin_token" {
  description = "Admin token for Synapse server"
  type        = string
  sensitive   = true
  default     = ""
}

variable "synapse_max_upload_size" {
  description = "Maximum upload size for Synapse"
  type        = number
  default     = 52428800
}

variable "synapse_db_pool_size" {
  description = "Database pool size for Synapse"
  type        = number
  default     = 10
}

variable "enable_slack_bridge" {
  description = "Enable Slack bridge"
  type        = bool
  default     = true
}

variable "enable_teams_bridge" {
  description = "Enable Teams bridge"
  type        = bool
  default     = false
}

variable "enable_google_chat_bridge" {
  description = "Enable Google Chat bridge"
  type        = bool
  default     = false
}

variable "enable_presence_sidecar" {
  description = "Enable presence sidecar"
  type        = bool
  default     = true
}

variable "enable_element_call" {
  description = "Enable Element Call"
  type        = bool
  default     = true
}

variable "primary_chat_platform" {
  description = "Primary chat platform"
  type        = string
  default     = "slack"
}

// ─────────────────────────────────────────────────────────────────────────────
// Docker Configuration
// ─────────────────────────────────────────────────────────────────────────────

variable "docker_host" {
  description = "Docker daemon socket URI (e.g., unix:///var/run/docker.sock or tcp://docker:2375)"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "docker_context" {
  description = "Docker context to use (e.g., 'default' or 'desktop-linux' on Docker Desktop)"
  type        = string
  default     = "default"
}

// ─────────────────────────────────────────────────────────────────────────────
// Workspace & Storage
// ─────────────────────────────────────────────────────────────────────────────

variable "workspace_path" {
  description = "Local filesystem path for workspace volume mount"
  type        = string
  default     = "./workspace"
}

variable "enable_workspace_mount" {
  description = "Enable mounting local workspace into code-server"
  type        = bool
  default     = true
}

// ─────────────────────────────────────────────────────────────────────────────
// Multi-Region Configuration
// ─────────────────────────────────────────────────────────────────────────────

variable "regions" {
  description = "List of AWS regions to deploy infrastructure in for multi-region support and data residency"
  type        = list(string)
  default     = ["us-central1"]
  validation {
    condition     = length(var.regions) > 0
    error_message = "At least one region must be specified."
  }
}

variable "matrix_domain" {
  description = "Domain for Matrix homeserver"
  type        = string
  default     = "matrix.kushnir.cloud"
}

variable "enable_ollama" {
  description = "Enable Ollama local LLM service"
  type        = bool
  default     = true
}

variable "ollama_num_threads" {
  description = "Number of CPU threads for Ollama (0 = auto)"
  type        = number
  default     = 8

  validation {
    condition     = var.ollama_num_threads >= 0 && var.ollama_num_threads <= 256
    error_message = "ollama_num_threads must be 0-256."
  }
}

variable "ollama_num_gpu" {
  description = "Number of GPUs for Ollama (0 = CPU only)"
  type        = number
  default     = 0
}

variable "ollama_default_model" {
  description = "Default model for Ollama inference (pulled on startup)"
  type        = string
  default     = "llama2:70b-chat"
}

// ─────────────────────────────────────────────────────────────────────────────
// Versioning & TLS
// ─────────────────────────────────────────────────────────────────────────────

variable "code_server_version" {
  description = "code-server base image version (must match codercom/code-server tags)"
  type        = string
  default     = "4.115.0"
}

variable "caddy_version" {
  description = "Caddy reverse proxy version"
  type        = string
  default     = "2.7.6"
}

variable "enable_https" {
  description = "Enable HTTPS/TLS (managed by Caddy with ACME)"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Logging level across all services"
  type        = string
  default     = "info"

  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "log_level must be one of: debug, info, warn, error."
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Deployment Host & Inventory (Inventory-Driven Architecture)
// ─────────────────────────────────────────────────────────────────────────────

variable "deployment_host" {
  description = "Primary SSH host for Terraform deployment (IP or FQDN from inventory)"
  type        = string
  default     = "192.168.168.31"

  validation {
    condition     = length(var.deployment_host) > 0
    error_message = "deployment_host must not be empty (derive from environments/production/hosts.yml)"
  }
}

variable "inventory" {
  description = "Production topology (source of truth for all infrastructure). Load from environments/production/hosts.yml and pass via terraform.tfvars"
  type = object({
    vip = object({
      ip   = string
      fqdn = string
    })
    hosts = object({
      primary = object({
        ip       = string
        fqdn     = string
        ssh_user = string
        ssh_port = number
        roles    = list(string)
      })
      replica = object({
        ip       = string
        fqdn     = string
        ssh_user = string
        ssh_port = number
        roles    = list(string)
      })
    })
  })
  nullable = false

  validation {
    condition     = length(var.inventory.vip.ip) > 0 && length(var.inventory.hosts.primary.ip) > 0 && length(var.inventory.hosts.replica.ip) > 0
    error_message = "inventory must contain valid VIP and host IP addresses"
  }
}

variable "enable_keepalived" {
  description = "Enable VRRP/Keepalived for virtual IP failover (set to false for single-host on-prem)"
  type        = bool
  default     = true
}

// ─────────────────────────────────────────────────────────────────────────────
// QA Credentials for OAuth Endpoint Testing (Immutable, IaC-Managed)
// ─────────────────────────────────────────────────────────────────────────────

variable "qa_password" {
  description = "QA user password for OAuth E2E testing (immutable, stored in GSM). Generate: openssl rand -hex 16 | head -c 32"
  type        = string
  sensitive   = true
  default     = ""
  
  validation {
    condition     = length(var.qa_password) == 0 || length(var.qa_password) >= 16
    error_message = "qa_password must be at least 16 characters (recommend 32-character random string)"
  }
}

variable "qa_email" {
  description = "QA user email for OAuth E2E testing (default: qa@kushnir.cloud)"
  type        = string
  default     = "qa@kushnir.cloud"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.qa_email))
    error_message = "qa_email must be a valid email address"
  }
}

variable "gcp_project_id" {
  description = "GCP project ID where QA credentials are stored in GSM (kushin77-ops)"
  type        = string
  default     = "kushin77-ops"
}

variable "ci_service_account_email" {
  description = "CI/CD service account email that requires access to QA credentials in GSM (GitHub Actions WIF)"
  type        = string
  default     = ""
}

// ─────────────────────────────────────────────────────────────────────────────

# Operational variables
variable "environment" {
  description = "Deployment environment name (e.g. production, staging)"
  type        = string
  default     = "production"
}
