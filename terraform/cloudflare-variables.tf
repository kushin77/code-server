# terraform/cloudflare-variables.tf
# Variables for Cloudflare Tunnel, WAF, and DNS management

variable "cloudflare_api_token" {
  description = "Cloudflare API token for zone management"
  type        = string
  sensitive   = true
  # Store in: export TF_VAR_cloudflare_api_token="..."
  # Or in: terraform.tfvars (git-ignored)
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
  description = "Cloudflare Tunnel authentication token"
  type        = string
  sensitive   = true
  # Stored in Vault and injected at deploy time
}

variable "primary_host_ip" {
  description = "Primary production host IP (192.168.168.31)"
  type        = string
  default     = "192.168.168.31"
}

variable "replica_host_ip" {
  description = "Replica standby host IP (192.168.168.42)"
  type        = string
  default     = "192.168.168.42"
}

variable "cloudflare_tunnel_cname" {
  description = "Cloudflare tunnel CNAME endpoint (e.g., tunnel-uuid.cfargotunnel.com)"
  type        = string
  # Format: {tunnel-uuid}.cfargotunnel.com
  # Get from: cloudflare_tunnel.code_server.cname in terraform output
}

variable "waf_enabled" {
  description = "Enable WAF custom rules"
  type        = bool
  default     = true
}

variable "dnssec_enabled" {
  description = "Enable DNSSEC for kushnir.cloud"
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
  description = "Cloudflare cache level (bypass, basic, simplified, aggressive, cache_everything)"
  type        = string
  default     = "cache_everything"
}

variable "allowed_email_addresses" {
  description = "Email addresses allowed to access via Cloudflare Access"
  type        = list(string)
  default     = ["alex@kushnir.cloud"]
  # Keep in sync with allowed-emails.txt
}

variable "security_email" {
  description = "Email for security notifications (CAA, DMARC, etc.)"
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

variable "tags" {
  description = "Common tags for all Cloudflare resources"
  type        = map(string)
  default = {
    project     = "code-server-enterprise"
    managed_by  = "terraform"
    phase       = "8"
    security    = "true"
    owner       = "kushin77"
  }
}
