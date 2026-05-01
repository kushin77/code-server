# Secrets Vault Integration - HashiCorp Vault for Centralized Secrets

**Document**: Secrets Management & Credential Rotation  
**Version**: Phase 13  
**Date**: April 30, 2026  
**Purpose**: Centralized credential storage with automatic rotation and audit

---

## Overview

Secrets Vault provides:
- **Centralization**: All secrets in one secure location
- **Rotation**: Automatic credential refresh (90-day cycle)
- **Audit**: Complete access logs for compliance
- **RBAC**: Role-based access to different secret types
- **Encryption**: At-rest and in-transit encryption
- **Expiration**: Temporary credentials with auto-revocation

---

## Architecture

```
Applications          Vault Server         Secret Backends
├─ code-server   →   ┌──────────────┐   →  ├─ Database passwords
├─ API server    →   │ Vault        │   →  ├─ API keys
├─ Worker        →   │ (Encrypted   │   →  ├─ TLS certificates
└─ Monitoring    →   │  Storage)    │   →  ├─ SSH keys
                 →   └──────────────┘   →  └─ OAuth tokens
                        ↓
                    Audit Log
                   (all access)
```

---

## Components

### 1. Vault Server
- Centralized secrets storage
- TLS encryption for all connections
- Audit logging for compliance
- Web UI (port 8250)
- API (port 8200)

### 2. Vault Policies (RBAC)
- **admin-policy**: Full access (operations team)
- **app-policy**: Read-only (applications)
- **ci-cd-policy**: Pipeline access
- **database-policy**: DB admin (password rotation)
- **monitoring-policy**: Observability access

### 3. Credential Rotation
- Automatic 90-day password rotation
- No downtime during rotation
- Old credentials revoked
- Audit trail for compliance

### 4. Secrets Synchronization
- Auto-sync on container startup
- Periodic refresh (every 5 minutes)
- Mount secrets as files in containers
- Change detection triggers restarts

---

## Secret Types Supported

| Type | Examples | Rotation | Auto-Renewal |
|------|----------|----------|--------------|
| **Database** | MySQL, PostgreSQL passwords | 90 days | ✅ Automatic |
| **API Keys** | SendGrid, Stripe tokens | 90 days | ✅ Manual trigger |
| **TLS Certificates** | code-server-api | 30 days before expiry | ✅ Automatic |
| **SSH Keys** | Host access | 24 hours (temporary) | ✅ On-demand |
| **OAuth Tokens** | GitHub, Google | 60 days | ✅ Automatic |

---

## Operational Procedures

### Procedure 1: Vault Deployment (20 min)

**Step 1: Start Vault services**
```bash
docker-compose -f docker-compose.vault.yml up -d
```

**Step 2: Unseal Vault (dev mode)**
```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root-token-dev

vault status
```

**Step 3: Load policies**
```bash
bash scripts/security/vault-integration.sh
vault policy write admin /tmp/vault-policies.hcl
vault policy write app /tmp/app-policy.hcl
```

**Step 4: Enable secret engines**
```bash
vault secrets enable -path=secret/ kv-v2
vault secrets enable database
vault secrets enable pki
```

---

### Procedure 2: Store Secrets (10 min)

**Store database password**:
```bash
vault kv put secret/database/production/app_user \
  value="secure-password-here"
```

**Store API key**:
```bash
vault kv put secret/api-keys/sendgrid \
  value="SG.abc123xyz..."
```

**Generate database dynamic credentials**:
```bash
vault write database/config/mysql \
  plugin_name=mysql-database-plugin \
  allowed_roles="app,monitoring" \
  connection_url="root:password@tcp(mysql:3306)/"

vault write database/roles/app \
  db_name=mysql \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'" \
  default_ttl="1h" \
  max_ttl="24h"
```

---

### Procedure 3: Rotate Credentials (5 min)

**Manual rotation**:
```bash
bash /tmp/vault-credential-rotation.sh
```

**Schedule automatic rotation** (crontab):
```bash
# Rotate credentials every 90 days
0 2 1 * * /home/akushnir/code-server/scripts/security/vault-credential-rotation.sh
```

**Verify rotation**:
```bash
vault kv get secret/database/production/app_user
```

---

### Procedure 4: Application Integration (15 min)

**Update docker-compose**:
```yaml
services:
  api-service:
    environment:
      VAULT_ADDR: "http://vault:8200"
      VAULT_TOKEN: "s.abc123xyz..."
    volumes:
      - /var/run/secrets:/run/secrets:ro
    depends_on:
      - vault
    healthcheck:
      test: ["CMD", "test", "-f", "/run/secrets/db-password"]
```

**Application code**:
```bash
# Read database password from secret file
DB_PASSWORD=$(cat /run/secrets/db-password)

# Or query Vault directly
curl -H "X-Vault-Token: $VAULT_TOKEN" \
  http://vault:8200/v1/secret/data/database/app_user | \
  jq -r '.data.data.value'
```

---

## Compliance & Audit

### Audit Trail
```
✓ Who accessed secret
✓ When (timestamp)
✓ Which secret
✓ From which host/IP
✓ Success or failure
✓ How long the token was valid
```

**Query audit logs**:
```bash
vault audit list
vault read sys/audit
```

**Export audit logs**:
```bash
# To Elasticsearch
curl -s http://vault:8200/sys/audit | \
  jq '.data.file | select(.path == "file/")' | \
  docker logs vault | grep audit
```

---

## Security Best Practices

### 1. Root Token Management
```bash
# Never hardcode root token in production
# Use IAM authentication instead
vault write auth/aws/config/client \
  access_key=AKIAIOSFODNN7EXAMPLE \
  secret_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

### 2. Secret Access Logging
```bash
# Every secret access logged
vault audit enable file file_path=/vault/logs/audit.log

# Log to syslog for aggregation
vault audit enable syslog tag="vault"
```

### 3. Token TTL
```bash
# Set short TTLs for applications
vault write auth/kubernetes/role/app-role \
  bound_service_account_names=app \
  token_ttl=1h \
  token_max_ttl=24h
```

### 4. Network Security
```yaml
# Vault only accessible from internal network
networks:
  - internal-only  # not exposed to internet
```

---

## Troubleshooting

### Issue 1: Vault Sealed

**Symptom**: `error checking seal status: error making API request`

**Solution**:
```bash
# Check status
vault status

# Unseal (production: use seal keys)
vault unseal <key1>
vault unseal <key2>
vault unseal <key3>
```

### Issue 2: Authentication Failed

**Symptom**: `permission denied` when accessing secrets

**Solution**:
```bash
# Check token
vault token lookup

# Check policy
vault policy read app-policy

# Verify token has policy
vault token lookup -format=json | jq '.data.policies'
```

### Issue 3: Credential Rotation Failed

**Symptom**: Old password still required by database

**Solution**:
```bash
# Verify new password generated
vault kv get secret/database/production/app_user

# Test database connection
mysql -u app_user -p"$(vault kv get -field=value secret/database/production/app_user)" db

# Check app updated credentials
docker restart api-service
```

---

## Benefits vs Traditional Secrets

### Before (Secrets in .env files)
```
❌ Secrets in git repository
❌ Hardcoded in docker-compose
❌ No rotation capability
❌ No audit trail
❌ Shared passwords across environments
❌ Manual credential management
```

### After (Vault)
```
✅ Secrets never in repository
✅ Dynamic credentials per application
✅ Automatic 90-day rotation
✅ Complete audit trail
✅ Unique passwords per environment
✅ Automated credential management
✅ Temporary credentials with expiry
✅ RBAC by role
```

---

**Status**: ✅ **SECRETS VAULT INTEGRATION COMPLETE**

Centralized secrets management ready for production deployment.

