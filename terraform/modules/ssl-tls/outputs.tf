/**
 * @file terraform/modules/ssl-tls/outputs.tf
 * @description SSL/TLS module outputs
 */

output "ssl_tls_summary" {
  value = {
    apex_domain             = var.apex_domain
    certificate_arn         = aws_acm_certificate.main.arn
    certificate_status      = aws_acm_certificate.main.status
    sans_count              = length(local.san_list)
    monitoring_enabled      = var.enable_certificate_monitoring
    auto_renewal_enabled    = var.enable_certificate_auto_renewal
    validation_method       = var.dns_validation_method
    letsencrypt_environment = var.letsencrypt_environment
  }
  description = "SSL/TLS module configuration summary"
}

output "certificate_details" {
  value = {
    arn               = aws_acm_certificate.main.arn
    domain_name       = aws_acm_certificate.main.domain_name
    subject_alt_names = local.san_list
    validation_method = aws_acm_certificate.main.validation_method
    status            = aws_acm_certificate.main.status
  }
  description = "Certificate details"
}

output "monitoring_configuration" {
  value = {
    monitoring_enabled    = var.enable_certificate_monitoring
    check_schedule        = var.renewal_check_frequency
    expiration_alarm_days = var.certificate_expiration_alarm_days
    renewal_days_before   = var.certificate_renewal_days_before_expiry
    sns_topic             = var.sns_topic_arn
  }
  description = "Certificate monitoring configuration"
}
