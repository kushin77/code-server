# Networking Module - Kong, CoreDNS, Load Balancing
# P2 #418 Phase 2 Implementation

variable "kong_version" {
  description = "Kong API Gateway version"
  type        = string
  default     = "3.4.0"
}

variable "kong_database_password" {
  description = "Kong PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "kong_storage_size" {
  description = "Kong persistent volume size"
  type        = string
  default     = "20Gi"
}

variable "coredns_version" {
  description = "CoreDNS version"
  type        = string
  default     = "1.10.1"
}

variable "coredns_config" {
  description = "CoreDNS configuration block"
  type        = string
  default     = "."
}

variable "load_balancer_algorithm" {
  description = "Load balancing algorithm (round_robin, least_connections, ip_hash)"
  type        = string
  default     = "round_robin"
}

variable "load_balancer_health_check_interval" {
  description = "Health check interval (seconds)"
  type        = number
  default     = 10
}

variable "service_upstream_timeout" {
  description = "Upstream service timeout (seconds)"
  type        = number
  default     = 60
}

variable "rate_limiting_requests_per_second" {
  description = "Rate limit (requests/second)"
  type        = number
  default     = 1000
}

variable "labels" {
  description = "Common labels for all networking resources"
  type        = map(string)
  default = {
    module      = "networking"
    managed_by  = "terraform"
  }
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "networking"
}

variable "docker_host" {
  description = "Docker host for non-K8s deployments"
  type        = string
  default     = ""
}
