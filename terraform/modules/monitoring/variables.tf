# Monitoring Module - Prometheus, Grafana, AlertManager, SLO Tracking
# P2 #418 Phase 2 Implementation

variable "prometheus_version" {
  description = "Prometheus version"
  type        = string
  default     = "v2.48.0"
}

variable "prometheus_storage_size" {
  description = "Prometheus persistent volume size"
  type        = string
  default     = "50Gi"
}

variable "prometheus_retention_days" {
  description = "Prometheus metrics retention (days)"
  type        = number
  default     = 30
}

variable "prometheus_scrape_interval" {
  description = "Prometheus scrape interval (seconds)"
  type        = number
  default     = 15
}

variable "grafana_version" {
  description = "Grafana version"
  type        = string
  default     = "10.2.3"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "grafana_storage_size" {
  description = "Grafana persistent volume size"
  type        = string
  default     = "10Gi"
}

variable "alertmanager_version" {
  description = "AlertManager version"
  type        = string
  default     = "v0.26.0"
}

variable "alertmanager_slack_webhook" {
  description = "Slack webhook for alerts (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alertmanager_pagerduty_key" {
  description = "PagerDuty integration key (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "slo_error_budget_percentage" {
  description = "SLO error budget percentage (default 0.1% = 99.9% availability)"
  type        = number
  default     = 0.1
}

variable "labels" {
  description = "Common labels for all monitoring resources"
  type        = map(string)
  default = {
    module      = "monitoring"
    managed_by  = "terraform"
  }
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "monitoring"
}

variable "docker_host" {
  description = "Docker host for non-K8s deployments (format: tcp://host:2375)"
  type        = string
  default     = ""
}
