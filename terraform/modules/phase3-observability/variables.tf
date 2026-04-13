variable "namespace_monitoring" {
  type        = string
  description = "Monitoring namespace"
  default     = "monitoring"
}

variable "enable_prometheus" {
  type        = bool
  description = "Enable Prometheus"
  default     = true
}

variable "enable_grafana" {
  type        = bool
  description = "Enable Grafana"
  default     = true
}

variable "enable_loki" {
  type        = bool
  description = "Enable Loki"
  default     = true
}

variable "prometheus_chart_version" {
  type        = string
  description = "Prometheus Helm chart version"
  default     = "57.0.0"  # kube-prometheus-stack
}

variable "loki_chart_version" {
  type        = string
  description = "Loki Helm chart version"
  default     = "6.3.0"
}

variable "prometheus_storage_size" {
  type        = number
  description = "Prometheus storage size in Gi"
  default     = 50
}

variable "loki_storage_size" {
  type        = number
  description = "Loki storage size in Gi"
  default     = 20
}

variable "prometheus_replicas" {
  type        = number
  description = "Number of Prometheus replicas"
  default     = 2
}

variable "grafana_replicas" {
  type        = number
  description = "Number of Grafana replicas"
  default     = 2
}

variable "loki_replicas" {
  type        = number
  description = "Number of Loki replicas"
  default     = 2
}

variable "prometheus_requests" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "Prometheus resource requests"
  default = {
    cpu    = "500m"
    memory = "2Gi"
  }
}

variable "prometheus_limits" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "Prometheus resource limits"
  default = {
    cpu    = "2000m"
    memory = "4Gi"
  }
}

variable "grafana_requests" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "Grafana resource requests"
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
}

variable "grafana_limits" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "Grafana resource limits"
  default = {
    cpu    = "1000m"
    memory = "2Gi"
  }
}

variable "loki_requests" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "Loki resource requests"
  default = {
    cpu    = "250m"
    memory = "512Mi"
  }
}

variable "loki_limits" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "Loki resource limits"
  default = {
    cpu    = "1000m"
    memory = "2Gi"
  }
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana admin password"
  sensitive   = true
  default     = "ChangeMe@123456789"
}
