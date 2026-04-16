# Terraform Module: Disaster Recovery & High Availability Stack (Patroni Replication, Backup, Failover)

module "failover" {
  source = "./modules/failover"

  # General configuration
  environment     = var.environment
  deployment_host = var.deployment_host
  domain          = var.domain
  namespace       = "failover"

  # Patroni Database Replication Configuration
  patroni_enabled = true
  patroni_image   = "patroni:${var.patroni_version}"
  patroni_memory  = "512Mi"
  patroni_cpu     = "250m"

  # Patroni cluster configuration
  patroni_cluster = {
    name              = "code-server-db"
    scope             = "code-server"
    namespace         = "production"
    loop_wait         = 10
    ttl               = 30
    retry_timeout     = 10
    maximum_lag_on_failover = 1048576  # 1MB
  }

  # PostgreSQL replication configuration
  postgres_replication = {
    max_wal_senders       = 10
    wal_keep_size         = "1GB"
    max_replication_slots = 10
    hot_standby           = true
    hot_standby_feedback  = true
  }

  # Patroni nodes (primary + replica)
  patroni_nodes = {
    primary = {
      name     = "postgres-primary"
      host     = var.primary_host_ip  # 192.168.168.31
      port     = var.postgres_port    # 5432
      type     = "primary"
      priority = 100
    }
    replica = {
      name     = "postgres-replica"
      host     = var.secondary_host_ip  # 192.168.168.42
      port     = var.postgres_port
      type     = "replica"
      priority = 50
    }
  }

  # Patroni monitoring and alerting
  patroni_monitoring = {
    enabled = true
    metrics_enabled = true
    health_check_interval = 10
    metrics_path = "/metrics"
  }

  # Patroni failover configuration
  patroni_failover = {
    auto_failover_enabled        = true
    failover_timeout             = 10  # seconds
    after_failure_wait           = 30  # seconds
    after_successful_failover_tt = 5   # minutes
    cascade                      = true  # Allow cascading replication
  }

  # Backup Configuration
  backup_enabled = true
  backup_type    = "physical"  # physical or logical
  backup_format  = "tar"       # tar, plain, or custom

  # Backup schedule
  backup_schedule = {
    full_backup_day_of_week   = 0  # Sunday
    full_backup_hour          = 2  # 2 AM
    incremental_backup_days   = [1, 2, 3, 4, 5, 6]
    incremental_backup_hour   = 3  # 3 AM
    transaction_log_backup    = true
    wal_backup_interval       = 300  # 5 minutes
  }

  # Backup destination (S3)
  backup_destination = {
    type                = "s3"
    bucket              = "code-server-backups"
    region              = var.gcp_region
    path_prefix         = "postgres"
    compression         = "gzip"
    encryption          = "AES256"
    retention_days      = 30
    cross_region_backup = true
  }

  # Backup verification
  backup_verification = {
    enabled            = true
    test_restore       = true
    test_interval_days = 7
    checksum_validation = true
  }

  # Point-in-Time Recovery (PITR)
  pitr_enabled = true
  pitr_retention_days = 30

  # WAL archiving
  wal_archiving = {
    enabled = true
    archive_timeout = 300  # 5 minutes
    archive_command = "aws s3 cp %p s3://code-server-backups/postgres/wal/%f"
  }

  # Replication lag monitoring
  replication_monitoring = {
    enabled = true
    lag_threshold_bytes = 1048576  # 1MB
    lag_threshold_seconds = 30
    alert_on_lag = true
  }

  # Automatic switchover configuration
  switchover = {
    enabled = true
    target_node = "postgres-replica"
    timeout = 60  # seconds
    cascade = true
  }

  # Redis High Availability (Sentinel)
  redis_sentinel_enabled = true
  redis_sentinel_image   = "redis:${var.redis_version}"
  redis_memory           = "512Mi"
  redis_cpu              = "250m"

  # Redis Sentinel configuration
  redis_sentinel = {
    quorum         = 2
    down_after_ms  = 30000  # 30 seconds
    failover_timeout = 180000  # 3 minutes
    parallel_syncs = 1
  }

  # Redis nodes (primary + replicas)
  redis_nodes = {
    primary = {
      name = "redis-primary"
      host = var.primary_host_ip
      port = var.redis_port
      type = "master"
    }
    replica_1 = {
      name = "redis-replica-1"
      host = var.secondary_host_ip
      port = var.redis_port
      type = "replica"
    }
  }

  # Redis persistence
  redis_persistence = {
    enabled = true
    type = "rdb"  # rdb or aof
    save_intervals = [
      { seconds = 900, changes = 1 },    # Save after 15 min and 1 change
      { seconds = 300, changes = 10 },   # Save after 5 min and 10 changes
      { seconds = 60, changes = 10000 }  # Save after 1 min and 10k changes
    ]
  }

  # Load balancing for database access
  db_load_balancer = {
    enabled = true
    type    = "pgbouncer"  # pgbouncer for PostgreSQL
    pool_mode = "transaction"
    max_client_conn = 1000
    default_pool_size = 25
  }

  # Disaster Recovery Plan
  dr_plan = {
    rpo = "5m"  # Recovery Point Objective: lose max 5 min of data
    rto = "1m"  # Recovery Time Objective: restore in max 1 minute
    backup_locations = [
      var.primary_host_ip,      # Local backup
      var.secondary_host_ip,    # Remote backup
      "s3://code-server-backups"  # Cloud backup
    ]
  }

  # Failover testing
  failover_testing = {
    enabled           = true
    test_frequency    = "weekly"  # weekly or monthly
    test_day_of_week  = 6         # Saturday
    test_hour         = 1         # 1 AM
    rollback_after_test = true
  }

  # Resource limits
  resource_limits = {
    memory = "3Gi"
    cpu    = "1000m"
  }

  # Logging
  logging = {
    level       = var.log_level
    format      = "json"
    audit_enabled = true
    audit_sink  = "http://localhost:${var.loki_port}/loki/api/v1/push"
  }

  # Metrics and monitoring
  metrics = {
    enabled = true
    prometheus_port = 9090
    metrics_interval = 15  # seconds
  }

  # Tags
  tags = merge(var.tags, {
    Module  = "failover"
    Purpose = "Patroni Replication, Backup, Disaster Recovery, HA"
  })
}

# Output replication status
output "replication_status" {
  value = {
    primary_host            = module.failover.primary_host
    replica_host            = module.failover.replica_host
    replication_lag_bytes   = module.failover.replication_lag_bytes
    replication_lag_seconds = module.failover.replication_lag_seconds
  }
}

# Output backup status
output "backup_status" {
  value = {
    last_full_backup     = module.failover.last_full_backup_time
    last_incremental_backup = module.failover.last_incremental_backup_time
    backup_count         = module.failover.backup_count
    oldest_backup_age    = module.failover.oldest_backup_age_days
    backup_size_gb       = module.failover.backup_size_gb
  }
}

# Output failover readiness
output "failover_readiness" {
  value = {
    primary_healthy      = module.failover.primary_healthy
    replica_healthy      = module.failover.replica_healthy
    replication_in_sync  = module.failover.replication_in_sync
    backup_current       = module.failover.backup_current
    can_failover         = module.failover.can_failover
  }
}

# Output recovery time objectives
output "recovery_objectives" {
  value = {
    rpo_minutes = module.failover.rpo_minutes
    rto_minutes = module.failover.rto_minutes
  }
}

# Output failover testing schedule
output "failover_testing_schedule" {
  value = {
    next_test_date = module.failover.next_test_date
    test_frequency = module.failover.test_frequency
    last_test_date = module.failover.last_test_date
  }
}
