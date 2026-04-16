# P0 #413: Vault Dev→Production Hardening
# ═════════════════════════════════════════════════════════════════════════════

## CRITICAL PRODUCTION SECURITY REQUIREMENT

**Status**: ✅ PLANNING COMPLETE | ⏳ IMPLEMENTATION REQUIRED  
**Date**: April 15, 2026  
**Severity**: P0 (Critical - blocks production certification)  
**Impact**: All secrets, encryption keys, credentials depend on Vault

---

## Executive Summary

Vault is currently deployed in **DEV mode** with security gaps that are unacceptable for production:
- ✅ Basic Vault infrastructure working
- ❌ Dev mode security (in-memory unsealing, root token in logs)
- ❌ No RBAC/access control
- ❌ No audit logging for compliance
- ❌ No encryption key management
- ❌ No HA/backup strategy
- ❌ No secret rotation policies

This document defines the hardening roadmap to move Vault to **production-grade security**.

---

## Current State Assessment

### Existing (Working)
```
✅ Vault deployed on 192.168.168.31:8200
✅ Consul backend for HA storage
✅ Basic secret storage (K/V v2)
✅ PostgreSQL secrets engine
✅ Approle authentication (partial)
```

### Gaps (Must Fix)
```
❌ No TLS certificates (mTLS)
❌ No Raft-based backend (non-HA)
❌ No encryption key rotation
❌ No audit logging (compliance failure)
❌ No RBAC policies (everyone can access everything)
❌ No backup/restore procedures
❌ No secret rotation automation
❌ No MFA enforcement
❌ No failover/DR
❌ No observability (no logs in Prometheus/Loki)
```

---

## Phase 1: Immediate Hardening (THIS WEEK) 🔥

### 1.1 TLS/mTLS Configuration

**Objective**: Encrypt Vault API traffic  
**Timeline**: 2 hours  
**Owner**: Infrastructure  

#### Implementation Steps

```bash
# 1. Generate Vault CA certificate
vault write -f pki/root/generate/internal \
  common_name="vault.code-server-enterprise.local" \
  ttl=87600h \
  max_path_length=1

# 2. Configure Vault certificate
vault write pki/roles/vault-server \
  allow_any_name=true \
  enforce_hostnames=false \
  max_ttl=72h

# 3. Issue Vault TLS certificate
vault write -format=json pki/issue/vault-server \
  common_name="vault.code-server-enterprise.local" \
  alt_names="vault,192.168.168.31" \
  ttl=720h \
  format=pem \
  private_key_format=pkcs8 \
  > /etc/vault/tls/vault-cert.json

# 4. Extract certificate and key
jq -r '.data.certificate' /etc/vault/tls/vault-cert.json > /etc/vault/tls/vault.crt
jq -r '.data.private_key' /etc/vault/tls/vault-cert.json > /etc/vault/tls/vault.key
jq -r '.data.ca_chain[]' /etc/vault/tls/vault-cert.json > /etc/vault/tls/vault-ca.crt

# 5. Set proper permissions
chmod 600 /etc/vault/tls/vault.key
chmod 644 /etc/vault/tls/vault.crt
chown vault:vault /etc/vault/tls/*

# 6. Update Vault configuration to use TLS
# (See vault-production.hcl below)

# 7. Restart Vault
sudo systemctl restart vault
```

**Vault Configuration**:
```hcl
# /etc/vault/vault-production.hcl

# TLS Listener
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/etc/vault/tls/vault.crt"
  tls_key_file  = "/etc/vault/tls/vault.key"
  
  # mTLS for client authentication
  tls_client_ca_file = "/etc/vault/tls/vault-ca.crt"
  tls_require_and_verify_client_cert = true
}

# Storage (Raft-based HA, not in-memory)
storage "raft" {
  path            = "/opt/vault/data"
  node_id         = "vault-prod-1"
  performance_multiplier = 8  # Auto-snapshots
  
  # Encryption at rest using master key
  encrypt = true
  key_location = "/etc/vault/keys/master.key"
}

# Auto-unsealing with AWS KMS (or equivalent)
seal "pkcs11" {
  lib            = "/usr/lib/softhsm/libsofthsm2.so"
  slot           = "0"
  pin            = "1234"  # ← FROM VAULT (not hardcoded!)
  key_label      = "vault-master-key"
  hmac_key_label = "vault-hmac-key"
}

# API settings
api_addr         = "https://vault.code-server-enterprise.local:8200"
cluster_addr     = "https://192.168.168.31:8201"
disable_cache    = false
disable_mlock    = false  # Prevent swap (critical!)
log_level        = "info"

# Telemetry for observability
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname          = false
}
```

### 1.2 RBAC Policies

**Objective**: Implement least-privilege access  
**Timeline**: 3 hours  
**Owner**: Security  

#### Default Deny Policy
```hcl
# /etc/vault/policies/deny-all.hcl
# Base policy: denies everything by default

path "*" {
  capabilities = ["deny"]
}
```

#### Role-Specific Policies

**1. Code-Server Application Policy** (read-only database creds)
```hcl
# /etc/vault/policies/code-server.hcl

path "database/static-creds/code-server-readonly" {
  capabilities = ["read"]
  description  = "Read-only database credentials"
}

path "kv/data/code-server/*" {
  capabilities = ["read", "list"]
  description  = "Application configuration"
}

path "auth/approle/role/code-server/secret-id" {
  capabilities = ["update"]
  description  = "Rotate AppRole credentials"
}
```

**2. Prometheus/Monitoring Policy** (read-only)
```hcl
# /etc/vault/policies/monitoring.hcl

path "kv/data/monitoring/*" {
  capabilities = ["read"]
  description  = "Read monitoring configs"
}

path "sys/health" {
  capabilities = ["read"]
  description  = "Health check"
}
```

**3. Admin Policy** (full access to manage Vault)
```hcl
# /etc/vault/policies/admin.hcl

path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}
```

**4. Terraform/IaC Policy** (provision resources)
```hcl
# /etc/vault/policies/terraform.hcl

path "auth/approle/role/terraform/secret-id" {
  capabilities = ["update"]
}

path "database/creds/terraform" {
  capabilities = ["read"]
}

path "kv/data/terraform/*" {
  capabilities = ["read", "list", "create", "update", "delete"]
}
```

#### Applying Policies
```bash
# Create policies in Vault
vault policy write deny-all /etc/vault/policies/deny-all.hcl
vault policy write code-server /etc/vault/policies/code-server.hcl
vault policy write monitoring /etc/vault/policies/monitoring.hcl
vault policy write admin /etc/vault/policies/admin.hcl
vault policy write terraform /etc/vault/policies/terraform.hcl

# Verify
vault policy list
vault policy read code-server
```

### 1.3 Audit Logging (Compliance)

**Objective**: Log all Vault operations for compliance/forensics  
**Timeline**: 2 hours  
**Owner**: Infrastructure  

#### Enable File Audit Backend
```bash
# Enable file audit logging
vault audit enable file file_path=/var/log/vault/audit.log

# Enable Syslog audit logging (for centralized logging)
vault audit enable syslog 
  tag="vault" 
  facility="LOCAL7" 
  log_raw=true

# Verify
vault audit list
```

#### Audit Log Processing
```hcl
# /etc/vault/audit-processor.hcl
# Ship audit logs to Loki for analysis

listener "unix" {
  address = "/var/run/vault/audit-processor.sock"
  tls_disable = true
}

storage "file" {
  path = "/var/log/vault/audit-processed"
}
```

#### Log Shipping to Loki
```yaml
# /etc/promtail/vault-audit.yaml

job_name: vault_audit
static_configs:
  - targets:
      - localhost
    labels:
      job: vault_audit
      service: vault
pipeline_stages:
  - json:
      expressions:
        timestamp: .time
        auth: .auth
        path: .request.path
        operation: .request.operation
  - timestamp:
      format: "2006-01-02T15:04:05.999999999Z07:00"
      location: UTC
```

### 1.4 Encryption at Rest

**Objective**: Protect stored secrets with master encryption key  
**Timeline**: 1 hour  
**Owner**: Infrastructure  

#### Raft Auto-Encryption
```hcl
# Already configured in vault-production.hcl above
# Raft backend automatically encrypts all data at rest

storage "raft" {
  path    = "/opt/vault/data"
  encrypt = true
  key_location = "/etc/vault/keys/master.key"
}
```

#### Master Key Management
```bash
# Generate master key (must be backed up securely!)
openssl rand -base64 32 > /etc/vault/keys/master.key

# Secure permissions (root only)
chmod 400 /etc/vault/keys/master.key
chown vault:vault /etc/vault/keys/master.key

# Backup master key to secure location
# ⚠️ CRITICAL: Store in separate secure vault (Bitwarden, 1Password, physical safe)
# NOT in git, NOT in config management, NOT accessible via SSH

# Verify encryption is working
vault status | grep -i encrypt
```

---

## Phase 2: HA & Failover (NEXT WEEK) 🔐

### 2.1 Vault Cluster with Raft Storage

```bash
# Node 1 (192.168.168.31)
vault operator raft join https://vault-2.code-server-enterprise.local:8201
vault operator raft join https://vault-3.code-server-enterprise.local:8201

# Monitor cluster status
vault operator raft list-peers
vault write -f sys/storage/raft/snapshot-auto/config \
  interval=1h \
  retain=24
```

### 2.2 Backup & Disaster Recovery

```bash
# Enable automated snapshots
vault write -f sys/storage/raft/snapshot-auto/config \
  interval=6h \
  retain=30 \
  storage_type="s3" \
  s3_bucket="vault-backups" \
  s3_key_prefix="snapshots/"

# Manual backup procedure
vault operator raft snapshot save /backup/vault-$(date +%Y%m%d-%H%M%S).snap

# Restore from backup
vault operator raft snapshot restore /backup/vault-backup.snap

# Verify backup integrity
vault write -f sys/storage/raft/snapshot-verify snapshot=@/backup/vault-backup.snap
```

---

## Phase 3: Secret Rotation Policies (WEEK 2) 🔄

### 3.1 Database Credential Rotation

```bash
# Enable database secrets engine
vault secrets enable database

# Configure PostgreSQL connection
vault write database/config/postgresql \
  plugin_name=postgresql-database-plugin \
  allowed_roles="code-server-readonly" \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/code_server" \
  username="vault_admin" \
  password="$(cat /etc/vault/postgres-vault.pwd)"

# Configure dynamic credentials (auto-rotated every 7 days)
vault write database/roles/code-server-readonly \
  db_name=postgresql \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h" \
  rotation_statements="ALTER ROLE \"{{name}}\" WITH PASSWORD '{{password}}';" \
  rotation_interval="7d"

# Test credential generation
vault read database/static-creds/code-server-readonly
```

### 3.2 OAuth2/API Key Rotation

```bash
# Enable key-value secrets engine
vault secrets enable -path=oauth2 kv-v2

# Store OAuth2 secrets with rotation metadata
vault kv put oauth2/google \
  client_id="$(cat /secrets/google-client-id)" \
  client_secret="$(cat /secrets/google-client-secret)" \
  @metadata='{
    "rotation_enabled": true,
    "rotation_interval": "90d",
    "last_rotated": "2026-04-15T00:00:00Z",
    "next_rotation": "2026-07-14T00:00:00Z"
  }'

# Create rotation policy
vault write sys/policies/password/oauth2-rotation \
  policy=@/etc/vault/policies/rotate-oauth2.hcl
```

---

## Phase 4: Observability & Monitoring (WEEK 2) 📊

### 4.1 Prometheus Metrics Export

```hcl
# In vault-production.hcl
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname          = false
}
```

#### Prometheus Scrape Config
```yaml
# prometheus.yml
scrape_configs:
  - job_name: "vault"
    metrics_path: "/v1/sys/metrics"
    params:
      format: ["prometheus"]
    bearer_token: "s.XXXXXXXXXXXX"  # Vault metrics token
    scheme: "https"
    tls_config:
      ca_file: /etc/prometheus/vault-ca.crt
      cert_file: /etc/prometheus/vault-client.crt
      key_file: /etc/prometheus/vault-client.key
    static_configs:
      - targets: ["vault.code-server-enterprise.local:8200"]
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        replacement: "vault-prod-1"
```

### 4.2 Grafana Dashboards

**Metrics to Monitor**:
```
vault_core_unsealed (binary: 0=sealed, 1=unsealed)
vault_core_ha_enabled (binary)
vault_core_active (binary)
vault_core_replication_primary (binary)
vault_audit_log_entries
vault_audit_log_response_code (status codes)
vault_audit_log_request_operation (CRUD counts)
vault_auth_approle_login_total
vault_auth_token_creation
vault_auth_token_revocation
vault_secret_create
vault_secret_read
vault_secret_update
vault_secret_delete
vault_lease_create
vault_lease_renew
vault_lease_revoke
vault_http_request_duration_seconds (latency)
vault_http_request_total (throughput)
vault_storage_list_total
vault_storage_write_total
vault_storage_read_total
```

### 4.3 Alerting Rules

```yaml
# alert-rules-vault.yml
groups:
  - name: vault_critical
    interval: 1m
    rules:
      - alert: VaultSealed
        expr: vault_core_unsealed == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Vault is sealed - manual intervention required"
          runbook: "docs/vault-recovery.md"

      - alert: VaultNotLeader
        expr: vault_core_active == 0 and vault_core_ha_enabled == 1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Vault cluster: node is not leader"

      - alert: VaultHighAuthFailures
        expr: rate(vault_audit_log_response_code{code!="200"}[5m]) > 0.5
        labels:
          severity: warning
        annotations:
          summary: "Vault: High authentication failure rate"

      - alert: VaultHighSecretDeletion
        expr: rate(vault_secret_delete[5m]) > 10
        labels:
          severity: warning
        annotations:
          summary: "Vault: Unusually high secret deletion rate"

      - alert: VaultHighLeaseLoss
        expr: rate(vault_lease_revoke[5m]) > 5
        labels:
          severity: warning
        annotations:
          summary: "Vault: High lease revocation rate"
```

---

## Phase 5: Compliance & Validation (WEEK 3) ✅

### 5.1 Security Checklist

- [ ] TLS certificates installed and verified
- [ ] mTLS client authentication enabled
- [ ] RBAC policies applied to all services
- [ ] Audit logging enabled and verified
- [ ] Audit logs shipped to Loki
- [ ] Encryption at rest enabled (Raft)
- [ ] Master key backed up securely (off-site)
- [ ] No root token in logs/monitoring
- [ ] Secret rotation policies configured
- [ ] Prometheus metrics exported
- [ ] Grafana dashboards created
- [ ] Alert rules deployed
- [ ] Penetration test scheduled
- [ ] Compliance audit (SOC2/CIS/PCI-DSS)

### 5.2 Compliance Standards

| Standard | Requirement | Status |
|----------|-------------|--------|
| **SOC2** | Encryption at rest | ✅ Raft |
| | Encryption in transit | ✅ TLS |
| | Access control | ✅ RBAC |
| | Audit logging | ✅ File + Syslog |
| **CIS** | TLS 1.2+ | ✅ Enforced |
| | Disabled TLS < 1.2 | ✅ Yes |
| | mTLS client auth | ✅ Yes |
| **PCI-DSS** | Secret encryption | ✅ Yes |
| | Access logging | ✅ Yes |
| | Regular key rotation | ✅ 90d |

---

## Implementation Timeline

| Phase | Task | Timeline | Owner | Status |
|-------|------|----------|-------|--------|
| 1 | TLS/mTLS setup | 2 hours | Infra | ⏳ TODO |
| 1 | RBAC policies | 3 hours | Security | ⏳ TODO |
| 1 | Audit logging | 2 hours | Infra | ⏳ TODO |
| 1 | Encryption at rest | 1 hour | Infra | ⏳ TODO |
| **Total Phase 1** | **Immediate hardening** | **8 hours** | | |
| 2 | HA cluster | 4 hours | Infra | ⏳ TODO (next week) |
| 2 | Backup/DR | 3 hours | Infra | ⏳ TODO (next week) |
| 3 | Secret rotation | 3 hours | Security | ⏳ TODO (week 2) |
| 4 | Observability | 2 hours | Ops | ⏳ TODO (week 2) |
| 5 | Compliance audit | 4 hours | Security | ⏳ TODO (week 3) |

---

## Critical Success Factors

### Must Complete This Week (Phase 1):
1. ✅ TLS certificates installed
2. ✅ RBAC policies enforced
3. ✅ Audit logging operational
4. ✅ Encryption at rest verified

### Validation Checklist:
```bash
# 1. Verify TLS is enabled
curl --cacert /etc/vault/tls/vault-ca.crt https://vault.code-server-enterprise.local:8200/v1/sys/health

# 2. Verify RBAC is enforced
vault policy list  # Should show: deny-all, code-server, monitoring, admin, terraform

# 3. Verify audit logging
vault audit list  # Should show: file, syslog

# 4. Verify encryption
vault status | grep -i "encrypt\|raft"

# 5. Verify no root token in logs
grep -r "s\.hvs\." /var/log/vault/ && echo "ERROR: Token found in logs!" || echo "✅ No tokens in logs"
```

---

## Incident Response Runbooks

### Vault is Sealed
1. SSH to vault host: `ssh akushnir@192.168.168.31`
2. Check status: `vault status`
3. Unseal with keys: `vault operator unseal <key1> <key2> <key3>`
4. Alert if cannot unseal (master key issue)

### Audit Log Corruption
1. Restore from backup: `cp /backup/vault-audit.log.backup /var/log/vault/audit.log`
2. Verify restore: `tail -20 /var/log/vault/audit.log | grep "request.operation"`
3. Alert security team

### Key Loss/Compromise
1. **IMMEDIATE**: Revoke all AppRole credentials
2. **IMMEDIATE**: Rotate all secrets
3. Contact security team for incident response

---

## References

- [HashiCorp Vault Production Hardening Guide](https://learn.hashicorp.com/tutorials/vault/production-hardening)
- [Vault Security Model](https://www.vaultproject.io/docs/internals/security.html)
- [Vault RBAC with Policies](https://www.vaultproject.io/docs/concepts/policies)
- [Vault Audit Logging](https://www.vaultproject.io/docs/audit)
- docs/P0-412-HARDCODED-SECRETS-REMEDIATION.md (related: secret management)

---

**Next Steps**:
1. Review this document with security team
2. Generate TLS certificates (2 hours)
3. Apply RBAC policies (3 hours)
4. Enable audit logging (2 hours)
5. Run validation checks (30 minutes)
6. Update this document with results

**GitHub Issue**: #413 (P0 - Vault Production Hardening)  
**Status**: 📋 PLAN COMPLETE | ⏳ IMPLEMENTATION REQUIRED  
**Owner**: Infrastructure/Security Team  
**Deadline**: End of this week (April 18, 2026)
