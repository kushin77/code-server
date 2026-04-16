# Vault Server Configuration
# Path: /vault/config/config.hcl
# This file is loaded by the Vault container during startup

listener "tcp" {
  address       = "127.0.0.1:8200"
  tls_disable   = 0
  tls_cert_file = "/vault/config/tls/vault.crt"
  tls_key_file  = "/vault/config/tls/vault.key"
}

storage "file" {
  path = "/vault/data"
}

api_addr     = "https://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
ui           = true
log_level    = "info"
