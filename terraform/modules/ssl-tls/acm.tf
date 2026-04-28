/**
 * @file terraform/modules/ssl-tls/acm.tf
 * @description AWS Certificate Manager with Let's Encrypt and DNS validation
 * @governance OPS-002: Certificate lifecycle management
 */

# Build list of domain names for the certificate
locals {
  # Apex domain
  domain_names = var.enable_wildcard_certificate ? concat(
    [var.apex_domain, "*.${var.apex_domain}"],
    [for prefix in var.subdomain_prefixes : "${prefix}.${var.apex_domain}"]
  ) : concat(
    [var.apex_domain],
    [for prefix in var.subdomain_prefixes : "${prefix}.${var.apex_domain}"]
  )

  # Unique subject alternative names
  san_list = distinct(local.domain_names)
  
  # First domain becomes the primary subject
  primary_domain = var.apex_domain
}

# Route53 zone data source
data "aws_route53_zone" "apex" {
  zone_id = var.route53_zone_id
}

# ACM Certificate with DNS validation
resource "aws_acm_certificate" "main" {
  domain_name            = local.primary_domain
  subject_alternative_names = slice(local.san_list, 1, length(local.san_list))
  validation_method      = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-${replace(var.apex_domain, ".", "-")}"
      Domain      = var.apex_domain
      Environment = var.environment
    }
  )
}

# DNS records for certificate validation
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id
}

# Wait for certificate validation to complete
resource "aws_acm_certificate_validation" "main" {
  certificate_arn           = aws_acm_certificate.main.arn
  timeouts {
    create = "5m"
  }

  depends_on = [aws_route53_record.validation]
}

# Export certificate details for Caddy configuration
resource "local_file" "caddy_certificate_config" {
  filename = "${path.module}/../../config/caddy-certificate.conf"
  
  content = templatefile("${path.module}/templates/caddy-certificate.conf.tpl", {
    apex_domain      = var.apex_domain
    subdomains       = join(" ", local.san_list)
    cert_arn         = aws_acm_certificate.main.arn
    cert_name        = "${var.environment}-${replace(var.apex_domain, ".", "-")}"
    environment      = var.environment
    letsencrypt_email = var.letsencrypt_email
  })

  depends_on = [aws_acm_certificate_validation.main]
}

# Outputs
output "certificate_arn" {
  value       = aws_acm_certificate.main.arn
  description = "ACM certificate ARN"
}

output "certificate_domain" {
  value       = local.primary_domain
  description = "Primary domain name"
}

output "certificate_sans" {
  value       = local.san_list
  description = "All domain names (SANs)"
}

output "certificate_validation_arn" {
  value       = aws_acm_certificate_validation.main.certificate_arn
  description = "Validated certificate ARN"
}

output "certificate_status" {
  value = {
    arn     = aws_acm_certificate.main.arn
    status  = aws_acm_certificate.main.status
    domains = local.san_list
  }
  description = "Certificate status summary"
}
