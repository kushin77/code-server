# Phase 10: Variables for On-Premises Optimization

variable "environment" {
  type        = string
  description = "Environment name for labels"
  default     = "production"
}

variable "namespace_monitoring" {
  type        = string
  description = "Kubernetes namespace for monitoring"
  default     = "monitoring"
}

variable "namespace_code_server" {
  type        = string
  description = "Kubernetes namespace for code-server"
  default     = "code-server"
}

# ===== RESOURCE MANAGEMENT =====

variable "enable_resource_quotas" {
  type        = bool
  description = "Enable Kubernetes resource quotas to prevent over-subscription"
  default     = true
}

variable "monitoring_quota_cpu" {
  type        = string
  description = "Monitoring namespace CPU request quota"
  default     = "10"
}

variable "monitoring_quota_memory" {
  type        = string
  description = "Monitoring namespace memory request quota"
  default     = "20Gi"
}

variable "monitoring_quota_cpu_limit" {
  type        = string
  description = "Monitoring namespace CPU limit quota"
  default     = "20"
}

variable "monitoring_quota_memory_limit" {
  type        = string
  description = "Monitoring namespace memory limit quota"
  default     = "40Gi"
}

variable "code_server_quota_cpu" {
  type        = string
  description = "code-server namespace CPU request quota"
  default     = "20"
}

variable "code_server_quota_memory" {
  type        = string
  description = "code-server namespace memory request quota"
  default     = "40Gi"
}

variable "code_server_quota_cpu_limit" {
  type        = string
  description = "code-server namespace CPU limit quota"
  default     = "40"
}

variable "code_server_quota_memory_limit" {
  type        = string
  description = "code-server namespace memory limit quota"
  default     = "80Gi"
}

# ===== PRIORITY & SCHEDULING =====

variable "enable_priority_classes" {
  type        = bool
  description = "Enable Kubernetes priority classes for workload prioritization"
  default     = true
}

variable "enable_hpa" {
  type        = bool
  description = "Enable Horizontal Pod Autoscaler for dynamic scaling"
  default     = true
}

variable "enable_code_server_hpa" {
  type        = bool
  description = "Enable HPA for code-server StatefulSet"
  default     = true
}

variable "code_server_hpa_min" {
  type        = number
  description = "Minimum number of code-server replicas"
  default     = 2
}

variable "code_server_hpa_max" {
  type        = number
  description = "Maximum number of code-server replicas"
  default     = 10
}

variable "code_server_cpu_threshold" {
  type        = number
  description = "CPU utilization threshold for HPA scale-up (%)"
  default     = 70
}

variable "code_server_memory_threshold" {
  type        = number
  description = "Memory utilization threshold for HPA scale-up (%)"
  default     = 75
}

# ===== NODE OPTIMIZATION =====

variable "create_node_optimization_script" {
  type        = bool
  description = "Create node optimization configuration script"
  default     = true
}

# ===== METRICS OPTIMIZATION =====

variable "create_metrics_optimization" {
  type        = bool
  description = "Create metrics optimization configuration"
  default     = true
}

variable "metrics_retention_days" {
  type        = string
  description = "Prometheus metrics retention period (days)"
  default     = "30"
}

variable "metrics_chunk_size" {
  type        = number
  description = "Metrics chunk size in MB (for compression)"
  default     = 512
}

variable "metrics_compact_interval" {
  type        = number
  description = "Metrics compaction interval (hours)"
  default     = 24
}

variable "metrics_max_storage_size" {
  type        = string
  description = "Maximum storage size for metrics (Prometheus disk)"
  default     = "50Gi"
}

# ===== COST OPTIMIZATION =====

variable "create_cost_optimization_report" {
  type        = bool
  description = "Create cost optimization analysis report"
  default     = true
}

variable "cluster_node_count" {
  type        = number
  description = "Number of nodes in on-premises cluster"
  default     = 3
}

variable "cost_per_server" {
  type        = number
  description = "Cost per on-premises server/node ($)"
  default     = 5000
}

variable "server_amortization_years" {
  type        = number
  description = "Server hardware amortization period (years)"
  default     = 5
}

variable "power_per_server_kw" {
  type        = number
  description = "Power consumption per server (kW)"
  default     = 0.5
}

variable "power_cost_per_kwh" {
  type        = number
  description = "Cost per kilowatt-hour ($)"
  default     = 0.12
}

variable "annual_power_cost" {
  type        = number
  description = "Total annual power cost ($)"
  default     = 5256  # (3 nodes * 0.5kW) * 24h * 365d * 0.12$/kWh
}

variable "cooling_cost_per_month" {
  type        = number
  description = "Monthly cooling/facilities cost ($)"
  default     = 500
}

variable "network_cost_per_month" {
  type        = number
  description = "Monthly network/bandwidth cost ($)"
  default     = 300
}

variable "target_node_utilization" {
  type        = number
  description = "Target average node utilization (%)"
  default     = 70
}

variable "power_efficiency_tier" {
  type        = number
  description = "Power efficiency tier (1=best, 5=worst)"
  default     = 2
}

# ===== OPERATIONAL =====

variable "ops_team_size" {
  type        = number
  description = "Number of full-time operations engineers"
  default     = 2
}

variable "engineering_cost_annual" {
  type        = number
  description = "Annual cost per engineer ($)"
  default     = 150000
}

variable "uptime_sla" {
  type        = number
  description = "Target uptime SLA (%)"
  default     = 99.9
}

variable "create_operational_runbooks" {
  type        = bool
  description = "Create operational runbooks for on-premises procedures"
  default     = true
}
