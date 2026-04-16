# Infrastructure Inventory Management - Terraform Integration

locals {
  # Safely decode infrastructure inventory (optional during validation)
  inventory_raw = try(file("${path.module}/../inventory/infrastructure.yaml"), "")
  
  # Parse YAML if available (use safe defaults if missing)
  inventory = local.inventory_raw != "" ? try(
    yamldecode(local.inventory_raw),
    { hosts = {}, network = {} }
  ) : { hosts = {}, network = {} }
  
  hosts              = try(local.inventory.hosts, {})
  network            = try(local.inventory.network, {})
  primary_host       = try(local.hosts.primary.ip_address, var.deployment_host)
  primary_ssh_user   = try(local.hosts.primary.ssh_user, var.deployment_user)
  replica_host       = try(local.hosts.replica.ip_address, "192.168.168.42")
  virtual_ip         = try(local.network.virtual_ip, "")
}

output "primary_host" {
  value = local.primary_host
}

output "replica_host" {
  value = local.replica_host
}
