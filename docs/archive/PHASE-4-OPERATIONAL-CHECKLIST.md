# PHASE 4 EXECUTION: SECRETS MANAGEMENT - OPERATIONAL CHECKLIST

**Status**: 🚀 **READY TO EXECUTE**  
**Start Time**: April 15, 2026 14:45 UTC  
**Estimated Duration**: 6 hours (15:00-21:00 UTC)  
**Target**: Deploy HashiCorp Vault + Migrate All Secrets  

---

## 🎯 MISSION

Move all plaintext secrets from docker-compose files to HashiCorp Vault. Implement AppRole authentication for Terraform. Rotate SSH keys. Zero secrets in git by end of Phase 4.

---

## 📋 STEP-BY-STEP EXECUTION

### Step 1: Vault Installation (30 min)

#### 1.1 SSH to Deployment Host
```bash
ssh akushnir@192.168.168.31
```

#### 1.2 Download & Install Vault v1.15.0
```bash
cd /tmp

# Download Vault
wget https://releases.hashicorp.com/vault/1.15.0/vault_1.15.0_linux_amd64.zip

# Extract and install
unzip vault_1.15.0_linux_amd64.zip
sudo mv vault /usr/local/bin/
vault --version
# Should output: Vault v1.15.0
```

#### 1.3 Create System User & Directories
```bash
# Create vault system user
sudo useradd --system --home /etc/vault --shell /bin/false vault || true

# Create directories
sudo mkdir -p /etc/vault /var/lib/vault
sudo chown vault:vault /etc/vault /var/lib/vault
sudo chmod 700 /etc/vault /var/lib/vault

echo "✅ Vault user and directories ready"
```

#### 1.4 Create Vault Configuration
```bash
# Create config file
sudo tee /etc/vault/config.hcl > /dev/null <<'EOF'
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

echo "✅ Vault config created"
```

#### 1.5 Generate TLS Certificates
```bash
# Create TLS directory
sudo mkdir -p /etc/vault/tls

# Generate self-signed certificate (365 days)
sudo openssl req -x509 -newkey rsa:4096 -keyout /etc/vault/tls/vault.key \
  -out /etc/vault/tls/vault.crt -days 365 -nodes \
  -subj "/CN=vault.kushnir.local/O=Kushnir/C=US" 2>/dev/null

# Set permissions
sudo chown vault:vault /etc/vault/tls/*
sudo chmod 600 /etc/vault/tls/*

echo "✅ TLS certificates generated"
```

#### 1.6 Create Systemd Service
```bash
sudo tee /etc/systemd/system/vault.service > /dev/null <<'EOF'
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

# Enable and start Vault
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault

# Verify status
sleep 3
sudo systemctl status vault

echo "✅ Vault service running"
```

---

### Step 2: Initialize Vault (30 min)

#### 2.1 Set Environment Variables
```bash
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY=true  # For self-signed cert

echo "✅ Environment variables set"
```

#### 2.2 Initialize Vault
```bash
# Initialize Vault (5 unseal keys, 3 required)
vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > ~/vault-init.json

# Display initialization output
echo "=== VAULT INITIALIZATION COMPLETE ==="
cat ~/vault-init.json | jq '.unseal_keys_b64'

# ⚠️ CRITICAL: Save vault-init.json securely!
# Store unseal keys with team leads (not in git)
```

#### 2.3 Unseal Vault
```bash
# Extract unseal keys and root token
export VAULT_TOKEN=$(jq -r '.root_token' ~/vault-init.json)

# Unseal with first 3 keys
vault operator unseal $(jq -r '.unseal_keys_b64[0]' ~/vault-init.json)
vault operator unseal $(jq -r '.unseal_keys_b64[1]' ~/vault-init.json)
vault operator unseal $(jq -r '.unseal_keys_b64[2]' ~/vault-init.json)

# Verify sealed status
vault status
# Should show: "Sealed: false"

echo "✅ Vault unsealed and operational"
```

---

### Step 3: Configure Secrets Engine (45 min)

#### 3.1 Enable KV2 Secrets Engine
```bash
# Enable kv2 engine at path "secret"
vault secrets enable -path=secret kv-v2

# Verify
vault secrets list
# Should list: secret/  kv-v2

echo "✅ KV2 secrets engine enabled"
```

#### 3.2 Store Database Secrets
```bash
# Generate random password for PostgreSQL
POSTGRES_PASSWORD=$(openssl rand -base64 32)

vault kv put secret/database/postgres \
  username=postgres \
  password="$POSTGRES_PASSWORD" \
  host=postgres.kushnir.local \
  port=5432 \
  database=code-server

echo "✅ PostgreSQL secrets stored"
```

#### 3.3 Store Cache Secrets
```bash
# Generate random password for Redis
REDIS_PASSWORD=$(openssl rand -base64 32)

vault kv put secret/cache/redis \
  password="$REDIS_PASSWORD" \
  host=redis.kushnir.local \
  port=6379

echo "✅ Redis secrets stored"
```

#### 3.4 Store Alerting Secrets
```bash
# Slack webhook (you'll need to provide actual value)
vault kv put secret/alerting/slack \
  webhook_url="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# PagerDuty service key
vault kv put secret/alerting/pagerduty \
  service_key="YOUR_PAGERDUTY_SERVICE_KEY"

echo "✅ Alerting secrets stored"
```

#### 3.5 Store SSH Key in Vault (Optional but Recommended)
```bash
# Read current SSH private key
vault kv put secret/ssh \
  private_key=@~/.ssh/id_rsa \
  public_key=@~/.ssh/id_rsa.pub

echo "✅ SSH keys backed up to Vault"
```

#### 3.6 Verify All Secrets Stored
```bash
# List all secret paths
vault kv list secret/
vault kv list secret/database/
vault kv list secret/cache/
vault kv list secret/alerting/

# Read a secret (shows it's working)
vault kv get secret/database/postgres

echo "✅ All secrets verified in Vault"
```

---

### Step 4: Configure AppRole Authentication (45 min)

#### 4.1 Enable AppRole Auth Method
```bash
# Enable AppRole
vault auth enable approle

echo "✅ AppRole auth method enabled"
```

#### 4.2 Create AppRole for code-server-elite
```bash
# Create role
vault write auth/approle/role/code-server-elite \
  token_ttl=1h \
  token_max_ttl=24h \
  secret_id_ttl=0 \
  secret_id_num_uses=0

echo "✅ AppRole 'code-server-elite' created"
```

#### 4.3 Create Policy for App
```bash
# Create policy allowing app to read secrets
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

path "auth/approle/role/code-server-elite/*" {
  capabilities = ["read"]
}
EOF

echo "✅ AppRole policy created"
```

#### 4.4 Bind Policy to Role
```bash
# Attach policy to role
vault write auth/approle/role/code-server-elite policies="code-server-elite"

echo "✅ Policy bound to AppRole"
```

#### 4.5 Generate RoleID & SecretID
```bash
# Get RoleID (long-term identifier)
export ROLE_ID=$(vault read -field=role_id auth/approle/role/code-server-elite/role-id)

# Generate SecretID (short-term credential, rotate regularly)
export SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/code-server-elite/secret-id)

echo "=== AppRole Credentials ==="
echo "ROLE_ID:   $ROLE_ID"
echo "SECRET_ID: $SECRET_ID"

# Save to environment (for Terraform)
cat >> ~/.bashrc <<EOF
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY=true
export VAULT_ROLE_ID="$ROLE_ID"
export VAULT_SECRET_ID="$SECRET_ID"
EOF

echo "✅ AppRole credentials generated and saved"
```

#### 4.6 Test AppRole Authentication
```bash
# Test login with RoleID + SecretID
vault write auth/approle/login \
  role_id="$ROLE_ID" \
  secret_id="$SECRET_ID"

# Should return: "auth.client_token" with valid token

echo "✅ AppRole authentication verified"
```

---

### Step 5: SSH Key Rotation (45 min)

#### 5.1 Backup Current Keys
```bash
# Create backup directory with timestamp
BACKUP_DIR="$HOME/.ssh-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup current keys
cp ~/.ssh/* "$BACKUP_DIR/" 2>/dev/null || true

echo "✅ Current SSH keys backed up to: $BACKUP_DIR"
```

#### 5.2 Generate New ED25519 Key
```bash
# Generate new ED25519 key (more secure than RSA)
ssh-keygen -t ed25519 -f ~/.ssh/akushnir-31-elite \
  -C "akushnir@code-server-elite" \
  -N ""  # Empty passphrase for automation

# Verify key generated
ls -lah ~/.ssh/akushnir-31-elite*

echo "✅ New ED25519 key generated"
```

#### 5.3 Set Proper Permissions
```bash
# Restrict permissions
chmod 600 ~/.ssh/akushnir-31-elite
chmod 644 ~/.ssh/akushnir-31-elite.pub

# Verify
ls -lah ~/.ssh/akushnir-31-elite*

echo "✅ SSH key permissions set correctly"
```

#### 5.4 Disable Old Keys (No Deletion Yet)
```bash
# Disable old key (in case we need to revert)
[ -f ~/.ssh/akushnir-31 ] && chmod 000 ~/.ssh/akushnir-31 || true

echo "✅ Old SSH key disabled (not deleted for rollback safety)"
```

#### 5.5 Test New Key
```bash
# Verify new key works
ssh-keygen -y -f ~/.ssh/akushnir-31-elite | head -1

# Should display public key content

echo "✅ New SSH key verified"
```

#### 5.6 Update GitHub Deploy Keys (Manual Step)
```bash
echo "=== ACTION REQUIRED ==="
echo "Add new public key to GitHub:"
echo ""
cat ~/.ssh/akushnir-31-elite.pub
echo ""
echo "Go to: https://github.com/kushin77/code-server/settings/keys"
echo "Click 'Add deploy key' and paste the above key"
echo ""
echo "Press Enter when complete..."
read
```

---

### Step 6: Update docker-compose Template (30 min)

#### 6.1 Check Current Secrets in docker-compose
```bash
# Look for plaintext secrets
grep -E 'POSTGRES_PASSWORD|REDIS_PASSWORD|SLACK_WEBHOOK' docker-compose.yml || echo "No hardcoded secrets found"
```

#### 6.2 Create Terraform Integration (If Using Terraform)

If you're using Terraform to generate docker-compose, create `terraform/secrets.tf`:

```hcl
# terraform/secrets.tf
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

# Output secrets for use in Terraform
output "postgres_password" {
  value     = data.vault_generic_secret.postgres.data["password"]
  sensitive = true
}

output "redis_password" {
  value     = data.vault_generic_secret.redis.data["password"]
  sensitive = true
}
```

#### 6.3 Test Terraform Vault Integration (If Using)
```bash
cd terraform
terraform init
terraform plan
# Should NOT display secrets in plan output (marked as sensitive)
```

---

### Step 7: Verification & Cleanup (15 min)

#### 7.1 Verify Zero Secrets in Git
```bash
# Scan for plaintext secrets
bash scripts/secrets-validation.sh
# Should output: ✅ PASSED: No plaintext secrets detected
```

#### 7.2 Verify Vault is Operational
```bash
# Check Vault status
vault status
# Should show: "Sealed: false", "Initialized: true"

# List all secrets stored
vault kv list secret/
```

#### 7.3 Create Vault Backup
```bash
# Backup Vault data (encrypted at rest)
sudo cp -r /var/lib/vault /var/lib/vault-backup-$(date +%Y%m%d)

echo "✅ Vault backup created"
```

#### 7.4 Document Vault Access
```bash
cat > ~/VAULT-ACCESS.txt <<'EOF'
=== VAULT RECOVERY INFORMATION ===

Vault Address: https://127.0.0.1:8200

CRITICAL: Store these safely (not in git):
- Unseal Keys (5 total, 3 needed to unseal): In ~/vault-init.json
- Root Token (backup only): In ~/vault-init.json

AppRole Credentials:
- RoleID: $VAULT_ROLE_ID
- SecretID: $VAULT_SECRET_ID (rotate regularly)

To restart Vault:
1. Start service: sudo systemctl start vault
2. Unseal: vault operator unseal (repeat 3x with different keys)
3. Verify: vault status

To access secrets:
vault kv get secret/database/postgres
vault kv get secret/cache/redis
vault kv get secret/alerting/slack
EOF

echo "✅ Vault access documentation created"
```

---

## ✅ PHASE 4 COMPLETION CHECKLIST

After executing all steps above, verify:

- [ ] Vault installed and running (`vault status` shows unsealed)
- [ ] KV2 secrets engine enabled (`vault secrets list`)
- [ ] Database secrets stored (`vault kv get secret/database/postgres`)
- [ ] Cache secrets stored (`vault kv get secret/cache/redis`)
- [ ] Alerting secrets stored (`vault kv get secret/alerting/*`)
- [ ] AppRole created and authenticated (`vault auth list` shows approle)
- [ ] Policy created (`vault policy list` shows code-server-elite)
- [ ] RoleID & SecretID generated
- [ ] SSH key rotated (ED25519 key exists)
- [ ] Old SSH key disabled
- [ ] GitHub deploy key updated
- [ ] Zero plaintext secrets in git (`bash scripts/secrets-validation.sh` passes)
- [ ] Vault backup created
- [ ] Recovery documentation saved

---

## 🎯 PHASE 4 SUCCESS CRITERIA

**PASS Phase 4 if:**
- ✅ All secrets moved to Vault (zero in docker-compose files)
- ✅ AppRole authentication working (test with: `vault login -method=approle`)
- ✅ SSH keys rotated (ED25519 key functional)
- ✅ `bash scripts/secrets-validation.sh` returns exit code 0
- ✅ Vault status shows: Sealed=false, Initialized=true
- ✅ All 6 hours of work documented in commit message

---

## ⏱️ TIME TRACKING

| Task | Est. | Actual | Status |
|------|------|--------|--------|
| Vault Install | 30m | ___ | ⏳ |
| Vault Init | 30m | ___ | ⏳ |
| Secrets Config | 45m | ___ | ⏳ |
| AppRole Setup | 45m | ___ | ⏳ |
| SSH Key Rotation | 45m | ___ | ⏳ |
| Template Updates | 30m | ___ | ⏳ |
| Verification | 15m | ___ | ⏳ |
| **TOTAL** | **6h** | ___ | 🚀 |

---

## 🚀 NEXT STEPS

**When Phase 4 Complete**:
1. Commit all changes: `git commit -m "feat(p4): Secrets management with HashiCorp Vault"`
2. Git push: `git push origin main`
3. Mark Phase 4 as complete in todo list
4. Begin Phase 5 (Windows Elimination) using [PHASE-5-WINDOWS-ELIMINATION-GUIDE.md](PHASE-5-WINDOWS-ELIMINATION-GUIDE.md)

---

**Phase 4 Duration**: 6 hours  
**Phase 4 Target**: April 15, 2026 15:00-21:00 UTC  
**Phase 5 Start**: April 16, 2026 06:00 UTC  
**Program Completion**: April 18, 2026  

