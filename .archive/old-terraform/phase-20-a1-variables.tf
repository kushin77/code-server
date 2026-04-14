# Phase 20-A1: Terraform Variables
# ✅ Immutable configuration values

variable "phase" {
  description = "Deployment phase identifier"
  type        = string
  default     = "phase-20-a1"
}

variable "docker_registry" {
  description = "Docker registry URL for container images"
  type        = string
  default     = "docker.io"
}

variable "enable_monitoring" {
  description = "Enable Prometheus and Grafana monitoring"
  type        = bool
  default     = true
}

variable "enable_health_checks" {
  description = "Enable container health checks"
  type        = bool
  default     = true
}

variable "region_count" {
  description = "Number of regions to configure"
  type        = number
  default     = 3
  
  validation {
    condition     = var.region_count > 0 && var.region_count <= 10
    error_message = "Region count must be between 1 and 10."
  }
}

variable "failover_timeout" {
  description = "Failover timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.failover_timeout > 0 && var.failover_timeout <= 300
    error_message = "Failover timeout must be between 1 and 300 seconds."
  }
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.health_check_interval > 0 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 1 and 300 seconds."
  }
}

variable "orchestrator_cpu_limit" {
  description = "CPU limit for orchestrator container"
  type        = string
  default     = "0.5"
}

variable "orchestrator_memory_limit" {
  description = "Memory limit for orchestrator container"
  type        = string
  default     = "1Gi"
}

variable "prometheus_retention_days" {
  description = "Prometheus data retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition     = var.prometheus_retention_days > 0
    error_message = "Retention days must be greater than 0."
  }
}

variable "enable_tls" {
  description = "Enable TLS for inter-service communication"
  type        = bool
  default     = false  # Staging only
}

variable "log_level" {
  description = "Application logging level"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "Log level must be DEBUG, INFO, WARNING, or ERROR."
  }
}

variable "enable_auto_failover" {
  description = "Enable automatic failover between regions"
  type        = bool
  default     = true
}

variable "enable_metrics_export" {
  description = "Enable Prometheus metrics export"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Common labels applied to all resources"
  type        = map(string)
  default = {
    "phase"         = "phase-20-a1"
    "component"     = "global-orchestration-framework"
    "environment"   = "staging"
    "created_by"    = "terraform"
    "iac"           = "true"
  }
}

variable "docker_compose_file" {
  description = "Path to docker-compose file"
  type        = string
  default     = "docker-compose-phase-20-a1.yml"
}

variable "config_file" {
  description = "Path to Phase 20-A1 configuration file"
  type        = string
  default     = "phase-20-a1-config.yml"
}

variable "prometheus_config_file" {
  description = "Path to Prometheus configuration file"
  type        = string
  default     = "phase-20-a1-prometheus.yml"
}

variable "grafana_datasources_file" {
  description = "Path to Grafana datasources configuration"
  type        = string
  default     = "grafana-datasources.yml"
}

# ========================================
# Local Variables (computed in main config)
# ========================================
locals {
  # Standard naming
  name_prefix = "${var.phase}-${var.environment}"
  
  # Service names
  orchestrator_name = "${local.name_prefix}-orchestrator"
  prometheus_name   = "${local.name_prefix}-prometheus"
  grafana_name      = "${local.name_prefix}-grafana"
  
  # Network configuration (phase-20-specific; see locals.tf for shared network_name)
  network_subnet = "10.20.0.0/16"
  network_gateway = "10.20.0.1"
  
  # Volume names
  orchestrator_volume = "${local.name_prefix}-orchestrator-logs"
  prometheus_volume   = "${local.name_prefix}-prometheus-data"
  grafana_volume      = "${local.name_prefix}-grafana-data"
  
  # Common tags
  common_tags = merge(
    var.labels,
    {
      "created_at" = timestamp()
    }
  )
}
