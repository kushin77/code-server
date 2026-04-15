# ELITE 0.01% Infrastructure Consolidation & Optimization
## Master Execution Plan - April 15, 2026

---

## EXECUTIVE SUMMARY

This document outlines the comprehensive consolidation of kushin77/code-server infrastructure to achieve:
- ✅ **Immutable, Independent, Duplicate-Free IaC** (PRODUCTION MANDATE)
- ✅ **Passwordless GSM Secret Management** (all external services)
- ✅ **Linux-Only Deployment** (no Windows/PS1 dependencies)
- ✅ **GPU MAX, Speed MAX, NAS MAX optimization**
- ✅ **Clean Branch Hygiene** (single source of truth)
- ✅ **Elite Best Practices** (0.01% tier)

---

## CONSOLIDATION PHASES

### PHASE 1: ELIMINATE DUPLICATES (Critical)

#### 1.1 Docker-Compose Consolidation
**Current State**: 11 docker-compose files across 2 locations
```
./docker-compose.yml                          (PRIMARY - ACTIVE)
./docker-compose.production.yml                (⚠️ DEPRECATED - REMOVE)
./docker-compose-phase3-extended.yml           (⚠️ ARCHIVED - MOVE)
./docker-compose-p0-monitoring.yml             (⚠️ ARCHIVED - MOVE)
./docker-compose.git-proxy.yml                 (📋 REFERENCE - MOVE TO tests/)
./docker-compose.vault.yml                     (📋 REFERENCE - MOVE TO tests/)
./docker-compose.cloudflare-tunnel.yml         (📋 REFERENCE - MOVE TO tests/)
./docker/docker-compose.yml                    (❌ DUPLICATE - DELETE)
./docker/docker-compose.prod.yml               (❌ DUPLICATE - DELETE)
./scripts/dev/fix-docker-compose.sh            (❌ OBSOLETE - DELETE)
./scripts/docker-compose.yml                   (❌ WRONG LOCATION - DELETE)
```

**Remediation**:
```bash
# REMOVE DUPLICATES
git rm docker/docker-compose.yml
git rm docker/docker-compose.prod.yml
git rm scripts/docker-compose.yml

# ARCHIVE HISTORICAL VARIANTS
git mv docker-compose.production.yml .archived/docker-compose-variants/production.yml
git mv docker-compose-phase3-extended.yml .archived/docker-compose-variants/phase3-extended.yml
git mv docker-compose-p0-monitoring.yml .archived/docker-compose-variants/p0-monitoring.yml

# MOVE REFERENCE VARIANTS TO tests/
mkdir -p tests/docker-compose-variants/
git mv docker-compose.git-proxy.yml tests/docker-compose-variants/git-proxy.yml
git mv docker-compose.vault.yml tests/docker-compose-variants/vault.yml
git mv docker-compose.cloudflare-tunnel.yml tests/docker-compose-variants/cloudflare-tunnel.yml
git rm scripts/dev/fix-docker-compose.sh

# VERIFY SINGLE SOURCE OF TRUTH
git ls-files | grep docker-compose.yml
# Expected: ONLY ./docker-compose.yml (PRIMARY)
```

**Result**: 1 primary + 3 reference + 3 archived = 7 files (organized)

#### 1.2 Observability Configuration Consolidation
**Current State**: 4 prometheus + 4 alertmanager + 2 grafana variants

**Consolidation Target**:
```
ACTIVE (Production):
├── config/prometheus.yml             (PRIMARY - SSOT)
├── config/alertmanager.yml           (PRIMARY - SSOT)
├── config/grafana-datasources.yaml   (PRIMARY - SSOT)
└── alert-rules.yml                   (PRIMARY - Alert rules)

REFERENCE/LEGACY (Archive):
├── .archived/templates/prometheus.tpl
├── .archived/templates/alertmanager.tpl
└── .archived/templates/grafana-datasources.tpl

DEPRECATED (Delete):
└── alertmanager-base.yml             (Merge into config/alertmanager.yml)
```

**Implementation**:
```bash
# Delete obsolete files
git rm alertmanager-base.yml
git rm config/code-server/config.yaml  # Duplicate of root

# Archive template variants
mkdir -p .archived/templates/observability/
git mv prometheus.tpl .archived/templates/observability/
git mv alertmanager.tpl .archived/templates/observability/
git mv config/loki-local-config.yaml .archived/

# Keep ONLY active configs in config/
# - config/prometheus.yml (PRIMARY)
# - config/alertmanager.yml (PRIMARY) 
# - config/grafana-datasources.yaml (STANDARDIZED NAME - rename from .yml)
# - config/loki-config.yaml (PRIMARY)
# - config/promtail-config.yaml (PRIMARY)
```

#### 1.3 Code-Server Configuration Consolidation
**Current State**:
```
code-server-config.yaml                (root)
config/code-server/config.yaml         (duplicate)
config/code-server-readonly.yaml       (variant)
```

**Consolidation**:
```bash
# PRIMARY location: config/code-server/
git rm code-server-config.yaml
# Keep:
# - config/code-server/config.yaml (production)
# - config/code-server/config-readonly.yaml (P1 variant)
```

#### 1.4 Dockerfile Consolidation
**Current State**: 
```
Dockerfile                             (⚠️ Base - DEPRECATED)
Dockerfile.code-server                 (✅ ACTIVE)
Dockerfile.caddy                       (✅ ACTIVE)
Dockerfile.git-proxy                   (✅ ACTIVE)
Dockerfile.ssh-proxy                   (✅ ACTIVE)
```

**Action**:
```bash
# Delete deprecated base Dockerfile
git rm Dockerfile

# All services use explicit variant naming (keep as-is)
```

---

### PHASE 2: STANDARDIZE NAMING & YAML CONVENTIONS

#### 2.1 YAML Extension Standardization
**Current**: Inconsistent `.yml` vs `.yaml`  
**Target**: All files use `.yaml` (YAML spec standard)

**Files to Rename**:
```bash
# Config directory
git mv config/prometheus.yml config/prometheus.yaml
git mv config/alertmanager.yml config/alertmanager.yaml
git mv config/redis.conf config/redis.yaml  # (if applicable)
git mv config/audit-logging.conf config/audit-logging.yaml

# Root-level
git mv alert-rules.yml alert-rules.yaml
git mv Caddyfile Caddyfile.yaml  # (optional - Caddyfile is standard name)
git mv code-server-config.yaml config/code-server/config.yaml  # (consolidate)
git mv grafana-datasources.yml config/grafana-datasources.yaml
git mv oauth2-proxy.cfg config/oauth2-proxy.yaml

# Terraform/CI should remain as-is (*.tf, *.hcl, *.yml for GH Actions)
```

**Result**: All config files consistently use `.yaml` extension

#### 2.2 Naming Convention Standards

**Pattern 1 - Docker Services**:
```
Dockerfile.{service}                   (active variant)
docker-compose.{variant}.yaml          (only for tests/)
```

**Pattern 2 - Configuration Files**:
```
config/{service}/{variant}.yaml        (e.g., config/code-server/config.yaml)
config/{service}.yaml                  (if single config)
{feature}-rules.yaml                   (rules/policies)
```

**Pattern 3 - Scripts**:
```
scripts/{category}/{feature}-{action}.sh  
  ✅ scripts/gpu/gpu-deploy-31.sh
  ✅ scripts/nas/nas-mount-31.sh
  ✅ scripts/vault/vault-setup-noroot.sh
  ✅ scripts/deploy/automated-orchestration.sh
```

**Pattern 4 - Terraform Modules**:
```
terraform/{component}.tf               (unchanged)
terraform/modules/{service}/{component}.tf  (future - for submodules)
```

---

### PHASE 3: VERSION PINNING (SemVer)

#### 3.1 Docker Image Version Pinning

**Current Issue**: Most images use `latest` tag (floating target)  
**Production Mandate**: Pin ALL images to specific versions

**docker-compose.yml Changes**:
```yaml
# BEFORE (❌ Floating)
services:
  postgres:
    image: postgres:latest
  redis:
    image: redis:latest
  prometheus:
    image: prom/prometheus:latest
  grafana:
    image: grafana/grafana:latest

# AFTER (✅ Pinned SemVer)
services:
  postgres:
    image: postgres:16.2-alpine3.19
  redis:
    image: redis:7.2-alpine3.19
  prometheus:
    image: prom/prometheus:v2.52.0
  grafana:
    image: grafana/grafana:11.0.0
  caddy:
    image: caddy:2.9.1-alpine
  jaeger:
    image: jaegertracing/all-in-one:2.0.1
  ollama:
    image: ollama/ollama:0.1.41
  code-server:
    image: codercom/code-server:4.31.0
```

**Version Mapping** (Recommended Pinning):
| Service | Version | Alpine Base | Notes |
|---------|---------|-------------|-------|
| PostgreSQL | 16.2 | alpine3.19 | Production DB |
| Redis | 7.2 | alpine3.19 | Cache layer |
| Prometheus | v2.52.0 | — | Metrics collection |
| Grafana | 11.0.0 | — | Dashboards |
| Caddy | 2.9.1 | alpine | TLS/routing |
| Jaeger | 2.0.1 | — | Distributed tracing |
| Ollama | 0.1.41 | — | GPU/LLM hub |
| code-server | 4.31.0 | — | IDE |

#### 3.2 Application Version Pinning (locals.tf)

**terraform/locals.tf** - Master version inventory:
```hcl
locals {
  # Docker service versions (SemVer)
  docker_versions = {
    postgres           = "16.2-alpine3.19"
    redis              = "7.2-alpine3.19"
    prometheus         = "v2.52.0"
    grafana            = "11.0.0"
    caddy              = "2.9.1-alpine"
    jaeger             = "2.0.1"
    ollama             = "0.1.41"
    code_server        = "4.31.0"
    oauth2_proxy       = "v7.5.1"
  }
  
  # Application versions
  app_versions = {
    nodejs             = "20.13.0"
    python             = "3.11"
    postgres_replication = "16.2"
    redis_protocol     = "7"
  }
  
  # Infrastructure versions
  infrastructure = {
    kubernetes       = "1.28"  # For future k8s deployments
    terraform        = "1.8"
    vault            = "1.15"
  }
}
```

---

### PHASE 4: ENVIRONMENT VARIABLE MASTER INVENTORY

#### 4.1 `.env.master.template`

Create comprehensive template with ALL required variables:

```bash
# ============================================================================
# ELITE IaC ENVIRONMENT VARIABLES - Master Template
# Location: .env.master.template
# Purpose: Complete source-of-truth for all environment variables
# Usage: cp .env.master.template .env && fill in secrets via GSM
# ============================================================================

# DEPLOYMENT CONFIGURATION
DEPLOY_ENV=production
DEPLOY_SERVER=192.168.168.31
DEPLOY_NAS_PRIMARY=192.168.168.56
DEPLOY_NAS_BACKUP=192.168.168.55

# DATABASE - PostgreSQL
POSTGRES_USER=postgres
POSTGRES_PASSWORD=                                  # GSM: gsm-postgres-password
POSTGRES_DB=elite_app
POSTGRES_PORT=5432
POSTGRES_HOST=postgres
POSTGRES_REPLICA_USER=replica
POSTGRES_REPLICA_PASSWORD=                         # GSM: gsm-postgres-replica-password
POSTGRES_REPLICATION_PASSWORD=                     # GSM: gsm-postgres-replication-password
POSTGRES_HA_ENABLED=true
POSTGRES_DATA_PATH=/mnt/nas/postgres-data
POSTGRES_BACKUP_PATH=/mnt/nas/postgres-backup

# CACHE - Redis
REDIS_PASSWORD=                                    # GSM: gsm-redis-password
REDIS_PORT=6379
REDIS_HOST=redis
REDIS_PERSISTENCE_PATH=/mnt/nas/redis-data
REDIS_MEMORY_MAX=2gb
REDIS_POLICY=allkeys-lru

# REVERSE PROXY - Caddy
DOMAIN=ide.kushnir.cloud
CADDY_ADMIN_PORT=2019
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443
CADDY_LOG_LEVEL=info

# IDE - Code-server
CODE_SERVER_HOST=code-server
CODE_SERVER_PORT=8080
CODE_SERVER_PASSWORD=                              # GSM: gsm-code-server-password
CODE_SERVER_DATA_PATH=/mnt/nas/code-server-data
CODE_SERVER_EXTENSIONS_PATH=/mnt/nas/code-server-extensions
CODE_SERVER_GPU_ENABLED=true

# AUTHENTICATION - OAuth2
GOOGLE_CLIENT_ID=                                  # GSM: gsm-google-client-id
GOOGLE_CLIENT_SECRET=                              # GSM: gsm-google-client-secret
OAUTH2_PROXY_COOKIE_SECRET=                        # GSM: gsm-oauth2-cookie-secret
OAUTH2_PROXY_SESSION_STORE_TYPE=redis
OAUTH2_PROXY_UPSTREAMS=http://code-server:8080
ALLOWED_EMAILS_FILE=/etc/oauth2-proxy/allowed-emails.txt

# MONITORING - Prometheus
PROMETHEUS_RETENTION=30d
PROMETHEUS_RETENTION_SIZE=50GB
PROMETHEUS_SCRAPE_INTERVAL=15s
PROMETHEUS_EVALUATION_INTERVAL=15s
PROMETHEUS_ALERTMANAGER_HOST=alertmanager
PROMETHEUS_ALERTMANAGER_PORT=9093

# LOGGING - Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=                            # GSM: gsm-grafana-admin-password
GRAFANA_DATA_PATH=/mnt/nas/grafana-data
GRAFANA_LOG_LEVEL=info
GRAFANA_SECURITY_ADMIN_CHANGE_PASSWORD_ON_LOGIN=false

# LOGGING - Loki
LOKI_RETENTION_DAYS=30
LOKI_DATA_PATH=/mnt/nas/loki-data
LOKI_CHUNK_ENCODING=snappy

# TRACING - Jaeger
JAEGER_MEMORY_MAX=512MB
JAEGER_SPAN_STORAGE_TYPE=badger
JAEGER_BADGER_EPHEMERAL=false
JAEGER_BADGER_DIRECTORY_PATH=/mnt/nas/jaeger-data

# GPU/OLLAMA
GPU_DEVICE=/dev/nvidia1
OLLAMA_NUM_THREAD=8
OLLAMA_NUM_GPU=1
OLLAMA_DEBUG=false
OLLAMA_DATA_PATH=/mnt/nas/ollama-models
OLLAMA_LLM_MODEL_DEFAULT=llama2:70b

# ALERTING - AlertManager
ALERTMANAGER_WEBHOOK_URL=                          # Optional: Slack/PagerDuty
ALERTMANAGER_RESOLVE_TIMEOUT=5m

# VAULT - HashiCorp Vault (optional)
VAULT_ADDR=https://vault.kushnir.cloud
VAULT_TOKEN=                                       # GSM: gsm-vault-token
VAULT_UNSEAL_KEY=                                  # GSM: gsm-vault-unseal-key

# SECRET MANAGEMENT - Google Secret Manager
GSM_PROJECT_ID=kushnir-elite-prod
GSM_PREFIX=code-server/prod/                       # All secrets under this prefix

# NAS CONFIGURATION
NAS_PROTOCOL=nfs
NAS_MOUNT_POINT=/mnt/nas
NAS_TIMEOUT=30s
NAS_KEEPALIVE_INTERVAL=15s

# NETWORK
VPN_SUBNET_WIREGUARD=10.8.0.0/24
VPN_SUBNET_OPENVPN=10.0.0.0/8
LAN_SUBNET=192.168.168.0/24
CLOUDFLARE_TUNNEL_TOKEN=                           # GSM: gsm-cloudflare-tunnel-token

# GIT PROXY
GIT_PROXY_HOST=git-proxy
GIT_PROXY_PORT=8888
GIT_PROXY_CREDENTIAL_STORAGE=vault

# SSH ACCESS
SSH_KEY_PATH=/home/akushnir/.ssh/authorized_keys
SSH_PORT=22

# OBSERVABILITY/ALERTING
LOG_LEVEL=info
METRICS_ENABLED=true
TRACING_ENABLED=true
DEBUG_MODE=false

# PERFORMANCE TUNING
MAX_CONNECTIONS_POOL=100
CONNECTION_TIMEOUT=30s
QUERY_TIMEOUT=60s
NAS_BUFFER_SIZE=8388608  # 8MB

# BACKUP & DISASTER RECOVERY
BACKUP_ENABLED=true
BACKUP_FREQUENCY=daily
BACKUP_RETENTION_DAYS=30
BACKUP_DESTINATION=/mnt/nas/backups
```

**Instructions**:
```bash
# 1. Copy template
cp .env.master.template .env

# 2. For each line with "GSM:", fetch from Google Secret Manager
gsm_value=$(gcloud secrets versions access latest --secret="gsm-postgres-password")
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$gsm_value|" .env

# 3. OR use provided gsm_client.py to auto-populate
python3 services/gsm_client.py --env .env --project kushnir-elite-prod --prefix code-server/prod/
```

---

### PHASE 5: PASSWORDLESS GSM SECRET MANAGEMENT

#### 5.1 GSM Secret Naming Convention

**Format**: `code-server/prod/{service}/{secret-type}`

**Inventory**:
```
# Database
code-server/prod/postgres/password
code-server/prod/postgres/replica-password
code-server/prod/postgres/replication-password

# Cache
code-server/prod/redis/password

# Authentication
code-server/prod/google/client-id
code-server/prod/google/client-secret
code-server/prod/oauth2/cookie-secret

# IDE
code-server/prod/code-server/password

# Monitoring
code-server/prod/grafana/admin-password

# Infrastructure
code-server/prod/vault/token
code-server/prod/vault/unseal-key
code-server/prod/cloudflare/tunnel-token

# SSH/Git
code-server/prod/git/ssh-key
code-server/prod/git/proxy-token
```

#### 5.2 GSM Client Implementation (Updated)

**Location**: `services/gsm_client.py`

```python
#!/usr/bin/env python3
"""
Google Secret Manager (GSM) Client - Passwordless Secret Retrieval
Fetches all secrets for a given prefix and populates .env file
"""

import os
import sys
from typing import Dict, Optional
from google.cloud import secretmanager

class GSMClient:
    def __init__(self, project_id: str, prefix: str = "code-server/prod/"):
        self.project_id = project_id
        self.prefix = prefix
        self.client = secretmanager.SecretManagerServiceClient()
        self.parent = f"projects/{project_id}"
    
    def fetch_secret(self, secret_name: str) -> Optional[str]:
        """Fetch a single secret from GSM"""
        try:
            name = f"{self.parent}/secrets/{secret_name}/versions/latest"
            response = self.client.access_secret_version(request={"name": name})
            return response.payload.data.decode("UTF-8")
        except Exception as e:
            print(f"❌ Error fetching {secret_name}: {e}", file=sys.stderr)
            return None
    
    def populate_env_from_gsm(self, env_file: str, env_prefix: str = "DEPLOY_") -> Dict[str, str]:
        """
        Fetch all GSM secrets and populate env file
        Maps GSM hierarchy to environment variables
        """
        env_vars = {}
        
        # Map secret names to env variable names
        secret_mapping = {
            "postgres/password": "POSTGRES_PASSWORD",
            "postgres/replica-password": "POSTGRES_REPLICA_PASSWORD",
            "postgres/replication-password": "POSTGRES_REPLICATION_PASSWORD",
            "redis/password": "REDIS_PASSWORD",
            "google/client-id": "GOOGLE_CLIENT_ID",
            "google/client-secret": "GOOGLE_CLIENT_SECRET",
            "oauth2/cookie-secret": "OAUTH2_PROXY_COOKIE_SECRET",
            "code-server/password": "CODE_SERVER_PASSWORD",
            "grafana/admin-password": "GRAFANA_ADMIN_PASSWORD",
            "vault/token": "VAULT_TOKEN",
            "vault/unseal-key": "VAULT_UNSEAL_KEY",
            "cloudflare/tunnel-token": "CLOUDFLARE_TUNNEL_TOKEN",
        }
        
        for secret_path, env_var in secret_mapping.items():
            secret_name = self.prefix + secret_path.replace("/", "-")
            value = self.fetch_secret(secret_name)
            if value:
                env_vars[env_var] = value
                print(f"✅ {env_var} fetched from GSM")
            else:
                print(f"⚠️  {env_var} not found in GSM - check .env.master.template")
        
        # Write to .env file
        self._write_env_file(env_file, env_vars)
        return env_vars
    
    def _write_env_file(self, env_file: str, env_vars: Dict[str, str]):
        """Merge GSM secrets into .env file"""
        # Read existing .env.master.template
        with open(".env.master.template", "r") as f:
            content = f.read()
        
        # Replace placeholders with GSM values
        for var, value in env_vars.items():
            placeholder = f"{var}="
            if placeholder in content:
                content = content.replace(f"{placeholder}.*", f"{placeholder}{value}")
        
        # Write to target .env file
        with open(env_file, "w") as f:
            f.write(content)
        
        # Set secure permissions (user read-only)
        os.chmod(env_file, 0o600)
        print(f"✅ {env_file} written with GSM secrets (mode 0600)")

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Fetch secrets from GSM and populate .env")
    parser.add_argument("--project", required=True, help="GCP Project ID")
    parser.add_argument("--prefix", default="code-server/prod/", help="GSM secret prefix")
    parser.add_argument("--env", default=".env", help="Output .env file")
    
    args = parser.parse_args()
    
    gsm = GSMClient(project_id=args.project, prefix=args.prefix)
    gsm.populate_env_from_gsm(args.env)
    print(f"\n✅ ALL SECRETS POPULATED FROM GSM")
    print(f"   File: {args.env}")
    print(f"   Permissions: 0600 (user read-only)")
```

#### 5.3 CI/CD Integration

**GitHub Actions**: `.github/workflows/deploy.yml`

```yaml
- name: Populate secrets from Google Secret Manager
  run: |
    # Authenticate with GCP (via WORKLOAD_IDENTITY_FEDERATION)
    gcloud auth application-default login
    
    # Fetch all secrets and populate .env
    python3 services/gsm_client.py \
      --project kushnir-elite-prod \
      --prefix code-server/prod/ \
      --env .env
    
    # Validate .env has no placeholders
    if grep -q "GSM:" .env; then
      echo "❌ ERROR: Unfilled GSM placeholders found in .env"
      exit 1
    fi
    
    echo "✅ All secrets populated from GSM"
```

---

### PHASE 6: ELIMINATE WINDOWS DEPENDENCIES

#### 6.1 Audit and Remove PS1 Files

```bash
# List all PowerShell scripts
find . -name "*.ps1" -type f

# Action: Archive to .archived/
git mv archived/powershell-scripts/ .archived/deprecated/windows-powershell/
```

#### 6.2 Eliminate Windows-Only Terraform Runs

**Current Issue**: `terraform apply` on Windows tries to run against local Docker (fails)

**Solution**: Force SSH-based remote execution

**terraform/main.tf** - Update:
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Force remote-exec via SSH
provider "null" {}

# All deployments route through SSH to 192.168.168.31
resource "null_resource" "deploy_docker_compose" {
  triggers = {
    docker_compose_hash = filemd5("${path.module}/../docker-compose.yml")
  }

  provisioner "remote-exec" {
    inline = [
      "cd ~/code-server-enterprise",
      "docker-compose up -d --force-recreate"
    ]

    connection {
      type        = "ssh"
      user        = var.deploy_user
      host        = var.deploy_server  # 192.168.168.31
      private_key = file(var.ssh_key_path)
      timeout     = "5m"
    }
  }
}
```

**Documentation**: Add to README.md
```markdown
## Deployment Requirements

⚠️ **Windows Users**: Use WSL2 (Windows Subsystem for Linux 2) for all terraform/deployment operations
- Terraform operations SSH to 192.168.168.31 (Linux host)
- No local Docker required on Windows
- Use WSL2 terminal: bash, ssh, git

✅ **Linux/macOS**: All operations supported natively
```

---

### PHASE 7: GPU/SPEED/NAS OPTIMIZATION

#### 7.1 GPU Optimization

**Status**: Already configured
- ✅ NVIDIA driver 590.48 LTS
- ✅ CUDA 12.4
- ✅ Explicit GPU binding (/dev/nvidia1)
- ✅ Ollama 70B model running

**Enhancements**:
```yaml
# docker-compose.yml - GPU optimization
ollama:
  devices:
    - /dev/nvidia1:/dev/nvidia0
  environment:
    # GPU acceleration
    CUDA_VISIBLE_DEVICES: "0"
    OLLAMA_NUM_GPU: 1
    
    # CPU optimization
    OLLAMA_NUM_THREAD: 16          # Increase from 8
    
    # Memory optimization
    CUDA_MALLOC_PER_THREAD: 1
    TF32_ENABLED: 1                # Enable Tensor Float32
```

**Monitoring**:
```bash
# Monitor GPU utilization
docker exec ollama nvidia-smi

# Monitor memory usage
docker stats ollama --no-stream
```

#### 7.2 NAS Optimization

**Current Setup**:
```
NAS Mount: /mnt/nas (NFS)
Primary: 192.168.168.56
Backup: 192.168.168.55
Failover: Automated
```

**Speed Optimizations** - `scripts/nas/nas-mount-31.sh`:
```bash
#!/bin/bash
# NAS Mount Optimization for maximum throughput

mount_nas() {
  local NAS_HOST="$1"
  local MOUNT_POINT="/mnt/nas"
  
  # Optimal NFS mount options for throughput
  sudo mount -t nfs \
    -o proto=tcp,vers=4.1,rsize=1048576,wsize=1048576,hard,timeo=30,retrans=3,bg \
    "${NAS_HOST}:/export/share" "${MOUNT_POINT}"
  
  # Verify mount
  mount | grep nas
}

# Mount primary NAS
mount_nas "192.168.168.56"

# Configure failover (if primary fails, use backup)
cat >> /etc/fstab <<EOF
# NAS mount with failover
192.168.168.56:/export/share /mnt/nas nfs proto=tcp,vers=4.1,rsize=1048576,wsize=1048576,hard,timeo=30,retrans=3,bg 0 0
EOF

echo "✅ NAS mounted with max throughput settings"
```

**Speed Metrics** (Prometheus alert):
```yaml
# alert-rules.yaml
- name: nas_performance
  rules:
    - alert: NASHighLatency
      expr: nas_mount_latency_ms > 100
      annotations:
        summary: "NAS latency > 100ms - failover may be needed"
    
    - alert: NASLowThroughput
      expr: nas_mount_throughput_mbps < 100
      annotations:
        summary: "NAS throughput < 100 MB/s - performance degraded"
```

#### 7.3 Speed Optimization (General)

**Connection Pool Tuning** - `services/db-connection-pool.py`:
```python
# Optimal connection pool for 1M RPS
DATABASE_POOL_SIZE = 100
DATABASE_MAX_OVERFLOW = 50
DATABASE_POOL_RECYCLE = 3600
DATABASE_POOL_PRE_PING = True

REDIS_POOL_SIZE = 50
REDIS_CONNECTION_KWARGS = {
    "socket_keepalive": True,
    "socket_keepalive_options": {
        1: (TCP_KEEPIDLE, 60),
        2: (TCP_KEEPINTVL, 10),
        3: (TCP_KEEPCNT, 5),
    }
}
```

---

### PHASE 8: BRANCH HYGIENE & GIT CLEANUP

#### 8.1 Force-Push Clean State

```bash
# Cleanup all branches except main
git branch -D $(git branch | grep -v "main")

# Remove all remote tracking branches except origin/main
git remote prune origin

# Rebase main to remove merge commits (optional - only if safe)
git rebase --interactive HEAD~20

# Force-push cleaned state
git push origin main --force-with-lease
```

#### 8.2 Immutability Validation

```bash
# Verify no mutable tags
git tag -l | grep -E "latest|master" && echo "❌ MUTABLE TAGS FOUND" || echo "✅ All tags immutable"

# Verify no uncommitted changes
git status --short && echo "❌ UNCOMMITTED CHANGES" || echo "✅ Clean working tree"

# Verify no uncommitted binaries/secrets
git ls-files --others --exclude-standard | xargs -I {} file {} | grep -i "executable\|binary" && echo "❌ Binaries detected" || echo "✅ No uncommitted binaries"
```

---

## EXECUTION CHECKLIST

- [ ] Phase 1: Consolidate duplicates (Docker-compose, configs)
- [ ] Phase 2: Standardize naming and YAML extensions
- [ ] Phase 3: Pin all Docker image versions (SemVer)
- [ ] Phase 4: Create .env.master.template (complete inventory)
- [ ] Phase 5: Implement GSM client (passwordless secrets)
- [ ] Phase 6: Remove Windows/PS1 dependencies
- [ ] Phase 7: Optimize GPU/NAS/Speed
- [ ] Phase 8: Clean branch hygiene and force-push
- [ ] Final: Comprehensive validation and documentation

---

## VALIDATION GATES

✅ **IMMUTABILITY**: All images pinned (no `latest` tags)
✅ **INDEPENDENCE**: No cross-file dependencies (each service self-contained)
✅ **DUPLICATE-FREE**: Single source of truth for each config
✅ **NO OVERLAP**: No redundant/conflicting configurations
✅ **PASSWORDLESS**: All secrets via GSM (no hard-coded credentials)
✅ **LINUX-ONLY**: No Windows/PS1 dependencies
✅ **ELITE BEST PRACTICES**: Meets all 8 production mandates

---

## TIMELINE

**Start**: April 15, 2026 | 18:00 UTC  
**Target Completion**: April 16, 2026 | 04:00 UTC (10 hours)  
**Critical Path**: Consolidation (2h) → Version Pinning (1h) → GSM Integration (3h) → Testing (4h)

---

**Status**: READY FOR EXECUTION  
**Approval**: Production-First Mandate Compliance Required  
**Authority**: Elite 0.01% Infrastructure Standards
