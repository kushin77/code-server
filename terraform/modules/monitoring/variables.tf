variable "prometheus_version" {
  description = "Prometheus version"
  type        = string
  default     = "v2.48.0"
}

variable "prometheus_port" {
  description = "Prometheus metrics port"
  type        = number
  default     = 9090
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "30d"
}

variable "prometheus_memory_limit" {
  description = "Prometheus container memory limit"
  type        = string
  default     = "2g"
}

variable "prometheus_cpu_limit" {
  description = "Prometheus container CPU limit"
  type        = string
  default     = "1.0"
}

variable "grafana_version" {
  description = "Grafana version"
  type        = string
  default     = "10.2.3"
}

variable "grafana_port" {
  description = "Grafana HTTP port"
  type        = number
  default     = 3000
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_memory_limit" {
  description = "Grafana container memory limit"
  type        = string
  default     = "512m"
}

variable "grafana_cpu_limit" {
  description = "Grafana container CPU limit"
  type        = string
  default     = "0.5"
}

variable "alertmanager_version" {
  description = "AlertManager version"
  type        = string
  default     = "v0.26.0"
}

variable "alertmanager_port" {
  description = "AlertManager port"
  type        = number
  default     = 9093
}

variable "alertmanager_memory_limit" {
  description = "AlertManager container memory limit"
  type        = string
  default     = "256m"
}

variable "alertmanager_cpu_limit" {
  description = "AlertManager container CPU limit"
  type        = string
  default     = "0.25"
}

variable "loki_version" {
  description = "Loki log aggregation version"
  type        = string
  default     = "2.9.5"
}

variable "loki_port" {
  description = "Loki port"
  type        = number
  default     = 3100
}

variable "loki_memory_limit" {
  description = "Loki container memory limit"
  type        = string
  default     = "1g"
}

variable "loki_cpu_limit" {
  description = "Loki container CPU limit"
  type        = string
  default     = "0.5"
}

variable "jaeger_version" {
  description = "Jaeger distributed tracing version"
  type        = string
  default     = "1.50"
}

variable "jaeger_port" {
  description = "Jaeger UI port"
  type        = number
  default     = 16686
}

variable "jaeger_otlp_port" {
  description = "Jaeger OTLP receiver port"
  type        = number
  default     = 4317
}

variable "jaeger_memory_limit" {
  description = "Jaeger container memory limit"
  type        = string
  default     = "1g"
}

variable "jaeger_cpu_limit" {
  description = "Jaeger container CPU limit"
  type        = string
  default     = "0.5"
}

variable "slo_target_availability" {
  description = "Service availability SLO target (percentage)"
  type        = number
  default     = 99.9
}

variable "slo_target_latency_p99" {
  description = "Service latency P99 SLO target (milliseconds)"
  type        = number
  default     = 500
}

variable "slo_target_error_rate" {
  description = "Service error rate SLO target (percentage)"
  type        = number
  default     = 0.1
}

variable "alert_severity_critical_enabled" {
  description = "Enable critical severity alerts"
  type        = bool
  default     = true
}

variable "alert_severity_high_enabled" {
  description = "Enable high severity alerts"
  type        = bool
  default     = true
}

variable "alert_severity_medium_enabled" {
  description = "Enable medium severity alerts"
  type        = bool
  default     = true
}
