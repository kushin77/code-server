# DNS Inventory Management - Terraform Integration
# Reads inventory/dns.yaml and configures DNS providers and records

locals {
  dns_inventory = yamldecode(file("${path.module}/../inventory/dns.yaml"))
  domains = local.dns_inventory.domains
  dns_providers = local.dns_inventory.providers
  dns_zones = local.dns_inventory.zones
  
  primary_domain = local.domains.primary.name
  primary_zone_id = local.dns_zones.example_com.zone_id
  
  all_dns_records = merge([
    for zone_name, zone_config in local.dns_zones :
    {
      for record in zone_config.records :
      "${zone_name}:${record.type}:${record.name}" => {
        zone_id = zone_config.zone_id
        provider = zone_config.provider
        name = record.name
        type = record.type
        value = record.value
        ttl = try(record.ttl, 3600)
      }
    }
  ]...)
}

output "primary_domain" {
  value = local.primary_domain
  description = "Primary domain name"
}

output "dns_providers" {
  value = keys(local.dns_providers)
  description = "Configured DNS providers"
}

output "dns_zones" {
  value = keys(local.dns_zones)
  description = "Configured DNS zones"
}

output "all_dns_records" {
  value = local.all_dns_records
  description = "All DNS records from inventory"
}
