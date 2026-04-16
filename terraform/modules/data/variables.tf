#!/usr/bin/env terraform
# modules/data/variables.tf — Data tier (PostgreSQL, Redis, PgBouncer)

variable "is_primary" {
  description = "Is this the primary host (true) or replica (false)?"
  type        = bool
}

variable "primary_host_ip" {
  description = "Primary host IP for replication source (replica only)"
  type        = string
  default     = ""
  validation {
    condition     = var.primary_host_ip == "" || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.primary_host_ip))
    error_message = "Must be empty or a valid IP address."
  }
}

variable "replica_host_ip" {
  description = "Replica host IP (primary only, for replication target)"
  type        = string
  default     = ""
}

variable "postgres_version" {
  description = "PostgreSQL Docker image version"
  type        = string
  default     = "15.6-alpine"
}

variable "postgres_db" {
  description = "Primary PostgreSQL database name"
  type        = string
  default     = "codeserver"
}

variable "postgres_user" {
  description = "PostgreSQL user (codeserver, not root)"
  type        = string
  default     = "codeserver"
}

variable "postgres_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "postgres_memory_limit" {
  description = "PostgreSQL memory limit"
  type        = string
  default     = "2g"
}

variable "postgres_cpu_limit" {
  description = "PostgreSQL CPU limit (cores)"
  type        = string
  default     = "1.0"
}

variable "postgres_replication_user" {
  description = "PostgreSQL replication user (for HA/DR)"
  type        = string
  default     = "replicator"
}

variable "postgres_replication_lag_limit_ms" {
  description = "Maximum acceptable replication lag (milliseconds)"
  type        = number
  default     = 5000
  validation {
    condition     = var.postgres_replication_lag_limit_ms > 0
    error_message = "Must be greater than 0."
  }
}

variable "redis_version" {
  description = "Redis Docker image version"
  type        = string
  default     = "7.2-alpine"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "redis_memory_limit" {
  description = "Redis memory limit (max memory in MB, e.g., 512mb)"
  type        = string
  default     = "512mb"
}

variable "redis_maxmemory" {
  description = "Redis maxmemory setting"
  type        = string
  default     = "512mb"
}

variable "redis_memory_limit_container" {
  description = "Redis container memory limit"
  type        = string
  default     = "768m"
}

variable "redis_cpu_limit" {
  description = "Redis CPU limit (cores)"
  type        = string
  default     = "0.5"
}

variable "redis_persistence_enabled" {
  description = "Enable Redis persistence (save/appendonly)"
  type        = bool
  default     = false  # Disable for cache-only; enable for data safety
}

variable "pgbouncer_version" {
  description = "PgBouncer version (optional connection pooler)"
  type        = string
  default     = "1.21"
}

variable "pgbouncer_port" {
  description = "PgBouncer listen port"
  type        = number
  default     = 6432
}

variable "pgbouncer_pool_size" {
  description = "PgBouncer default pool size per database"
  type        = number
  default     = 25
  validation {
    condition     = var.pgbouncer_pool_size >= 10 && var.pgbouncer_pool_size <= 200
    error_message = "Pool size should be between 10 and 200."
  }
}

variable "pgbouncer_pool_mode" {
  description = "PgBouncer pool mode (session, transaction, statement)"
  type        = string
  default     = "transaction"
  validation {
    condition     = contains(["session", "transaction", "statement"], var.pgbouncer_pool_mode)
    error_message = "Must be one of: session, transaction, statement."
  }
}

variable "pgbouncer_connect_timeout" {
  description = "PgBouncer connect timeout (seconds)"
  type        = number
  default     = 15
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Retention must be between 7 and 365 days."
  }
}

variable "backup_schedule_cron" {
  description = "Cron schedule for automated backups"
  type        = string
  default     = "0 2 * * *"  # 2 AM daily
}

variable "enable_replication" {
  description = "Enable PostgreSQL streaming replication"
  type        = bool
  default     = true
}

variable "enable_hot_standby" {
  description = "Enable hot standby mode on replica"
  type        = bool
  default     = true
}

variable "enable_synchronous_replication" {
  description = "Require replica to acknowledge writes (trade latency for safety)"
  type        = bool
  default     = false
}
