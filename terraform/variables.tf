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

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "production"
}

# domain variable defined in DNS/access-control configuration

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
  default     = "KPm7K8L9vN6q3W2zM5xJ4pL6K9mN8qW3zR5xY7tJ9pM2vO4wQ6sT8uV0xW2zY4aB"

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
// Cloudflare Configuration
// ─────────────────────────────────────────────────────────────────────────────

# cloudflare_api_token, cloudflare_zone_id, cloudflare_account_id defined in DNS/access-control layer
# eks_cluster_endpoint, eks_cluster_ca, eks_cluster_token defined in compute layer

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

// ─────────────────────────────────────────────────────────────────────────────
