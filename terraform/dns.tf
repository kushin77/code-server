################################################################################
# terraform/dns.tf — DNS and Failover Configuration
#
# Purpose: Define DNS entries and automatic failover logic for multi-region
# Failover: Automatic DNS failover <30 seconds
# Health Checks: Active monitoring of all regions
################################################################################

variable "dns_config" {
  type = object({
    base_domain         = string  # code-server.internal
    load_balancer_ip    = string  # 192.168.168.100
    health_check_port   = number  # 9090
    health_check_interval_s = number
    failover_threshold  = number  # consecutive failures before failover
    ttl                 = number  # seconds
  })
  
  description = "DNS and failover configuration"
  
  default = {
    base_domain          = "code-server.internal"
    load_balancer_ip     = "192.168.168.100"
    health_check_port    = 9090
    health_check_interval_s = 10
    failover_threshold   = 3  # 3 consecutive failures = failover
    ttl                  = 10  # Short TTL for quick propagation
  }
}

variable "dns_entries" {
  type = map(object({
    hostname  = string
    ip_address = string
    ttl       = number
    type      = string  # A, CNAME, SRV
  }))
  
  description = "DNS entries for all regions"
  
  default = {
    primary = {
      hostname   = "code-server.internal"
      ip_address = "192.168.168.31"
      ttl        = 10
      type       = "A"
    }
    region1 = {
      hostname   = "region1.internal"
      ip_address = "192.168.168.31"
      ttl        = 10
      type       = "A"
    }
    region2 = {
      hostname   = "region2.internal"
      ip_address = "192.168.168.32"
      ttl        = 10
      type       = "A"
    }
    region3 = {
      hostname   = "region3.internal"
      ip_address = "192.168.168.33"
      ttl        = 10
      type       = "A"
    }
    region4 = {
      hostname   = "region4.internal"
      ip_address = "192.168.168.34"
      ttl        = 10
      type       = "A"
    }
    region5 = {
      hostname   = "region5.internal"
      ip_address = "192.168.168.35"
      ttl        = 10
      type       = "A"
    }
    postgres_primary = {
      hostname   = "postgres-primary.internal"
      ip_address = "192.168.168.31"
      ttl        = 10
      type       = "A"
    }
    redis_primary = {
      hostname   = "redis-primary.internal"
      ip_address = "192.168.168.31"
      ttl        = 10
      type       = "A"
    }
  }
}

variable "health_checks" {
  type = map(object({
    name            = string
    target_ip       = string
    port            = number
    protocol        = string  # http, tcp, udp
    path            = string  # for HTTP
    interval_s      = number
    timeout_s       = number
    healthy_threshold = number
    unhealthy_threshold = number
  }))
  
  description = "Health check configuration"
  
  default = {
    region1_http = {
      name                = "region1-http-health"
      target_ip           = "192.168.168.31"
      port                = 9090
      protocol            = "http"
      path                = "/health"
      interval_s          = 10
      timeout_s           = 5
      healthy_threshold   = 2
      unhealthy_threshold = 3
    }
    region2_http = {
      name                = "region2-http-health"
      target_ip           = "192.168.168.32"
      port                = 9090
      protocol            = "http"
      path                = "/health"
      interval_s          = 10
      timeout_s           = 5
      healthy_threshold   = 2
      unhealthy_threshold = 3
    }
    region3_http = {
      name                = "region3-http-health"
      target_ip           = "192.168.168.33"
      port                = 9090
      protocol            = "http"
      path                = "/health"
      interval_s          = 10
      timeout_s           = 5
      healthy_threshold   = 2
      unhealthy_threshold = 3
    }
    region4_http = {
      name                = "region4-http-health"
      target_ip           = "192.168.168.34"
      port                = 9090
      protocol            = "http"
      path                = "/health"
      interval_s          = 10
      timeout_s           = 5
      healthy_threshold   = 2
      unhealthy_threshold = 3
    }
  }
}

################################################################################
# DNS Output
################################################################################

output "dns_configuration" {
  description = "DNS configuration for zone file"
  value = {
    base_domain = var.dns_config.base_domain
    entries     = var.dns_entries
    ttl         = var.dns_config.ttl
  }
}

output "failover_configuration" {
  description = "Failover behavior configuration"
  value = {
    detection_interval_s  = var.dns_config.health_check_interval_s
    failover_threshold    = var.dns_config.failover_threshold
    failover_time_s       = var.dns_config.health_check_interval_s * var.dns_config.failover_threshold
    total_failover_time_s = (var.dns_config.health_check_interval_s * var.dns_config.failover_threshold) + 10  # +10s for DNS propagation
  }
}

output "dns_server_setup" {
  description = "Instructions for DNS server setup (BIND9 example)"
  value = {
    zone_file = "code-server.internal"
    records   = "A records for all regions and services"
    example_commands = [
      "# Add these to /etc/bind/named.conf.local:",
      "zone \"code-server.internal\" {",
      "  type master;",
      "  file \"/etc/bind/db.code-server.internal\";",
      "  notify yes;",
      "  allow-transfer { 192.168.168.11; };",
      "};",
      "",
      "# Then create /etc/bind/db.code-server.internal with A records",
      "# See outputs.dns_configuration for entries"
    ]
  }
}
