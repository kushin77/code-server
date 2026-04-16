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
  description = "Root domain for deployment (used by oauth2-proxy for OIDC redirect)"
  type        = string
  default     = "ide.kushnir.cloud"
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

variable "oauth2_proxy_cookie_secret" {
  description = "Random cookie encryption secret for oauth2-proxy (generate: openssl rand -base64 32)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.oauth2_proxy_cookie_secret) > 0
    error_message = "oauth2_proxy_cookie_secret is required; generate: openssl rand -base64 32"
  }
}

variable "github_token" {
  description = "GitHub Personal Access Token (optional, for higher Copilot rate limits)"
  type        = string
  sensitive   = true
  default     = ""
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
// Ollama (Local LLM Server)
// ─────────────────────────────────────────────────────────────────────────────

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
