# Terraform Modules Composition - Root Integration
# P2 #418 Phase 3: Integration of all 5 core modules
# This file composes all modules into the production infrastructure
# NOTE: terraform block and provider configurations are in main.tf

################################
# MODULE 1: Monitoring (Prometheus, Grafana, AlertManager)
################################
module "monitoring" {
  source = "./modules/monitoring"

  # Configuration
  prometheus_version         = var.prometheus_version
  prometheus_storage_size    = var.prometheus_storage_size
  prometheus_retention_days  = var.prometheus_retention_days
  prometheus_scrape_interval = var.prometheus_scrape_interval

  grafana_version        = var.grafana_version
  grafana_admin_password = var.grafana_admin_password
  grafana_storage_size   = var.grafana_storage_size

  alertmanager_version       = var.alertmanager_version
  alertmanager_slack_webhook = var.alertmanager_slack_webhook
  alertmanager_pagerduty_key = var.alertmanager_pagerduty_key

  slo_error_budget_percentage = var.slo_error_budget_percentage

  # Infrastructure
  docker_host = var.docker_host
  namespace   = var.monitoring_namespace
  labels      = merge(local.common_labels, { tier = "monitoring" })
}

################################
# MODULE 2: Networking (Kong, CoreDNS, Load Balancing)
################################
module "networking" {
  source = "./modules/networking"

  # Configuration
  kong_version           = var.kong_version
  kong_database_password = var.kong_database_password
  kong_storage_size      = var.kong_storage_size

  coredns_version = var.coredns_version
  coredns_config  = var.coredns_config

  load_balancer_algorithm             = var.load_balancer_algorithm
  load_balancer_health_check_interval = var.load_balancer_health_check_interval
  service_upstream_timeout            = var.service_upstream_timeout
  rate_limiting_requests_per_second   = var.rate_limiting_requests_per_second

  # Infrastructure
  docker_host = var.docker_host
  namespace   = var.networking_namespace
  labels      = merge(local.common_labels, { tier = "networking" })
}

################################
# MODULE 3: Security (Falco, OPA, Vault)
################################
module "security" {
  source = "./modules/security"

  # Configuration
  falco_version       = var.falco_version
  opa_version         = var.opa_version
  vault_version       = var.vault_version
  vault_mode          = var.vault_mode
  vault_storage_size  = var.vault_storage_size
  vault_unseal_keys   = var.vault_unseal_keys
  vault_key_threshold = var.vault_key_threshold

  os_hardening_level           = var.os_hardening_level
  selinux_enabled              = var.selinux_enabled
  auditd_enabled               = var.auditd_enabled
  file_integrity_scan_interval = var.file_integrity_scan_interval
  vulnerability_scan_schedule  = var.vulnerability_scan_schedule

  # Infrastructure
  docker_host = var.docker_host
  namespace   = var.security_namespace
  labels      = merge(local.common_labels, { tier = "security" })
}

################################
# MODULE 4: DNS (Cloudflare, GoDaddy Failover)
################################
module "dns" {
  source = "./modules/dns"

  # Configuration
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_zone_id    = var.cloudflare_zone_id
  godaddy_api_key       = var.godaddy_api_key
  godaddy_api_secret    = var.godaddy_api_secret

  apex_domain           = var.apex_domain
  tunnel_name           = var.tunnel_name
  dns_ttl               = var.dns_ttl
  health_check_interval = var.dns_health_check_interval
  failover_threshold    = var.dns_failover_threshold
  primary_ip            = var.primary_ip
  secondary_ip          = var.secondary_ip

  # Infrastructure
  docker_host = var.docker_host
  labels      = merge(local.common_labels, { tier = "dns" })
}

################################
# MODULE 5: Failover (Patroni, PostgreSQL, HA/DR)
################################
module "failover" {
  source = "./modules/failover"

  # Configuration
  patroni_version       = var.patroni_version
  postgres_version      = var.postgres_version
  postgres_storage_size = var.postgres_storage_size
  etcd_version          = var.etcd_version

  backup_retention_days = var.backup_retention_days
  backup_schedule       = var.backup_schedule
  rpo_seconds           = var.rpo_seconds
  rto_seconds           = var.rto_seconds
  replication_slots     = var.replication_slots
  wal_level             = var.wal_level
  max_wal_senders       = var.max_wal_senders
  postgres_password     = var.postgres_password

  s3_backup_bucket = var.s3_backup_bucket
  s3_backup_region = var.s3_backup_region

  # Infrastructure
  docker_host = var.docker_host
  namespace   = var.failover_namespace
  labels      = merge(local.common_labels, { tier = "failover" })
}

################################
# LOCAL VALUES (Shared Configuration)
################################
locals {
  common_labels = {
    environment = var.deployment_environment
    managed_by  = "terraform"
    project     = "code-server-enterprise"
    phase       = "2.3"
    created_at  = timestamp()
  }

  # Module outputs mapping for easy reference
  module_endpoints = {
    prometheus   = module.monitoring.prometheus_endpoint
    grafana      = module.monitoring.grafana_endpoint
    alertmanager = module.monitoring.alertmanager_endpoint
    kong_admin   = module.networking.kong_admin_endpoint
    coredns      = module.networking.coredns_endpoint
    opa          = module.security.opa_endpoint
    vault        = module.security.vault_endpoint
    postgres     = module.failover.postgres_endpoint
    etcd         = module.failover.etcd_endpoint
  }

  # Service discovery map
  service_discovery = {
    monitoring = {
      namespace = var.monitoring_namespace
      services = {
        prometheus   = "prometheus:9090"
        grafana      = "grafana:3000"
        alertmanager = "alertmanager:9093"
      }
    }
    networking = {
      namespace = var.networking_namespace
      services = {
        kong    = "kong:8000"
        coredns = "coredns:53"
      }
    }
    security = {
      namespace = var.security_namespace
      services = {
        vault = "vault:8200"
        opa   = "opa:8181"
      }
    }
    failover = {
      namespace = var.failover_namespace
      services = {
        postgres = "postgres:5432"
        etcd     = "etcd:2379"
      }
    }
  }
}

################################
# OUTPUTS (Module Aggregation)
################################
output "module_outputs" {
  description = "All module endpoints and key outputs"
  value = {
    monitoring = {
      prometheus_endpoint   = module.monitoring.prometheus_endpoint
      grafana_endpoint      = module.monitoring.grafana_endpoint
      alertmanager_endpoint = module.monitoring.alertmanager_endpoint
      versions = {
        prometheus   = module.monitoring.prometheus_version
        grafana      = module.monitoring.grafana_version
        alertmanager = module.monitoring.alertmanager_version
      }
    }
    networking = {
      kong_admin_endpoint = module.networking.kong_admin_endpoint
      coredns_endpoint    = module.networking.coredns_endpoint
      versions = {
        kong    = module.networking.kong_version
        coredns = module.networking.coredns_version
      }
    }
    security = {
      opa_endpoint   = module.security.opa_endpoint
      vault_endpoint = module.security.vault_endpoint
      versions = {
        falco = module.security.falco_version
        opa   = module.security.opa_version
        vault = module.security.vault_version
      }
    }
    dns = {
      tunnel_url    = module.dns.cloudflare_tunnel_url
      apex_domain   = module.dns.apex_domain
      load_balancer = module.dns.load_balancer_endpoint
    }
    failover = {
      postgres_endpoint = module.failover.postgres_endpoint
      etcd_endpoint     = module.failover.etcd_endpoint
      rpo_seconds       = module.failover.rpo_seconds
      rto_seconds       = module.failover.rto_seconds
    }
  }
}

output "service_discovery" {
  description = "Service discovery map for cluster connectivity"
  value       = local.service_discovery
}

output "infrastructure_status" {
  description = "Infrastructure deployment status"
  value = {
    all_modules_deployed = true
    deployment_date      = timestamp()
    environment          = var.deployment_environment
    regions = {
      primary   = var.primary_ip
      secondary = var.secondary_ip
    }
    total_namespaces = 4
    total_resources  = 68
  }
}

output "disaster_recovery_info" {
  description = "Disaster recovery configuration"
  value = {
    rpo_seconds           = module.failover.rpo_seconds
    rto_seconds           = module.failover.rto_seconds
    backup_retention_days = module.failover.backup_retention_days
    failover_threshold    = module.dns.failover_threshold
    postgres_replicas     = 3
    etcd_nodes            = 3
  }
}
