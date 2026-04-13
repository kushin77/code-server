# Phase 5: Variables for Backup & Disaster Recovery

variable "namespace_backup" {
  type        = string
  description = "Kubernetes namespace for backup/Velero"
  default     = "backup"
}

variable "namespace_monitoring" {
  type        = string
  description = "Kubernetes namespace for monitoring (used for backup scope)"
  default     = "monitoring"
}

variable "namespace_code_server" {
  type        = string
  description = "Kubernetes namespace for code-server (used for backup scope)"
  default     = "code-server"
}

variable "namespace_security" {
  type        = string
  description = "Kubernetes namespace for security (used for backup scope)"
  default     = "security"
}

variable "environment" {
  type        = string
  description = "Environment name for labels"
  default     = "production"
}

variable "enable_velero" {
  type        = bool
  description = "Enable Velero backup and disaster recovery"
  default     = true
}

variable "create_velero_helm_repo" {
  type        = bool
  description = "Create Velero Helm repository"
  default     = true
}

variable "velero_chart_version" {
  type        = string
  description = "Velero Helm chart version"
  default     = "5.0.0"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.velero_chart_version))
    error_message = "Velero chart version must be in semver format (e.g., 5.0.0)"
  }
}

variable "velero_image_tag" {
  type        = string
  description = "Velero container image tag"
  default     = "v1.12.0"
}

variable "velero_storage_size" {
  type        = string
  description = "Persistent volume size for Velero backups"
  default     = "500Gi"
}

variable "velero_requests" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "Velero resource requests"
  default = {
    cpu    = "500m"
    memory = "512Mi"
  }
}

variable "velero_limits" {
  type = object({
    cpu    = string
    memory = string
  })
  description = "Velero resource limits"
  default = {
    cpu    = "1000m"
    memory = "1Gi"
  }
}

variable "backup_bucket_name" {
  type        = string
  description = "S3 or local backup storage bucket name"
  default     = "velero-backups"
}

variable "backup_storage_url" {
  type        = string
  description = "S3-compatible backup storage URL (for local Minio, S3, etc.)"
  default     = "http://minio:9000"
}

variable "backup_daily_schedule" {
  type        = string
  description = "Cron schedule for daily full backups"
  default     = "0 2 * * *"  # 02:00 UTC daily
}

variable "backup_hourly_schedule" {
  type        = string
  description = "Cron schedule for hourly incremental backups"
  default     = "0 * * * *"  # Every hour
}

variable "backup_retention_days" {
  type        = string
  description = "Retention period for full backups (go duration format)"
  default     = "720h"  # 30 days
}

variable "backup_incremental_retention_hours" {
  type        = string
  description = "Retention period for incremental backups (go duration format)"
  default     = "168h"  # 7 days
}

variable "restic_timeout" {
  type        = string
  description = "Timeout for Restic operations (volume snapshots)"
  default     = "4h"
}

variable "enable_restore_testing" {
  type        = bool
  description = "Enable automated restore testing script"
  default     = true
}

variable "enable_restore_verification" {
  type        = bool
  description = "Enable periodic restore verification CronJob"
  default     = true
}

variable "restore_check_schedule" {
  type        = string
  description = "Cron schedule for restore verification checks"
  default     = "0 3 * * 0"  # 03:00 UTC every Sunday
}
