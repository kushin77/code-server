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

variable "caddy_version" {
  description = "Caddy reverse proxy version"
  type        = string
  default     = "2.9.1-alpine"
}

variable "caddy_http_port" {
  description = "Caddy HTTP port"
  type        = number
  default     = 80
}

variable "caddy_https_port" {
  description = "Caddy HTTPS port"
  type        = number
  default     = 443
}

variable "caddy_admin_port" {
  description = "Caddy admin API port"
  type        = number
  default     = 2019
}

variable "caddy_auto_https" {
  description = "Caddy HTTPS mode (on/off/ignore_loaded_certs)"
  type        = string
  default     = "on"
}

variable "caddy_memory_limit" {
  description = "Caddy container memory limit"
  type        = string
  default     = "256m"
}

variable "caddy_cpu_limit" {
  description = "Caddy container CPU limit"
  type        = string
  default     = "0.5"
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
