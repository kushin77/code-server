# Failover Module - Patroni Replication, Backups, DR
# P2 #418 Phase 2 Implementation

variable "patroni_version" {
  description = "Patroni cluster manager version"
  type        = string
  default     = "3.0.0"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.3"
}

variable "postgres_storage_size" {
  description = "PostgreSQL persistent volume size"
  type        = string
  default     = "100Gi"
}

variable "etcd_version" {
  description = "etcd version for Patroni"
  type        = string
  default     = "3.5.9"
}

variable "backup_retention_days" {
  description = "Backup retention period (days)"
  type        = number
  default     = 30
}

variable "backup_schedule" {
  description = "Backup schedule (cron format)"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM
}

variable "rpo_seconds" {
  description = "Recovery Point Objective (seconds)"
  type        = number
  default     = 300  # 5 minutes
}

variable "rto_seconds" {
  description = "Recovery Time Objective (seconds)"
  type        = number
  default     = 60   # 1 minute
}

variable "replication_slots" {
  description = "Number of logical replication slots"
  type        = number
  default     = 3
}

variable "wal_level" {
  description = "WAL level (replica, logical)"
  type        = string
  default     = "replica"
}

variable "max_wal_senders" {
  description = "Maximum WAL senders"
  type        = number
  default     = 10
}

variable "s3_backup_bucket" {
  description = "S3 bucket for backups (optional)"
  type        = string
  default     = ""
}

variable "s3_backup_region" {
  description = "S3 region"
  type        = string
  default     = "us-east-1"
}

variable "labels" {
  description = "Common labels for all failover resources"
  type        = map(string)
  default = {
    module      = "failover"
    managed_by  = "terraform"
  }
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "failover"
}

variable "docker_host" {
  description = "Docker host for non-K8s deployments"
  type        = string
  default     = ""
}
