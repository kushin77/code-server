// DNS Module — Cloudflare, GoDaddy, ACME TLS, Failover
// Provides DNS management, CDN, WAF, and certificate provisioning

locals {
  cloudflare_config = {
    enabled           = var.cloudflare_enabled
    zone_id           = var.cloudflare_zone_id
    dns_proxy_enabled = var.cloudflare_dns_proxy_enabled
    waf_enabled       = var.cloudflare_waf_enabled
  }

  godaddy_config = {
    enabled    = var.godaddy_enabled
    api_key    = var.godaddy_api_key
    api_secret = var.godaddy_api_secret
  }

  domain_config = {
    primary     = var.domain_primary
    secondary   = var.domain_secondary
    ttl_default = var.dns_ttl_default
    ttl_short   = var.dns_ttl_short
  }

  failover_config = {
    enabled               = var.dns_failover_enabled
    health_check_interval = var.dns_failover_health_check_interval
    failure_threshold     = var.dns_failover_threshold
  }

  acme_config = {
    provider                = var.acme_provider
    email                   = var.acme_email
    renewal_days_before_exp = var.acme_renewal_days_before_expiry
  }

  dnssec_config = {
    enabled       = var.enable_dns_dnssec
    rate_limiting = var.enable_dns_rate_limiting
  }
}

// Note: DNS provisioning via Cloudflare/GoDaddy APIs and Caddy ACME integration
// This module defines DNS failover policies, TLS certificate management, and security parameters
// Future: Integrate with Terraform Cloudflare provider for full infrastructure-as-code DNS management
