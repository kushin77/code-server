# P0 Security & Operational Fixes - Execution Plan
**Date**: April 17, 2026  
**Priority**: CRITICAL - Block all merges until complete  
**Estimated Duration**: 10-15 hours  

---

## Executive Summary

5 critical P0 issues block production certification. All must be fixed before any P1/P2 work. This document tracks execution status.

| Issue | Title | Status | ETA | Owner |
|-------|-------|--------|-----|-------|
| #412 | Hardcoded secrets removal | IN-PROGRESS | 2h | Security |
| #413 | Vault production setup | PENDING | 4h | DevOps |
| #414 | Enforce auth (code-server/Loki) | COMPLETED | ✅ | Security |
| #415 | Fix terraform{} blocks | PENDING | 1h | Infra |
| #417 | Remote state backend | PENDING | 2h | Infra |

---

## Issue #414: Enforce Authentication ✅ COMPLETED

**Status**: FIXED  
**Changes Made**:
- ✅ code-server: `--auth=password` (already set)
- ✅ Loki: Changed from `ports: [0.0.0.0:3100]` to `expose: [3100]`
- ✅ Grafana: Changed from `ports: [0.0.0.0:3000]` to `expose: [3000]`
- ✅ Both now accessible ONLY through oauth2-proxy

**Verification**:
```bash
# Test: Loki should NOT be reachable on 3100
ss -tlnp | grep 3100  # Should have NO results
# Test: Should be accessible through oauth2-proxy
curl -I https://logs.kushnir.cloud/loki/api/v1/query  # Should 302 to /oauth2/sign_in
```

---

## Issue #412: Remove Hardcoded Secrets - IN-PROGRESS

**Root Cause**:  
- `.env.ci`: has test passwords (acceptable for CI, but should use Vault references)
- `docker-compose.yml`: MinIO default password `minio_password_change_me`
- Terraform: Some variables have examples/defaults in comments

**Fix Applied**:  
- ✅ `docker-compose.yml` line 128: Removed MinIO default password, now requires `${MINIO_ROOT_PASSWORD:?...}`
- 🟡 `.env.ci`: Still has test passwords (acceptable for CI-only usage, but should be reviewed)
- 📋 Terraform: Review all variables.tf files for defaults

**Remaining Work**:
1. Audit all Terraform variable defaults
2. Ensure .env.ci credentials are CI-test-only (not production)
3. Implement Vault integration for all production credentials

**Verification**:
```bash
gitleaks detect --verbose 2>&1 | grep "Secret found" | wc -l  # Should be 0
terraform validate  # Should pass
```

---

## Issue #413: Vault Production Setup - PENDING

**Current State**: Vault running in `vault server -dev` mode (hardcoded, loses data on restart)

**Required Changes**:

### 1. Create Vault Config File
```bash
# /opt/vault/config.hcl
storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/opt/vault/tls/vault.crt"
  tls_key_file  = "/opt/vault/tls/vault.key"
}

api_addr = "https://192.168.168.31:8200"
cluster_addr = "https://192.168.168.31:8201"
ui = true
```

### 2. Generate TLS Certificates
```bash
# Create Vault PKI backend OR use Let's Encrypt/self-signed
openssl req -x509 -newkey rsa:4096 -keyout /opt/vault/tls/vault.key -out /opt/vault/tls/vault.crt -days 365 -nodes
chmod 600 /opt/vault/tls/vault.*
```

### 3. Update docker-compose.yml Vault Service
```yaml
vault:
  image: vault:1.16.0
  command: server -config=/vault/config/config.hcl
  volumes:
    - ./vault-config.hcl:/vault/config/config.hcl:ro
    - vault-data:/vault/data
    - ./tls:/vault/tls:ro
  ports:
    - "8200:8200"
  cap_add: [IPC_LOCK]  # Memory locking for HSM compatibility
```

### 4. Initialize Vault (One-time)
```bash
vault operator init -key-shares=5 -key-threshold=3 > /secure/location/recovery-keys.txt
# Save recovery keys securely (NEVER in Git or logs)
```

### 5. Unseal Vault
```bash
vault operator unseal <key1>
vault operator unseal <key2>
vault operator unseal <key3>
```

**Terraform Integration**:
- Update `terraform/phase-8-vault-secrets-rotation.tf` to use persistent Vault
- Configure terraform provider to connect to https://192.168.168.31:8200
- Test: `vault status` should show `sealed: false`

---

## Issue #415: Fix Terraform{} Blocks - PENDING

**Problem**: 9 files have `terraform {}` blocks (only main.tf should have one)

**Files to Fix**:
- phase-8b-falco-runtime-security.tf
- phase-8b-renovate-automation.tf
- phase-8b-supply-chain-security.tf
- phase-9-cloudflare-dns.tf
- phase-9-cloudflare-tunnel.tf
- phase-9-cloudflare-waf.tf
- phase-9-egress-filtering.tf
- phase-9-host-hardening.tf

**Action**: Remove `terraform {}` block from each file (keep only in main.tf)

**Verification**:
```bash
cd terraform
terraform validate  # Should pass with 0 errors
```

---

## Issue #417: Remote Terraform State Backend - PENDING

**Current State**: Local state (insecure, no locking, corruption risk)

**Solution**: Use MinIO as S3-compatible backend

### 1. Create Terraform Backend Config
```hcl
# terraform/backend-config.s3.hcl
bucket         = "code-server-tfstate"
key            = "prod/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "terraform-lock"
skip_region_validation = true
skip_credentials_validation = true
skip_metadata_api_check = true
endpoint = "http://minio:9000"
access_key = "${MINIO_ROOT_USER}"
secret_key = "${MINIO_ROOT_PASSWORD}"
```

### 2. Update main.tf
```hcl
terraform {
  backend "s3" {
    # Configured via backend-config flag at init
  }
}
```

### 3. Initialize Backend
```bash
cd terraform
terraform init -backend-config=backend-config.s3.hcl -upgrade
# Migrate state from local to MinIO if needed
terraform state push
```

### 4. Verify
```bash
# State should be in MinIO, not local
ls terraform.tfstate*  # Should NOT exist
curl http://minio:9000/code-server-tfstate/prod/terraform.tfstate  # Should exist
```

---

## Validation Checklist

After EACH fix, run:

```bash
# 1. Security scan
gitleaks detect --verbose 2>&1 | grep -i "secret found" | wc -l  # Should be 0

# 2. Terraform validation
cd terraform && terraform validate  # Should pass

# 3. Docker compose
docker-compose config --quiet  # Should pass

# 4. Service health
curl -s http://192.168.168.31:8080/health  # code-server
curl -s http://192.168.168.31:9090/api/v1/query  # Prometheus
curl -s http://192.168.168.31:3000/api/health  # Grafana (should require auth)

# 5. Auth enforcement
curl -I http://192.168.168.31:3000/  # Should fail (port not exposed)
curl -I https://grafana.kushnir.cloud/  # Should 302 to oauth2-proxy login
```

---

## Deployment Steps

```bash
# 1. Verify all P0 fixes complete
git status  # All files should show changes

# 2. Run validation
cd /home/akushnir/code-server-enterprise
bash scripts/validate-deployment.sh

# 3. Apply changes
terraform apply -auto-approve
docker-compose restart

# 4. Post-deployment verification
docker-compose ps | grep -c healthy  # Should be 14
docker-compose logs vault | grep -i error  # Should be empty

# 5. Commit changes
git add -A
git commit -m "fix(p0): Close all critical security issues #412 #413 #414 #415 #417"
git push origin main
```

---

## Success Criteria

All P0 issues resolved when:
- ✅ Zero hardcoded secrets (gitleaks clean)
- ✅ Vault running in production mode with persistent storage
- ✅ Code-server/Loki authenticated (not exposed on host ports)
- ✅ Terraform validates without errors  
- ✅ State stored in MinIO with locking enabled
- ✅ All services healthy post-deploy
- ✅ No security warnings in CI

---

## Time Tracking

| Task | Estimate | Actual | Status |
|------|----------|--------|--------|
| #414 - Auth enforcement | 1h | 30min | ✅ DONE |
| #412 - Secrets audit | 1h | 1h | IN-PROGRESS |
| #413 - Vault production | 4h | TBD | PENDING |
| #415 - Terraform blocks | 1h | TBD | PENDING |
| #417 - Remote state | 2h | TBD | PENDING |
| **TOTAL** | **9-10h** | TBD | **~30% complete** |

---

**Next Step**: Implement #413 (Vault production) and #415 (terraform blocks) in parallel
