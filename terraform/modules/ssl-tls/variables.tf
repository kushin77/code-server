/**
 * @file terraform/modules/ssl-tls/variables.tf
 * @description SSL/TLS ACME certificate management variables
 * @governance OPS-002: Certificate infrastructure as code
 */

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "apex_domain" {
  description = "Apex domain for certificate (e.g., example.com)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$", var.apex_domain))
    error_message = "Must be a valid domain name."
  }
}

variable "subdomain_prefixes" {
  description = "Subdomain prefixes to include in certificate (e.g., [api, admin, dashboard])"
  type        = list(string)
  default     = ["api", "admin", "dashboard", "monitoring"]
  validation {
    condition     = length(var.subdomain_prefixes) > 0 && length(var.subdomain_prefixes) <= 10
    error_message = "Must have 1-10 subdomain prefixes."
  }
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.letsencrypt_email))
    error_message = "Must be a valid email address."
  }
}

variable "letsencrypt_environment" {
  description = "Let's Encrypt environment (production or staging)"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["production", "staging"], var.letsencrypt_environment)
    error_message = "Must be production or staging."
  }
}

variable "certificate_renewal_days_before_expiry" {
  description = "Trigger certificate renewal this many days before expiry"
  type        = number
  default     = 30
  validation {
    condition     = var.certificate_renewal_days_before_expiry >= 7 && var.certificate_renewal_days_before_expiry <= 60
    error_message = "Renewal trigger must be 7-60 days before expiry."
  }
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for domain validation"
  type        = string
}

variable "dns_validation_method" {
  description = "DNS validation method for Let's Encrypt (dns01 or http01)"
  type        = string
  default     = "dns01"
  validation {
    condition     = contains(["dns01", "http01"], var.dns_validation_method)
    error_message = "Must be dns01 or http01."
  }
}

variable "enable_wildcard_certificate" {
  description = "Include wildcard certificate (*.domain.com)"
  type        = bool
  default     = true
}

variable "enable_certificate_monitoring" {
  description = "Enable monitoring and alerting for certificates"
  type        = bool
  default     = true
}

variable "certificate_expiration_alarm_days" {
  description = "Alert when certificate expires in this many days"
  type        = number
  default     = 14
  validation {
    condition     = var.certificate_expiration_alarm_days >= 1 && var.certificate_expiration_alarm_days <= 30
    error_message = "Alarm threshold must be 1-30 days."
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for certificate expiration alerts"
  type        = string
}

variable "caddy_certificate_path" {
  description = "Path where Caddy certificates are stored"
  type        = string
  default     = "/etc/caddy/certificates"
}

variable "enable_certificate_auto_renewal" {
  description = "Enable automatic certificate renewal"
  type        = bool
  default     = true
}

variable "renewal_check_frequency" {
  description = "Cron expression for renewal check frequency"
  type        = string
  default     = "0 2 * * *"  # Daily at 02:00 UTC
  validation {
    condition     = can(regex("^(([^\\s]+\\s){5}([^\\s]+))$", var.renewal_check_frequency))
    error_message = "Must be a valid cron expression."
  }
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project   = "infrastructure-modernization"
    ManagedBy = "Terraform"
    Phase     = "3"
  }
}
