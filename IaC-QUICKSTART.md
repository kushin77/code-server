# Infrastructure-as-Code Quick Start

## What Changed

The entire deployment is now **IaC (Infrastructure as Code)**, **Immutable**, and **Idempotent**.

### Before (❌ Manual & Fragile)
- Docker-compose.yml was hand-edited with latest extension versions
- Terraform only rendered a Caddyfile
- Re-running deployment could pull different extension versions
- Manual steps to install extensions at runtime
- No clear versioning or reproducibility

### After (✅ Enterprise Grade)
- **Terraform** is the single source of truth for ALL infrastructure
- **docker-compose.yml** is *generated* from Terraform (never hand-edited)
- **All versions pinned** at build time (code-server, copilot, copilot-chat, ollama, caddy, oauth2-proxy)
- **Immutable images**: Rebuild from scratch on each deployment; old containers replaced atomically
- **Idempotent**: Safe to run `terraform apply && bash scripts/deploy.sh` repeatedly; result is identical

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              TERRAFORM (Single Source of Truth)         │
│  ✓ main.tf         (orchestrator, 300+ lines)           │
│  ✓ variables.tf    (all configuration)                  │
│  ✓ terraform.tfvars (secrets, DO NOT COMMIT)            │
└────────────┬────────────────────────────────────────────┘
             │
             ├─→ Generates: docker-compose.yml (with pinned versions)
             ├─→ Generates: .env (secrets from variables)
             ├─→ Generates: Caddyfile (routing config)
             └─→ Generates: scripts/deploy.sh (orchestration)
                     │
                     ↓
         ┌───────────────────────────┐
         │  DOCKER COMPOSE (Execution)
         │  ✓ code-server:4.115.0    │  ← Navigator shim patch baked in
         │  ✓ copilot:1.388.0        │  ← Version pinned at build
         │  ✓ copilot-chat:0.43.xxx  │  ← Downloaded at build time
         │  ✓ oauth2-proxy:v7.5.1    │  ← Immutable
         │  ✓ caddy:2.7.6            │  ← Immutable
         │  ✓ ollama:0.1.27          │  ← Immutable
         └───────────────────────────┘
```

---

## Files & Their Roles

| File | Purpose | Manual? | In Git? |
|------|---------|---------|---------|
| `main.tf` | IaC orchestrator (300+ lines) | ✏️ Edit | ✅ YES |
| `variables.tf` | Configuration schema | ✏️ Edit | ✅ YES |
| `terraform.tfvars` | Secret values | ✏️ Edit locally | ❌ NO (.gitignore) |
| `Dockerfile.code-server` | Image with navigator patch & version args | ✏️ Edit | ✅ YES |
| `docker-compose.tpl` | Compose template | ✏️ Edit | ✅ YES |
| `docker-compose.yml` | **GENERATED** by Terraform | 🚫 Never | ❌ NO |
| `.env` | **GENERATED** secrets | 🚫 Never | ❌ NO |
| `Caddyfile` | **GENERATED** routing | 🚫 Never | ❌ NO |
| `scripts/deploy.sh` | **GENERATED** orchestrator | 🚫 Never | ❌ NO |

---

## Deployment Workflow

### 1. Copy Configuration Template
```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Fill in Secrets (DO NOT COMMIT)
Edit `terraform.tfvars`:
```hcl
# Required: Google OAuth2 credentials
google_client_id     = "xxx.apps.googleusercontent.com"
google_client_secret = "your-secret"
oauth2_proxy_cookie_secret = "$(openssl rand -base64 32)"
domain = "ide.kushnir.cloud"
```

### 3. Initialize Terraform (One Time)
```bash
terraform init
# Output: Successfully configured!
```

### 4. Plan Changes (Review Before Applying)
```bash
terraform plan -out=tfplan
# Shows: 6 resources will be created (docker-compose.yml, .env, etc.)
```

### 5. Apply Infrastructure (Generates Artifacts)
```bash
terraform apply tfplan
# Output: ✅ docker-compose.yml generated with pinned versions
#         ✅ .env generated with secrets
#         ✅ scripts/deploy.sh generated
```

### 6. Deploy Containers (Immutable Build)
```bash
bash scripts/deploy.sh
```

**What this does:**
1. `terraform apply` → regenerates docker-compose.yml with versions
2. `docker compose build --no-cache` → full rebuild from scratch (immutability guarantee)
3. `docker compose up -d` → start services
4. Verifies all healthchecks pass
5. Validates critical paths (HTTP, extensions, OAuth)

---

## Key Guarantees

### ✅ IaC (Infrastructure as Code)
- Everything defined in Terraform (`main.tf`, `variables.tf`)
- No manual steps in production
- All changes tracked in Git (except secrets)
- Auditable: `git log --oneline` shows all infrastructure changes

### ✅ Immutable
- All versions pinned: `code_server_version`, `copilot_version`, `copilot_chat_version`, etc.
- Images built at deployment time with `--no-cache` (forces full rebuild)
- Extensions downloaded at build time, baked into image
- Never modify running containers (always rebuild and replace)

### ✅ Idempotent
- Safe to run `terraform apply` multiple times → same result
- Safe to run `docker compose build --no-cache && docker compose up -d` repeatedly → identical state
- No side effects from re-running deployment commands
- Secrets are idempotent: re-applying terraform regenerates `.env` from `terraform.tfvars`

---

## Making Changes

### Update Copilot Version
```hcl
# Edit terraform.tfvars
copilot_chat_version = "0.44.0"  # ← NEW
```

Then:
```bash
terraform apply
docker compose build --no-cache
docker compose up -d
```

**Result:**
- docker-compose.yml regenerated with new version
- Image rebuilt from scratch
- Extension downloaded from marketplace at build time
- New version deployed atomically
- Old containers gone; no downtime during update

### Increase Code-Server Memory
```hcl
# Edit terraform.tfvars
code_server_memory_limit = "8g"
```

Then:
```bash
terraform apply
docker compose up -d  # Rolling restart
```

---

## Validation Commands

```bash
# Check Terraform syntax
terraform validate
# Output: Success! The configuration is valid.

# Show what would be created
terraform plan
# Output: Plan: 6 to add, 0 to change, 0 to destroy

# Show generated artifacts
cat docker-compose.yml | grep -E "image:|COPILOT|VERSION"

# Verify versions are pinned in image
docker exec code-server grep "COPILOT_VERSION\|CODE_SERVER_VERSION" /opt/vsix/*
```

---

## State & Secrets

### Terraform State
```bash
ls -la terraform.tfstate*
# Stores: which resources were created, versions, etc.
# Keep safe; regenerate with `terraform destroy && terraform apply` if lost
```

### Secrets Management
**Never commit `terraform.tfvars` to Git:**
```bash
# .gitignore already includes:
terraform.tfvars
.env
.terraform
```

**Option 1: Use environment variables**
```bash
export TF_VAR_google_client_id="..."
export TF_VAR_google_client_secret="..."
terraform apply  # Reads from env
```

**Option 2: Use Google Secret Manager**
```bash
bash scripts/fetch-gsm-secrets.sh
# Populates terraform.tfvars from GSM
```

---

## Disaster Recovery

**Full reset (destructive):**
```bash
# Remove all containers and volumes
docker compose down --remove-orphans --volumes

# Destroy Terraform-managed resources
terraform destroy

# Rebuild from scratch (identical to before due to immutability)
terraform apply
bash scripts/deploy.sh

# Result: Identical state (same versions, same config)
```

---

## Monitoring & Debugging

```bash
# Check all services
docker compose ps

# View logs
docker compose logs -f code-server

# Check versions baked into image
docker exec code-server code-server --list-extensions

# Verify navigator patch
docker exec code-server grep -c "navigator is now a global" \
  /usr/lib/code-server/lib/vscode/out/vs/workbench/api/node/extensionHostProcess.js
# Expected: 0 (patch applied)

# Terraform state
terraform state list
terraform output deployment_summary
```

---

## Production Checklist

- [ ] `terraform init` successful
- [ ] `terraform.tfvars` populated with secrets (not in Git)
- [ ] `terraform plan` shows 6 resources to create
- [ ] `terraform apply` successful
- [ ] `bash scripts/deploy.sh` completes with all health checks passing
- [ ] `docker compose ps` shows all services running/healthy
- [ ] Copilot Chat extension installed: `docker exec code-server code-server --list-extensions | grep copilot`
- [ ] Navigator patch applied: grep returns 0
- [ ] HTTP health check passes: `curl -s http://localhost:8080/healthz`
- [ ] VPN tests pass: See [COPILOT_CHAT_VPN_TESTING_GUIDE.md](COPILOT_CHAT_VPN_TESTING_GUIDE.md)

---

## Next Steps

1. **Fill in secrets**: Edit `terraform.tfvars` with Google OAuth credentials
2. **Initialize**: Run `terraform init`
3. **Plan**: Run `terraform plan` to review changes
4. **Deploy**: Run `terraform apply && bash scripts/deploy.sh`
5. **Test**: Follow [IaC-DEPLOYMENT.md](IaC-DEPLOYMENT.md) for complete validation

---

**Status: ✅ IaC | ✅ Immutable | ✅ Idempotent**

See [IaC-DEPLOYMENT.md](IaC-DEPLOYMENT.md) for detailed workflows and troubleshooting.
