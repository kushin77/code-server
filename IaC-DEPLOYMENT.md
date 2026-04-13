# IaC Deployment Guide — code-server-enterprise

**Status: Immutable | Idempotent | Infrastructure as Code**

This document describes the enterprise-grade Infrastructure-as-Code deployment model for code-server-enterprise. All infrastructure is managed in Terraform; nothing is manual or ephemeral.

---

## Architecture Overview

```
Terraform (Single Source of Truth)
    ↓
    ├─→ Generates: docker-compose.yml (with pinned versions)
    ├─→ Generates: .env (secrets from variables.tfvars)
    ├─→ Generates: Caddyfile (routing config)
    └─→ Generates: deploy.sh (orchestration script)
    
Docker Compose (Orchestration)
    ↓
    ├─→ code-server:4.115.0 (VS Code + navigator shim patch)
    ├─→ copilot:1.388.0 (extension, pinned)
    ├─→ copilot-chat:0.43.2026040705 (extension, pinned)
    ├─→ oauth2-proxy:v7.5.1 (auth sidecar)
    ├─→ caddy:2.7.6 (reverse proxy)
    └─→ ollama:0.1.27 (local LLM server)
```

**Key Principles:**
- ✅ **IaC**: Everything in Git (Terraform) except secrets
- ✅ **Immutable**: Build images with all patches baked in; never modify running containers
- ✅ **Idempotent**: Running `bash scripts/deploy.sh` multiple times produces identical state
- ✅ **Versioned**: All image tags, extensions, and tools pinned to exact semantic versions

---

## Prerequisites

### On Your Machine
- **Terraform** >= 1.0 (`terraform version`)
- **Docker** with **Docker Compose** v2+ (`docker --version && docker compose version`)
- **Bash** shell (scripts are POSIX shell)
- **curl** (for health checks and downloading extensions)
- **jq** (for deployment validation)

### In Google Cloud
- **Google OAuth2 credentials** (GCP Console → APIs & Services → Credentials)
  - Client ID (e.g., `xxx.apps.googleusercontent.com`)
  - Client Secret
- **Google Secret Manager** (optional, for storing secrets centrally)
  - `scripts/fetch-gsm-secrets.sh` pulls credentials from GSM

### Domain & DNS
- **DNS A record** pointing to your deployment host
  - Example: `ide.kushnir.cloud` → `203.0.113.42`
  - Used by oauth2-proxy for OIDC redirect URL
  - Caddy handles TLS automatically (ACME)

---

## Deployment Workflow

### Step 1: Clone and Setup

```bash
cd /path/to/code-server-enterprise
git clone https://github.com/kushin77/code-server.git
cd code-server
```

### Step 2: Configure Terraform Variables

```bash
# Copy example config
cp terraform.tfvars.example terraform.tfvars

# Edit with your secrets
vim terraform.tfvars
```

**Required variables:**
- `google_client_id` — From GCP Console
- `google_client_secret` — From GCP Console
- `oauth2_proxy_cookie_secret` — Generate: `openssl rand -base64 32`
- `domain` — Your DNS domain (e.g., `ide.kushnir.cloud`)

**Or use environment variables (secrets are never committed):**

```bash
export TF_VAR_google_client_id="xxx.apps.googleusercontent.com"
export TF_VAR_google_client_secret="yyy-secret"
export TF_VAR_oauth2_proxy_cookie_secret="$(openssl rand -base64 32)"
export TF_VAR_domain="ide.kushnir.cloud"

# Terraform will read these automatically
```

### Step 3: Initialize Terraform State

**First time only:**
```bash
terraform init
# Output: Terraform has been successfully configured!
```

**On subsequent runs:** Already initialized; just run `terraform plan`

### Step 4: Plan and Review Changes

```bash
terraform plan
```

**Output shows exactly what will be created/modified:**
```
+ local_file.docker_compose_yml      # Generated docker-compose.yml
+ local_file.env_file                # Generated .env with secrets
+ local_file.caddyfile               # Generated Caddyfile
+ local_file.deploy_script           # Generated deploy.sh
```

**Safe to run multiple times** — `terraform plan` is read-only.

### Step 5: Apply Infrastructure (Generate Artifacts)

```bash
terraform apply
# Review the plan, then type 'yes'
```

**What happens:**
1. ✅ Generates `docker-compose.yml` with all version pinning
2. ✅ Generates `.env` with secrets from variables.tf
3. ✅ Generates `Caddyfile` for routing
4. ✅ Generates `scripts/deploy.sh` (orchestration script)
5. ✅ Creates workspace directory if needed

**Result:**
```
Apply complete! Resources created: 5
docker-compose.yml updated with pinned versions
.env generated (add to .gitignore)
```

### Step 6: Deploy Containers (Idempotent)

**Option A: Automated deployment (recommended)**
```bash
bash scripts/deploy.sh
```

**What this does:**
1. Runs `terraform apply` again (regenerates artifacts)
2. Rebuilds Docker images: `docker compose build --no-cache`
3. Brings up services: `docker compose up -d`
4. Waits for healthchecks to pass
5. Validates critical paths (HTTP, extensions, OAuth)

**Option B: Manual orchestration**
```bash
# Step by step
terraform apply                                  # Regenerate artifacts
docker compose build --no-cache code-server    # Build image with pinned versions
docker compose up -d                            # Start services
docker compose ps                               # Verify all running
```

### Step 7: Verify Deployment

```bash
# Check all services are healthy
docker compose ps
# Expected: all running, health checks "healthy"

# Check code-server logs
docker compose logs code-server

# Test HTTP endpoint
curl -s http://localhost:8080/healthz

# Verify navigator shim patch is applied
docker exec code-server grep -c "navigator is now a global" \
  /usr/lib/code-server/lib/vscode/out/vs/workbench/api/node/extensionHostProcess.js
# Expected: 0 (shim removed)
```

---

## Making Changes (Immutability)

### To Update Versions

**Example: Upgrade Copilot Chat to new version**

1. **Edit variables.tf** or create terraform.tfvars override:
   ```hcl
   # Add to terraform.tfvars
   copilot_chat_version = "0.44.0"  # NEW VERSION
   ```

2. **Re-apply Terraform:**
   ```bash
   terraform plan      # Review version change
   terraform apply     # Regenerates docker-compose.yml
   ```

3. **Rebuild and redeploy:**
   ```bash
   bash scripts/deploy.sh
   ```

**Result:**
- New version is pinned in docker-compose.yml
- Image is rebuilt from scratch (--no-cache)
- Old containers replaced atomically
- No downtime (rolling update via compose)

### To Update Configuration

**Example: Increase code-server memory to 8GB**

1. **Update variables.tfvars:**
   ```hcl
   code_server_memory_limit = "8g"
   ```

2. **Re-apply:**
   ```bash
   terraform apply
   docker compose up -d  # Rolling restart
   ```

**Changes propagate through:**
```
terraform.tfvars → main.tf → docker-compose.yml → docker compose up
```

### To Add New Extensions

**Option 1: Build time (recommended for immutable images)**

Edit `Dockerfile.code-server`:
```dockerfile
# Add to entrypoint.sh
docker exec code-server code-server --install-extension owner.extension-name
```

Then rebuild:
```bash
docker compose build --no-cache code-server
docker compose up -d
```

**Option 2: Runtime (for testing only)**

```bash
docker exec code-server code-server --install-extension owner.extension-name
```

⚠️ **Note:** Runtime additions don't survive container restarts. Always add to Dockerfile for persistence.

---

## State Management

### Terraform State

Stored locally in `terraform.tfstate` (by default):
```bash
ls -la terraform.tfstate*
# terraform.tfstate          — Current state
# terraform.tfstate.backup   — Previous state
```

**To move to remote backend (Google Cloud Storage):**

```hcl
# main.tf: Add cloud block
terraform {
  cloud {
    organization = "your-org"
    workspaces {
      name = "code-server-production"
    }
  }
}
```

Then:
```bash
terraform login  # Authenticate to Terraform Cloud
terraform init   # Migrate state to cloud
```

### Secrets Management

**Never commit secrets to Git:**

1. **Use terraform.tfvars (local, gitignored):**
   ```bash
   # .gitignore already excludes:
   terraform.tfvars
   .env
   .env.local
   ```

2. **Or use environment variables:**
   ```bash
   export TF_VAR_google_client_secret="..."
   terraform apply  # Reads from env automatically
   ```

3. **Or fetch from Google Secret Manager:**
   ```bash
   bash scripts/fetch-gsm-secrets.sh
   # Populates terraform.tfvars with secrets from GSM
   ```

---

## Troubleshooting Idempotency

### If `terraform apply` fails

**Problem:** "Error acquiring the lock..."
```
Error: Failed to acquire lock on resource
```

**Solution:**
```bash
rm terraform.tfstate.lock.hcl  # Remove stale lock
terraform apply                 # Retry
```

**Problem:** "docker: command not found"
```
Error: exec: "docker": executable file not found
```

**Solution:**
```bash
# Set Docker context
export DOCKER_CONTEXT='desktop-linux'  # Or 'default' on Linux
terraform apply
```

### If `docker compose build` fails

**Problem:** "Failed to download extension..."
```
FATAL: Failed to download github.copilot v1.388.0
```

**Solution:**
- Extension version no longer available on marketplace
- Update `variables.tf` with new version number
- Run `terraform apply && docker compose build --no-cache`

**Problem:** "Navigator shim patch did not apply"
```
FATAL: navigator shim patch did not apply
```

**Solution:**
- VS Code version changed its internal structure
- Update Dockerfile.code-server regex pattern
- Run `docker compose build --no-cache`

### If deployment is stuck

**Problem:** Services not starting after 5 minutes

**Check logs:**
```bash
docker compose logs --tail=50 code-server
docker compose logs --tail=50 oauth2-proxy
docker compose logs --tail=50 caddy
```

**Hard reset (destructive):**
```bash
# Stop and remove ALL containers/volumes
docker compose down --remove-orphans --volumes

# Full rebuild from scratch
terraform apply
docker compose build --no-cache
docker compose up -d
```

---

## Verification Checklist

### Health Checks
```bash
# Code-server HTTP endpoint
curl -s http://localhost:8080/healthz

# OAuth2-proxy auth endpoint
curl -s http://localhost:4180/ping

# All services running
docker compose ps
# Expected: all "Up" and "healthy"
```

### Extension Validation
```bash
# Check extensions installed
docker exec code-server /usr/bin/code-server --list-extensions --extensions-dir \
  /home/coder/.local/share/code-server/extensions

# Expected output:
# github.copilot
# github.copilot-chat
```

### Immutability Verification
```bash
# Check navigator shim is patched
docker exec code-server grep -c "navigator is now a global" \
  /usr/lib/code-server/lib/vscode/out/vs/workbench/api/node/extensionHostProcess.js
# Expected: 0 (no matches = shim removed)

# Check product.json is patched
docker exec code-server grep -c '"github.copilot-chat"' \
  /usr/lib/code-server/lib/vscode/product.json
# Expected: >= 1 (extension in trustedExtensionAuthAccess)
```

---

## Complete Example Workflow

### Fresh Deployment to Production

```bash
# 1. Initialize
terraform init

# 2. Configure secrets
set -a
source <(scripts/fetch-gsm-secrets.sh)  # From Google Secret Manager
set +a

# 3. Plan and review
terraform plan -out=tfplan

# 4. Apply infrastructure
terraform apply tfplan

# 5. Automated deployment
bash scripts/deploy.sh

# 6. Verify
docker compose ps
curl -s http://localhost:8080/healthz
echo "✅ Deployment complete. Access via: https://ide.kushnir.cloud"
```

### Update to New Copilot Version

```bash
# 1. Update version in terraform.tfvars
echo 'copilot_chat_version = "0.44.0"' >> terraform.tfvars

# 2. Re-apply infrastructure
terraform apply

# 3. Rebuild and deploy
bash scripts/deploy.sh

# 4. Verify new version installed
docker compose logs code-server | grep "copilot-chat"
```

### Disaster Recovery (Full Reset)

```bash
# 1. Destroy all containers and volumes
docker compose down --remove-orphans --volumes

# 2. Destroy Terraform state (BE CAREFUL)
terraform destroy

# 3. Rebuild from scratch
terraform apply
bash scripts/deploy.sh

# Result: Identical deployment as before (immutability!)
```

---

## Key Files & Their Roles

| File | Role | Generated? | Commit to Git? |
|------|------|----------|---|
| `main.tf` | IaC orchestrator | ❌ Manual | ✅ Yes |
| `variables.tf` | Variable definitions | ❌ Manual | ✅ Yes |
| `terraform.tfvars` | Secret values | ✅ Generated | ❌ **NO** (.gitignore) |
| `docker-compose.tpl` | Compose template | ❌ Manual | ✅ Yes |
| `docker-compose.yml` | Generated compose | ✅ Generated | ❌ **NO** (regenerated by Terraform) |
| `Dockerfile.code-server` | Image build spec | ❌ Manual | ✅ Yes |
| `.env` | Generated secrets | ✅ Generated | ❌ **NO** (.gitignore) |
| `Caddyfile` | Generated routes | ✅ Generated | ❌ **NO** (in config/) |
| `scripts/deploy.sh` | Generated orchestration | ✅ Generated | ❌ **NO** (regenerated) |

---

## Design Principles Explained

### Why Terraform is Master Orchestrator?
- **Single source of truth**: All versions, secrets, and config in one place
- **Auditability**: `terraform plan` shows exact changes before applying
- **Reproducibility**: `terraform apply` creates identical state every time
- **Version control**: Git tracks all infrastructure decisions

### Why docker-compose.yml is Generated?
- Prevents manual edits that break reproducibility
- Ensures versions are always pinned (immutable)
- Terraform can validate before generating (safety checks)
- Changes propagate automatically through IaC

### Why docker-compose, Not Kubernetes?
- Simpler for single-host deployments
- Terraform can still orchestrate it (docker-compose is just configuration)
- Same immutability + idempotency principles apply
- Can migrate to K8s later by regenerating manifests from Terraform

### Why Dockerfile Patches, Not Base Image?
- Patches are versioned with code (Dockerfile in Git)
- Changes (navigator shim) are explicit and auditable
- Can verify patches applied: `grep -c "navigator..." extensionHostProcess.js`
- Rebuilding image validates patches still work

---

## Support & Debugging

### Check Deployment Logs
```bash
terraform apply 2>&1 | tee deployment.log
docker compose logs --tail=100 code-server 2>&1 | tee code-server.log
```

### Validate Terraform Syntax
```bash
terraform validate
terraform fmt -check .  # Check formatting (run without -check to auto-fix)
```

### State Inspection
```bash
terraform state list
terraform state show local_file.docker_compose_yml
terraform output deployment_summary
```

### Manual Cleanup (if deployment breaks)
```bash
# List all containers/volumes
docker compose ps -a
docker volume ls | grep "code-server\|ollama\|caddy"

# Remove specific resources
docker compose rm -f code-server
docker volume rm code-server-enterprise-data

# Rebuild
docker compose build --no-cache
docker compose up -d
```

---

## Next Steps

1. **Set up Production Monitoring**: Add prometheus + alerting to `docker-compose.yml`
2. **Enable Remote State**: Move `terraform.tfstate` to Google Cloud Storage or Terraform Cloud
3. **Automate Updates**: Add GitHub Actions workflow to `git push` → `terraform apply` → deploy
4. **Disaster Recovery**: Document backup strategy for code-server workspace volume
5. **Cost Optimization**: Add GCP cost monitoring to Terraform outputs

---

**Questions?** Refer to `CONTRIBUTION.md` or open an issue with deployment tag.

---

**Last Updated:** April 2026  
**Terraform Version:** >= 1.0  
**Status:** ✅ IaC | ✅ Immutable | ✅ Idempotent
