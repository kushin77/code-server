# DNS Inventory Management - Terraform Integration
# Reads inventory/dns.yaml and configures DNS providers and records

locals {
  # Safely decode DNS inventory (YAML file can have complex structure)
  # For Terraform validation: if file doesn't exist or is invalid, use empty object
  dns_inventory_raw = try(file("${path.module}/../inventory/dns.yaml"), "")
  
  # Parse YAML if available (skip if validation/test mode)
  dns_inventory = local.dns_inventory_raw != "" ? try(
    yamldecode(local.dns_inventory_raw),
    { domains = {}, providers = {}, zones = {} }
  ) : { domains = {}, providers = {}, zones = {} }
  
  domains           = try(local.dns_inventory.domains, {})
  dns_providers     = try(local.dns_inventory.providers, {})
  dns_zones         = try(local.dns_inventory.zones, {})
  primary_domain    = try(local.domains.primary.name, "example.com")
  primary_zone_id   = try(local.dns_zones.example_com.zone_id, "")
  
  all_dns_records = length(local.dns_zones) > 0 ? merge([
    for zone_name, zone_config in local.dns_zones :
    {
      for record in try(zone_config.records, []) :
      "${zone_name}:${record.type}:${record.name}" => {
        zone_id = zone_config.zone_id
        provider = zone_config.provider
        name = record.name
        type = record.type
        value = record.value
        ttl = try(record.ttl, 3600)
      }
    }
  ]...) : {}
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
