# Post-PR#79 Merge Deployment Checklist

This checklist covers the complete deployment workflow after PR#79 (Dual-Auth + IaC Refactor) merges to main.

## Pre-Deployment Verification

### Code Quality ✓
- [ ] PR #79 has 2 approvals (code review complete)
- [ ] All 6 CI checks pass (validate, snyk, gitleaks, checkov, tfsec, run validation)
- [ ] No merge conflicts
- [ ] Working tree clean (`git status` returns nothing)

### Infrastructure Readiness ✓
- [ ] Terraform configuration validated: `terraform validate` PASS
- [ ] Terraform plan generated: `terraform plan` shows expected changes
- [ ] Docker Desktop running (if local deployment)
- [ ] Sufficient disk space (50GB+ for Docker images + LLM models)

### Secrets Management ✓
- [ ] Google OAuth2 credentials obtained (GCP Console)
- [ ] GitHub Personal Access Token generated (read:user, user:email scopes)
- [ ] oauth2-proxy cookie secret generated: `openssl rand -base64 32`
- [ ] All secrets stored in Google Secret Manager or .env (not in git)

## Deployment Workflow

### Phase 1: Merge to Main

```bash
# Switch to main branch (from fix/copilot-auth-and-user-management)
git checkout main
git pull origin main

# Merge PR #79 via GitHub UI or CLI
# (PR #79 status: all checks passing + 2 approvals)
git merge fix/copilot-auth-and-user-management
git push origin main

# Tag release (optional but recommended)
git tag v2.0-enterprise
git push origin v2.0-enterprise
```

### Phase 2: Terraform Infrastructure Setup

```bash
# Navigate to project root
cd c:\code-server-enterprise

# Verify Terraform version
terraform version  # Expect: >= 1.0

# Initialize Terraform state management
terraform init
# Output: "Terraform has been successfully configured!"

# Plan infrastructure changes
terraform plan -out=tfplan
# Review output:
#   - local_file.docker_compose_yml will be created
#   - local_file.env_file will be created
#   - local_file.deploy_script will be created
#   - local_file.caddyfile will be created

# Apply infrastructure configuration
terraform apply tfplan
# Output: "Apply complete! Resources: X added, 0 changed, 0 destroyed."

# Verify generated files
ls -la docker-compose.yml .env scripts/deploy.sh Caddyfile
```

### Phase 3: Docker Image Build

```bash
# Set Docker context (if on Docker Desktop for Mac/Windows)
export DOCKER_CONTEXT=desktop-linux  # macOS/Windows
# or leave unset for Linux

# Build all images with pinned versions (--no-cache for clean build)
docker compose build --no-cache

# Expected output:
#   ✓ code-server:4.115.0 with Copilot VSIX versions pinned
#   ✓ caddy:2.7.6 with rate-limit module
#   ✓ oauth2-proxy:v7.5.1 with Google OAuth2 config
#   ✓ ollama:0.1.27 with model support
```

### Phase 4: Service Deployment

```bash
# Start all services (containers defined in docker-compose.yml)
docker compose up -d

# Verify service health
docker compose ps
# Expected output:
#   ✓ code-server   running (port 8080)
#   ✓ caddy        running (port 80, 443)
#   ✓ oauth2-proxy running (port 4180)
#   ✓ ollama       running (port 11434)

# Check internal health endpoints (from within docker network)
docker compose exec caddy curl -s http://code-server:8080/health | jq .        # code-server
docker compose exec ollama curl -s http://localhost:11434/api/tags | jq .      # ollama

# Or access via domain (external)
curl -H "Authorization: Bearer $GITHUB_TOKEN" https://ide.kushnir.cloud/health
```

### Phase 5: Configuration Verification

```bash
# Verify Copilot Chat auth configuration
docker compose exec code-server bash -c \
  'grep -A 5 "trustedExtensionAuthAccess" /usr/lib/code-server/lib/vscode/product.json'
# Expected: Both github.copilot AND github.copilot-chat in the array

# Verify OAuth2 proxy is protecting /
docker compose logs oauth2-proxy | grep -i "listening\|signin"

# Verify Ollama models available
docker compose exec ollama ollama list
# Or via HTTP:
curl http://localhost:11434/api/tags
```

### Phase 6: Access Verification

```bash
# For production deployment:
# 1. Open browser: https://ide.kushnir.cloud
# 2. Redirected to Google login (oauth2-proxy)
# 3. Sign in with Google account
# 4. Redirected back to code-server IDE
# 5. Inside IDE: Copilot Chat should be available
#    - Extensions sidebar → search "copilot" → both should be installed
#    - Click Copilot Chat icon in Activity Bar (left side)
#    - Should NOT get "Sign in" prompt if GITHUB_TOKEN set in .env

# If Copilot Chat prompts for sign-in:
# - Visit https://ide.kushnir.cloud/reset-browser-state (clears cached denial)
# - Reload IDE
# - Copilot Chat should use cached GitHub token from .env
```

## Post-Deployment Testing

### Core Functionality Tests

#### 1. Dual-Auth System
- [ ] Google login works and redirects to IDE
- [ ] IDE loads after Google authentication
- [ ] Code-server dashboard accessible
- [ ] Logout and re-login works

#### 2. Copilot Chat
- [ ] Copilot extension installed and activated
- [ ] Copilot Chat extension installed and activated
- [ ] Chat panel opens from Activity Bar
- [ ] Chat requests get responses (no auth errors)
- [ ] `/explain` commands work
- [ ] Code completion suggestions appear

#### 3. Ollama Integration
- [ ] Ollama service running: `docker compose ps ollama`
- [ ] Models installed: `docker compose exec ollama curl -s http://localhost:11434/api/tags`
- [ ] Can invoke model: `docker compose exec ollama curl -X POST http://localhost:11434/api/generate -d '{"model":"llama2","prompt":"hello"}'`

#### 4. Infrastructure
- [ ] All services healthy: `docker compose ps` shows all "running"
- [ ] No ERROR logs: `docker compose logs | grep -i error` returns nothing
- [ ] Rate limiting works: multiple rapid requests to /oauth2/sign_in get rate-limited
- [ ] Caddyfile routing correct:
  ```bash
  curl -I https://ide.kushnir.cloud/              # Redirects to /signin
  curl -I -H "Cookie: oauth2proxy_..." https://ide.kushnir.cloud/  # 200 OK to IDE
  ```

### Performance Baseline

```bash
# Record baseline metrics for future comparison
docker compose stats --no-stream

# Expected resources (with 4 CPU, 8GB RAM limit per service):
# - code-server:   ~2-3% CPU, 800MB-1.5GB RAM
# - ollama:        0-20% CPU (idle-40% when inferencing), 4-6GB RAM
# - caddy:         <1% CPU, 50-100MB RAM
# - oauth2-proxy:  <1% CPU, 50-100MB RAM
```

## Rollback Procedure

If critical issues occur post-deployment:

```bash
# Stop all services without removing volumes
docker compose down

# Revert code to previous version
git revert HEAD                    # Revert the merge commit
git push origin main

# Re-checkout pre-PR#79 state
git checkout v2.0-enterprise~1    # Tag for previous stable version

# Rebuild and redeploy
terraform init
terraform apply tfplan
docker compose up -d
```

## Monitoring After Deployment

### Daily Checks
- [ ] All services running: `docker compose ps`
- [ ] No error logs in last 24h: `docker compose logs --since 24h | grep ERROR`
- [ ] Disk space sufficient: `df -h | grep -E "/$|/usr"` (>30% free)
- [ ] Ollama models still available: `docker compose exec ollama ollama list`

### Weekly Checks
- [ ] Full system health: run test suite
- [ ] Security scan results (gitleaks, snyk)
- [ ] Backup status (if automated backups configured)
- [ ] Copilot rate limits not exceeded

### Monthly Checks
- [ ] Update LLM models to latest versions
- [ ] Apply security patches to base images
- [ ] Review and reconcile secrets in GSM
- [ ] Performance metrics: measure against baseline

## Support & Escalation

**Issue: "Sign in" prompt on Copilot Chat**
- Solution: Set `GITHUB_TOKEN` in `.env` with valid PAT (read:user, user:email scopes)
- Or: Clear browser state: `https://ide.kushnir.cloud/reset-browser-state`

**Issue: Slow Ollama responses**
- Check: `docker compose stats ollama` — ensure not memory-bound
- Solution: Allocate more GPU if available, or reduce model size

**Issue: OAuth2 login loop (Google)**
- Check: `docker compose logs oauth2-proxy | tail -20`
- Verify: Google OAuth credentials in .env match GCP Console setup
- Solution: Regenerate OAuth2 credentials in GCP Console

**Issue: terraform apply fails**
- Check: `terraform plan` for detailed error message
- Verify: All variables set in `terraform.tfvars`
- Solution: Re-run `terraform init` to reinitialize state

## Sign-Off

- [ ] Deployed by: _________________
- [ ] Date: _________________
- [ ] All tests passed: [ ] Yes [ ] No
- [ ] In contact with on-call: [ ] Yes [ ] No
- [ ] Rollback path tested: [ ] Yes [ ] No
- [ ] Handoff documented: [ ] Yes [ ] No
