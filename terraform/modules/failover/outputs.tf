output "patroni_config" {
  description = "Patroni PostgreSQL HA configuration"
  value = {
    enabled = local.patroni_config.enabled
    version = local.patroni_config.version
  }
}

output "replication_config" {
  description = "PostgreSQL replication configuration"
  value = {
    slot_enabled            = local.replication_config.slot_enabled
    slot_name               = local.replication_config.slot_name
    wal_level               = local.replication_config.wal_level
    max_wal_senders         = local.replication_config.max_wal_senders
    wal_keep_size_gb        = local.replication_config.wal_keep_size_gb
    hot_standby_enabled     = local.replication_config.hot_standby
    synchronous_replication = local.replication_config.synchronous_enabled
    sync_replica_count      = local.replication_config.sync_replica_count
  }
}

output "backup_config" {
  description = "Backup automation configuration"
  value = {
    enabled                       = local.backup_config.enabled
    backup_method                 = local.backup_config.method
    schedule_cron                 = local.backup_config.schedule
    retention_days                = local.backup_config.retention_days
    compression_enabled           = local.backup_config.compression
    point_in_time_recovery_window = "${local.backup_config.pitr_window_days} days"
    storage_backend               = local.backup_config.storage_backend
  }
}

output "redis_sentinel_config" {
  description = "Redis Sentinel HA configuration"
  value = {
    enabled       = local.redis_sentinel_config.enabled
    port          = local.redis_sentinel_config.port
    quorum        = local.redis_sentinel_config.quorum
    down_after_ms = local.redis_sentinel_config.down_after_ms
  }
}

output "disaster_recovery_config" {
  description = "Disaster recovery objectives and procedures"
  value = {
    enabled                    = local.dr_config.enabled
    rto_minutes                = local.dr_config.rto_minutes
    rpo_seconds                = local.dr_config.rpo_seconds
    cross_region_replication   = local.dr_config.cross_region_enabled
    automatic_failover_enabled = local.dr_config.auto_failover
    failover_timeout_seconds   = local.dr_config.failover_timeout_secs
  }
}

output "recovery_objectives" {
  description = "Service recovery targets"
  value = {
    rto_sla = "≤ ${local.dr_config.rto_minutes} minutes"
    rpo_sla = "≤ ${local.dr_config.rpo_seconds} seconds"
  }
}
