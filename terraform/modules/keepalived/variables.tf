# Variables for Keepalived Module

variable "inventory" {
  description = "Production topology (hosts, roles, VIP)"
  type = object({
    vip = object({
      ip   = string
      fqdn = string
    })
    hosts = object({
      primary = object({
        ip        = string
        fqdn      = string
        ssh_user  = string
        ssh_port  = number
        roles     = list(string)
      })
      replica = object({
        ip        = string
        fqdn      = string
        ssh_user  = string
        ssh_port  = number
        roles     = list(string)
      })
    })
  })
  nullable = false
}

variable "enable_on_primary" {
  description = "Deploy Keepalived on primary host"
  type        = bool
  default     = true
}

variable "enable_on_replica" {
  description = "Deploy Keepalived on replica host"
  type        = bool
  default     = true
}

variable "docker_host" {
  description = "Docker host URL (e.g., ssh://user@host)"
  type        = string
  default     = ""
}

variable "keepalived_version" {
  description = "Keepalived container version"
  type        = string
  default     = "2.2.8"
}

variable "vrrp_interval" {
  description = "VRRP advertisement interval (seconds)"
  type        = number
  default     = 1
  validation {
    condition     = var.vrrp_interval >= 1 && var.vrrp_interval <= 255
    error_message = "VRRP interval must be between 1 and 255 seconds"
  }
}

variable "vrrp_router_id" {
  description = "VRRP virtual router ID (1-255)"
  type        = number
  default     = 51
  validation {
    condition     = var.vrrp_router_id >= 1 && var.vrrp_router_id <= 255
    error_message = "VRRP router ID must be between 1 and 255"
  }
}

variable "health_check_interval" {
  description = "Health check interval (seconds)"
  type        = number
  default     = 5
}

variable "health_check_retries" {
  description = "Number of failed health checks before failover"
  type        = number
  default     = 2
}

variable "health_check_timeout" {
  description = "Health check timeout (seconds)"
  type        = number
  default     = 2
}

variable "failover_sla_seconds" {
  description = "SLA for failover (VIP move from primary to replica)"
  type        = number
  default     = 2
  description = "Expected failover time: <2 seconds"
}
