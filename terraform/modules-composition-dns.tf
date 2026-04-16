# Terraform Module: DNS & Tunneling Stack (Cloudflare Tunnel, GoDaddy Failover, External DNS)

module "dns" {
  source = "./modules/dns"

  # General configuration
  environment     = var.environment
  deployment_host = var.deployment_host
  domain          = var.domain
  namespace       = "dns"

  # Cloudflare Tunnel Configuration
  cloudflare_tunnel_enabled = true
  cloudflare_tunnel_token   = var.cloudflare_tunnel_token  # From GCP Secret Manager
  cloudflare_zone_id        = var.cloudflare_zone_id
  cloudflare_account_id     = var.cloudflare_account_id
  cloudflare_api_key        = var.cloudflare_api_key

  # Cloudflare tunnel routing
  cloudflare_routes = {
    ide_primary = {
      hostname     = var.domain
      service      = "http://localhost:443"
      path         = "/"
      priority     = 10
      ttl          = 1
    }
    ops_secondary = {
      hostname     = "ops.${var.domain}"
      service      = "http://localhost:8443"
      path         = "/"
      priority     = 20
      ttl          = 3600  # Higher TTL for ops portal (less frequent)
    }
  }

  # Cloudflare DDoS and security settings
  cloudflare_security = {
    ddos_protection_level = "high"
    waf_enabled           = true
    bot_management        = true
    rate_limiting_enabled = true
    rate_limiting_rules = {
      general = {
        threshold = 100
        period    = 10  # seconds
      }
      auth_endpoints = {
        threshold = 10
        period    = 60
      }
    }
    ip_reputation_list = "cloudflare"
    country_blocking   = ["OFAC-sanctioned-countries"]
    min_tls_version    = "1.2"
    auto_minify        = true
    enable_brotli      = true
  }

  # GoDaddy DNS Failover Configuration
  godaddy_failover_enabled = true
  godaddy_api_key         = var.godaddy_api_key
  godaddy_api_secret      = var.godaddy_api_secret
  godaddy_domain          = var.godaddy_domain

  # GoDaddy DNS records (failover targets)
  godaddy_records = {
    primary_host = {
      type   = "A"
      name   = "@"
      data   = var.primary_host_ip      # 192.168.168.31
      ttl    = 600  # 10 minutes (failover requires quick update)
      priority = 10
    }
    secondary_host = {
      type   = "A"
      name   = "@"
      data   = var.secondary_host_ip    # 192.168.168.42
      ttl    = 600
      priority = 20
    }
    cname_alias = {
      type   = "CNAME"
      name   = "www"
      data   = var.domain
      ttl    = 3600
    }
    mx_record = {
      type     = "MX"
      name     = "@"
      data     = "mail.${var.domain}"
      ttl      = 3600
      priority = 10
    }
  }

  # DNS failover health checks
  godaddy_health_checks = {
    http_check = {
      protocol = "HTTPS"
      path     = "/health"
      port     = 443
      interval = 30  # seconds
      timeout  = 10
      unhealthy_threshold = 3
      healthy_threshold   = 2
    }
    tcp_check = {
      protocol = "TCP"
      port     = 22
      interval = 60
      timeout  = 10
      unhealthy_threshold = 2
      healthy_threshold   = 1
    }
  }

  # External DNS (KUBE-DNS or CoreDNS integration)
  external_dns_enabled  = true
  external_dns_image    = "k8s.gcr.io/external-dns/external-dns:v${var.external_dns_version}"
  external_dns_provider = "cloudflare"  # Or: godaddy, route53, azure
  external_dns_memory   = "256Mi"
  external_dns_cpu      = "100m"

  # External DNS configuration
  external_dns_config = {
    zone_id_filter = var.cloudflare_zone_id
    policy         = "sync"  # Or: upsert-only, create-only
    txt_owner_id   = "code-server"
    txt_prefix     = "external-dns-"
    registry       = "txt"
    managed_policies = true
  }

  # DNS DNSSEC configuration
  dnssec = {
    enabled = true
    ksk_bits = 2048
    zsk_bits = 1024
    ksk_lifetime = "1y"
    zsk_lifetime = "30d"
  }

  # DNS caching
  caching = {
    enabled = true
    ttl_default = 300  # 5 minutes
    ttl_min     = 30
    ttl_max     = 86400  # 24 hours
    cache_size  = "512MB"
  }

  # DNS query logging
  query_logging = {
    enabled = true
    format  = "json"
    sink    = "http://localhost:${var.loki_port}/loki/api/v1/push"
  }

  # Subdomain management
  subdomains = {
    ide = {
      service = "code-server"
      auth_required = true
    }
    ops = {
      service = "monitoring"
      auth_required = true
      internal_only = true
    }
    prometheus = {
      service = "prometheus"
      auth_required = true
      internal_only = true
    }
    grafana = {
      service = "grafana"
      auth_required = true
      internal_only = true
    }
    api = {
      service = "kong"
      auth_required = true
    }
  }

  # Resource limits
  resource_limits = {
    memory = "512Mi"
    cpu    = "250m"
  }

  # High availability
  replicas = {
    external_dns = 2  # Two instances for redundancy
  }

  # Logging
  logging = {
    level  = var.log_level
    format = "json"
  }

  # Tags
  tags = merge(var.tags, {
    Module  = "dns"
    Purpose = "Cloudflare Tunnel, GoDaddy Failover, External DNS, DNSSEC"
  })
}

# Output DNS endpoints and configuration
output "dns_configuration" {
  value = {
    primary_domain      = module.dns.primary_domain
    cloudflare_tunnel_id = module.dns.cloudflare_tunnel_id
    godaddy_zone_id    = module.dns.godaddy_zone_id
    dnssec_enabled     = module.dns.dnssec_enabled
    nameservers        = module.dns.nameservers
  }
}

# Output health check status
output "health_check_status" {
  value = {
    primary_healthy   = module.dns.primary_healthy
    secondary_healthy = module.dns.secondary_healthy
    failover_status   = module.dns.failover_status
  }
}

# Output DNS records
output "dns_records" {
  value = module.dns.dns_records
  sensitive = true
}
