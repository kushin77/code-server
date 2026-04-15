################################################################################
# terraform/compute.tf — Multi-Region Compute Resources
#
# Purpose: Define 5-region server instances for active-active deployment
# Immutable: All VMs defined via Terraform, no manual provisioning
# Independent: Each region is self-contained, can fail independently
################################################################################

variable "compute_specs" {
  type = object({
    vcpu   = number
    memory_gb = number
    storage_gb = number
  })
  
  description = "Compute specifications per region"
  
  default = {
    vcpu       = 4
    memory_gb  = 16
    storage_gb = 200
  }
}

variable "region_roles" {
  type = map(object({
    name       = string
    ip_address = string
    role       = string  # primary, failover, standby
    enabled    = bool
  }))
  
  description = "Region role definitions"
  
  default = {
    region1 = {
      name       = "region1-primary"
      ip_address = "192.168.168.31"
      role       = "primary"
      enabled    = true
    }
    region2 = {
      name       = "region2-failover1"
      ip_address = "192.168.168.32"
      role       = "failover"
      enabled    = true
    }
    region3 = {
      name       = "region3-failover2"
      ip_address = "192.168.168.33"
      role       = "failover"
      enabled    = true
    }
    region4 = {
      name       = "region4-failover3"
      ip_address = "192.168.168.34"
      role       = "failover"
      enabled    = true
    }
    region5 = {
      name       = "region5-standby"
      ip_address = "192.168.168.35"
      role       = "standby"
      enabled    = true
    }
  }
}

variable "container_images" {
  type = map(string)
  
  description = "Container images for services"
  
  default = {
    postgres    = "postgres:15.6-alpine"
    redis       = "redis:7.0-alpine"
    code_server = "codercom/code-server:latest"
    ollama      = "ollama/ollama:latest"
    caddy       = "caddy:2.7-alpine"
    pgbouncer   = "pgbouncer:latest"
  }
}

################################################################################
# Compute Output
################################################################################

output "compute_instances" {
  description = "Compute instance configuration"
  value = {
    for region, config in var.region_roles :
    region => {
      name          = config.name
      ip_address    = config.ip_address
      role          = config.role
      enabled       = config.enabled
      vcpu          = var.compute_specs.vcpu
      memory_gb     = var.compute_specs.memory_gb
      storage_gb    = var.compute_specs.storage_gb
      api_endpoint  = "http://${config.ip_address}:8080"
      ssh_endpoint  = "ssh://root@${config.ip_address}:22"
      health_check  = "http://${config.ip_address}:9090/health"
    }
  }
}

output "container_registry" {
  description = "Container images to be deployed"
  value = {
    images = var.container_images
    note   = "All images pulled from registries during deployment"
  }
}

output "deployment_checklist" {
  description = "Pre-deployment checklist"
  value = [
    "✅ Verify SSH connectivity to all 5 regions",
    "✅ Verify Docker/container runtime installed",
    "✅ Verify NAS mounts accessible",
    "✅ Verify network connectivity (ping tests)",
    "✅ Verify DNS resolves regional IPs",
    "✅ Verify load balancer IP is reachable",
    "✅ Verify firewall rules allow required ports",
    "✅ Backup existing configurations",
    "✅ Schedule deployment window (low-traffic period)",
    "✅ Notify stakeholders of deployment"
  ]
}
