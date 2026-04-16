# DNS Module - Cloudflare Tunnel, GoDaddy Failover
# P2 #418 Phase 2 Implementation

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID"
  type        = string
  sensitive   = true
}

variable "godaddy_api_key" {
  description = "GoDaddy API key for failover DNS"
  type        = string
  sensitive   = true
}

variable "godaddy_api_secret" {
  description = "GoDaddy API secret"
  type        = string
  sensitive   = true
}

variable "apex_domain" {
  description = "Apex domain (e.g., example.com)"
  type        = string
}

variable "tunnel_name" {
  description = "Cloudflare Tunnel name"
  type        = string
  default     = "on-prem-tunnel"
}

variable "dns_ttl" {
  description = "DNS TTL (seconds)"
  type        = number
  default     = 300
}

variable "health_check_interval" {
  description = "Health check interval (seconds)"
  type        = number
  default     = 30
}

variable "failover_threshold" {
  description = "Consecutive failed checks before failover"
  type        = number
  default     = 3
}

variable "primary_ip" {
  description = "Primary server IP address"
  type        = string
}

variable "secondary_ip" {
  description = "Secondary/failover server IP address"
  type        = string
}

variable "labels" {
  description = "Common labels for all DNS resources"
  type        = map(string)
  default = {
    module     = "dns"
    managed_by = "terraform"
  }
}

variable "docker_host" {
  description = "Docker host for non-K8s deployments"
  type        = string
  default     = ""
}
