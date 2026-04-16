# Phase 8: Secrets Management (#356)
# SOPS + age encryption, Vault integration, dynamic secrets, rotation
# Immutable, idempotent, on-prem focused

variable "vault_version" {
  description = "Vault version (immutable)"
  type        = string
  default     = "1.15.0"
}

variable "age_version" {
  description = "age encryption version (immutable)"
  type        = string
  default     = "1.1.1"
}

# ============================================================================
# Secrets Management Configuration
# ============================================================================

resource "local_file" "sops_config" {
  filename = "${path.module}/../.sops.yaml"
  content = templatefile("${path.module}/../templates/.sops.yaml.tpl", {
    kms_key = "arn:aws:kms:us-west-2:ACCOUNT:key/KEYID" # Update with actual KMS key
  })
}

resource "local_file" "vault_config" {
  filename = "${path.module}/../config/vault-config.hcl"
  content = templatefile("${path.module}/../templates/vault-config.hcl.tpl", {
    storage_path  = "/mnt/vault/data"
    http_addr     = "127.0.0.1:8200"
    tls_cert_file = "/etc/vault/tls/tls.crt"
    tls_key_file  = "/etc/vault/tls/tls.key"
    disable_mlock = false
    api_addr      = "https://vault.internal:8200"
    ui            = true
    log_level     = "info"
  })
}

resource "local_file" "deploy_secrets_management" {
  filename = "${path.module}/../scripts/deploy-secrets-management.sh"
  content = templatefile("${path.module}/../templates/deploy-secrets-management.sh.tpl", {
    primary_host  = var.primary_host_ip
    vault_version = var.vault_version
    age_version   = var.age_version
  })
}

resource "local_file" "rotate_credentials_script" {
  filename = "${path.module}/../scripts/rotate-credentials.sh"
  content  = file("${path.module}/../templates/rotate-credentials.sh.tpl")
}

output "secrets_management_config" {
  value = {
    encryption_method = "SOPS + age"
    key_management    = "Vault PKI"
    secret_rotation   = "24 hour max TTL"
    credential_types_managed = [
      "Database passwords (PostgreSQL)",
      "Cache passwords (Redis)",
      "API keys",
      "TLS certificates",
      "OAuth client secrets",
      "Webhook signing keys"
    ]
    immutable_versions = {
      vault = var.vault_version
      age   = var.age_version
    }
  }
}
