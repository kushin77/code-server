# Production Deployment Runbook — April 25, 2026

**Status:** Ready for Production Deployment  
**Date:** April 25, 2026  
**Branch:** feat/testing-observability-dns-2026-04-25 (merged to main locally)  
**IaC Compliance:** ✅ All code immutable, idempotent, environment-driven  

---

## 🚀 Quick Start

### Prerequisites
- Repository: https://github.com/kushin77/code-server.git
- Primary host: 192.168.168.31 (admin user)
- Network connectivity: SSH access required
- Disk space: 100GB+ free
- Docker: v20.10+
- Git: v2.30+

### Environment Variables (All Deployment Scripts)

All deployment automation uses environment variables. No hardcoding.

```bash
# Primary deployment
export DEPLOY_HOST="192.168.168.31"
export DEPLOY_USER="admin"
export DEPLOY_BRANCH="main"
export GIT_REPO_URL="https://github.com/kushin77/code-server.git"

# Ollama external deployment
export OLLAMA_HOST="192.168.168.31"
export OLLAMA_USER="admin"
export OLLAMA_PORT="11434"
export OLLAMA_REPO="https://github.com/kushin77/ollama.git"

# Health check configuration
export HEALTH_CHECK_RETRIES="30"
export HEALTH_CHECK_INTERVAL="10"
```

---

## 📋 Deployment Steps

### Step 1: Merge PR to Main

**Current Status:** Code is locally merged but blocked by GitHub branch protection.

**Action Required:** Repository owner (kushin77) must:
1. Go to: https://github.com/kushin77/code-server/compare/main...feat/testing-observability-dns-2026-04-25
2. Click **Create Pull Request**
3. Wait for 7 GitHub Actions status checks to pass
4. Merge PR to main

**Why:** Branch protection ensures all 7 CI checks pass before merge:
- unit-tests.yml (bats + pytest)
- stress-tests.yml (k6 load testing)
- governance-checks.yml (IaC compliance, DNS validation)

---

### Step 2: Deploy Main Stack

Deploy the primary code-server-enterprise services to 192.168.168.31.

**Command:**
```bash
bash scripts/ops/deploy-production.sh
```

**What It Does:**
1. ✅ Verifies prerequisites (SSH, Git, Docker available)
2. ✅ Pulls latest code from main branch
3. ✅ Runs IaC compliance validation on target
4. ✅ Starts services with docker-compose
5. ✅ Runs health checks (30 retries, 10s interval)
6. ✅ Rolls back automatically if any step fails

**Expected Output:**
```
[INFO] === Code-Server-Enterprise Production Deployment ===
[INFO] Target: admin@192.168.168.31
[INFO] Branch: main
[INFO] Repository: https://github.com/kushin77/code-server.git
[INFO] ✓ SSH connectivity verified
[INFO] ✓ Git available on target
[INFO] ✓ Docker available on target
[INFO] ✓ Code deployed successfully
[INFO] ✓ IaC compliance verified on target
[INFO] ✓ Services started
[INFO] ✓ Health check passed on attempt 5
[INFO] === Deployment Complete ===
[INFO] Services running at http://192.168.168.31:3100
[INFO] All IaC compliance checks passed
```

**Configuration:**
```bash
# All env-var driven (override as needed)
export DEPLOY_HOST="192.168.168.31"
export DEPLOY_USER="admin"
export DEPLOY_BRANCH="main"
export HEALTH_CHECK_RETRIES="30"
export HEALTH_CHECK_INTERVAL="10"
```

---

### Step 3: Deploy External Ollama Stack

Deploy Ollama LLM services to separate location (can be same host).

**Command:**
```bash
bash scripts/ops/deploy-ollama-external.sh
```

**What It Does:**
1. ✅ Verifies Ollama host connectivity
2. ✅ Clones/updates kushin77/ollama repository
3. ✅ Starts Ollama services with docker-compose
4. ✅ Runs health checks on Ollama API
5. ✅ Verifies deployment connectivity

**Expected Output:**
```
[OLLAMA] === External Ollama Deployment (IaC Compliant) ===
[OLLAMA] Target: admin@192.168.168.31:11434
[OLLAMA] Repository: https://github.com/kushin77/ollama.git
[OLLAMA] Branch: main
[OLLAMA] ✓ Ollama host connectivity verified
[OLLAMA] ✓ Docker available
[OLLAMA] ✓ Ollama repository deployed
[OLLAMA] ✓ Ollama services started
[OLLAMA] ✓ Ollama health check passed on attempt 3
[OLLAMA] ✓ Deployment connectivity verified
[OLLAMA] === External Ollama Deployment Complete ===
[OLLAMA] Ollama API: http://192.168.168.31:11434
[OLLAMA] Configure main deployment with: OLLAMA_HOST=http://192.168.168.31:11434
```

**Configuration:**
```bash
export OLLAMA_HOST="192.168.168.31"
export OLLAMA_USER="admin"
export OLLAMA_PORT="11434"
export OLLAMA_REPO="https://github.com/kushin77/ollama.git"
```

---

### Step 4: Post-Deployment Validation

Validate that deployed infrastructure meets IaC standards.

**Command:**
```bash
bash scripts/ops/validate-post-deployment.sh
```

**What It Checks:**
1. ✅ IaC compliance script present and passing
2. ✅ Environment variables used (no hardcoding)
3. ✅ Error handling in scripts (set -euo pipefail)
4. ✅ Governance headers documented
5. ✅ Docker Compose configuration valid
6. ✅ Services running and healthy
7. ✅ Health endpoints responding

**Expected Output:**
```
=== IaC Compliance Script Validation ===
[VALIDATE] Validating...
[✓ PASS] IaC compliance script validation

=== Environment Variable Usage (No Hardcoding) ===
[VALIDATE] Validating...
[✓ PASS] Environment variable usage validation

=== Error Handling (set -euo pipefail) ===
[VALIDATE] Validating...
[✓ PASS] Error handling validation

... (5 more validation checks) ...

[VALIDATE] === Validation Summary ===
[✓ PASS] Post-deployment IaC validation complete

[INFO] Passed: 7/7 validations
```

---

## 🔄 Complete Deployment Sequence

For automated end-to-end deployment:

```bash
#!/bin/bash
set -euo pipefail

# 1. Deploy main stack
echo "Deploying main stack..."
bash scripts/ops/deploy-production.sh

# Wait for services to stabilize
echo "Waiting for services to stabilize..."
sleep 60

# 2. Deploy external Ollama
echo "Deploying Ollama..."
bash scripts/ops/deploy-ollama-external.sh

# 3. Validate deployment
echo "Validating post-deployment..."
bash scripts/ops/validate-post-deployment.sh

echo "✅ Complete deployment successful!"
```

---

## ⚙️ Configuration Reference

### Main Deployment (deploy-production.sh)

| Variable | Default | Purpose |
|----------|---------|---------|
| `DEPLOY_HOST` | 192.168.168.31 | Target host IP |
| `DEPLOY_USER` | admin | SSH user |
| `DEPLOY_BRANCH` | main | Git branch to deploy |
| `GIT_REPO_URL` | https://github.com/kushin77/code-server.git | Repository URL |
| `DEPLOY_TIMEOUT_SECONDS` | 600 | Deployment timeout |
| `HEALTH_CHECK_RETRIES` | 30 | Health check attempts |
| `HEALTH_CHECK_INTERVAL` | 10 | Health check interval (seconds) |

### Ollama External Deployment (deploy-ollama-external.sh)

| Variable | Default | Purpose |
|----------|---------|---------|
| `OLLAMA_HOST` | 192.168.168.31 | Ollama host IP |
| `OLLAMA_USER` | admin | SSH user |
| `OLLAMA_PORT` | 11434 | Ollama API port |
| `OLLAMA_REPO` | https://github.com/kushin77/ollama.git | Ollama repo |
| `OLLAMA_BRANCH` | main | Git branch |
| `HEALTH_CHECK_RETRIES` | 20 | Health check attempts |
| `HEALTH_CHECK_INTERVAL` | 15 | Health check interval (seconds) |

---

## 🛠️ Troubleshooting

### Deployment Fails: SSH Connection Error

**Error:**
```
ERROR: Cannot connect to 192.168.168.31
```

**Solution:**
```bash
# Verify SSH connectivity
ssh -v admin@192.168.168.31 "echo 'SSH OK'"

# Verify host is up
ping 192.168.168.31

# Check SSH key permissions
chmod 600 ~/.ssh/id_rsa
```

### Deployment Fails: Git Repository Not Found

**Error:**
```
ERROR: Code deployment failed
```

**Solution:**
```bash
# Verify git repository is accessible
git ls-remote https://github.com/kushin77/code-server.git main

# Check network connectivity
curl -I https://github.com
```

### Health Check Fails

**Error:**
```
ERROR: Health check failed after 30 attempts
```

**Solution:**
```bash
# SSH to target and check service logs
ssh admin@192.168.168.31 "docker compose logs --tail 100"

# Check if services are running
ssh admin@192.168.168.31 "docker compose ps"

# Restart services
ssh admin@192.168.168.31 "cd /root/code-server-enterprise && docker compose restart"
```

### IaC Compliance Fails

**Error:**
```
ERROR: IaC compliance validation failed on target
```

**Solution:**
```bash
# SSH to target and run validation directly
ssh admin@192.168.168.31 "cd /root/code-server-enterprise && bash scripts/ci/validate-iac-compliance.sh"

# Review compliance violations
ssh admin@192.168.168.31 "bash scripts/ci/validate-iac-compliance.sh 2>&1 | head -50"
```

---

## 📊 Verification Checklist

After deployment completes:

- [ ] Main deployment health check passed
- [ ] Ollama deployment health check passed
- [ ] Post-deployment validation shows 7/7 checks passing
- [ ] Can access http://192.168.168.31:3100
- [ ] Can access http://192.168.168.31:11434/api/tags
- [ ] Docker Compose logs show no errors
- [ ] All services in "Up" state

**Verify:**
```bash
# SSH to target
ssh admin@192.168.168.31

# Check services
docker compose ps -a

# Check main API
curl http://localhost:3100/api/health

# Check Ollama
curl http://localhost:11434/api/tags

# Check logs
docker compose logs --tail 50
```

---

## 🔐 IaC Compliance Standards

All deployment scripts enforce Infrastructure as Code (IaC) principles:

### ✅ Immutability
- All code version-controlled (git)
- No dynamic values in source
- All scripts tracked in repository

### ✅ Idempotency
- Safe to run multiple times
- No hardcoded timestamps
- Deterministic execution
- Reproducible deployments

### ✅ Environment-Driven
- All config via environment variables
- No hardcoded IPs or ports
- Default values for all parameters
- Easy to override per environment

### ✅ Fault-Safe
- All scripts use `set -euo pipefail`
- Error handling on all commands
- Automatic rollback on failure
- Clear error messages

### ✅ Documented
- All scripts have @governance headers
- Inline comments for complex logic
- Parameter documentation
- Usage examples in README

---

## 📞 Support

For issues or questions:

1. Review deployment logs: `docker compose logs`
2. Check IaC compliance: `bash scripts/ci/validate-iac-compliance.sh`
3. Run validation: `bash scripts/ops/validate-post-deployment.sh`
4. Review repository: https://github.com/kushin77/code-server
5. Check branch: feat/testing-observability-dns-2026-04-25

---

**Runbook Status:** ✅ Production Ready  
**Last Updated:** April 25, 2026  
**Maintainer:** Autonomous Agent  
