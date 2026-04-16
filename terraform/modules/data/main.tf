#!/usr/bin/env terraform
# modules/data/main.tf — Data tier provisioning (PostgreSQL, Redis, PgBouncer)
# Currently, data services are Docker-managed via docker-compose.yml
# This module serves as configuration/reference layer

# Future: Native Terraform resources for:
# - Google Cloud SQL (if migrating to cloud)
# - AWS RDS + ElastiCache (if migrating to cloud)
# - On-prem: Patroni-managed PostgreSQL with Terraform provisioning

locals {
  data_services = {
    postgres = {
      name     = "postgres"
      version  = var.postgres_version
      port     = var.postgres_port
      memory   = var.postgres_memory_limit
      cpu      = var.postgres_cpu_limit
      database = var.postgres_db
      user     = var.postgres_user
      replication = {
        enabled                 = var.enable_replication
        user                    = var.postgres_replication_user
        max_lag_ms              = var.postgres_replication_lag_limit_ms
        hot_standby             = var.enable_hot_standby
        synchronous_replication = var.enable_synchronous_replication
      }
    }
    redis = {
      name      = "redis"
      version   = var.redis_version
      port      = var.redis_port
      maxmemory = var.redis_maxmemory
      memory    = var.redis_memory_limit_container
      cpu       = var.redis_cpu_limit
      persistence = {
        enabled = var.redis_persistence_enabled
        save    = "" # Disable RDB snapshots for cache-only
      }
    }
    pgbouncer = {
      name            = "pgbouncer"
      version         = var.pgbouncer_version
      port            = var.pgbouncer_port
      pool_mode       = var.pgbouncer_pool_mode
      pool_size       = var.pgbouncer_pool_size
      connect_timeout = var.pgbouncer_connect_timeout
      enabled         = true # When connection pooling needed
    }
  }

  # Replication configuration (primary vs replica differentiation)
  replication_config = var.is_primary ? {
    role                  = "primary"
    standby_setup_enabled = true
    replication_targets   = var.replica_host_ip != "" ? [var.replica_host_ip] : []
    replication_source    = ""
    } : {
    role                  = "replica"
    standby_setup_enabled = false
    replication_targets   = []
    replication_source    = var.primary_host_ip
  }
}
