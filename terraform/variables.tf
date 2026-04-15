// ════════════════════════════════════════════════════════════════════════════
// IaC Deployment Variables — All infrastructure config flows through here
// These are the ONLY configuration inputs; everything else is derived
// ════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// Service Configuration
// ─────────────────────────────────────────────────────────────────────────────

variable "code_server_password" {
  description = "Code-Server authentication password (minimum 12 characters, must contain uppercase, lowercase, numbers, symbols)"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.code_server_password) >= 12 && can(regex("[A-Z]", var.code_server_password)) && can(regex("[a-z]", var.code_server_password)) && can(regex("[0-9]", var.code_server_password))
    error_message = "code_server_password must be at least 12 characters with uppercase, lowercase, and numbers (no default for security)."
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
  description = "Google OAuth2 Client ID (from GCP Console OAuth2.0 credentials - required for production)"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "google_client_secret" {
  description = "Google OAuth2 Client Secret (from GCP Console OAuth2.0 credentials - required for production)"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.google_client_secret) >= 20
    error_message = "google_client_secret appears invalid (too short for Google OAuth2 secret)."
  }
}

variable "oauth2_proxy_cookie_secret" {
  description = "OAuth2-Proxy cookie encryption secret (must be exactly 16, 24, or 32 bytes when decoded from base64; generate: openssl rand -base64 32)"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(base64decode(var.oauth2_proxy_cookie_secret)) == 16 || length(base64decode(var.oauth2_proxy_cookie_secret)) == 24 || length(base64decode(var.oauth2_proxy_cookie_secret)) == 32
    error_message = "oauth2_proxy_cookie_secret must be base64 string that decodes to exactly 16, 24, or 32 bytes (no default for security)."
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

// ─────────────────────────────────────────────────────────────────────────────
// Deployment Host Configuration (for scaling & migration)
// ─────────────────────────────────────────────────────────────────────────────

variable "deployment_host" {
  description = "SSH host for production deployment (IP or FQDN). Change this to scale/migrate infrastructure."
  type        = string
  default     = "192.168.168.31"

  validation {
    condition     = length(var.deployment_host) > 0
    error_message = "deployment_host must be specified (IP or hostname)."
  }
}

variable "deployment_user" {
  description = "SSH user for production deployment"
  type        = string
  default     = "akushnir"
}

variable "deployment_port" {
  description = "SSH port for production deployment"
  type        = number
  default     = 22

  validation {
    condition     = var.deployment_port > 0 && var.deployment_port <= 65535
    error_message = "deployment_port must be 1-65535."
  }
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
