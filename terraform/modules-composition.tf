#!/usr/bin/env terraform
# terraform/modules-composition.tf — Module composition for root module
# This file composes all child modules to create the full infrastructure

# Module: Core Application Services (code-server, Caddy, OAuth2-proxy)
module "core" {
  source = "./modules/core"

  host_ip                   = var.host_ip
  domain                    = var.domain
  code_server_port          = var.code_server_port
  code_server_version       = var.code_server_version
  code_server_memory_limit  = var.code_server_memory_limit
  code_server_cpu_limit     = var.code_server_cpu_limit
  caddy_version             = var.caddy_version
  caddy_port_http           = var.caddy_port_http
  caddy_port_https          = var.caddy_port_https
  caddy_admin_port          = var.caddy_admin_port
  caddy_auto_https          = var.caddy_auto_https
  caddy_tls_email           = var.caddy_tls_email
  oauth2_proxy_version      = var.oauth2_proxy_version
  oauth2_proxy_port         = var.oauth2_proxy_port
  oauth2_provider           = var.oauth2_provider
  oauth2_callback_url       = var.oauth2_callback_url
  oauth2_memory_limit       = var.oauth2_memory_limit
  oauth2_cpu_limit          = var.oauth2_cpu_limit

  depends_on = [module.data]
}

# Module: Data Tier (PostgreSQL, Redis, PgBouncer)
module "data" {
  source = "./modules/data"

  is_primary                        = var.is_primary
  primary_host_ip                   = var.primary_host_ip
  replica_host_ip                   = var.replica_host_ip
  postgres_version                  = var.postgres_version
  postgres_db                       = var.postgres_db
  postgres_user                     = var.postgres_user
  postgres_port                     = var.postgres_port
  postgres_memory_limit             = var.postgres_memory_limit
  postgres_cpu_limit                = var.postgres_cpu_limit
  postgres_replication_user         = var.postgres_replication_user
  postgres_replication_lag_limit_ms = var.postgres_replication_lag_limit_ms
  redis_version                     = var.redis_version
  redis_port                        = var.redis_port
  redis_memory_limit                = var.redis_memory_limit
  redis_maxmemory                   = var.redis_maxmemory
  redis_memory_limit_container      = var.redis_memory_limit_container
  redis_cpu_limit                   = var.redis_cpu_limit
  redis_persistence_enabled         = var.redis_persistence_enabled
  pgbouncer_version                 = var.pgbouncer_version
  pgbouncer_port                    = var.pgbouncer_port
  pgbouncer_pool_size               = var.pgbouncer_pool_size
  pgbouncer_pool_mode               = var.pgbouncer_pool_mode
  pgbouncer_connect_timeout         = var.pgbouncer_connect_timeout
  backup_retention_days             = var.backup_retention_days
  backup_schedule_cron              = var.backup_schedule_cron
  enable_replication                = var.enable_replication
  enable_hot_standby                = var.enable_hot_standby
  enable_synchronous_replication    = var.enable_synchronous_replication
}

# TODO: Add remaining modules
# module "monitoring" {
#   source = "./modules/monitoring"
#   # ...
# }
#
# module "networking" {
#   source = "./modules/networking"
#   # ...
# }
#
# module "security" {
#   source = "./modules/security"
#   # ...
# }
#
# module "dns" {
#   source = "./modules/dns"
#   # ...
# }
#
# module "failover" {
#   source = "./modules/failover"
#   # ...
# }
