/**
 * @file terraform/ssl-tls.tf
 * @description SSL/TLS module integration
 * @governance OPS-002: Certificate infrastructure
 * @note Phase 3 Week 2: SSL/TLS ACME automation
 */

# SSL/TLS Module - Let's Encrypt ACME Automation
module "ssl_tls" {
  count  = var.enable_ssl_tls_module ? 1 : 0
  source = "./modules/ssl-tls"

  environment                 = var.environment
  apex_domain                 = var.ssl_tls_apex_domain
  subdomain_prefixes          = var.ssl_tls_subdomain_prefixes
  enable_wildcard_certificate = var.ssl_tls_enable_wildcard

  # Let's Encrypt configuration
  letsencrypt_email       = var.ssl_tls_letsencrypt_email
  letsencrypt_environment = var.environment == "production" ? "production" : "staging"

  # Renewal configuration
  certificate_renewal_days_before_expiry = 30
  enable_certificate_auto_renewal        = true

  # Monitoring
  enable_certificate_monitoring     = var.environment != "dev"
  certificate_expiration_alarm_days = var.environment == "production" ? 14 : 21
  renewal_check_frequency           = "cron(0 2 * * ? *)" # Daily at 02:00 UTC

  # AWS resources
  route53_zone_id = var.route53_zone_id
  sns_topic_arn   = var.ssl_tls_sns_topic_arn

  common_tags = merge(
    var.common_tags,
    {
      Module = "ssl-tls"
      Phase  = "3"
      Tier   = "security"
    }
  )

}

# Output certificate information for operations
output "ssl_tls_certificate_info" {
  value = var.enable_ssl_tls_module ? {
    certificate_arn    = module.ssl_tls[0].certificate_details.arn
    domain             = module.ssl_tls[0].certificate_details.domain_name
    subject_alt_names  = module.ssl_tls[0].certificate_details.subject_alt_names
    status             = module.ssl_tls[0].certificate_details.status
    monitoring_enabled = var.ssl_tls_enable_monitoring
    auto_renewal       = var.ssl_tls_enable_auto_renewal
  } : null
  description = "SSL/TLS certificate information"
}

# Output Caddy integration
output "caddy_certificate_configuration" {
  value       = var.enable_ssl_tls_module ? module.ssl_tls[0].ssl_tls_summary : null
  description = "Caddy certificate configuration details"
}
