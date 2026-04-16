# Infrastructure Inventory Management - Terraform Integration

locals {
  inventory = yamldecode(file("${path.module}/../inventory/infrastructure.yaml"))
  hosts = local.inventory.hosts
  network = local.inventory.network
  
  primary_host = local.hosts.primary.ip_address
  primary_ssh_user = local.hosts.primary.ssh_user
  replica_host = local.hosts.replica.ip_address
  virtual_ip = local.network.virtual_ip
}

output "primary_host" {
  value = local.primary_host
}

output "replica_host" {
  value = local.replica_host
}
