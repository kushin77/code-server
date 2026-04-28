# SSL/TLS Configuration - Development
# Location: terraform/environments/dev/ssl-tls.tfvars

ssl_tls_apex_domain           = "dev.kushnir.local"
ssl_tls_subdomain_prefixes    = ["api", "admin", "dashboard"]
ssl_tls_letsencrypt_email     = "dev-admin@example.local"
ssl_tls_enable_wildcard       = false
ssl_tls_enable_monitoring     = false
ssl_tls_enable_auto_renewal   = false

# Note: Development uses internal certificates (Caddyfile tls internal)
