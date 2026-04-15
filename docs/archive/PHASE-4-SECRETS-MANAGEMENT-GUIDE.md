# Phase 4: Secrets Management - IMPLEMENTATION GUIDE

**Status**: 🚀 **EXECUTING**  
**Duration**: 6 hours  
**Priority**: 🔴 P0 CRITICAL  
**Objective**: Migrate all plaintext credentials to HashiCorp Vault, rotate SSH keys, enforce zero-secrets policy  

---

## 📋 AUDIT FINDINGS: Plaintext Secrets Identified

### Category 1: Environment Variables (docker-compose files)
**Location**: docker-compose.yml, docker-compose.production.yml  
**Secrets Found**:
```yaml
# POSTGRESQL_PASSWORD=
# REDIS_PASSWORD=
# OLLAMA_API_KEY=
# ALERTMANAGER_SLACK_WEBHOOK=
# ALERTMANAGER_PAGERDUTY_SERVICE_KEY=
# PROMETHEUS_REMOTE_STORAGE_KEY=
```

### Category 2: Configuration Files (templates)
**Location**: *.tpl files  
**Risk**: Terraform templates may embed secrets during apply

### Category 3: SSH Keys (on-prem)
**Location**: ~/.ssh/akushnir-31, ~/.ssh/* (if present)
**Risk**: SSH keys may be readable by multiple users

### Category 4: Vault Configuration (missing)
**Location**: hashicorp-vault/ (doesn't exist yet)
**Gap**: No secrets engine initialized

---

## ✅ PHASE 4 IMPLEMENTATION STEPS

### Step 1: HashiCorp Vault Setup (1 hour)
**Goal**: Install and initialize Vault on 192.168.168.31

#### 1.1 Install Vault
```bash
# SSH to deployment host
ssh akushnir@192.168.168.31

# Download Vault v1.15.0
cd /tmp
wget https://releases.hashicorp.com/vault/1.15.0/vault_1.15.0_linux_amd64.zip
unzip vault_1.15.0_linux_amd64.zip
sudo mv vault /usr/local/bin/
vault --version
```

#### 1.2 Create Vault Service
```bash
# Create system user for Vault
sudo useradd --system --home /etc/vault --shell /bin/false vault || true

# Create config directory
sudo mkdir -p /etc/vault
sudo mkdir -p /var/lib/vault
sudo chown vault:vault /etc/vault /var/lib/vault
sudo chmod 700 /etc/vault /var/lib/vault

# Create Vault config file
sudo tee /etc/vault/config.hcl <<'EOF'
listener "tcp" {
  address       = "127.0.0.1:8200"
  tls_disable   = 0
  tls_cert_file = "/etc/vault/tls/vault.crt"
  tls_key_file  = "/etc/vault/tls/vault.key"
}

storage "file" {
  path = "/var/lib/vault"
}

api_addr     = "https://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
ui           = true
EOF

# Create TLS certificates for Vault
sudo mkdir -p /etc/vault/tls
cd /etc/vault/tls

# Generate self-signed cert (or use Let's Encrypt)
sudo openssl req -x509 -newkey rsa:4096 -keyout vault.key -out vault.crt -days 365 -nodes \
  -subj "/CN=vault.kushnir.local/O=Kushnir/C=US"

sudo chown vault:vault /etc/vault/tls/*
sudo chmod 600 /etc/vault/tls/*
```

#### 1.3 Create Systemd Service
```bash
sudo tee /etc/systemd/system/vault.service <<'EOF'
[Unit]
Description=HashiCorp Vault
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault/config.hcl

[Service]
Type=notify
ExecStart=/usr/local/bin/vault server -config=/etc/vault/config.hcl
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
User=vault
Group=vault

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault
sudo systemctl status vault
```

#### 1.4 Initialize Vault
```bash
# Initialize Vault (generates unseal keys + root token)
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY=true  # For self-signed cert

vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > ~/vault-init.json

# Save output securely (this is critical!)
# ⚠️ Store vault-init.json in secure location (not git)
# ⚠️ Share unseal keys with team leads in KeePass/1Password

# Extract root token
export VAULT_TOKEN=$(jq -r '.root_token' ~/vault-init.json)

# Unseal Vault (use 3 of 5 unseal keys)
vault operator unseal $(jq -r '.unseal_keys_b64[0]' ~/vault-init.json)
vault operator unseal $(jq -r '.unseal_keys_b64[1]' ~/vault-init.json)
vault operator unseal $(jq -r '.unseal_keys_b64[2]' ~/vault-init.json)

# Verify Vault is unsealed
vault status
```

### Step 2: Configure Secrets Engine (1 hour)
**Goal**: Setup kv2 secrets engine for application secrets

```bash
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY=true
export VAULT_TOKEN=$(jq -r '.root_token' ~/vault-init.json)

# Enable KV v2 secrets engine
vault secrets enable -path=secret kv-v2

# Verify
vault secrets list

# Create secret store for different services
vault kv put secret/database/postgres \
  username=postgres \
  password=$(openssl rand -base64 32) \
  host=postgres.kushnir.local \
  port=5432 \
  database=code-server

vault kv put secret/cache/redis \
  password=$(openssl rand -base64 32) \
  host=redis.kushnir.local \
  port=6379

vault kv put secret/alerting/slack \
  webhook_url=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

vault kv put secret/alerting/pagerduty \
  service_key=YOUR_PAGERDUTY_SERVICE_KEY

vault kv put secret/ssh \
  private_key=@/home/akushnir/.ssh/id_rsa
```

### Step 3: Create AppRole for Applications (1 hour)
**Goal**: Enable secure service-to-Vault authentication

```bash
# Enable AppRole auth method
vault auth enable approle

# Create role for code-server app
vault write auth/approle/role/code-server-elite \
  token_ttl=1h \
  token_max_ttl=24h \
  secret_id_ttl=0 \
  secret_id_num_uses=0

# Create policy for app (read-only access to secrets)
vault policy write code-server-elite - <<'EOF'
path "secret/data/database/postgres" {
  capabilities = ["read", "list"]
}

path "secret/data/cache/redis" {
  capabilities = ["read", "list"]
}

path "secret/data/alerting/*" {
  capabilities = ["read", "list"]
}
EOF

# Bind policy to role
vault write auth/approle/role/code-server-elite policies="code-server-elite"

# Generate RoleID (long-term)
ROLE_ID=$(vault read -field=role_id auth/approle/role/code-server-elite/role-id)
echo "RoleID: $ROLE_ID"

# Generate SecretID (should be rotated periodically)
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/code-server-elite/secret-id)
echo "SecretID: $SECRET_ID"

# Test authentication
vault write auth/approle/login \
  role_id="$ROLE_ID" \
  secret_id="$SECRET_ID"
```

### Step 4: Create Terraform Vault Provider Config (1 hour)
**Goal**: Integrate Vault with Terraform for secret injection

#### 4.1 Create terraform/secrets.tf
```hcl
# terraform/secrets.tf
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "vault" {
  address   = "https://127.0.0.1:8200"
  skip_tls_verify = true
  
  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = var.vault_role_id
      secret_id = var.vault_secret_id
    }
  }
}

# Read secrets from Vault
data "vault_generic_secret" "postgres" {
  path = "secret/data/database/postgres"
}

data "vault_generic_secret" "redis" {
  path = "secret/data/cache/redis"
}

data "vault_generic_secret" "slack" {
  path = "secret/data/alerting/slack"
}

# Output secrets for docker-compose rendering
output "postgres_password" {
  value     = data.vault_generic_secret.postgres.data["password"]
  sensitive = true
}

output "redis_password" {
  value     = data.vault_generic_secret.redis.data["password"]
  sensitive = true
}

output "slack_webhook" {
  value     = data.vault_generic_secret.slack.data["webhook_url"]
  sensitive = true
}
```

#### 4.2 Create terraform/variables.tf
```hcl
variable "vault_role_id" {
  type        = string
  description = "Vault AppRole RoleID"
  sensitive   = true
}

variable "vault_secret_id" {
  type        = string
  description = "Vault AppRole SecretID"
  sensitive   = true
}
```

#### 4.3 Create terraform/docker-compose.tf
```hcl
# Generate docker-compose.yml from template with Vault secrets injected
resource "local_file" "docker_compose" {
  content = templatefile("${path.module}/../docker-compose.tpl", {
    postgres_password = data.vault_generic_secret.postgres.data["password"]
    redis_password    = data.vault_generic_secret.redis.data["password"]
    slack_webhook     = data.vault_generic_secret.slack.data["webhook_url"]
  })
  filename = "${path.module}/../docker-compose.yml"
  
  file_permission = "0600"  # Restrict access to owner only
}
```

### Step 5: Update docker-compose Template (1 hour)
**Goal**: Remove hardcoded secrets, use template variables

#### 5.1 Create docker-compose.tpl (updated)
```yaml
# docker-compose.tpl
version: '3.9'

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: ${postgres_password}
      POSTGRES_USER: postgres
      POSTGRES_DB: code-server
    volumes:
      - postgres-data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass "${redis_password}"
    volumes:
      - redis-data:/data

  alertmanager:
    image: prom/alertmanager:latest
    environment:
      ALERTMANAGER_SLACK_WEBHOOK: ${slack_webhook}
    volumes:
      - ./alertmanager.tpl:/etc/alertmanager/alertmanager.yml:ro

  # ... rest of services
```

### Step 6: SSH Key Rotation (1 hour)
**Goal**: Generate new SSH keypair, secure old keys

```bash
# On 192.168.168.31 as akushnir user
ssh akushnir@192.168.168.31 << 'EOF'

# Backup old keys
mkdir -p ~/.ssh-backup-$(date +%Y%m%d)
cp ~/.ssh/* ~/.ssh-backup-$(date +%Y%m%d)/ 2>/dev/null || true

# Generate new ED25519 key (more secure than RSA)
ssh-keygen -t ed25519 -f ~/.ssh/akushnir-31-elite \
  -C "akushnir@code-server-elite" \
  -N ""  # Empty passphrase for automation

# Restrict permissions
chmod 600 ~/.ssh/akushnir-31-elite
chmod 644 ~/.ssh/akushnir-31-elite.pub

# Store new public key in GitHub deploy keys
# (manual step: add ~/.ssh/akushnir-31-elite.pub to GitHub)

# Disable old keys (don't delete immediately, in case rollback needed)
chmod 000 ~/.ssh/akushnir-31 2>/dev/null || true

# Verify new key works
ssh-keygen -y -f ~/.ssh/akushnir-31-elite

echo "✅ SSH key rotation complete"
EOF
```

### Step 7: Create Secrets Validation Script (1 hour)
**Goal**: Automated scanning to prevent secrets from being committed

#### 7.1 Create scripts/secrets-validation.sh
```bash
#!/bin/bash
# Scans codebase for plaintext secrets

set -e

SECRETS_FOUND=0

# Patterns to detect
PATTERNS=(
  "password.*=.*['\"]"
  "secret.*=.*['\"]"
  "api_key.*=.*['\"]"
  "webhook.*=.*https://hooks.slack.com"
  "BEGIN RSA PRIVATE KEY"
  "BEGIN OPENSSH PRIVATE KEY"
  "aws_access_key_id"
  "VAULT_TOKEN"
)

for pattern in "${PATTERNS[@]}"; do
  echo "[*] Scanning for: $pattern"
  
  if grep -r "$pattern" . --include="*.yml" --include="*.yaml" --include="*.json" \
     --include="*.env" --exclude-dir=.git --exclude-dir=.archived 2>/dev/null; then
    echo "⚠️  POTENTIAL SECRET FOUND: $pattern"
    SECRETS_FOUND=$((SECRETS_FOUND + 1))
  fi
done

if [ $SECRETS_FOUND -gt 0 ]; then
  echo "❌ FAILED: $SECRETS_FOUND potential secrets found"
  exit 1
else
  echo "✅ PASSED: No plaintext secrets detected"
  exit 0
fi
```

#### 7.2 Add to Git Pre-Commit Hook
```bash
# .git/hooks/pre-commit
#!/bin/bash
set -e

echo "Running secrets validation..."
bash scripts/secrets-validation.sh

echo "✅ Pre-commit checks passed"
```

---

## 🎯 PHASE 4 DELIVERABLES

### Completed
- [ ] Vault installed on 192.168.168.31
- [ ] Vault initialized (unseal keys secured)
- [ ] KV2 secrets engine enabled
- [ ] Database secrets migrated to Vault
- [ ] Alerting secrets migrated to Vault
- [ ] AppRole auth configured
- [ ] Terraform secrets.tf created
- [ ] docker-compose.tpl updated (no hardcoded secrets)
- [ ] SSH key rotation completed
- [ ] Pre-commit secrets validation enabled
- [ ] Documentation updated

### Verification Commands
```bash
# Verify Vault is running
vault status

# List stored secrets
vault kv list secret/

# Read a specific secret
vault kv get secret/database/postgres

# Test Terraform integration
terraform init
terraform plan  # Should pull secrets from Vault without displaying them
```

### Success Criteria
- ✅ Zero plaintext secrets in git
- ✅ All secrets stored in Vault
- ✅ AppRole authentication working
- ✅ Terraform successfully injects secrets
- ✅ Pre-commit hook blocks secret commits
- ✅ SSH keys rotated
- ✅ Audit trail: `vault audit list`

---

## 📊 TIME ALLOCATION

| Task | Duration | Status |
|------|----------|--------|
| Vault Install + Init | 1 hour | ⏳ Pending |
| Secrets Engine Config | 1 hour | ⏳ Pending |
| AppRole Setup | 1 hour | ⏳ Pending |
| Terraform Integration | 1 hour | ⏳ Pending |
| docker-compose Template | 1 hour | ⏳ Pending |
| SSH Key Rotation | 1 hour | ⏳ Pending |
| **Total Phase 4** | **6 hours** | 🚀 Ready |

---

**Next Phase**: Phase 5 - Windows Elimination (4 hours)  
**Total Remaining**: Phases 4-8 = 26 hours  
**Target Completion**: April 18, 2026  

