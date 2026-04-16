output "cloudflare_config" {
  description = "Cloudflare DNS and CDN configuration"
  value = {
    enabled           = local.cloudflare_config.enabled
    zone_id           = local.cloudflare_config.zone_id
    dns_proxy_enabled = local.cloudflare_config.dns_proxy_enabled
    waf_enabled       = local.cloudflare_config.waf_enabled
  }
  sensitive = true
}

output "godaddy_config" {
  description = "GoDaddy DNS failover configuration"
  value = {
    enabled = local.godaddy_config.enabled
  }
}

output "domain_config" {
  description = "Domain and DNS TTL configuration"
  value = {
    primary_domain       = local.domain_config.primary
    secondary_domain     = local.domain_config.secondary
    default_ttl_seconds  = local.domain_config.ttl_default
    failover_ttl_seconds = local.domain_config.ttl_short
  }
}

output "failover_policy" {
  description = "DNS failover policy configuration"
  value = {
    enabled                       = local.failover_config.enabled
    health_check_interval_seconds = local.failover_config.health_check_interval
    failure_threshold_checks      = local.failover_config.failure_threshold
  }
}

output "acme_config" {
  description = "ACME TLS certificate provisioning configuration"
  value = {
    provider                   = local.acme_config.provider
    email                      = local.acme_config.email
    renewal_days_before_expiry = local.acme_config.renewal_days_before_exp
  }
}

output "dnssec_policy" {
  description = "DNSSEC and DNS security configuration"
  value = {
    dnssec_enabled        = local.dnssec_config.enabled
    rate_limiting_enabled = local.dnssec_config.rate_limiting
  }
}
