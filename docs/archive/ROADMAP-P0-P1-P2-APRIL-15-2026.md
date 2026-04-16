# ACTIONABLE ROADMAP: kushin77/code-server
**Last Updated**: April 15, 2026  
**Priority**: Fix P0 issues FIRST, then P1, then P2

---

## CRITICAL PATH TO PRODUCTION CERTIFICATION

### WEEK 1: P0 Issues (10-15 hours) — DO NOT SKIP

| Issue | Title | Blocker | Fix Effort | Person |
|-------|-------|---------|-----------|--------|
| #413 | Vault production setup | YES | 4-6 hrs | DevOps |
| #412 | Remove hardcoded secrets | YES | 2-3 hrs | Security |
| #414 | Enforce auth (code-server, Loki) | YES | 1-2 hrs | Security |
| #415 | Fix terraform{} blocks | YES | 1 hr | Infra |
| #417 | Remote state backend (MinIO) | YES | 2-3 hrs | Infra |

**Milestone**: After Week 1, all P0 issues resolved → system production-ready

### WEEK 2-3: P1 Issues (20-25 hours) — Operational Excellence

| Issue | Title | Impact | Fix Effort |
|-------|-------|--------|-----------|
| #431 | Backup/DR hardening | RTO/RPO undefined | 6-8 hrs |
| #425 | Container hardening (network segmentation) | Security isolation missing | 8-10 hrs |
| #422 | Primary/replica HA (Patroni, Sentinel) | No automatic failover | 16-24 hrs |
| #416 | GitHub Actions deploy.yml | CI/CD broken | 4-6 hrs |

**Recommended Order**: #431 → #425 → #422 → #416
**Milestone**: After Week 3, HA and backup validated

### MONTH 2: P2 Issues (60-80 hours) — Architecture Excellence

**Recommended Order**:
1. #423: CI/CD consolidation (6-8 hrs) — unblocks faster iteration
2. #420: Caddyfile consolidation (3-4 hrs)
3. #419: Alert rules consolidation (4-6 hrs)
4. #418: Terraform module refactoring (8-12 hrs) — enables #427
5. #427: terraform-docs (4 hrs)
6. #421: Scripts consolidation (5-8 hrs)
7. #424: K8s migration ADR (4-6 hrs)
8. #428: Renovate hardening (4-6 hrs)
9. #429: Observability enhancements (6-10 hrs)
10. #430: Kong hardening (4-6 hrs)

---

## QUICK FIX GUIDE: P0 Issues

### #413: Vault Production Setup (4-6 hours)

**Current Problem**:
```bash
vault server -dev  # ← Hardcoded, loses data on restart
```

**Fix**:
```bash
# 1. Create storage backend (use existing MinIO or NAS)
# Option A: File backend (for testing)
mkdir -p /opt/vault/data

# Option B: PostgreSQL backend (production)
psql -c "CREATE DATABASE vault;"

# 2. Create Vault config (HCL)
cat > /opt/vault/config.hcl << 'EOF'
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
EOF

# 3. Start Vault in production mode
vault server -config=/opt/vault/config.hcl

# 4. Initialize and unseal
vault operator init -key-shares=5 -key-threshold=3
vault operator unseal  # (repeat 3 times with 3 of the 5 keys)

# 5. Save root token securely (NOT in logs or version control)
# Use SOPS/age to encrypt the recovery keys
age -r $PUBLIC_KEY -o recovery-keys.age recovery-keys.txt
git-crypt lock  # if using git-crypt for secrets
```

**Validation**:
```bash
curl -k https://192.168.168.31:8200/v1/sys/health
# Expected: {"sealed":false,"standby":false,...}
```

**Implementation Step**:
1. Update `terraform/phase-9d-backup.tf` to provision persistent Vault
2. Add Vault service to docker-compose with persistent volume
3. Implement unseal automation (via Terraform or CI secret injection)
4. Update `.env` to use Vault endpoints instead of plaintext secrets
5. Migrate all service secrets to Vault

**Test**:
```bash
ssh akushnir@192.168.168.31 "docker-compose logs vault | grep -i error"
curl -s https://192.168.168.31:8200/v1/sys/health | jq '.sealed'
```

---

### #412: Remove Hardcoded Secrets (2-3 hours)

**Audit**:
```bash
# Find all hardcoded secrets in codebase
cd c:\code-server-enterprise

# Terraform
grep -r "password\|secret\|token\|key" terraform/*.tf | grep -v "^#" | grep -v "var\." | grep -v "sensitive"

# Docker-compose
grep -r "password\|secret\|token" docker-compose.yml | grep -v "^#" | grep -v "${" | grep -v "PLACEHOLDER"

# Shell scripts
grep -r "export.*=.*[A-Za-z0-9]" scripts/*.sh | grep -E "(pass|secret|token|key)" | head -20

# Scan with gitleaks
docker run --rm -v $PWD:/path zricethezav/gitleaks:latest detect --source /path --verbose
```

**Fix**:
```hcl
# BEFORE (terraform/variables.tf)
variable "db_password" {
  default = "admin123"  # ← HARDCODED SECRET
}

# AFTER
variable "db_password" {
  type      = string
  sensitive = true
  # No default — must come from .env or -var flag
}
```

```bash
# BEFORE (.env)
POSTGRES_PASSWORD=admin123  # ← Could be readable

# AFTER
POSTGRES_PASSWORD=${VAULT_POSTGRES_PASSWORD}  # or leave blank, inject via CI
```

**For all services**:
1. Remove all example/default passwords from `variables.tf`
2. Mark all sensitive variables as `sensitive = true`
3. Force all secrets to come from `.env` or Vault injection
4. Update `.env.example` to show structure without values
5. Configure CI to inject secrets at deploy time

**Test**:
```bash
# Run gitleaks scan — should find 0 secrets
gitleaks detect --verbose | grep -i "secret found" | wc -l
# Expected output: 0
```

---

### #414: Enforce Authentication (1-2 hours)

**code-server**:
```bash
# Check current auth setting
docker-compose exec code-server code-server --help | grep -A2 "auth"

# Expected: --auth=password (NOT --auth=none)
```

**Fix in docker-compose.yml**:
```yaml
code-server:
  command:
    - code-server
    - --bind-addr=127.0.0.1:8080
    - --auth=password  # ← NOT "none"
    - --disable-update-check
  # NOTE: password-based auth is overridden by oauth2-proxy at Caddy layer
  # This is just a fallback security layer
```

**Loki**:
```yaml
# Check if Loki has auth-proxy frontend
loki:
  environment:
    LOKI_AUTH_ENABLED: "true"  # ← Add this
    # OR configure auth at reverse proxy layer (oauth2-proxy)
```

**oauth2-proxy Gate** (in Caddyfile):
```caddy
# Ensure NO service is exposed without oauth2-proxy gate
# Example for Loki:
loki.${APEX_DOMAIN} {
  reverse_proxy oauth2-proxy:4180 {
    header_up -Authorization  # clear any direct auth headers
  }
}
```

**Test**:
```bash
# Unauthenticated access should fail
curl -I http://code-server:8080/  # Should fail or redirect to login
curl -I http://loki:3100/loki/api/v1/query  # Should fail
```

---

### #415: Fix terraform{} Blocks (1 hour)

**Find all duplicate blocks**:
```bash
grep -n "^terraform {" terraform/*.tf | head -20
```

**Expected output**: Show each file with `terraform {` blocks

**Fix**: Keep ONLY ONE `terraform {}` block, and it should be in `main.tf`:
```hcl
# terraform/main.tf
terraform {
  required_version = ">= 1.7"
  
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "code-server-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}
```

**Remove from all other files** (`database.tf`, `network.tf`, `compute.tf`, etc.) — they should NOT have `terraform {}` blocks.

**Test**:
```bash
cd terraform
terraform validate
# Expected: ✅ All Terraform files validated successfully
```

---

### #417: Remote Terraform State Backend (2-3 hours)

**Current State**:
```bash
# Likely stored locally or in git (insecure)
ls -la terraform/terraform.tfstate*
```

**Setup MinIO backend** (S3-compatible):
```bash
# 1. Verify MinIO is running (already in docker-compose)
docker-compose exec minio ls

# 2. Create S3 bucket and DynamoDB table (Terraform lock)
# Use Terraform remote backend config

# 3. Create terraform/backend-config.s3.hcl
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

# 4. Update terraform/main.tf
terraform {
  backend "s3" {
    # Configured via backend-config flag at init
  }
}

# 5. Initialize with backend config
cd terraform
terraform init -backend-config=backend-config.s3.hcl

# 6. Migrate state (if exists locally)
terraform state push
```

**Test**:
```bash
# Verify state is in MinIO, not local
ls -la terraform/terraform.tfstate  # Should NOT exist
curl http://minio:9000/code-server-tfstate/prod/terraform.tfstate  # Should exist
```

---

## VALIDATION CHECKLIST

After each P0 fix, run:
```bash
# 1. Code scan
gitleaks detect --verbose 2>&1 | grep "secret found" | wc -l  # Should be 0

# 2. Terraform validation
cd terraform && terraform validate && terraform plan -json | jq '.diagnostics | length'  # Should be 0 errors

# 3. Docker Compose
docker-compose config --quiet  # Should pass

# 4. Security scan
docker run --rm -v $PWD:/workspace aquasec/trivy config /workspace  # Should show 0 HIGH/CRITICAL

# 5. Service health
curl -s http://192.168.168.31:8080/health  # code-server
curl -s http://192.168.168.31:9090/api/v1/query  # Prometheus
curl -s http://192.168.168.31:3000/api/health  # Grafana
```

---

## P1 QUICK START

After P0 is done, tackle P1 in this order:

### #431: Backup/DR Hardening
```bash
# Step 1: Verify WAL archiving
docker-compose exec postgres psql -U postgres -c "
  SELECT pg_is_in_recovery(), 
         current_setting('archive_mode'),
         current_setting('archive_command');
"
# Expected: f | on | cp %p /archive/%f && true

# Step 2: Test restore
./scripts/backup-restore-test.sh

# Step 3: Add Prometheus alert
cat >> config/prometheus/rules/backup.yml << 'EOF'
- alert: BackupStale
  expr: time() - backup_last_success_timestamp_seconds > 86400
  for: 30m
  annotations:
    summary: "Database backup has not run in >24 hours"
EOF
```

### #425: Container Hardening
```bash
# Segment networks in docker-compose.yml
networks:
  frontend:   # Caddy, kong proxy
  app:        # code-server, oauth2-proxy
  data:       # postgres, redis
  monitoring: # prometheus, grafana
```

### #422: HA Implementation
```bash
# Deploy Patroni for PostgreSQL HA
docker-compose pull patroni
docker-compose up -d patroni

# Deploy Redis Sentinel
docker-compose pull redis-sentinel
docker-compose up -d redis-sentinel

# Deploy HAProxy for transparent failover
docker-compose pull haproxy
docker-compose up -d haproxy
```

---

## SUCCESS CRITERIA

**P0 Complete** ✅:
- [ ] All secrets removed from version control
- [ ] Vault running in production mode with persistent storage
- [ ] All services using authenticated endpoints
- [ ] terraform validate passing
- [ ] Remote state backend configured
- [ ] gitleaks scan returns 0 secrets
- [ ] Production certificate issued and trusted

**P1 Complete** ✅:
- [ ] Backup age monitored with Prometheus alert
- [ ] Automated restore test job running weekly
- [ ] Network segmentation implemented (4+ networks)
- [ ] Patroni/Sentinel deployed for HA
- [ ] Failover tested (<60s RTO)
- [ ] GitHub Actions deploy working

**P2 Complete** ✅:
- [ ] CI reduced to 5 canonical workflows
- [ ] Terraform organized into modules
- [ ] Single consolidated Caddyfile
- [ ] Scripts consolidated to <50 files
- [ ] Alert rules in single file
- [ ] K&s strategy documented
- [ ] Repository cleaned (session files deleted)

---

**Next Action**: Start with #413 (Vault) — it unblocks the most other work.
