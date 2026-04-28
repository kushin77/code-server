# SSL/TLS Configuration - Staging
# Location: terraform/environments/staging/ssl-tls.tfvars
# Note: Uses Let's Encrypt production by default in module

ssl_tls_apex_domain           = "staging.example.com"
ssl_tls_subdomain_prefixes    = ["api", "admin", "dashboard", "monitoring"]
ssl_tls_letsencrypt_email     = "infrastructure@example.com"
ssl_tls_enable_wildcard       = true
ssl_tls_enable_monitoring     = true
ssl_tls_enable_auto_renewal   = true
ssl_tls_renewal_days_before_expiry = 30
ssl_tls_expiration_alarm_threshold_days = 21
