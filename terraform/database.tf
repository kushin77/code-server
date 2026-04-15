################################################################################
# terraform/database.tf — PostgreSQL Replication Configuration
#
# Purpose: Define cross-region PostgreSQL replication (primary → 4 replicas)
# Replication: Streaming replication, RPO=0 (zero data loss)
# Failover: Automatic promotion of replica to primary (<30 seconds)
################################################################################

variable "postgres_replication_config" {
  type = object({
    primary_ip       = string  # 192.168.168.31
    replica_ips      = list(string)  # [192.168.168.32, 192.168.168.33, ...]
    replication_user = string
    replication_password = string  # From .env, never hardcoded
    port             = number
    max_wal_senders  = number  # Concurrent replicas
    max_replication_slots = number
    wal_level        = string  # logical, replica
    synchronous_commit = string  # remote_apply, on, off
  })
  
  description = "PostgreSQL replication configuration"
  
  default = {
    primary_ip           = "192.168.168.31"
    replica_ips          = ["192.168.168.32", "192.168.168.33", "192.168.168.34"]
    replication_user     = "replicator"
    replication_password = "CHANGEME"  # MUST be overridden in .env
    port                 = 5432
    max_wal_senders      = 10
    max_replication_slots = 10
    wal_level            = "replica"
    synchronous_commit   = "remote_apply"  # Synchronous for zero data loss
  }
}

variable "postgres_backup_config" {
  type = object({
    backup_frequency_hours = number
    retention_days         = number
    compression            = string  # gzip, bzip2
    backup_location        = string  # NAS path
  })
  
  description = "PostgreSQL backup configuration"
  
  default = {
    backup_frequency_hours = 4
    retention_days         = 30
    compression            = "gzip"
    backup_location        = "/mnt/nas-56/postgres-backups"
  }
}

################################################################################
# Database Output
################################################################################

output "replication_topology" {
  description = "PostgreSQL replication topology"
  value = {
    primary_server = {
      ip_address = var.postgres_replication_config.primary_ip
      role       = "primary"
      write_access = true
      read_access  = true
    }
    replica_servers = [
      for ip in var.postgres_replication_config.replica_ips :
      {
        ip_address   = ip
        role         = "hot-standby"
        write_access = false
        read_access  = true
        promotion_capable = true
      }
    ]
  }
}

output "replication_parameters" {
  description = "PostgreSQL replication parameters to configure"
  value = {
    port                    = var.postgres_replication_config.port
    wal_level               = var.postgres_replication_config.wal_level
    max_wal_senders         = var.postgres_replication_config.max_wal_senders
    max_replication_slots   = var.postgres_replication_config.max_replication_slots
    synchronous_commit      = var.postgres_replication_config.synchronous_commit
    replication_user        = var.postgres_replication_config.replication_user
    heartbeat_interval_s    = 10
    recovery_target_timeline = "latest"
  }
}

output "backup_strategy" {
  description = "Backup and recovery strategy"
  value = {
    frequency      = "${var.postgres_backup_config.backup_frequency_hours}h"
    retention      = "${var.postgres_backup_config.retention_days} days"
    compression    = var.postgres_backup_config.compression
    location       = var.postgres_backup_config.backup_location
    rpo_target     = "0 (zero data loss)"
    rto_target     = "5 minutes"
    backup_type    = "Full + WAL streaming"
    verification   = "Quarterly restore drills"
  }
}

output "replication_monitoring" {
  description = "Replication monitoring metrics"
  value = {
    lag_monitoring_interval = "10s"
    lag_alert_threshold_ms  = 1000
    replica_status_query    = "SELECT slot_name, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots"
    replication_lag_query   = "SELECT extract(epoch from (now() - pg_last_xact_replay_time()))"
  }
}

output "disaster_recovery_procedures" {
  description = "DR procedures for PostgreSQL"
  value = {
    "scenario_primary_failure" = {
      steps = [
        "1. Detect primary failure (health check timeout)",
        "2. Promote highest LSN replica to primary",
        "3. Update connection strings to new primary",
        "4. Verify data consistency across replicas",
        "5. Resume writes on new primary"
      ]
      rto_minutes = 5
    }
    "scenario_replica_failure" = {
      steps = [
        "1. Detect replica failure (health check timeout)",
        "2. Remove failed replica from replication slots",
        "3. Mark replica for rebuild",
        "4. Rebuild replica from base backup",
        "5. Resume streaming replication"
      ]
      rto_minutes = 30
    }
    "scenario_network_partition" = {
      steps = [
        "1. Detect network split",
        "2. Activate fence protocol (shoot the other side)",
        "3. Establish quorum (3+ regions)",
        "4. Primary continues in quorum subset",
        "5. Waiting replicas go read-only until reconnect"
      ]
      rto_minutes = 2
    }
  }
}
