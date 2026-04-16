################################################################################
# Vault Production Configuration
# File: config/vault/vault.hcl
# Purpose: Configure HashiCorp Vault in production mode with persistence & TLS
# Owner: Infrastructure Team
# References: Issue #413 - Vault production hardening
# Last Updated: April 17, 2026
################################################################################

# ════════════════════════════════════════════════════════════════════════════
# DISABLE ADMIN ENDPOINT (security best practice)
# ════════════════════════════════════════════════════════════════════════════
admin                   = false
ui                      = false
log_level               = "info"
log_format              = "json"
plugin_directory        = "/vault/plugins"

# ════════════════════════════════════════════════════════════════════════════
# PERSISTENT STORAGE BACKEND (replaces dev mode's in-memory)
# ════════════════════════════════════════════════════════════════════════════
storage "file" {
  path                  = "/vault/file"
  ha_enabled            = false  # Set to true when deploying HA with Consul/Raft
}

# Alternative: Integrated Raft storage (HA-ready, no external dependency)
# storage "raft" {
#   path                = "/vault/raft"
#   node_id             = "node1"
#   performance_multiplier = 8  # For production: tune based on load
# }

# ════════════════════════════════════════════════════════════════════════════
# LISTENER CONFIGURATION (TLS REQUIRED)
# ════════════════════════════════════════════════════════════════════════════
listener "tcp" {
  address               = "0.0.0.0:8200"
  tls_cert_file         = "/vault/tls/cert.pem"
  tls_key_file          = "/vault/tls/key.pem"
  
  # Require TLS 1.2 minimum
  tls_min_version       = "tls12"
  tls_prefer_server_cipher_suites = true
  
  # Disable redirect (on-prem, no Cloudflare)
  tls_disable_client_certs = false
}

# ════════════════════════════════════════════════════════════════════════════
# AUDIT LOGGING (Required for compliance & incident response)
# ════════════════════════════════════════════════════════════════════════════
audit {
  file {
    path                = "/vault/logs/audit.log"
    hmac_accessor       = true
  }
}

# ════════════════════════════════════════════════════════════════════════════
# TELEMETRY (Optional: export to Prometheus)
# ════════════════════════════════════════════════════════════════════════════
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname          = false
}

# ════════════════════════════════════════════════════════════════════════════
# SEAL CONFIGURATION (Unsealing strategy)
# ════════════════════════════════════════════════════════════════════════════
# For on-prem without HSM, use Shamir seal (default)
# Initialize with: vault operator init -key-shares=5 -key-threshold=3
# This generates 5 keys; need any 3 to unseal

# Alternatively, use Transit auto-unseal (requires secondary Vault instance)
# seal "transit" {
#   address            = "https://vault-secondary:8200"
#   token              = "..."
#   disable_renewal    = false
#   engine_path        = "transit/"
#   key_name           = "vault-unseal-key"
# }

# For testing only: disable seal (NEVER in production)
# seal "shamir" {
# }

# ════════════════════════════════════════════════════════════════════════════
# REPLICATION (Optional: for HA across sites)
# ════════════════════════════════════════════════════════════════════════════
# replication {
#   resolver_discover_servers = true
# }

# ════════════════════════════════════════════════════════════════════════════
# VAULT SERVER SETTINGS
# ════════════════════════════════════════════════════════════════════════════
disable_cache                = false
disable_mlock                = false  # Prevents memory swapping (security critical)
default_lease_duration        = "168h"  # 7 days
max_lease_duration            = "720h"   # 30 days
default_ui                    = false
