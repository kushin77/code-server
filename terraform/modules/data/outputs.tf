#!/usr/bin/env terraform
# modules/data/outputs.tf — Data module outputs

output "postgres_config" {
  description = "PostgreSQL service configuration"
  value = {
    name                  = "postgres"
    version               = var.postgres_version
    port                  = var.postgres_port
    database              = var.postgres_db
    user                  = var.postgres_user
    memory                = var.postgres_memory_limit
    cpu                   = var.postgres_cpu_limit
    replication_user      = var.postgres_replication_user
    replication_lag_limit = "${var.postgres_replication_lag_limit_ms}ms"
  }
}

output "redis_config" {
  description = "Redis service configuration"
  value = {
    name                     = "redis"
    version                  = var.redis_version
    port                     = var.redis_port
    maxmemory                = var.redis_maxmemory
    memory_limit             = var.redis_memory_limit_container
    cpu                      = var.redis_cpu_limit
    persistence_enabled      = var.redis_persistence_enabled
  }
}

output "pgbouncer_config" {
  description = "PgBouncer connection pooler configuration"
  value = {
    name            = "pgbouncer"
    version         = var.pgbouncer_version
    port            = var.pgbouncer_port
    pool_mode       = var.pgbouncer_pool_mode
    pool_size       = var.pgbouncer_pool_size
    connect_timeout = "${var.pgbouncer_connect_timeout}s"
  }
}

output "replication_config" {
  description = "PostgreSQL replication configuration (primary vs replica)"
  value = {
    is_primary = var.is_primary
    role       = var.is_primary ? "primary" : "replica"
    replication_enabled = var.enable_replication
    hot_standby_enabled = var.enable_hot_standby
    synchronous_replication = var.enable_synchronous_replication
  }
}

output "backup_config" {
  description = "Backup configuration"
  value = {
    retention_days = var.backup_retention_days
    schedule       = var.backup_schedule_cron
  }
}
