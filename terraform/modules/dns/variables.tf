variable "cloudflare_enabled" {
  description = "Enable Cloudflare tunnel and CDN"
  type        = bool
  default     = true
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare Tunnel authentication token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID"
  type        = string
  sensitive   = true
  default     = ""
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

variable "acme_email" {
  description = "Email for ACME certificate notifications"
  type        = string
  default     = "ops@kushnir.cloud"
}

variable "acme_renewal_days_before_expiry" {
  description = "Days before cert expiry to trigger renewal"
  type        = number
  default     = 30
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
