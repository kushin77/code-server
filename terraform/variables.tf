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

variable "cloudflare_api_token" {
  description = "Cloudflare API token (set via TF_VAR_cloudflare_api_token or .tfvars)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "domain" {
  description = "Root domain for deployment"
  type        = string
  default     = "ide.kushnir.cloud"
}

// ─────────────────────────────────────────────────────────────────────────────
// AWS / EKS Configuration
// ─────────────────────────────────────────────────────────────────────────────

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "code-server-k8s-prod"
}

variable "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  type        = string
  default     = ""
}

variable "eks_cluster_ca" {
  description = "EKS cluster CA certificate (base64)"
  type        = string
  default     = ""
}

variable "eks_cluster_token" {
  description = "EKS cluster authentication token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_region" {
  description = "AWS region for EKS and supporting resources"
  type        = string
  default     = "us-east-1"
}

variable "gpu_node_ssh_key" {
  description = "SSH public key for GPU node access"
  type        = string
  default     = ""
}

variable "admin_cidr" {
  description = "CIDR block for administrative access to GPU nodes"
  type        = string
  default     = "10.0.0.0/8"
}

variable "gpu_subnet_ids" {
  description = "Subnet IDs for GPU node group"
  type        = list(string)
  default     = []
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
// FEATURE FLAGS: Infrastructure Capabilities (Modular Deployment)
// Enable/disable major infrastructure modules independently
// ─────────────────────────────────────────────────────────────────────────────

variable "enable_kubernetes_orchestration" {
  description = "Enable Kubernetes orchestration (EKS cluster)"
  type        = bool
  default     = true
}

variable "enable_observability_operations" {
  description = "Enable observability & operations (Prometheus, Grafana, AlertManager, Velero)"
  type        = bool
  default     = true
}

variable "enable_api_gateway" {
  description = "Enable GraphQL API gateway & developer portal"
  type        = bool
  default     = true
}

variable "enable_dns_access_control" {
  description = "Enable DNS access control & Cloudflare routing"
  type        = bool
  default     = true
}

variable "phase_22_b_enabled" {
  description = "Enable Phase 22-B Advanced Networking (Istio, BGP, CloudFlare CDN)"
  type        = bool
  default     = false
}

# NOTE: cloudflare_zone_id, cloudflare_api_token, cloudflare_account_id already defined above
# Removed duplicate declarations to comply with terraform unique variable requirement

// ─────────────────────────────────────────────────────────────────────────────
