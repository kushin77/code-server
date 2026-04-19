# ─────────────────────────────────────────────────────────────────────────────
# terraform/network-variables.tf
# Network topology variables for on-prem deployments
# ─────────────────────────────────────────────────────────────────────────────

variable "vip_host" {
  description = "Virtual IP address for failover (floats between primary and replica). If DNS points to VIP, primary down triggers promotion of replica."
  type        = string
  default     = "192.168.168.30"
  
  validation {
    condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", var.vip_host))
    error_message = "vip_host must be a valid IPv4 address"
  }
}

variable "primary_host" {
  description = "Primary deployment host IP (production). Runs docker-compose main stack, Redis, PostgreSQL, Code-server, Prometheus, Grafana, AlertManager, etc."
  type        = string
  default     = "192.168.168.31"
  
  validation {
    condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", var.primary_host))
    error_message = "primary_host must be a valid IPv4 address"
  }
}

variable "replica_host" {
  description = "Replica/failover host IP (standby). Synced with primary; promoted if primary fails."
  type        = string
  default     = "192.168.168.42"
  
  validation {
    condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", var.replica_host))
    error_message = "replica_host must be a valid IPv4 address"
  }
}

variable "nas_host" {
  description = "NAS primary IP for shared volume storage (code-server profiles, workspace data). Backup: 192.168.168.50"
  type        = string
  default     = "192.168.168.56"
  
  validation {
    condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$", var.nas_host))
    error_message = "nas_host must be a valid IPv4 address"
  }
}

variable "nas_export_path" {
  description = "NAS export path for shared volumes (e.g., /export/code-server). Must be exported on nas_host and support NFSv4."
  type        = string
  default     = "/export/code-server"
  
  validation {
    condition     = can(regex("^/[a-z0-9/_-]+$", var.nas_export_path))
    error_message = "nas_export_path must be an absolute Unix path"
  }
}

variable "deploy_user" {
  description = "SSH user for remote deployments (used for docker-compose redeploy, failover orchestration)"
  type        = string
  default     = "akushnir"
}

variable "ssh_key_path" {
  description = "Path to SSH private key for remote access (loaded from local filesystem or GSM). If empty, uses ssh-agent."
  type        = string
  default     = ""
  sensitive   = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Outputs for reference in other modules
# ─────────────────────────────────────────────────────────────────────────────

output "network_topology" {
  description = "Network topology summary for operations"
  value = {
    vip          = var.vip_host
    primary      = var.primary_host
    replica      = var.replica_host
    nas          = var.nas_host
    deploy_user  = var.deploy_user
    nas_export   = var.nas_export_path
  }
}
