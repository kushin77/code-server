// Failover Module — Patroni, Replication, Backup, Disaster Recovery
// Provides high availability, backup automation, and disaster recovery procedures

locals {
  patroni_config = {
    enabled        = var.patroni_enabled
    version        = var.patroni_version
  }

  replication_config = {
    slot_enabled       = var.replication_slot_enabled
    slot_name          = var.replication_slot_name
    wal_level          = var.wal_level
    max_wal_senders    = var.max_wal_senders
    wal_keep_size_gb   = var.wal_keep_size
    hot_standby        = var.hot_standby_enabled
    synchronous_enabled = var.synchronous_replication_enabled
    sync_replica_count = var.synchronous_replica_count
  }

  backup_config = {
    enabled           = var.backup_enabled
    method            = var.backup_method
    schedule          = var.backup_schedule_cron
    retention_days    = var.backup_retention_days
    compression       = var.backup_compression_enabled
    pitr_window_days  = var.point_in_time_recovery_days
    storage_backend   = var.backup_storage_backend
  }

  redis_sentinel_config = {
    enabled         = var.redis_sentinel_enabled
    port            = var.redis_sentinel_port
    quorum          = var.redis_sentinel_quorum
    down_after_ms   = var.redis_sentinel_down_after_ms
  }

  dr_config = {
    enabled               = var.disaster_recovery_enabled
    rto_minutes           = var.rto_target_minutes
    rpo_seconds           = var.rpo_target_seconds
    cross_region_enabled  = var.enable_cross_region_replication
    auto_failover         = var.failover_auto_enabled
    failover_timeout_secs = var.failover_timeout_seconds
  }
}

// Note: HA configuration, replication, and backup management via docker-compose and scripts
// This module defines recovery objectives, failover policies, and backup strategies
// Future: Integrate with Kubernetes operators (Zalando postgres-operator, Redis Enterprise) for full K8s HA
