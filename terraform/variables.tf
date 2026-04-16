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
// Cloudflare Configuration (Tunnels, DNS, WAF, Security)
// ─────────────────────────────────────────────────────────────────────────────

variable "cloudflare_api_token" {
  description = "Cloudflare API token for zone management"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID (numeric)"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for kushnir.cloud"
  type        = string
  sensitive   = true
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare Tunnel authentication token (injected from Vault at deploy time)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "replica_host_ip" {
  description = "Replica standby host IP (on-prem)"
  type        = string
  default     = "192.168.168.42"
}

variable "cloudflare_tunnel_cname" {
  description = "Cloudflare tunnel CNAME endpoint (e.g., {uuid}.cfargotunnel.com)"
  type        = string
  default     = ""
}

variable "tunnel_name_prefix" {
  description = "Tunnel name prefix for Cloudflare tunnel"
  type        = string
  default     = "code-server"
}

variable "waf_enabled" {
  description = "Enable Cloudflare WAF custom rules"
  type        = bool
  default     = true
}

variable "dnssec_enabled" {
  description = "Enable DNSSEC for domain"
  type        = bool
  default     = true
}

variable "http3_enabled" {
  description = "Enable HTTP/3 (QUIC) protocol"
  type        = bool
  default     = true
}

variable "brotli_compression" {
  description = "Enable Brotli compression"
  type        = bool
  default     = true
}

variable "tls_version_minimum" {
  description = "Minimum TLS version (1.2 or 1.3)"
  type        = string
  default     = "1.3"
  validation {
    condition     = contains(["1.2", "1.3"], var.tls_version_minimum)
    error_message = "Must be 1.2 or 1.3."
  }
}

variable "ssl_mode" {
  description = "SSL/TLS encryption mode (off, flexible, full, strict)"
  type        = string
  default     = "strict"
  validation {
    condition     = contains(["off", "flexible", "full", "strict"], var.ssl_mode)
    error_message = "Must be off, flexible, full, or strict."
  }
}

variable "cache_level" {
  description = "Cloudflare cache level"
  type        = string
  default     = "cache_everything"
}

variable "allowed_email_addresses" {
  description = "Email addresses allowed to access via Cloudflare Access"
  type        = list(string)
  default     = ["alex@kushnir.cloud"]
}

variable "security_email" {
  description = "Email for security notifications (CAA, DMARC records)"
  type        = string
  default     = "security@kushnir.cloud"
}

variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Must be production, staging, or development."
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vault Production Configuration (Issue #413)
// ─────────────────────────────────────────────────────────────────────────────

variable "vault_postgres_user" {
  description = "PostgreSQL user for Vault storage backend"
  type        = string
  default     = "vault"
  sensitive   = true
}

variable "vault_postgres_password" {
  description = "PostgreSQL password for Vault storage backend"
  type        = string
  sensitive   = true
  default     = "" // Will use environment variable VAULT_POSTGRES_PASSWORD if not set
}

variable "vault_postgres_db" {
  description = "PostgreSQL database for Vault storage backend"
  type        = string
  default     = "vault"
}

variable "vault_api_addr" {
  description = "Vault API address for cluster communication"
  type        = string
  default     = "https://vault.kushnir.cloud:8200"
}

variable "vault_cluster_addr" {
  description = "Vault cluster address (HA communication)"
  type        = string
  default     = "https://192.168.168.31:8201"
}

variable "vault_tls_cert_pem" {
  description = "Vault TLS certificate (PEM format). If empty, self-signed will be generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_tls_key_pem" {
  description = "Vault TLS private key (PEM format). If empty, self-signed will be generated."
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_auto_unseal_enabled" {
  description = "Enable auto-unseal for Vault (requires KMS or HTTPS seal for on-prem)"
  type        = bool
  default     = false // Set to true once KMS or HTTPS seal configured
}

variable "vault_ha_enabled" {
  description = "Enable HA mode for Vault (requires >= 2 instances)"
  type        = bool
  default     = true
}

variable "vault_log_level" {
  description = "Vault log level (trace, debug, info, warn, err)"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["trace", "debug", "info", "warn", "err"], var.vault_log_level)
    error_message = "Must be trace, debug, info, warn, or err."
  }
}

variable "vault_max_lease_ttl" {
  description = "Maximum lease duration (in hours) for Vault tokens"
  type        = number
  default     = 768 // 32 days
  validation {
    condition     = var.vault_max_lease_ttl > 0
    error_message = "vault_max_lease_ttl must be greater than 0."
  }
}

variable "vault_default_lease_ttl" {
  description = "Default lease duration (in hours) for Vault tokens"
  type        = number
  default     = 24 // 1 day
  validation {
    condition     = var.vault_default_lease_ttl > 0 && var.vault_default_lease_ttl <= var.vault_max_lease_ttl
    error_message = "vault_default_lease_ttl must be 0 < ttl <= max_lease_ttl."
  }
}

// ═══════════════════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════════════════════
// CONSOLIDATED VARIABLES - 47 duplicates removed
// ════════════════════════════════════════════════════════════════════════════
