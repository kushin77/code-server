# Variables for ArgoCD Terraform module

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "cluster_context" {
  description = "Kubernetes context name"
  type        = string
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_version" {
  description = "ArgoCD version to deploy"
  type        = string
  default     = "v2.10.0"
}

variable "github_repo_url" {
  description = "GitHub repository URL for applications"
  type        = string
  default     = "https://github.com/kushin77/code-server"
}

variable "github_branch" {
  description = "Git branch for deployments"
  type        = string
  default     = "main"
}

variable "enable_ha" {
  description = "Enable HA (minimum 2 replicas)"
  type        = bool
  default     = true
}

variable "enable_tls" {
  description = "Enable TLS for ArgoCD server"
  type        = bool
  default     = false
}

variable "tls_issuer" {
  description = "Cert-manager issuer name for TLS"
  type        = string
  default     = "letsencrypt-prod"
}

variable "oidc_enabled" {
  description = "Enable OIDC authentication"
  type        = bool
  default     = false
}

variable "oidc_provider" {
  description = "OIDC provider URL"
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC client ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "oidc_client_secret" {
  description = "OIDC client secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "notification_slack_webhook" {
  description = "Slack webhook URL for notifications"
  type        = string
  sensitive   = true
  default     = ""
}

variable "notification_email" {
  description = "Email address for notifications"
  type        = string
  default     = ""
}

variable "sync_wave_timeout" {
  description = "Timeout for sync waves in seconds"
  type        = number
  default     = 300
}

variable "auto_sync_enabled" {
  description = "Enable automatic sync by default"
  type        = bool
  default     = true
}

variable "auto_prune_enabled" {
  description = "Enable automatic pruning of out-of-sync resources"
  type        = bool
  default     = true
}

variable "self_heal_enabled" {
  description = "Enable self-healing of drifted resources"
  type        = bool
  default     = true
}

variable "webhook_github_secret" {
  description = "GitHub webhook secret for ArgoCD"
  type        = string
  sensitive   = true
  default     = ""
}

variable "log_level" {
  description = "ArgoCD log level"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "Log level must be one of: debug, info, warn, error."
  }
}

variable "metrics_port" {
  description = "Prometheus metrics port for ArgoCD"
  type        = number
  default     = 8082
}

variable "dex_enabled" {
  description = "Enable Dex for OIDC"
  type        = bool
  default     = false
}

variable "redis_persistence_enabled" {
  description = "Enable Redis persistence"
  type        = bool
  default     = true
}

variable "redis_size" {
  description = "Redis storage size"
  type        = string
  default     = "10Gi"
}

variable "backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Backup schedule (cron format)"
  type        = string
  default     = "0 2 * * *"
}

variable "backup_retention_days" {
  description = "Retention period for backups in days"
  type        = number
  default     = 30
}

variable "monitored_namespaces" {
  description = "List of namespaces to monitor"
  type        = list(string)
  default     = ["*"]
}

variable "cluster_labels" {
  description = "Labels for cluster identification in ApplicationSets"
  type        = map(string)
  default = {
    "environment" = "production"
    "region"      = "us-east"
  }
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    "Phase"      = "9-gitops"
    "ManagedBy"  = "terraform"
    "Version"    = "1.0.0"
  }
}
