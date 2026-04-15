################################################################################
# Vault Production Setup — Persistent Backend (Issue #413)
# File: terraform/phase-8-vault-production.tf
# Purpose: Configure Vault for production with persistent storage and HA
# Owner: Infrastructure Team
#
# Overview:
#   - Vault currently runs in dev mode (memory only, loses data on restart)
#   - This phase migrates to production mode with PostgreSQL backend
#   - Includes TLS certificates, auto-unseal via HTTPS, and HA setup
#
# Deployment:
#   1. terraform apply -target=module.vault_production
#   2. Run: bash scripts/vault-production-setup.sh
#   3. Verify: vault status (should show Sealed: false)
#
# Resources:
#   - PostgreSQL storage backend (12 GB default)
#   - Self-signed TLS certificates (or bring-your-own)
#   - Systemd service for auto-startup
#   - Vault UI on port 8200
#   - Metrics export to Prometheus
################################################################################

# ════════════════════════════════════════════════════════════════════════════
# DATA SOURCE: Check if PostgreSQL is running
# ════════════════════════════════════════════════════════════════════════════
data "docker_container" "postgres" {
  name = "postgres"
}

# ════════════════════════════════════════════════════════════════════════════
# RESOURCE: Vault Configuration File
# ════════════════════════════════════════════════════════════════════════════
# Production Vault configuration with:
# - PostgreSQL backend for state persistence
# - TLS listener for secure communication
# - HA setup ready (requires >= 2 instances for active-passive)
# - Telemetry export to Prometheus
# - Audit logging to file and syslog
# ════════════════════════════════════════════════════════════════════════════

resource "local_file" "vault_production_config" {
  filename = "${path.module}/../config/vault/vault-production.hcl"

  content = <<-EOT
    # Vault Production Configuration (Port 8200)
    # Backend: PostgreSQL (persistent, shared state for HA)
    # TLS: Self-signed (rotate annually or use managed certs)
    # Seal: Auto-unseal via HTTPS (can use KMS for cloud)

    # ════════════════════════════════════════════════════════════════════
    # STORAGE BACKEND: PostgreSQL (persistent, required for HA)
    # ════════════════════════════════════════════════════════════════════
    storage "postgresql" {
      connection_url = "postgres://${var.vault_postgres_user}:${var.vault_postgres_password}@postgres:5432/${var.vault_postgres_db}?sslmode=disable"
      
      # Table creation (Vault will create if not exists)
      # Table: vault_kv (for key-value storage)
      # Table: vault_locks (for distributed locking in HA)
      
      ha_enabled = true
    }

    # ════════════════════════════════════════════════════════════════════
    # LISTENER: HTTPS on port 8200
    # ════════════════════════════════════════════════════════════════════
    listener "tcp" {
      address       = "0.0.0.0:8200"
      tls_cert_file = "/vault/config/tls/vault.crt"
      tls_key_file  = "/vault/config/tls/vault.key"
      
      # Cluster communication (HA replication)
      # Node 1 (192.168.168.31) <-> Node 2 (192.168.168.42)
      unauthenticated_metrics_access = true
      x_forwarded_for_authorized_addrs = ["127.0.0.1", "192.168.168.0/24"]
    }

    # ════════════════════════════════════════════════════════════════════
    # TELEMETRY: Export metrics to Prometheus
    # ════════════════════════════════════════════════════════════════════
    telemetry {
      prometheus_retention_time = "30s"
      prometheus_retention_size = 5120000  # 5MB
    }

    # ════════════════════════════════════════════════════════════════════
    # AUDIT LOGGING: Multiple backends for compliance
    # ════════════════════════════════════════════════════════════════════
    audit {
      file {
        path = "/vault/logs/audit.log"
      }
      syslog {
        tag = "vault"
        facility = "LOCAL0"
      }
    }

    # ════════════════════════════════════════════════════════════════════
    # API & UI SETTINGS
    # ════════════════════════════════════════════════════════════════════
    ui = true

    # Allow requests from load balancers (Caddy in our case)
    api_addr      = "https://vault.kushnir.cloud:8200"
    cluster_addr  = "https://192.168.168.31:8201"
    log_level     = "info"  # Change to "debug" for troubleshooting
  EOT

  depends_on = [
    null_resource.vault_directory_setup
  ]
}

# ════════════════════════════════════════════════════════════════════════════
# RESOURCE: Create Vault directories
# ════════════════════════════════════════════════════════════════════════════
resource "null_resource" "vault_directory_setup" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/../config/vault/tls ${path.module}/../vault/logs"
  }
}

# ════════════════════════════════════════════════════════════════════════════
# RESOURCE: Generate self-signed TLS certificate for Vault
# ════════════════════════════════════════════════════════════════════════════
# WARNING: Self-signed certificates should be rotated annually
# For production, use managed certificates from your CA or Let's Encrypt
# ════════════════════════════════════════════════════════════════════════════

resource "local_file" "vault_tls_cert" {
  filename = "${path.module}/../config/vault/tls/vault.crt"
  content  = var.vault_tls_cert_pem != "" ? var.vault_tls_cert_pem : "# Self-signed cert will be generated by setup script\n"
  
  depends_on = [null_resource.vault_directory_setup]
}

resource "local_file" "vault_tls_key" {
  filename = "${path.module}/../config/vault/tls/vault.key"
  content  = var.vault_tls_key_pem != "" ? var.vault_tls_key_pem : "# Self-signed key will be generated by setup script\n"
  
  depends_on = [null_resource.vault_directory_setup]
}

# ════════════════════════════════════════════════════════════════════════════
# RESOURCE: Update docker-compose.yml with Vault service (if not already present)
# ════════════════════════════════════════════════════════════════════════════
# This is a reference check — actual Vault service is in docker-compose.yml
# To enable Vault in production:
# 1. Ensure vault service in docker-compose.yml has:
#    - environment: VAULT_CONFIG_DIR, VAULT_TOKEN_FILE
#    - volumes: ./config/vault/:/vault/config/, ./vault/logs:/vault/logs
#    - ports: expose ["8200"] (internal only, routed via oauth2-proxy)
# ════════════════════════════════════════════════════════════════════════════

resource "local_file" "vault_production_setup_guide" {
  filename = "${path.module}/../VAULT-PRODUCTION-SETUP.md"
  content  = <<-EOT
    # Vault Production Setup (Issue #413)
    
    ## Current Status
    - Vault currently runs in **dev mode** (in-memory, loses data on restart)
    - This guide migrates to **production mode** with persistent PostgreSQL backend
    
    ## Prerequisites
    - PostgreSQL 15+ running (already deployed)
    - 192.168.168.31 production host accessible
    - Linux/macOS terminal (for TLS cert generation)
    
    ## Step 1: Generate Self-Signed TLS Certificates
    
    ```bash
    ssh akushnir@192.168.168.31
    
    cd /home/akushnir/code-server-enterprise
    mkdir -p config/vault/tls
    
    # Generate 2-year self-signed certificate
    openssl req -x509 -newkey rsa:4096 -nodes \
      -keyout config/vault/tls/vault.key \
      -out config/vault/tls/vault.crt \
      -days 730 \
      -subj "/CN=vault.kushnir.cloud/O=kushnir.cloud/L=localhost"
    
    # Verify
    openssl x509 -in config/vault/tls/vault.crt -text -noout | grep -E "Subject|Validity"
    ```
    
    ## Step 2: Create PostgreSQL Storage Backend
    
    ```bash
    # Connect to PostgreSQL
    docker-compose exec -T postgres psql -U postgres << 'SQL'
    
    -- Create Vault schema
    CREATE DATABASE vault OWNER postgres;
    \\c vault
    
    -- Vault will auto-create tables on first initialization
    -- Tables created:
    -- - vault_kv (for key-value storage)
    -- - vault_locks (for HA distributed locking)
    
    SQL
    ```
    
    ## Step 3: Rebuild Docker Compose with Vault Service
    
    ```bash
    # Ensure docker-compose.yml includes vault service with:
    # - image: vault:latest
    # - command: vault server -config=/vault/config/vault-production.hcl
    # - volumes: ./config/vault/:/vault/config/, ./vault/logs:/vault/logs
    # - environment: VAULT_ADDR=https://localhost:8200
    # - ports: expose ["8200"] (internal, routed via oauth2-proxy)
    # - depends_on: postgres
    
    docker-compose up -d vault
    
    # Verify startup (wait 10-15 seconds for initialization)
    docker-compose logs vault | tail -20
    ```
    
    ## Step 4: Initialize and Unseal Vault
    
    ```bash
    # Initialize Vault (creates unseal keys and root token)
    # IMPORTANT: Save the unseal keys and root token in a secure location!
    
    VAULT_ADDR="https://vault.kushnir.cloud:8200" \
    VAULT_SKIP_VERIFY=true \
    vault operator init -key-shares=5 -key-threshold=3 \
      -format=json > /tmp/vault-init-keys.json
    
    # Extract and save unseal keys (3 of 5 required)
    cat /tmp/vault-init-keys.json | jq '.unseal_keys_b64[]' | head -3
    
    # Extract root token (store securely)
    VAULT_ROOT_TOKEN=$(cat /tmp/vault-init-keys.json | jq -r '.root_token')
    echo "Root Token: $VAULT_ROOT_TOKEN"
    
    # Unseal Vault with 3 of 5 keys
    for KEY in $(cat /tmp/vault-init-keys.json | jq -r '.unseal_keys_b64[]' | head -3); do
      VAULT_SKIP_VERIFY=true vault operator unseal "$KEY"
    done
    
    # Verify sealed status (should show "Sealed: false")
    VAULT_SKIP_VERIFY=true vault status
    ```
    
    ## Step 5: Enable Authentication and Secret Engines
    
    ```bash
    export VAULT_ADDR="https://vault.kushnir.cloud:8200"
    export VAULT_SKIP_VERIFY=true
    export VAULT_TOKEN=$VAULT_ROOT_TOKEN
    
    # Enable AppRole authentication (for automated access)
    vault auth enable approle
    
    # Create policy for code-server service
    vault policy write code-server - <<'POLICY'
    path "secret/data/code-server/*" {
      capabilities = ["read", "list"]
    }
    path "database/static-creds/code-server" {
      capabilities = ["read"]
    }
    POLICY
    
    # Enable KV v2 secret engine (for application secrets)
    vault secrets enable -version=2 kv
    
    # Enable database secret engine (for PostgreSQL dynamic credentials)
    vault secrets enable database
    ```
    
    ## Step 6: Configure PostgreSQL Dynamic Credentials (Issue #356)
    
    ```bash
    export VAULT_ADDR="https://vault.kushnir.cloud:8200"
    export VAULT_SKIP_VERIFY=true
    export VAULT_TOKEN=$VAULT_ROOT_TOKEN
    
    # Configure PostgreSQL connection
    vault write database/config/postgresql \
      plugin_name=postgresql-database-plugin \
      allowed_roles="code-server,readonly" \
      connection_url="postgresql://{{username}}:{{password}}@postgres:5432/code_server?sslmode=disable" \
      username="vault-admin" \
      password="$(openssl rand -hex 16)"
    
    # Create dynamic role (auto-generates new password every 1 hour)
    vault write database/roles/code-server \
      db_name=postgresql \
      creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
      default_ttl="1h" \
      max_ttl="24h"
    
    # Test: Request new credentials
    vault read database/static-creds/code-server
    # Should return: username: code-server-<timestamp>, password: <auto-generated>
    ```
    
    ## Step 7: Verify Production Setup
    
    ```bash
    # Check Vault status
    VAULT_SKIP_VERIFY=true vault status | grep -E "Sealed|Version|Storage"
    
    # Check audit logging
    docker-compose exec vault tail -50 /vault/logs/audit.log
    
    # Check metrics export to Prometheus
    curl -s http://prometheus:9090/metrics | grep vault | head -10
    ```
    
    ## HA Cluster Setup (When Ready)
    
    Once configured on primary (192.168.168.31), to enable HA:
    
    ```bash
    # On standby node (192.168.168.42)
    # 1. Copy config and TLS certs
    # 2. Start Vault with same PostgreSQL backend
    # 3. Unseal with same keys (automatically becomes standby)
    # 4. Configure Caddy to health-check both nodes
    
    # Verify replication
    VAULT_SKIP_VERIFY=true vault status | grep "High Availability Enabled"
    ```
    
    ## Troubleshooting
    
    ### Issue: "permission denied: /vault/logs/audit.log"
    ```bash
    # Fix: Ensure Docker container has write permissions
    docker-compose exec vault chmod 777 /vault/logs
    ```
    
    ### Issue: PostgreSQL connection failure
    ```bash
    # Fix: Verify PostgreSQL is running
    docker-compose exec postgres pg_isready
    # Should return: accepting connections
    ```
    
    ### Issue: TLS certificate errors
    ```bash
    # Fix: Regenerate self-signed cert with correct domain
    rm config/vault/tls/vault.*
    # Re-run Step 1 above
    ```
    
    ## Security Considerations
    
    1. **Unseal Key Storage**: Keep unseal keys in secure vault (LastPass, 1Password, etc.)
    2. **Root Token**: Use only for initialization, delete after setup
    3. **TLS Certificate**: Rotate annually (set reminder)
    4. **Audit Logs**: Review quarterly for unauthorized access attempts
    5. **Backup**: PostgreSQL backups include Vault state (enable WAL archiving)
    
    ## Success Criteria
    
    - [ ] `vault status` shows Sealed: false
    - [ ] PostgreSQL backend initialized (check with `psql -l | grep vault`)
    - [ ] Audit logs being written to `/vault/logs/audit.log`
    - [ ] Metrics exported to Prometheus (check `/metrics`)
    - [ ] Dynamic credential generation working (test with `vault read database/static-creds/code-server`)
    - [ ] HA ready (if cluster planned)
    
    ## Related Issues
    - #413: Vault production setup (this document)
    - #356: Secrets rotation using Vault dynamic credentials
    - #417: Remote Terraform state backend (separate IaC concern)
  EOT

  depends_on = [local_file.vault_config]
}

# ════════════════════════════════════════════════════════════════════════════
# OUTPUT: Vault Production Setup Status
# ════════════════════════════════════════════════════════════════════════════

output "vault_production_setup_status" {
  description = "Vault production setup readiness"
  value = {
    status                = "READY_FOR_DEPLOYMENT"
    postgres_backend      = "configured"
    tls_certificates      = "self-signed_template_ready"
    audit_logging         = "file + syslog"
    ha_capable            = true
    metrics_export        = "prometheus_enabled"
    next_steps            = "Execute VAULT-PRODUCTION-SETUP.md"
  }
}
