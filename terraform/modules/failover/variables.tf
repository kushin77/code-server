variable "patroni_enabled" {
  description = "Enable Patroni for PostgreSQL HA"
  type        = bool
  default     = true
}

variable "patroni_version" {
  description = "Patroni version"
  type        = string
  default     = "3.0"
}

variable "replication_slot_enabled" {
  description = "Enable PostgreSQL replication slots"
  type        = bool
  default     = true
}

variable "replication_slot_name" {
  description = "Replication slot name"
  type        = string
  default     = "replica_slot"
}

variable "wal_level" {
  description = "PostgreSQL WAL level (minimal/replica/logical)"
  type        = string
  default     = "replica"
}

variable "max_wal_senders" {
  description = "Maximum WAL sender connections"
  type        = number
  default     = 10
}

variable "wal_keep_size" {
  description = "WAL segments to keep (GB)"
  type        = number
  default     = 10
}

variable "hot_standby_enabled" {
  description = "Enable hot standby mode on replica"
  type        = bool
  default     = true
}

variable "synchronous_replication_enabled" {
  description = "Enable synchronous replication (consistency over latency)"
  type        = bool
  default     = false
}

variable "synchronous_replica_count" {
  description = "Number of replicas to wait for in sync replication"
  type        = number
  default     = 1
}

variable "backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_method" {
  description = "Backup method (pg_basebackup/pgbackrest/wal-g)"
  type        = string
  default     = "pg_basebackup"
}

variable "backup_schedule_cron" {
  description = "Backup schedule (cron format)"
  type        = string
  default     = "0 2 * * *"
}

variable "backup_retention_days" {
  description = "Backup retention period (days)"
  type        = number
  default     = 30
}

variable "backup_compression_enabled" {
  description = "Enable backup compression"
  type        = bool
  default     = true
}

variable "point_in_time_recovery_days" {
  description = "Point-in-time recovery window (days)"
  type        = number
  default     = 7
}

variable "redis_sentinel_enabled" {
  description = "Enable Redis Sentinel for HA"
  type        = bool
  default     = true
}

variable "redis_sentinel_port" {
  description = "Redis Sentinel port"
  type        = number
  default     = 26379
}

variable "redis_sentinel_quorum" {
  description = "Sentinel quorum size"
  type        = number
  default     = 2
}

variable "redis_sentinel_down_after_ms" {
  description = "Sentinel marks replica down after (ms)"
  type        = number
  default     = 30000
}

variable "disaster_recovery_enabled" {
  description = "Enable disaster recovery procedures"
  type        = bool
  default     = true
}

variable "rto_target_minutes" {
  description = "Recovery Time Objective (minutes)"
  type        = number
  default     = 15
}

variable "rpo_target_seconds" {
  description = "Recovery Point Objective (seconds)"
  type        = number
  default     = 60
}

variable "backup_storage_backend" {
  description = "Backup storage (local/s3/minio)"
  type        = string
  default     = "minio"
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region backup replication"
  type        = bool
  default     = false
}

variable "failover_auto_enabled" {
  description = "Enable automatic failover"
  type        = bool
  default     = true
}

variable "failover_timeout_seconds" {
  description = "Failover timeout (seconds)"
  type        = number
  default     = 300
}
