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
  default     = "change-me-in-production"

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

variable "external_domain" {
  description = "External domain for DNS-based access (for on-prem: e.g., '192.168.168.31.nip.io'; for production: 'kushnir.cloud')"
  type        = string
  default     = "192.168.168.31.nip.io"
}

variable "acme_email" {
  description = "Email for Let's Encrypt ACME certificate notifications (required for HTTPS)"
  type        = string
  default     = "ops@kushnir.cloud"
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare Tunnel run token (required for cloudflared sidecar)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_cloudflare_tunnel" {
  description = "Enable cloudflared service in generated docker-compose.yml"
  type        = bool
  default     = true
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
  default     = "test-client-id-123.apps.googleusercontent.com"

  validation {
    condition     = length(trimspace(var.google_client_id)) > 10 && trimspace(var.google_client_id) != "\\"
    error_message = "google_client_id must be non-empty and valid-looking (not a placeholder slash)."
  }
}

variable "google_client_secret" {
  description = "Google OAuth2 Client Secret (from GCP Console OAuth2.0 credentials)"
  type        = string
  sensitive   = true
  default     = "test-client-secret-xyz"

  validation {
    condition     = length(trimspace(var.google_client_secret)) > 5 && trimspace(var.google_client_secret) != "\\"
    error_message = "google_client_secret must be non-empty and valid-looking (not a placeholder slash)."
  }
}

variable "oauth2_proxy_cookie_secret" {
  description = "Random cookie encryption secret for oauth2-proxy (16/24/32 bytes in hex format)"
  type        = string
  sensitive   = true
  default     = "867e5c21f89d4b162a3dbe5924761c8a"

  validation {
    condition = (
      can(regex("^[0-9a-fA-F]{32}$", trimspace(var.oauth2_proxy_cookie_secret))) ||
      can(regex("^[0-9a-fA-F]{48}$", trimspace(var.oauth2_proxy_cookie_secret))) ||
      can(regex("^[0-9a-fA-F]{64}$", trimspace(var.oauth2_proxy_cookie_secret)))
    )
    error_message = "oauth2_proxy_cookie_secret must be hex length 32/48/64 (16/24/32 bytes). Example: openssl rand -hex 16"
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
// Resource Management
// ─────────────────────────────────────────────────────────────────────────────

variable "code_server_memory_limit" {
  description = "Memory limit for code-server container"
  type        = string
  default     = "4g"
}

variable "code_server_cpus_limit" {
  description = "CPU limit for code-server container"
  type        = string
  default     = "2.0"
}

variable "enable_healthchecks" {
  description = "Enable container health checks"
  type        = bool
  default     = true
}

// ─────────────────────────────────────────────────────────────────────────────
// Deployment Tags (for resource auditing)
// ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags to apply to all infrastructure resources"
  type        = map(string)
  default = {
    Project    = "code-server-enterprise"
    IaC        = "terraform"
    Immutable  = "true"
    Idempotent = "true"
  }
}
