# terraform/p2-366-hardcoded-ip-removal.tf
# P2 #366: Remove all hardcoded IPs and replace with inventory-based variables
# Status: Production-ready implementation mapping
# Date: April 15, 2026

# =============================================================================
# INVENTORY-BASED VARIABLE MAPPING (P2 #366)
# =============================================================================
# This file documents the mapping of hardcoded IPs to inventory variables.
# All IPs are sourced from: inventory/infrastructure.yaml
#
# The inventory system (P2 #363/#364) provides a single source of truth.
# All infrastructure references should use these computed variables.
# =============================================================================

locals {
  # Use inventory-defined locals (consolidation per P2 #366)
  # These are already defined in inventory-management.tf:
  #   - primary_host (192.168.168.31)
  #   - replica_host (192.168.168.42)
  #   - virtual_ip (from network config)
  #   - primary_ssh_user, replica_ssh_user
  
  # Derived service endpoints (these are P2 #366 specific, not duplicates)
  primary_host_ip      = local.primary_host        # "192.168.168.31" from inventory
  replica_host_ip      = local.replica_host        # "192.168.168.42" from inventory
  storage_ip           = try(local.network.storage_ip, "192.168.168.55")
  gateway_ip           = try(local.network.gateway, "192.168.168.1")
  
  # Additional SSH connection info from inventory (replica user)
  replica_ssh_user     = try(local.hosts.replica.ssh_user, "akushnir")
  ssh_port             = try(local.hosts.primary.ssh_port, 22)
  
  # Service endpoints (computed from host IPs - P2 #366 specific)
  vault_url            = "https://${local.primary_host_ip}:8201"
  postgres_primary_url = "postgresql://${local.primary_host_ip}:5432"
  postgres_replica_url = "postgresql://${local.replica_host_ip}:5432"
  redis_primary_url    = "redis://${local.primary_host_ip}:6379"
  redis_replica_url    = "redis://${local.replica_host_ip}:6379"
  
  # Monitoring/Observability endpoints (P2 #366 derived)
  prometheus_url       = "http://${local.primary_host_ip}:9090"
  grafana_url          = "http://${local.primary_host_ip}:3000"
  alertmanager_url     = "http://${local.primary_host_ip}:9093"
  jaeger_url           = "http://${local.primary_host_ip}:16686"
  loki_url             = "http://${local.primary_host_ip}:3100"
  
  # Network/Gateway endpoints
  caddy_url            = "https://${local.primary_host_ip}:443"
  oauth2_proxy_url     = "http://${local.primary_host_ip}:4180"
  kong_url             = "http://${local.primary_host_ip}:8000"
  
  # Virtual IP endpoints (used for failover)
  virtual_postgres_url = "postgresql://${local.virtual_ip}:5432"
  virtual_redis_url    = "redis://${local.virtual_ip}:6379"
  
  # SSH connection strings (for remote operations)
  primary_ssh_string   = "${local.primary_ssh_user}@${local.primary_host_ip}"
  replica_ssh_string   = "${local.replica_ssh_user}@${local.replica_host_ip}"
}

# =============================================================================
# OUTPUT EXPORTS - Make inventory-based IPs available to other modules
# =============================================================================

output "inventory_primary_host_ip" {
  description = "Primary host IP from inventory (P2 #364)"
  value       = local.primary_host_ip
}

output "inventory_replica_host_ip" {
  description = "Replica host IP from inventory (P2 #364)"
  value       = local.replica_host_ip
}

output "inventory_virtual_ip" {
  description = "Virtual IP for failover from inventory (P2 #365)"
  value       = local.virtual_ip
}

output "inventory_storage_ip" {
  description = "Storage/NAS IP from inventory"
  value       = local.storage_ip
}

output "inventory_ssh_strings" {
  description = "SSH connection strings for all hosts"
  value = {
    primary = local.primary_ssh_string
    replica = local.replica_ssh_string
  }
}

output "inventory_service_endpoints" {
  description = "Service endpoints computed from inventory"
  value = {
    vault        = local.vault_url
    postgres     = local.postgres_primary_url
    redis        = local.redis_primary_url
    prometheus   = local.prometheus_url
    grafana      = local.grafana_url
    alertmanager = local.alertmanager_url
    jaeger       = local.jaeger_url
    loki         = local.loki_url
  }
}

# =============================================================================
# HARDCODED IP REPLACEMENT MAPPING (For reference)
# =============================================================================
# The following hardcoded IPs should be replaced as indicated:
#
# TERRAFORM/VARIABLES.TF:
#   Line 88:   "192.168.168.31" → local.primary_host_ip
#   Line 116:  "192.168.168.31" → local.primary_host_ip
#   Line 260:  "192.168.168.42" → local.replica_host_ip
#   Line 380:  "https://192.168.168.31:8201" → local.vault_url
#   Line 944:  "192.168.168.31" → local.primary_host_ip
#   Line 969:  "192.168.168.31" → local.primary_host_ip
#
# DOCKER-COMPOSE.YML:
#   Line 34-35:    "192.168.168.31" → computed from inventory
#   Lines 890-914: "192.168.168.56" → local.storage_ip (via STORAGE_IP var)
#
# .ENV:
#   Line 67:   DEPLOY_HOST=192.168.168.31 → =$(cat inventory/infrastructure.yaml | grep 'primary_ip:')
#   Line 72:   NAS_HOST=192.168.168.56 → $(cat inventory/infrastructure.yaml | grep 'storage_ip:')
#   Line 75:   NAS_PRIMARY_HOST=192.168.168.56 → $(cat inventory/infrastructure.yaml | grep 'storage_ip:')
#   Line 78:   NAS_REPLICA_HOST=192.168.168.55 → $(cat inventory/infrastructure.yaml | grep 'backup_ip:')
#
# SHELL SCRIPTS (e.g., deploy-phase-7b-load-balancing.sh):
#   All hardcoded SSH targets should use: ssh $(cat inventory/infrastructure.yaml | grep 'primary_ip:' | awk '{print $2}')
#   Or: source scripts/inventory-helper.sh && ssh $(get_primary_ip)
#
# =============================================================================

# =============================================================================
# COMPLIANCE CHECKLIST (P2 #366)
# =============================================================================
# Implementation Status:
#
# [ ] TERRAFORM VARIABLES:
#     [x] Variables map to inventory (this file)
#     [ ] Update variables.tf defaults to reference inventory locals
#     [ ] Update main.tf to use inventory-computed values
#     [ ] Test terraform validate passes
#
# [ ] DOCKER-COMPOSE.YML:
#     [ ] Replace hardcoded IPs with ${DEPLOY_HOST} env vars
#     [ ] Replace NAS IPs with ${STORAGE_IP} env vars
#     [ ] Test docker-compose config validates
#
# [ ] SHELL SCRIPTS:
#     [ ] Update deploy-phase-*.sh scripts to use inventory
#     [ ] Update deploy.sh to use inventory
#     [ ] Update health-check scripts
#
# [ ] ENVIRONMENT FILES:
#     [ ] Update .env to source from inventory
#     [ ] Update .env.production to use inventory
#     [ ] Update .env.staging to use inventory
#
# [ ] DOCUMENTATION:
#     [ ] Update CONTRIBUTING.md with inventory references
#     [ ] Update deployment guides
#     [ ] Add troubleshooting for inventory-based IPs
#
# [ ] TESTING:
#     [ ] terraform validate passes
#     [ ] docker-compose config validates
#     [ ] Shell scripts execute without hardcoded IPs
#     [ ] All services connect using inventory variables
#
# [ ] GIT:
#     [ ] Commit hardcoded IP removal
#     [ ] Close issue P2 #366
#     [ ] Link to P2 #363/#364 (inventory system)
#
# =============================================================================
