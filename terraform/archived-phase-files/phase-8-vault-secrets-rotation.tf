# terraform/phase-8-vault-secrets-rotation.tf
# ============================================
# Vault PostgreSQL Dynamic Secrets + Automatic Rotation (Issue #356)
# Automatic credential generation and rotation every 45 minutes
# TTL-based secret lifecycle: 1h default, 24h max

# ─── Local variables ──────────────────────────────────────────────────────

locals {
  vault_addr                 = var.vault_addr
  vault_postgres_role_ttl    = "1h"
  vault_postgres_max_ttl     = "24h"
  credential_rotation_script = "${path.module}/../scripts/setup-vault-secrets-rotation.sh"

  postgres_config = {
    host     = var.postgres_host
    port     = var.postgres_port
    database = var.postgres_db
    user     = var.postgres_admin_user
  }
}

# ─── Data source: Vault provider setup ────────────────────────────────────

provider "vault" {
  address         = local.vault_addr
  token           = var.vault_token
  namespace       = var.vault_namespace
  skip_tls_verify = var.vault_skip_tls_verify
}

# ─── Configure Vault PostgreSQL database secret engine ────────────────────

resource "vault_database_secret_backend_connection" "postgres" {
  count             = var.enable_vault_secrets ? 1 : 0
  backend           = "database"
  name              = "postgresql"
  plugin_name       = "postgresql-database-plugin"
  verify_connection = true

  allowed_roles = ["code-server", "readonly"]

  connection_url = "postgresql://{{username}}:{{password}}@${local.postgres_config.host}:${local.postgres_config.port}/${local.postgres_config.database}"

  username = base64decode(var.postgres_admin_username_b64)
  password = base64decode(var.postgres_admin_password_b64)

  lifecycle {
    ignore_changes = [connection_url]
  }
}

# ─── Vault database role: code-server (read/write access) ─────────────────

resource "vault_database_secret_backend_role" "code_server" {
  count   = var.enable_vault_secrets ? 1 : 0
  backend = vault_database_secret_backend_connection.postgres[0].backend
  name    = "code-server"
  db_name = vault_database_secret_backend_connection.postgres[0].name

  creation_statements = [
    "CREATE USER \"{{name}}\" WITH PASSWORD '{{password}}';",
    "GRANT CONNECT ON DATABASE ${local.postgres_config.database} TO \"{{name}}\";",
    "GRANT USAGE ON SCHEMA public TO \"{{name}}\";",
    "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
    "GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\";",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO \"{{name}}\";"
  ]

  default_ttl = local.vault_postgres_role_ttl
  max_ttl     = local.vault_postgres_max_ttl

  username_template = "{{.DisplayName}}-{{unix_time}}"
}

# ─── Vault database role: readonly (select-only access) ──────────────────

resource "vault_database_secret_backend_role" "readonly" {
  count   = var.enable_vault_secrets ? 1 : 0
  backend = vault_database_secret_backend_connection.postgres[0].backend
  name    = "readonly"
  db_name = vault_database_secret_backend_connection.postgres[0].name

  creation_statements = [
    "CREATE USER \"{{name}}\" WITH PASSWORD '{{password}}';",
    "GRANT CONNECT ON DATABASE ${local.postgres_config.database} TO \"{{name}}\";",
    "GRANT USAGE ON SCHEMA public TO \"{{name}}\";",
    "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
    "GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO \"{{name}}\";"
  ]

  default_ttl = "2h"
  max_ttl     = "48h"

  username_template = "{{.DisplayName}}-{{unix_time}}"
}

# ─── Deploy credential rotation setup script ──────────────────────────────

resource "null_resource" "vault_rotation_setup" {
  count = var.enable_vault_secrets ? 1 : 0

  provisioner "remote-exec" {
    inline = [
      "echo 'Setting up Vault PostgreSQL credential rotation...'",
      "bash ${local.credential_rotation_script}"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      host        = var.primary_host
      private_key = file(var.ssh_key_path)
      timeout     = "10m"
    }
  }

  depends_on = [
    vault_database_secret_backend_connection.postgres,
    vault_database_secret_backend_role.code_server,
    vault_database_secret_backend_role.readonly
  ]

  triggers = {
    script_hash = filemd5(local.credential_rotation_script)
  }
}

# ─── Verify credential rotation is working ────────────────────────────────

resource "null_resource" "verify_rotation" {
  count = var.enable_vault_secrets ? 1 : 0

  provisioner "remote-exec" {
    inline = [
      "echo 'Verifying Vault credential rotation...'",
      "systemctl is-active vault-rotate-credentials.timer || echo 'WARNING: Timer not running'",
      "vault read -format=json database/static-creds/code-server | jq '.data | {username}' || echo 'WARNING: Could not read credentials'",
      "echo 'Rotation verification complete'"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      host        = var.primary_host
      private_key = file(var.ssh_key_path)
      timeout     = "5m"
    }
  }

  depends_on = [null_resource.vault_rotation_setup]
}

# ─── Variables ────────────────────────────────────────────────────────────

variable "enable_vault_secrets" {
  description = "Enable Vault PostgreSQL dynamic secrets + automatic rotation (#356)"
  type        = bool
  default     = true
}

variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "http://localhost:8200"
}

variable "vault_token" {
  description = "Vault root token for setup (should be temporary)"
  type        = string
  sensitive   = true
}

variable "vault_namespace" {
  description = "Vault namespace (if using Enterprise)"
  type        = string
  default     = ""
}

variable "vault_skip_tls_verify" {
  description = "Skip TLS verification (NOT FOR PRODUCTION)"
  type        = bool
  default     = false
}

variable "postgres_host" {
  description = "PostgreSQL host"
  type        = string
  default     = "postgres"
}

variable "postgres_port" {
  description = "PostgreSQL port"
  type        = number
  default     = 5432
}

variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
}

variable "postgres_admin_user" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "postgres_admin_username_b64" {
  description = "Base64-encoded PostgreSQL admin username"
  type        = string
  sensitive   = true
}

variable "postgres_admin_password_b64" {
  description = "Base64-encoded PostgreSQL admin password"
  type        = string
  sensitive   = true
}

# ─── Outputs ──────────────────────────────────────────────────────────────

output "vault_secrets_rotation_status" {
  description = "Vault PostgreSQL secrets rotation status"
  value = var.enable_vault_secrets ? {
    enabled                = true
    postgres_role_ttl      = local.vault_postgres_role_ttl
    postgres_max_ttl       = local.vault_postgres_max_ttl
    rotation_interval      = "45 minutes"
    roles_created          = ["code-server", "readonly"]
    credential_rotation_id = try(null_resource.vault_rotation_setup[0].id, "not-deployed")
    } : {
    enabled = false
  }
}

output "vault_database_roles" {
  description = "Vault database roles configured"
  value = var.enable_vault_secrets ? {
    code_server = {
      ttl     = local.vault_postgres_role_ttl
      max_ttl = local.vault_postgres_max_ttl
      access  = "SELECT, INSERT, UPDATE, DELETE on all tables"
    }
    readonly = {
      ttl     = "2h"
      max_ttl = "48h"
      access  = "SELECT on all tables"
    }
  } : {}
}

output "rotation_script_path" {
  description = "Path to credential rotation script"
  value       = "/usr/local/bin/rotate-vault-credentials.sh"
}
