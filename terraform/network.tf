################################################################################
# terraform/network.tf — Multi-Region Network Configuration
#
# Purpose: Define on-premises network topology for 5-region deployment
# Network: 192.168.168.0/24 (local on-prem network)
# Security: Firewall rules, network segmentation
################################################################################

variable "network_config" {
  type = object({
    base_cidr          = string  # 192.168.168.0/24
    public_subnet_mask = string  # /25 for each region
    private_subnet_mask = string # /26 for each region
  })
  
  description = "Network configuration"
  
  default = {
    base_cidr           = "192.168.168.0/24"
    public_subnet_mask  = "/25"
    private_subnet_mask = "/26"
  }
}

# Regional subnets
variable "regional_subnets" {
  type = map(object({
    public_subnet  = string
    private_subnet = string
    gateway_ip     = string
  }))
  
  description = "Subnet allocation per region"
  
  default = {
    region1 = {
      public_subnet  = "192.168.168.0/26"
      private_subnet = "192.168.168.64/26"
      gateway_ip     = "192.168.168.1"
    }
    region2 = {
      public_subnet  = "192.168.168.128/26"
      private_subnet = "192.168.168.192/26"
      gateway_ip     = "192.168.168.129"
    }
    region3 = {
      public_subnet  = "192.168.168.64/26"
      private_subnet = "192.168.168.130/26"
      gateway_ip     = "192.168.168.65"
    }
    region4 = {
      public_subnet  = "192.168.168.96/26"
      private_subnet = "192.168.168.160/26"
      gateway_ip     = "192.168.168.97"
    }
    region5 = {
      public_subnet  = "192.168.168.160/26"
      private_subnet = "192.168.168.224/26"
      gateway_ip     = "192.168.168.161"
    }
  }
}

# Firewall rules (security groups)
variable "firewall_rules" {
  type = list(object({
    name      = string
    direction = string  # inbound, outbound
    protocol  = string  # tcp, udp, all
    port      = number
    source    = string  # CIDR or security group
  }))
  
  description = "Network firewall rules"
  
  default = [
    {
      name      = "allow-ssh-local"
      direction = "inbound"
      protocol  = "tcp"
      port      = 22
      source    = "192.168.168.0/24"
    },
    {
      name      = "allow-code-server"
      direction = "inbound"
      protocol  = "tcp"
      port      = 8080
      source    = "192.168.168.0/24"
    },
    {
      name      = "allow-postgres"
      direction = "inbound"
      protocol  = "tcp"
      port      = 5432
      source    = "192.168.168.0/24"
    },
    {
      name      = "allow-redis"
      direction = "inbound"
      protocol  = "tcp"
      port      = 6379
      source    = "192.168.168.0/24"
    },
    {
      name      = "allow-postgres-replication"
      direction = "inbound"
      protocol  = "tcp"
      port      = 5432
      source    = "192.168.168.0/24"
    },
    {
      name      = "allow-dns"
      direction = "inbound"
      protocol  = "udp"
      port      = 53
      source    = "192.168.168.0/24"
    },
    {
      name      = "allow-ntp"
      direction = "inbound"
      protocol  = "udp"
      port      = 123
      source    = "192.168.168.0/24"
    },
    {
      name      = "allow-health-check"
      direction = "inbound"
      protocol  = "tcp"
      port      = 9090
      source    = "192.168.168.0/24"
    }
  ]
}

################################################################################
# On-Premises Security Groups (P1 #428: Network Isolation)
################################################################################

variable "security_group_rules" {
  type = map(object({
    description = string
    ingress     = list(object({
      protocol = string
      from_port = number
      to_port = number
      cidr_blocks = list(string)
      description = string
    }))
    egress = list(object({
      protocol = string
      from_port = number
      to_port = number
      cidr_blocks = list(string)
      description = string
    }))
  }))
  
  description = "Security groups for each network zone"
  
  default = {
    primary_production = {
      description = "Primary production host (192.168.168.31) - All services"
      ingress = [
        {
          protocol = "tcp"
          from_port = 22
          to_port = 22
          cidr_blocks = ["192.168.168.0/24"]
          description = "SSH management"
        },
        {
          protocol = "tcp"
          from_port = 8080
          to_port = 8080
          cidr_blocks = ["192.168.168.0/24"]
          description = "Code-Server IDE"
        },
        {
          protocol = "tcp"
          from_port = 5432
          to_port = 5432
          cidr_blocks = ["192.168.168.42/32", "192.168.168.0/24"]
          description = "PostgreSQL database"
        },
        {
          protocol = "tcp"
          from_port = 6379
          to_port = 6379
          cidr_blocks = ["192.168.168.0/24"]
          description = "Redis cache"
        },
        {
          protocol = "tcp"
          from_port = 3000
          to_port = 3000
          cidr_blocks = ["192.168.168.0/24"]
          description = "Grafana monitoring"
        },
        {
          protocol = "tcp"
          from_port = 9090
          to_port = 9090
          cidr_blocks = ["192.168.168.0/24"]
          description = "Prometheus metrics"
        },
        {
          protocol = "tcp"
          from_port = 9093
          to_port = 9093
          cidr_blocks = ["192.168.168.0/24"]
          description = "AlertManager"
        },
        {
          protocol = "tcp"
          from_port = 16686
          to_port = 16686
          cidr_blocks = ["192.168.168.0/24"]
          description = "Jaeger tracing"
        }
      ]
      egress = [
        {
          protocol = "-1"
          from_port = 0
          to_port = 0
          cidr_blocks = ["0.0.0.0/0"]
          description = "Allow all outbound"
        }
      ]
    }
    
    replica_standby = {
      description = "Replica standby host (192.168.168.42) - Replication only"
      ingress = [
        {
          protocol = "tcp"
          from_port = 22
          to_port = 22
          cidr_blocks = ["192.168.168.0/24"]
          description = "SSH management"
        },
        {
          protocol = "tcp"
          from_port = 5432
          to_port = 5432
          cidr_blocks = ["192.168.168.31/32"]
          description = "PostgreSQL replication from primary"
        },
        {
          protocol = "tcp"
          from_port = 9090
          to_port = 9090
          cidr_blocks = ["192.168.168.0/24"]
          description = "Health check"
        }
      ]
      egress = [
        {
          protocol = "tcp"
          from_port = 5432
          to_port = 5432
          cidr_blocks = ["192.168.168.31/32"]
          description = "PostgreSQL replication egress to primary"
        },
        {
          protocol = "tcp"
          from_port = 53
          to_port = 53
          cidr_blocks = ["192.168.168.0/24"]
          description = "DNS resolution"
        }
      ]
    }
    
    storage_nas = {
      description = "NAS storage tier (192.168.168.56) - Storage only"
      ingress = [
        {
          protocol = "tcp"
          from_port = 22
          to_port = 22
          cidr_blocks = ["192.168.168.0/24"]
          description = "SSH management"
        },
        {
          protocol = "tcp"
          from_port = 111
          to_port = 111
          cidr_blocks = ["192.168.168.31/32", "192.168.168.42/32"]
          description = "NFS portmapper"
        },
        {
          protocol = "tcp"
          from_port = 2049
          to_port = 2049
          cidr_blocks = ["192.168.168.31/32", "192.168.168.42/32"]
          description = "NFS server"
        },
        {
          protocol = "udp"
          from_port = 111
          to_port = 111
          cidr_blocks = ["192.168.168.31/32", "192.168.168.42/32"]
          description = "NFS portmapper (UDP)"
        },
        {
          protocol = "udp"
          from_port = 2049
          to_port = 2049
          cidr_blocks = ["192.168.168.31/32", "192.168.168.42/32"]
          description = "NFS server (UDP)"
        }
      ]
      egress = [
        {
          protocol = "-1"
          from_port = 0
          to_port = 0
          cidr_blocks = ["0.0.0.0/0"]
          description = "Allow all outbound"
        }
      ]
    }
  }
}

################################################################################
# On-Premises Access Control List (ACL) - Least Privilege
################################################################################

variable "network_acl_rules" {
  type = list(object({
    rule_number = number
    action      = string  # allow, deny
    protocol    = string  # tcp, udp, icmp, -1 (all)
    from_port   = number
    to_port     = number
    cidr_block  = string
    egress      = bool
  }))
  
  description = "Network ACL rules for on-prem segmentation"
  
  default = [
    # Inbound rules (production tier)
    {
      rule_number = 100
      action      = "allow"
      protocol    = "tcp"
      from_port   = 22
      to_port     = 22
      cidr_block  = "192.168.168.0/24"
      egress      = false
    },
    {
      rule_number = 110
      action      = "allow"
      protocol    = "tcp"
      from_port   = 5432
      to_port     = 5432
      cidr_block  = "192.168.168.0/24"
      egress      = false
    },
    {
      rule_number = 120
      action      = "allow"
      protocol    = "tcp"
      from_port   = 6379
      to_port     = 6379
      cidr_block  = "192.168.168.0/24"
      egress      = false
    },
    # Outbound rules (all)
    {
      rule_number = 100
      action      = "allow"
      protocol    = "-1"
      from_port   = 0
      to_port     = 65535
      cidr_block  = "0.0.0.0/0"
      egress      = true
    },
    # Default deny
    {
      rule_number = 32767
      action      = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 65535
      cidr_block  = "0.0.0.0/0"
      egress      = false
    }
  ]
}

################################################################################
# Network Configuration Output
################################################################################

output "network_topology" {
  description = "Network topology configuration"
  value = {
    base_network   = var.network_config.base_cidr
    subnets        = var.regional_subnets
    firewall_rules = length(var.firewall_rules)
    regions        = 5
  }
}

output "connectivity_requirements" {
  description = "Network connectivity requirements"
  value = {
    internet_gateway    = "192.168.168.1"
    dns_servers         = ["192.168.168.10", "192.168.168.11"]
    load_balancer       = "192.168.168.100"
    ntp_servers         = ["192.168.168.12"]
    connectivity_type   = "Direct local network (on-premises)"
    replication_port    = 5432
    health_check_port   = 9090
    management_port     = 22
  }
}

output "security_zones" {
  description = "Security zone configuration"
  value = {
    zone1_production = {
      subnets = ["192.168.168.0/26"]
      rules   = "Allow: SSH, Code-Server, PostgreSQL, Redis"
    }
    zone2_replication = {
      subnets = ["192.168.168.64/26"]
      rules   = "Allow: PostgreSQL replication only"
    }
    zone3_management = {
      subnets = ["192.168.168.128/26"]
      rules   = "Allow: SSH, health checks, monitoring"
    }
  }
}
