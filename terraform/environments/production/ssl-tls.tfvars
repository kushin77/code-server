# SSL/TLS Configuration - Production
# Location: terraform/environments/production/ssl-tls.tfvars
# WARNING: Changes to production certificates should follow change control

ssl_tls_apex_domain           = "example.com"
ssl_tls_subdomain_prefixes    = ["api", "admin", "dashboard", "monitoring", "auth", "control"]
ssl_tls_letsencrypt_email     = "infrastructure@example.com"
ssl_tls_enable_wildcard       = true
ssl_tls_enable_monitoring     = true
ssl_tls_enable_auto_renewal   = true
ssl_tls_renewal_days_before_expiry = 30
ssl_tls_expiration_alarm_threshold_days = 14
