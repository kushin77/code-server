/**
 * @file terraform/variables-ssl-tls.tf
 * @description SSL/TLS module variables (add to root terraform/variables.tf)
 * @governance OPS-002: Certificate configuration
 */

variable "ssl_tls_apex_domain" {
  description = "Apex domain for SSL/TLS certificates"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$", var.ssl_tls_apex_domain))
    error_message = "Must be a valid domain name."
  }
}

variable "ssl_tls_subdomain_prefixes" {
  description = "Subdomain prefixes for certificates (api, admin, dashboard, etc.)"
  type        = list(string)
  default     = ["api", "admin", "dashboard", "monitoring"]
  validation {
    condition     = length(var.ssl_tls_subdomain_prefixes) >= 1 && length(var.ssl_tls_subdomain_prefixes) <= 10
    error_message = "Must specify 1-10 subdomain prefixes."
  }
}

variable "ssl_tls_letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.ssl_tls_letsencrypt_email))
    error_message = "Must be a valid email address."
  }
}

variable "ssl_tls_enable_wildcard" {
  description = "Include wildcard certificate (*.domain.com)"
  type        = bool
  default     = true
}

variable "ssl_tls_enable_monitoring" {
  description = "Enable certificate monitoring and alerting"
  type        = bool
  default     = true
}

variable "ssl_tls_enable_auto_renewal" {
  description = "Enable automatic certificate renewal"
  type        = bool
  default     = true
}

variable "ssl_tls_renewal_days_before_expiry" {
  description = "Trigger renewal this many days before certificate expiry"
  type        = number
  default     = 30
  validation {
    condition     = var.ssl_tls_renewal_days_before_expiry >= 7 && var.ssl_tls_renewal_days_before_expiry <= 60
    error_message = "Must be between 7 and 60 days."
  }
}

variable "ssl_tls_expiration_alarm_threshold_days" {
  description = "Alert when certificate expires in this many days"
  type        = number
  default     = 14
  validation {
    condition     = var.ssl_tls_expiration_alarm_threshold_days >= 1 && var.ssl_tls_expiration_alarm_threshold_days <= 30
    error_message = "Must be between 1 and 30 days."
  }
}
