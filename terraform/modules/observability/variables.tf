# @file terraform/modules/observability/variables.tf
# @description Observability infrastructure (Prometheus, Grafana, Loki)

variable "prometheus_image" {
  type    = string
  default = "prom/prometheus:latest"
}

variable "grafana_image" {
  type    = string
  default = "grafana/grafana:latest"
}

variable "loki_image" {
  type    = string
  default = "grafana/loki:latest"
}

variable "metrics_retention_days" {
  description = "Metrics retention in Prometheus (days)"
  type        = number
  default     = 30
}

variable "logs_retention_days" {
  description = "Logs retention in Loki (days)"
  type        = number
  default     = 7
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "tags" {
  type = map(string)
  default = {}
}
