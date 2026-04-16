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
// Module-Scoped Variables (for composing child modules)
// ═══════════════════════════════════════════════════════════════════════════

variable "host_ip" {
  description = "Primary host IP address (e.g., 192.168.168.31)"
  type        = string
  default     = "192.168.168.31"
  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.host_ip))
    error_message = "Must be a valid IPv4 address."
  }
}

variable "is_primary" {
  description = "Is this the primary host (true) or replica (false)?"
  type        = bool
  default     = true
}

variable "primary_host_ip" {
  description = "Primary host IP (for replica replication source)"
  type        = string
  default     = "192.168.168.31"
}

variable "replica_host_ip" {
  description = "Replica host IP (for primary failover target)"
  type        = string
  default     = "192.168.168.42"
}

variable "code_server_port" {
  description = "Code-server application port"
  type        = number
  default     = 8080
}

variable "code_server_version" {
  description = "Code-server Docker image version"
  type        = string
  default     = "4.115.0"
}

variable "code_server_memory_limit" {
  description = "Code-server container memory limit"
  type        = string
  default     = "4g"
}

variable "code_server_cpu_limit" {
  description = "Code-server container CPU limit (cores)"
  type        = string
  default     = "2.0"
}

variable "caddy_port_http" {
  description = "Caddy HTTP port"
  type        = number
  default     = 80
}

variable "caddy_port_https" {
  description = "Caddy HTTPS port"
  type        = number
  default     = 443
}

variable "caddy_admin_port" {
  description = "Caddy admin API port (loopback only)"
  type        = number
  default     = 2019
}

variable "caddy_auto_https" {
  description = "Caddy HTTPS mode (on/off/ignore_loaded_certs)"
  type        = string
  default     = "on"
}

variable "caddy_tls_email" {
  description = "Email for Let's Encrypt TLS certificates"
  type        = string
  default     = "ops@kushnir.cloud"
}

variable "caddy_version" {
  description = "Caddy reverse proxy version"
  type        = string
  default     = "2.9.1-alpine"
}

variable "oauth2_proxy_version" {
  description = "OAuth2-proxy version"
  type        = string
  default     = "7.5.1"
}

variable "oauth2_proxy_port" {
  description = "OAuth2-proxy listen port"
  type        = number
  default     = 4180
}

variable "oauth2_provider" {
  description = "OAuth2 provider (google/github/okta)"
  type        = string
  default     = "google"
}

variable "oauth2_callback_url" {
  description = "OAuth2 callback URL"
  type        = string
  default     = "https://ide.kushnir.cloud/oauth2/callback"
}

variable "oauth2_memory_limit" {
  description = "OAuth2-proxy memory limit"
  type        = string
  default     = "256m"
}

variable "oauth2_cpu_limit" {
  description = "OAuth2-proxy CPU limit"
  type        = string
  default     = "0.25"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.6-alpine"
}

variable "postgres_db" {
  description = "PostgreSQL primary database name"
  type        = string
  default     = "codeserver"
}

variable "postgres_user" {
  description = "PostgreSQL primary user"
  type        = string
  default     = "codeserver"
}

variable "postgres_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "postgres_memory_limit" {
  description = "PostgreSQL container memory limit"
  type        = string
  default     = "2g"
}

variable "postgres_cpu_limit" {
  description = "PostgreSQL container CPU limit"
  type        = string
  default     = "1.0"
}

variable "postgres_replication_user" {
  description = "PostgreSQL replication user"
  type        = string
  default     = "replicator"
}

variable "postgres_replication_lag_limit_ms" {
  description = "Maximum acceptable replication lag (ms)"
  type        = number
  default     = 5000
}

variable "redis_version" {
  description = "Redis version"
  type        = string
  default     = "7.2-alpine"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "redis_memory_limit" {
  description = "Redis memory limit"
  type        = string
  default     = "512mb"
}

variable "redis_maxmemory" {
  description = "Redis maxmemory setting"
  type        = string
  default     = "512mb"
}

variable "redis_memory_limit_container" {
  description = "Redis container memory limit"
  type        = string
  default     = "768m"
}

variable "redis_cpu_limit" {
  description = "Redis container CPU limit"
  type        = string
  default     = "0.5"
}

variable "redis_persistence_enabled" {
  description = "Enable Redis persistence"
  type        = bool
  default     = false
}

variable "pgbouncer_version" {
  description = "PgBouncer version"
  type        = string
  default     = "1.21"
}

variable "pgbouncer_port" {
  description = "PgBouncer port"
  type        = number
  default     = 6432
}

variable "pgbouncer_pool_size" {
  description = "PgBouncer pool size"
  type        = number
  default     = 25
}

variable "pgbouncer_pool_mode" {
  description = "PgBouncer pool mode"
  type        = string
  default     = "transaction"
}

variable "pgbouncer_connect_timeout" {
  description = "PgBouncer connect timeout (seconds)"
  type        = number
  default     = 15
}

variable "backup_retention_days" {
  description = "Backup retention period (days)"
  type        = number
  default     = 30
}

variable "backup_schedule_cron" {
  description = "Backup schedule (cron format)"
  type        = string
  default     = "0 2 * * *"
}

variable "enable_replication" {
  description = "Enable PostgreSQL replication"
  type        = bool
  default     = true
}

variable "enable_hot_standby" {
  description = "Enable hot standby on replica"
  type        = bool
  default     = true
}

variable "enable_synchronous_replication" {
  description = "Enable synchronous replication (consistency > latency)"
  type        = bool
  default     = false
}

// ═══════════════════════════════════════════════════════════════════════════
// Module-Scoped Variables (for composing child modules)
// ═══════════════════════════════════════════════════════════════════════════

variable "host_ip" {
  description = "Primary host IP address (e.g., 192.168.168.31)"
  type        = string
  default     = "192.168.168.31"
  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.host_ip))
    error_message = "Must be a valid IPv4 address."
  }
}

variable "is_primary" {
  description = "Is this the primary host (true) or replica (false)?"
  type        = bool
  default     = true
}

variable "primary_host_ip" {
  description = "Primary host IP (for replica replication source)"
  type        = string
  default     = "192.168.168.31"
}

variable "replica_host_ip" {
  description = "Replica host IP (for primary failover target)"
  type        = string
  default     = "192.168.168.42"
}

variable "code_server_port" {
  description = "Code-server application port"
  type        = number
  default     = 8080
}

variable "code_server_version" {
  description = "Code-server Docker image version"
  type        = string
  default     = "4.115.0"
}

variable "code_server_memory_limit" {
  description = "Code-server container memory limit"
  type        = string
  default     = "4g"
}

variable "code_server_cpu_limit" {
  description = "Code-server container CPU limit (cores)"
  type        = string
  default     = "2.0"
}

variable "caddy_port_http" {
  description = "Caddy HTTP port"
  type        = number
  default     = 80
}

variable "caddy_port_https" {
  description = "Caddy HTTPS port"
  type        = number
  default     = 443
}

variable "caddy_admin_port" {
  description = "Caddy admin API port (loopback only)"
  type        = number
  default     = 2019
}

variable "caddy_auto_https" {
  description = "Caddy HTTPS mode (on/off/ignore_loaded_certs)"
  type        = string
  default     = "on"
}

variable "caddy_tls_email" {
  description = "Email for Let's Encrypt TLS certificates"
  type        = string
  default     = "ops@kushnir.cloud"
}

variable "caddy_version" {
  description = "Caddy reverse proxy version"
  type        = string
  default     = "2.9.1-alpine"
}

variable "oauth2_proxy_version" {
  description = "OAuth2-proxy version"
  type        = string
  default     = "7.5.1"
}

variable "oauth2_proxy_port" {
  description = "OAuth2-proxy listen port"
  type        = number
  default     = 4180
}

variable "oauth2_provider" {
  description = "OAuth2 provider (google/github/okta)"
  type        = string
  default     = "google"
}

variable "oauth2_callback_url" {
  description = "OAuth2 callback URL"
  type        = string
  default     = "https://ide.kushnir.cloud/oauth2/callback"
}

variable "oauth2_memory_limit" {
  description = "OAuth2-proxy memory limit"
  type        = string
  default     = "256m"
}

variable "oauth2_cpu_limit" {
  description = "OAuth2-proxy CPU limit"
  type        = string
  default     = "0.25"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.6-alpine"
}

variable "postgres_db" {
  description = "PostgreSQL primary database name"
  type        = string
  default     = "codeserver"
}

variable "postgres_user" {
  description = "PostgreSQL primary user"
  type        = string
  default     = "codeserver"
}

variable "postgres_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "postgres_memory_limit" {
  description = "PostgreSQL container memory limit"
  type        = string
  default     = "2g"
}

variable "postgres_cpu_limit" {
  description = "PostgreSQL container CPU limit"
  type        = string
  default     = "1.0"
}

variable "postgres_replication_user" {
  description = "PostgreSQL replication user"
  type        = string
  default     = "replicator"
}

variable "postgres_replication_lag_limit_ms" {
  description = "Maximum acceptable replication lag (ms)"
  type        = number
  default     = 5000
}

variable "redis_version" {
  description = "Redis version"
  type        = string
  default     = "7.2-alpine"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "redis_memory_limit" {
  description = "Redis memory limit"
  type        = string
  default     = "512mb"
}

variable "redis_maxmemory" {
  description = "Redis maxmemory setting"
  type        = string
  default     = "512mb"
}

variable "redis_memory_limit_container" {
  description = "Redis container memory limit"
  type        = string
  default     = "768m"
}

variable "redis_cpu_limit" {
  description = "Redis container CPU limit"
  type        = string
  default     = "0.5"
}

variable "redis_persistence_enabled" {
  description = "Enable Redis persistence"
  type        = bool
  default     = false
}

variable "pgbouncer_version" {
  description = "PgBouncer version"
  type        = string
  default     = "1.21"
}

variable "pgbouncer_port" {
  description = "PgBouncer port"
  type        = number
  default     = 6432
}

variable "pgbouncer_pool_size" {
  description = "PgBouncer pool size"
  type        = number
  default     = 25
}

variable "pgbouncer_pool_mode" {
  description = "PgBouncer pool mode"
  type        = string
  default     = "transaction"
}

variable "pgbouncer_connect_timeout" {
  description = "PgBouncer connect timeout (seconds)"
  type        = number
  default     = 15
}

variable "backup_retention_days" {
  description = "Backup retention period (days)"
  type        = number
  default     = 30
}

variable "backup_schedule_cron" {
  description = "Backup schedule (cron format)"
  type        = string
  default     = "0 2 * * *"
}

variable "enable_replication" {
  description = "Enable PostgreSQL replication"
  type        = bool
  default     = true
}

variable "enable_hot_standby" {
  description = "Enable hot standby on replica"
  type        = bool
  default     = true
}

variable "enable_synchronous_replication" {
  description = "Enable synchronous replication (consistency > latency)"
  type        = bool
  default     = false
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW MONITORING MODULE VARIABLES (Prometheus, Grafana, Loki, Jaeger, AlertManager)
// ═══════════════════════════════════════════════════════════════════════════

variable "prometheus_version" {
  description = "Prometheus version"
  type        = string
  default     = "v2.48.0"
}

variable "prometheus_port" {
  description = "Prometheus metrics port"
  type        = number
  default     = 9090
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "30d"
}

variable "prometheus_memory_limit" {
  description = "Prometheus container memory limit"
  type        = string
  default     = "2g"
}

variable "prometheus_cpu_limit" {
  description = "Prometheus container CPU limit"
  type        = string
  default     = "1.0"
}

variable "grafana_version" {
  description = "Grafana version"
  type        = string
  default     = "10.2.3"
}

variable "grafana_port" {
  description = "Grafana HTTP port"
  type        = number
  default     = 3000
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_memory_limit" {
  description = "Grafana container memory limit"
  type        = string
  default     = "512m"
}

variable "grafana_cpu_limit" {
  description = "Grafana container CPU limit"
  type        = string
  default     = "0.5"
}

variable "alertmanager_version" {
  description = "AlertManager version"
  type        = string
  default     = "v0.26.0"
}

variable "alertmanager_port" {
  description = "AlertManager port"
  type        = number
  default     = 9093
}

variable "alertmanager_memory_limit" {
  description = "AlertManager container memory limit"
  type        = string
  default     = "256m"
}

variable "alertmanager_cpu_limit" {
  description = "AlertManager container CPU limit"
  type        = string
  default     = "0.25"
}

variable "loki_version" {
  description = "Loki log aggregation version"
  type        = string
  default     = "2.9.5"
}

variable "loki_port" {
  description = "Loki port"
  type        = number
  default     = 3100
}

variable "loki_memory_limit" {
  description = "Loki container memory limit"
  type        = string
  default     = "1g"
}

variable "loki_cpu_limit" {
  description = "Loki container CPU limit"
  type        = string
  default     = "0.5"
}

variable "jaeger_version" {
  description = "Jaeger distributed tracing version"
  type        = string
  default     = "1.50"
}

variable "jaeger_port" {
  description = "Jaeger UI port"
  type        = number
  default     = 16686
}

variable "jaeger_otlp_port" {
  description = "Jaeger OTLP receiver port"
  type        = number
  default     = 4317
}

variable "jaeger_memory_limit" {
  description = "Jaeger container memory limit"
  type        = string
  default     = "1g"
}

variable "jaeger_cpu_limit" {
  description = "Jaeger container CPU limit"
  type        = string
  default     = "0.5"
}

variable "slo_target_availability" {
  description = "Service availability SLO target (percentage)"
  type        = number
  default     = 99.9
}

variable "slo_target_latency_p99" {
  description = "Service latency P99 SLO target (milliseconds)"
  type        = number
  default     = 500
}

variable "slo_target_error_rate" {
  description = "Service error rate SLO target (percentage)"
  type        = number
  default     = 0.1
}

variable "alert_severity_critical_enabled" {
  description = "Enable critical severity alerts"
  type        = bool
  default     = true
}

variable "alert_severity_high_enabled" {
  description = "Enable high severity alerts"
  type        = bool
  default     = true
}

variable "alert_severity_medium_enabled" {
  description = "Enable medium severity alerts"
  type        = bool
  default     = true
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW NETWORKING MODULE VARIABLES (Kong, CoreDNS)
// ═══════════════════════════════════════════════════════════════════════════

variable "kong_version" {
  description = "Kong API Gateway version"
  type        = string
  default     = "3.4.0-alpine"
}

variable "kong_proxy_port" {
  description = "Kong proxy HTTP port"
  type        = number
  default     = 8000
}

variable "kong_proxy_ssl_port" {
  description = "Kong proxy HTTPS port"
  type        = number
  default     = 8443
}

variable "kong_admin_port" {
  description = "Kong admin API port (loopback only)"
  type        = number
  default     = 8001
}

variable "kong_memory_limit" {
  description = "Kong container memory limit"
  type        = string
  default     = "512m"
}

variable "kong_cpu_limit" {
  description = "Kong container CPU limit"
  type        = string
  default     = "0.5"
}

variable "kong_rate_limit_minute" {
  description = "Kong global rate limit (requests per minute)"
  type        = number
  default     = 60
}

variable "kong_rate_limit_hour" {
  description = "Kong global rate limit (requests per hour)"
  type        = number
  default     = 1000
}

variable "kong_rate_limit_auth_minute" {
  description = "Kong rate limit on auth endpoints (requests per minute)"
  type        = number
  default     = 10
}

variable "coredns_version" {
  description = "CoreDNS version"
  type        = string
  default     = "1.10.1"
}

variable "coredns_port" {
  description = "CoreDNS DNS port"
  type        = number
  default     = 53
}

variable "coredns_memory_limit" {
  description = "CoreDNS container memory limit"
  type        = string
  default     = "128m"
}

variable "coredns_cpu_limit" {
  description = "CoreDNS container CPU limit"
  type        = string
  default     = "0.25"
}

variable "enable_tls_termination" {
  description = "Enable TLS termination on Caddy"
  type        = bool
  default     = true
}

variable "enable_rate_limiting" {
  description = "Enable Kong rate limiting"
  type        = bool
  default     = true
}

variable "enable_service_discovery" {
  description = "Enable CoreDNS service discovery"
  type        = bool
  default     = true
}

variable "load_balancing_algorithm" {
  description = "Load balancing algorithm (round_robin/least_conn/random/ip_hash)"
  type        = string
  default     = "round_robin"
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW SECURITY MODULE VARIABLES (Falco, OPA)
// ═══════════════════════════════════════════════════════════════════════════

variable "falco_version" {
  description = "Falco runtime security engine version"
  type        = string
  default     = "0.37.1"
}

variable "falco_mode" {
  description = "Falco execution mode (modern-bpf/legacy)"
  type        = string
  default     = "modern-bpf"
}

variable "falco_memory_limit" {
  description = "Falco container memory limit"
  type        = string
  default     = "512m"
}

variable "falco_cpu_limit" {
  description = "Falco container CPU limit"
  type        = string
  default     = "0.5"
}

variable "opa_version" {
  description = "Open Policy Agent version"
  type        = string
  default     = "0.58.0"
}

variable "opa_port" {
  description = "OPA HTTP port"
  type        = number
  default     = 8181
}

variable "opa_memory_limit" {
  description = "OPA container memory limit"
  type        = string
  default     = "256m"
}

variable "opa_cpu_limit" {
  description = "OPA container CPU limit"
  type        = string
  default     = "0.25"
}

variable "enable_apparmor" {
  description = "Enable AppArmor security profiles"
  type        = bool
  default     = true
}

variable "enable_seccomp" {
  description = "Enable seccomp system call filtering"
  type        = bool
  default     = true
}

variable "enable_selinux" {
  description = "Enable SELinux (if available on OS)"
  type        = bool
  default     = false
}

variable "enable_runtime_monitoring" {
  description = "Enable Falco runtime security monitoring"
  type        = bool
  default     = true
}

variable "enable_policy_enforcement" {
  description = "Enable OPA policy enforcement"
  type        = bool
  default     = true
}

variable "enable_secret_management" {
  description = "Enable Vault secret management"
  type        = bool
  default     = true
}

variable "audit_log_retention_days" {
  description = "Security audit log retention (days)"
  type        = number
  default     = 90
}

variable "vulnerability_scan_enabled" {
  description = "Enable automated vulnerability scanning"
  type        = bool
  default     = true
}

variable "container_image_scan_enabled" {
  description = "Enable container image scanning"
  type        = bool
  default     = true
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW DNS MODULE VARIABLES (CloudFlare, GoDaddy DNS Failover)
// ═══════════════════════════════════════════════════════════════════════════

variable "cloudflare_enabled" {
  description = "Enable Cloudflare tunnel and CDN"
  type        = bool
  default     = true
}

variable "cloudflare_dns_proxy_enabled" {
  description = "Enable Cloudflare DNS proxy (orange cloud)"
  type        = bool
  default     = true
}

variable "cloudflare_waf_enabled" {
  description = "Enable Cloudflare WAF"
  type        = bool
  default     = true
}

variable "godaddy_enabled" {
  description = "Enable GoDaddy DNS failover"
  type        = bool
  default     = true
}

variable "godaddy_api_key" {
  description = "GoDaddy API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "godaddy_api_secret" {
  description = "GoDaddy API secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "domain_primary" {
  description = "Primary domain name"
  type        = string
  default     = "kushnir.cloud"
}

variable "domain_secondary" {
  description = "Secondary domain for failover"
  type        = string
  default     = "code-server.kushnir.cloud"
}

variable "dns_ttl_default" {
  description = "Default DNS TTL (seconds)"
  type        = number
  default     = 300
}

variable "dns_ttl_short" {
  description = "Short DNS TTL for failover (seconds)"
  type        = number
  default     = 60
}

variable "dns_failover_enabled" {
  description = "Enable automatic DNS failover"
  type        = bool
  default     = true
}

variable "dns_failover_health_check_interval" {
  description = "DNS failover health check interval (seconds)"
  type        = number
  default     = 30
}

variable "dns_failover_threshold" {
  description = "Failed checks before failover"
  type        = number
  default     = 3
}

variable "acme_provider" {
  description = "ACME TLS certificate provider (letsencrypt/zerossl)"
  type        = string
  default     = "letsencrypt"
}

variable "enable_dns_dnssec" {
  description = "Enable DNSSEC signing"
  type        = bool
  default     = true
}

variable "enable_dns_rate_limiting" {
  description = "Enable DNS query rate limiting"
  type        = bool
  default     = true
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW FAILOVER MODULE VARIABLES (Patroni, Replication, Backup, DR)
// ═══════════════════════════════════════════════════════════════════════════

variable "patroni_enabled" {
  description = "Enable Patroni for PostgreSQL HA"
  type        = bool
  default     = true
}

variable "patroni_version" {
  description = "Patroni version"
  type        = string
  default     = "3.0"
}

variable "replication_slot_enabled" {
  description = "Enable PostgreSQL replication slots"
  type        = bool
  default     = true
}

variable "replication_slot_name" {
  description = "Replication slot name"
  type        = string
  default     = "replica_slot"
}

variable "wal_level" {
  description = "PostgreSQL WAL level (minimal/replica/logical)"
  type        = string
  default     = "replica"
}

variable "max_wal_senders" {
  description = "Maximum WAL sender connections"
  type        = number
  default     = 10
}

variable "wal_keep_size" {
  description = "WAL segments to keep (GB)"
  type        = number
  default     = 10
}

variable "hot_standby_enabled_failover" {
  description = "Enable hot standby mode on replica"
  type        = bool
  default     = true
}

variable "synchronous_replica_count" {
  description = "Number of replicas to wait for in sync replication"
  type        = number
  default     = 1
}

variable "backup_method" {
  description = "Backup method (pg_basebackup/pgbackrest/wal-g)"
  type        = string
  default     = "pg_basebackup"
}

variable "backup_compression_enabled" {
  description = "Enable backup compression"
  type        = bool
  default     = true
}

variable "point_in_time_recovery_days" {
  description = "Point-in-time recovery window (days)"
  type        = number
  default     = 7
}

variable "redis_sentinel_enabled" {
  description = "Enable Redis Sentinel for HA"
  type        = bool
  default     = true
}

variable "redis_sentinel_port" {
  description = "Redis Sentinel port"
  type        = number
  default     = 26379
}

variable "redis_sentinel_quorum" {
  description = "Sentinel quorum size"
  type        = number
  default     = 2
}

variable "redis_sentinel_down_after_ms" {
  description = "Sentinel marks replica down after (ms)"
  type        = number
  default     = 30000
}

variable "disaster_recovery_enabled" {
  description = "Enable disaster recovery procedures"
  type        = bool
  default     = true
}

variable "rto_target_minutes" {
  description = "Recovery Time Objective (minutes)"
  type        = number
  default     = 15
}

variable "rpo_target_seconds" {
  description = "Recovery Point Objective (seconds)"
  type        = number
  default     = 60
}

variable "backup_storage_backend" {
  description = "Backup storage (local/s3/minio)"
  type        = string
  default     = "minio"
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region backup replication"
  type        = bool
  default     = false
}

variable "failover_auto_enabled" {
  description = "Enable automatic failover"
  type        = bool
  default     = true
}

variable "failover_timeout_seconds" {
  description = "Failover timeout (seconds)"
  type        = number
  default     = 300
}
