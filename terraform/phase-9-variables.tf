# terraform/phase-9-variables.tf
# Phase 9: Cloudflare Variables

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "domain" {
  description = "Domain for Cloudflare tunnel"
  type        = string
  default     = "kushnir.cloud"
}

variable "primary_host_ip" {
  description = "Primary host IP address"
  type        = string
  default     = "192.168.168.31"
}

variable "replica_host_ip" {
  description = "Replica host IP address"
  type        = string
  default     = "192.168.168.42"
}

variable "tunnel_name_prefix" {
  description = "Tunnel name prefix"
  type        = string
  default     = "code-server"
}

variable "dnssec_enabled" {
  description = "Enable DNSSEC"
  type        = bool
  default     = true
}

variable "waf_enabled" {
  description = "Enable WAF rules"
  type        = bool
  default     = true
}

variable "security_email" {
  description = "Security contact email for CAA records"
  type        = string
  default     = "security@kushnir.cloud"
}

variable "tls_version_minimum" {
  description = "Minimum TLS version"
  type        = string
  default     = "1.3"
}

variable "ssl_mode" {
  description = "SSL/TLS mode"
  type        = string
  default     = "strict"
}

variable "http3_enabled" {
  description = "Enable HTTP/3 (QUIC)"
  type        = bool
  default     = true
}

variable "brotli_compression" {
  description = "Enable Brotli compression"
  type        = bool
  default     = true
}

variable "cache_level" {
  description = "Cache level"
  type        = string
  default     = "cache_everything"
}
