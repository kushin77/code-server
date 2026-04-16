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

# Module: Observability & Monitoring (Prometheus, Grafana, AlertManager, Loki, Jaeger)
module "monitoring" {
  source = "./modules/monitoring"

  prometheus_version                = var.prometheus_version
  prometheus_port                   = var.prometheus_port
  prometheus_retention              = var.prometheus_retention
  prometheus_memory_limit           = var.prometheus_memory_limit
  prometheus_cpu_limit              = var.prometheus_cpu_limit
  grafana_version                   = var.grafana_version
  grafana_port                      = var.grafana_port
  grafana_admin_user                = var.grafana_admin_user
  grafana_memory_limit              = var.grafana_memory_limit
  grafana_cpu_limit                 = var.grafana_cpu_limit
  alertmanager_version              = var.alertmanager_version
  alertmanager_port                 = var.alertmanager_port
  alertmanager_memory_limit         = var.alertmanager_memory_limit
  alertmanager_cpu_limit            = var.alertmanager_cpu_limit
  loki_version                      = var.loki_version
  loki_port                         = var.loki_port
  loki_memory_limit                 = var.loki_memory_limit
  loki_cpu_limit                    = var.loki_cpu_limit
  jaeger_version                    = var.jaeger_version
  jaeger_port                       = var.jaeger_port
  jaeger_otlp_port                  = var.jaeger_otlp_port
  jaeger_memory_limit               = var.jaeger_memory_limit
  jaeger_cpu_limit                  = var.jaeger_cpu_limit
  slo_target_availability           = var.slo_target_availability
  slo_target_latency_p99            = var.slo_target_latency_p99
  slo_target_error_rate             = var.slo_target_error_rate
  alert_severity_critical_enabled   = var.alert_severity_critical_enabled
  alert_severity_high_enabled       = var.alert_severity_high_enabled
  alert_severity_medium_enabled     = var.alert_severity_medium_enabled

  depends_on = [module.core, module.data]
}

# Module: Networking & API Gateway (Kong, CoreDNS, Caddy)
module "networking" {
  source = "./modules/networking"

  kong_version                      = var.kong_version
  kong_proxy_port                   = var.kong_proxy_port
  kong_proxy_ssl_port               = var.kong_proxy_ssl_port
  kong_admin_port                   = var.kong_admin_port
  kong_memory_limit                 = var.kong_memory_limit
  kong_cpu_limit                    = var.kong_cpu_limit
  kong_rate_limit_minute            = var.kong_rate_limit_minute
  kong_rate_limit_hour              = var.kong_rate_limit_hour
  kong_rate_limit_auth_minute       = var.kong_rate_limit_auth_minute
  coredns_version                   = var.coredns_version
  coredns_port                      = var.coredns_port
  coredns_memory_limit              = var.coredns_memory_limit
  coredns_cpu_limit                 = var.coredns_cpu_limit
  caddy_version                     = var.caddy_version
  caddy_http_port                   = var.caddy_http_port
  caddy_https_port                  = var.caddy_https_port
  caddy_admin_port                  = var.caddy_admin_port
  caddy_auto_https                  = var.caddy_auto_https
  caddy_memory_limit                = var.caddy_memory_limit
  caddy_cpu_limit                   = var.caddy_cpu_limit
  enable_tls_termination            = var.enable_tls_termination
  enable_rate_limiting              = var.enable_rate_limiting
  enable_service_discovery          = var.enable_service_discovery
  load_balancing_algorithm          = var.load_balancing_algorithm

  depends_on = [module.core]
}

# Module: Security & Policy Enforcement (Falco, Vault, OPA)
module "security" {
  source = "./modules/security"

  falco_version                     = var.falco_version
  falco_mode                        = var.falco_mode
  falco_memory_limit                = var.falco_memory_limit
  falco_cpu_limit                   = var.falco_cpu_limit
  vault_version                     = var.vault_version
  vault_port                        = var.vault_port
  vault_memory_limit                = var.vault_memory_limit
  vault_cpu_limit                   = var.vault_cpu_limit
  vault_max_lease_ttl               = var.vault_max_lease_ttl
  vault_default_lease_ttl           = var.vault_default_lease_ttl
  opa_version                       = var.opa_version
  opa_port                          = var.opa_port
  opa_memory_limit                  = var.opa_memory_limit
  opa_cpu_limit                     = var.opa_cpu_limit
  enable_apparmor                   = var.enable_apparmor
  enable_seccomp                    = var.enable_seccomp
  enable_selinux                    = var.enable_selinux
  enable_runtime_monitoring         = var.enable_runtime_monitoring
  enable_policy_enforcement         = var.enable_policy_enforcement
  enable_secret_management          = var.enable_secret_management
  audit_log_retention_days          = var.audit_log_retention_days
  vulnerability_scan_enabled        = var.vulnerability_scan_enabled
  container_image_scan_enabled      = var.container_image_scan_enabled

  depends_on = [module.core]
}

# Module: DNS Management & TLS Certificates (Cloudflare, GoDaddy, ACME)
module "dns" {
  source = "./modules/dns"

  cloudflare_enabled                = var.cloudflare_enabled
  cloudflare_tunnel_token           = var.cloudflare_tunnel_token
  cloudflare_zone_id                = var.cloudflare_zone_id
  cloudflare_dns_proxy_enabled      = var.cloudflare_dns_proxy_enabled
  cloudflare_waf_enabled            = var.cloudflare_waf_enabled
  godaddy_enabled                   = var.godaddy_enabled
  godaddy_api_key                   = var.godaddy_api_key
  godaddy_api_secret                = var.godaddy_api_secret
  domain_primary                    = var.domain_primary
  domain_secondary                  = var.domain_secondary
  dns_ttl_default                   = var.dns_ttl_default
  dns_ttl_short                     = var.dns_ttl_short
  dns_failover_enabled              = var.dns_failover_enabled
  dns_failover_health_check_interval = var.dns_failover_health_check_interval
  dns_failover_threshold            = var.dns_failover_threshold
  acme_provider                     = var.acme_provider
  acme_email                        = var.acme_email
  acme_renewal_days_before_expiry   = var.acme_renewal_days_before_expiry
  enable_dns_dnssec                 = var.enable_dns_dnssec
  enable_dns_rate_limiting          = var.enable_dns_rate_limiting

  depends_on = [module.networking]
}

# Module: High Availability & Disaster Recovery (Patroni, Backup, Failover)
module "failover" {
  source = "./modules/failover"

  patroni_enabled                   = var.patroni_enabled
  patroni_version                   = var.patroni_version
  replication_slot_enabled          = var.replication_slot_enabled
  replication_slot_name             = var.replication_slot_name
  wal_level                         = var.wal_level
  max_wal_senders                   = var.max_wal_senders
  wal_keep_size                     = var.wal_keep_size
  hot_standby_enabled               = var.hot_standby_enabled
  synchronous_replication_enabled   = var.synchronous_replication_enabled
  synchronous_replica_count         = var.synchronous_replica_count
  backup_enabled                    = var.backup_enabled
  backup_method                     = var.backup_method
  backup_schedule_cron              = var.backup_schedule_cron
  backup_retention_days             = var.backup_retention_days
  backup_compression_enabled        = var.backup_compression_enabled
  point_in_time_recovery_days       = var.point_in_time_recovery_days
  redis_sentinel_enabled            = var.redis_sentinel_enabled
  redis_sentinel_port               = var.redis_sentinel_port
  redis_sentinel_quorum             = var.redis_sentinel_quorum
  redis_sentinel_down_after_ms      = var.redis_sentinel_down_after_ms
  disaster_recovery_enabled         = var.disaster_recovery_enabled
  rto_target_minutes                = var.rto_target_minutes
  rpo_target_seconds                = var.rpo_target_seconds
  backup_storage_backend            = var.backup_storage_backend
  enable_cross_region_replication   = var.enable_cross_region_replication
  failover_auto_enabled             = var.failover_auto_enabled
  failover_timeout_seconds          = var.failover_timeout_seconds

  depends_on = [module.data]
}
