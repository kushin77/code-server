# Vault Server Configuration
# For use in ~/vault-data directory
# Paths are relative to the working directory where vault is started

listener "tcp" {
  address       = "127.0.0.1:8200"
  tls_disable   = 0
  tls_cert_file = "./config/tls/vault.crt"
  tls_key_file  = "./config/tls/vault.key"
}

storage "file" {
  path = "./data"
}

api_addr     = "https://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
ui           = true
log_level    = "info"
