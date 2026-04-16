# ════════════════════════════════════════════════════════════════════════════
# Phase 8-A: Secrets Management - SOPS + age encryption + Vault integration
# Issue #356: SOPS + age encryption for .env + Vault dynamic credentials
# ════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# 1. SOPS Configuration - age-based encryption
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "sops_config" {
  filename = "${path.module}/../.sops.yaml"
  content  = yamlencode({
    creation_rules = [
      {
        path_regex   = "secrets/.*\\.yaml$"
        age          = var.sops_age_public_key
        key_groups   = [{ age = [var.sops_age_public_key] }]
      }
    ]
  })

  depends_on = [null_resource.age_keyring_setup]
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. age Key Setup (one-time initialization)
# ─────────────────────────────────────────────────────────────────────────────

variable "sops_age_public_key" {
  type        = string
  description = "age public key for SOPS encryption (format: age1...)"
  sensitive   = true
  default     = ""  # Initialize with existing key or generate
}

variable "sops_age_private_key" {
  type        = string
  description = "age private key for SOPS decryption (KEEP SECURE!)"
  sensitive   = true
  default     = ""  # Initialize with existing key or generate
}

# Generate age keys if not provided (first-time setup)
resource "null_resource" "age_keyring_setup" {
  provisioner "local-exec" {
    command = <<-EOH
      set -e
      
      # Create keyring directory
      mkdir -p ~/.config/sops/age
      
      # Check if keys exist
      if [[ -f ~/.config/sops/age/keys.txt ]]; then
        echo "Age keys already exist in ~/.config/sops/age/keys.txt"
      else
        echo "Generating age keypair for SOPS..."
        # This requires age to be installed: brew install age (or apt-get install age)
        if command -v age-keygen &>/dev/null; then
          age-keygen -o ~/.config/sops/age/keys.txt
          chmod 600 ~/.config/sops/age/keys.txt
          echo "✓ Age keypair generated and stored (private key)"
          
          # Extract and output public key for Terraform variable
          echo "Add this to your terraform.tfvars:"
          grep "^# public key:" ~/.config/sops/age/keys.txt
        else
          echo "⚠ age-keygen not found. Install age: https://github.com/FiloSottile/age"
          exit 1
        fi
      fi
    EOH
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Vault Configuration - Dynamic Secrets
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "vault_config" {
  filename = "${path.module}/../config/vault-config.hcl"
  content  = yamlencode({
    ui           = true
    log_level    = "info"
    disable_mlock = false

    storage = {
      file = {
        path = "/vault/data"
      }
    }

    listener = {
      tcp = {
        address       = "0.0.0.0:8200"
        tls_cert_file = "/vault/config/tls/server.crt"
        tls_key_file  = "/vault/config/tls/server.key"
      }
    }

    # Auto-unseal (requires cloud provider or HSM setup)
    # seal "awskms" { region = "us-east-1", key_id = "arn:aws:..." }
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Vault Dynamic Secrets Configuration
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "vault_policies" {
  filename = "${path.module}/../config/vault-policies.hcl"
  content  = <<-EOH
# Policy for code-server application
path "secret/data/code-server/*" {
  capabilities = ["read", "list"]
}

# Policy for postgres rotation
path "database/static-creds/postgres" {
  capabilities = ["read"]
}

# Policy for redis rotation
path "database/static-creds/redis" {
  capabilities = ["read"]
}

# Policy for JWT issuance
path "jwt/issue/code-server" {
  capabilities = ["update"]
}

# Enable app to list secret versions
path "secret/metadata/*" {
  capabilities = ["list"]
}
  EOH
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Encrypted Secrets Template (.env.enc)
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "secrets_template" {
  filename = "${path.module}/../secrets/database.template.yaml"
  content  = yamlencode({
    # Database credentials (will be managed by Vault)
    postgres_password     = "{{ vault 'database/static-creds/postgres' 'username' }}"
    postgres_repl_password = "{{ vault 'database/static-creds/postgres-repl' 'username' }}"

    # Cache credentials (will be managed by Vault)
    redis_password = "{{ vault 'database/static-creds/redis' 'username' }}"

    # OAuth secrets (encrypted with age)
    google_oauth_client_id     = "REPLACE_WITH_GOOGLE_CLIENT_ID"
    google_oauth_client_secret = "REPLACE_WITH_GOOGLE_CLIENT_SECRET"

    # Cloudflare API credentials (encrypted with age)
    cloudflare_api_token = "REPLACE_WITH_CLOUDFLARE_TOKEN"
    cloudflare_zone_id   = "REPLACE_WITH_ZONE_ID"

    # GitHub token for Copilot support
    github_token = "REPLACE_WITH_GITHUB_TOKEN"

    # Webhook signing keys
    webhook_secret = "REPLACE_WITH_WEBHOOK_SECRET"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. Credential Rotation Automation
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "credential_rotation_config" {
  filename = "${path.module}/../config/credential-rotation.yaml"
  content  = yamlencode({
    schedules = [
      {
        name          = "postgres-rotation"
        schedule_cron = "0 2 * * *"  # Daily at 2 AM
        secret_path   = "database/static-creds/postgres"
        ttl           = "24h"
        max_ttl       = "25h"
      },
      {
        name          = "postgres-repl-rotation"
        schedule_cron = "0 3 * * *"  # Daily at 3 AM
        secret_path   = "database/static-creds/postgres-repl"
        ttl           = "24h"
        max_ttl       = "25h"
      },
      {
        name          = "redis-rotation"
        schedule_cron = "0 4 * * *"  # Daily at 4 AM
        secret_path   = "database/static-creds/redis"
        ttl           = "24h"
        max_ttl       = "25h"
      },
      {
        name          = "oauth-secrets-rotation"
        schedule_cron = "0 2 1 * *"  # Monthly at 2 AM on 1st
        secret_path   = "secret/data/oauth-secrets"
        ttl           = "30d"
        max_ttl       = "31d"
      },
      {
        name          = "webhook-keys-rotation"
        schedule_cron = "0 2 15 * *"  # Semi-monthly (15th)
        secret_path   = "secret/data/webhook-keys"
        ttl           = "30d"
        max_ttl       = "31d"
      },
      {
        name          = "tls-cert-rotation"
        schedule_cron = "0 3 1 * *"  # Monthly on 1st
        secret_path   = "pki/issue/code-server"
        ttl           = "90d"
        max_ttl       = "91d"
      },
    ]

    # Alert on staleness (credentials unused for > 45 days)
    staleness_alert_threshold = "45d"
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. Monitoring & Alerting for Secrets
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "secrets_monitoring_alerts" {
  filename = "${path.module}/../config/monitoring/secrets-alerts.yaml"
  content  = yamlencode({
    groups = [
      {
        name  = "vault-secrets"
        rules = [
          {
            alert      = "VaultSealed"
            expr       = "vault_core_unsealed == 0"
            for        = "1m"
            labels     = { severity = "critical" }
            annotations = { summary = "Vault is sealed (emergency)" }
          },
          {
            alert      = "VaultCertificateExpiring"
            expr       = "vault_secret_pki_certificates_expiry_seconds < 604800"
            for        = "1h"
            labels     = { severity = "warning" }
            annotations = { summary = "Vault TLS certificate expiring in < 7 days" }
          },
          {
            alert      = "SecretStaleness"
            expr       = "vault_secret_last_renewal_seconds > 3888000"
            for        = "1h"
            labels     = { severity = "warning" }
            annotations = { summary = "Secret not renewed for > 45 days (staleness alert)" }
          },
          {
            alert      = "CredentialRotationFailed"
            expr       = "vault_credential_rotation_errors_total > 0"
            for        = "5m"
            labels     = { severity = "high" }
            annotations = { summary = "Vault credential rotation failed (manual intervention needed)" }
          },
          {
            alert      = "SOPSDecryptionFailure"
            expr       = "rate(sops_decryption_errors_total[5m]) > 0"
            for        = "2m"
            labels     = { severity = "high" }
            annotations = { summary = "SOPS decryption failure (may indicate key compromise)" }
          },
        ]
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. Secrets Encryption Status Output
# ─────────────────────────────────────────────────────────────────────────────

output "sops_config_file" {
  value       = local_file.sops_config.filename
  description = "SOPS configuration file path"
}

output "vault_config_file" {
  value       = local_file.vault_config.filename
  description = "Vault configuration file path"
}

output "vault_policies_file" {
  value       = local_file.vault_policies.filename
  description = "Vault policies file path"
}

output "secrets_template_file" {
  value       = local_file.secrets_template.filename
  description = "Encrypted secrets template path"
}

output "credential_rotation_config_file" {
  value       = local_file.credential_rotation_config.filename
  description = "Credential rotation schedule file path"
}

output "secrets_management_status" {
  value       = "CONFIGURED - SOPS + age encryption, Vault PKI/dynamic secrets, credential rotation automation"
  description = "Secrets management deployment status"
}

output "encryption_method" {
  value       = "SOPS + age (AES-256)"
  description = "Encryption method for secrets at rest"
}

output "key_rotation_schedule" {
  value = {
    database_credentials = "24 hours"
    oauth_secrets        = "30 days"
    tls_certificates     = "90 days"
  }
  description = "Key and credential rotation schedule"
}

output "vault_seal_status_cmd" {
  value       = "vault status (check Sealed: false)"
  description = "Command to verify Vault is unsealed"
}

output "sops_encrypt_cmd" {
  value       = "sops -e secrets/database.yaml > secrets/database.enc.yaml"
  description = "Command to encrypt secrets with SOPS"
}

output "sops_decrypt_cmd" {
  value       = "sops -d secrets/database.enc.yaml"
  description = "Command to decrypt secrets with SOPS (requires age private key)"
}
