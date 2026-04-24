# P0 Security Fixes Deployment Runbook

**Commits to Deploy**:
- b183388b: security(P0-968,P0-998) - Remove hardcoded secrets and fallbacks
- 52295d5f: security(P0-980) - Add secret scanning workflow and git-secrets setup
- 94c45ef5: docs(P0-security) - Complete security fixes implementation guide

**Affected Files**:
- .env.defaults (hardcoded secrets removed)
- docker-compose.yml (7 security hardening changes)
- .github/workflows/secret-scanning.yml (NEW - GitHub Actions workflow)
- scripts/setup/install-git-secrets.sh (NEW - Pre-commit hook setup)
- P0-SECURITY-FIXES-IMPLEMENTATION-COMPLETE.md (NEW - Documentation)

**Deployment Timeline**: 15 hours total (7.5h per replica)

---

## PRE-DEPLOYMENT VALIDATION (5 min)

### 1. Verify Git Changes
```bash
cd /mnt/c/code-server-enterprise  # Linux/WSL required
git log --oneline | head -5
# Expected:
# 94c45ef5 docs(P0-security): Complete security fixes implementation guide
# 52295d5f security(P0-980): Add secret scanning workflow and git-secrets setup
# b183388b security(P0-968,P0-998): Remove hardcoded secrets and fallbacks
# ce24b942 monitoring(P0-1635): NVMe hardware failure alert rules
# ...
```

### 2. Verify Files Exist
```bash
ls -la .env.defaults docker-compose.yml .github/workflows/secret-scanning.yml \
  scripts/setup/install-git-secrets.sh P0-SECURITY-FIXES-IMPLEMENTATION-COMPLETE.md
```

### 3. Syntax Validation
```bash
# Validate docker-compose
docker-compose config -q

# Validate YAML
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/secret-scanning.yml'))" && echo "✓ YAML valid"

# Check bash syntax
bash -n scripts/setup/install-git-secrets.sh
```

---

## REPLICA 2 DEPLOYMENT (Staging) - 7.5 hours

### Step 1: Environment Preparation (15 min)

**On Replica 2** (192.168.168.42) via SSH:
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42

# Set environment variables from GSM
export OAUTH2_PROXY_COOKIE_SECRET=$(gcloud secrets versions access latest --secret=oauth2-proxy-cookie-secret)
export POSTGRES_PASSWORD=$(gcloud secrets versions access latest --secret=postgres-password)
export POSTGRES_USER=postgres
export POSTGRES_DB=codeserver
export REDIS_PASSWORD=$(gcloud secrets versions access latest --secret=redis-password)
export SLACK_SIGNING_SECRET=$(gcloud secrets versions access latest --secret=slack-signing-secret)
export SLACK_BOT_TOKEN=$(gcloud secrets versions access latest --secret=slack-bot-token)
export REGISTRY_AUTH_TOKEN_SECRET=$(gcloud secrets versions access latest --secret=registry-auth-token-secret)

# Verify variables are set
env | grep -E "OAUTH2_PROXY_COOKIE_SECRET|POSTGRES_PASSWORD|REDIS_PASSWORD" | head -3
```

### Step 2: Code Update (5 min)
```bash
cd /home/akushnir/code-server-enterprise
git fetch origin main
git checkout main
git pull origin main
# Should see commits: 94c45ef5, 52295d5f, b183388b
```

### Step 3: Service Update (120 min)
```bash
# Pull latest images
docker-compose pull

# Bring up services with new environment variables
docker-compose up -d

# Monitor startup (watch for 5 min)
docker-compose logs -f
# Press Ctrl+C after initial startup complete

# Wait for all services to be ready (typically 2-3 min)
sleep 180
```

### Step 4: Health Check (30 min)
```bash
# Verify all services running
docker-compose ps | grep -E "Up|healthy"
# Expected: All 21 services should show "Up" status

# Verify no critical errors
docker-compose logs | grep -iE "error|critical|failed" | grep -v "ERR_" | tail -20

# Test specific security hardening changes
# 1. Non-root users
docker inspect ollama --format='{{.Config.User}}'      # Should be 1001:1001
docker inspect jaeger --format='{{.Config.User}}'      # Should be 10001:10001
docker inspect loki --format='{{.Config.User}}'        # Should be 10001:10001

# 2. Redis authentication
docker exec -it redis redis-cli ping
# Should return: (error) NOAUTH Authentication required

docker exec -it redis redis-cli -a "$REDIS_PASSWORD" ping
# Should return: PONG

# 3. Caddy capabilities
docker inspect caddy --format='{{.HostConfig.CapAdd}}'   # Should be [CAP_NET_BIND_SERVICE]
docker inspect caddy --format='{{.HostConfig.CapDrop}}'  # Should include ALL

# 4. Test application endpoints
curl -s http://localhost/api/health | jq .
curl -s https://ide.kushnir.cloud/api/health -k | jq .
```

### Step 5: Staging Validation (6.5 hours)
```bash
# Run smoke tests
bash scripts/ci/run-kushnir-cloud-appsmith-login-e2e.sh

# Monitor for 24-48 hours:
# - Check logs regularly: docker-compose logs -f
# - Monitor resource usage: docker stats
# - Verify no connection storms: docker logs postgres | grep "invalid startup packet"
```

---

## REPLICA 1 DEPLOYMENT (Production) - 7.5 hours

**Prerequisites**: Replica 2 staging validation complete & healthy

### Step 1: Environment Preparation (15 min)

**On Replica 1** (192.168.168.31) via SSH:
```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31

# Set environment variables from GSM (same as Replica 2)
export OAUTH2_PROXY_COOKIE_SECRET=$(gcloud secrets versions access latest --secret=oauth2-proxy-cookie-secret)
export POSTGRES_PASSWORD=$(gcloud secrets versions access latest --secret=postgres-password)
# ... (same 8 variables as Replica 2)

# Verify variables are set
env | grep -E "OAUTH2_PROXY_COOKIE_SECRET|POSTGRES_PASSWORD|REDIS_PASSWORD" | head -3
```

### Step 2: Code Update (5 min)
```bash
cd /home/akushnir/code-server-enterprise
git fetch origin main
git checkout main
git pull origin main
```

### Step 3: Service Update (120 min)
```bash
docker-compose pull
docker-compose up -d
sleep 180  # Wait for services to stabilize
```

### Step 4: Health Check (30 min)
```bash
# Verify all services running (same checks as Replica 2)
docker-compose ps | grep "Up"
docker-compose logs | grep -iE "error|critical|failed" | grep -v "ERR_" | tail -20

# Verify security hardening
docker inspect ollama --format='{{.Config.User}}'
docker inspect jaeger --format='{{.Config.User}}'
docker inspect loki --format='{{.Config.User}}'
docker exec -it redis redis-cli -a "$REDIS_PASSWORD" ping  # PONG expected
docker inspect caddy --format='{{.HostConfig.CapAdd}}'
```

### Step 5: Production Monitoring (6.5 hours)
```bash
# Monitor for issues
docker-compose logs -f | tee deployment.log

# Key things to watch:
# 1. No "invalid startup packet" errors from postgres (healthcheck issue)
# 2. All services healthy (no restarts)
# 3. No authentication/authorization errors from new REDIS_PASSWORD requirement
# 4. No errors from missing OAUTH2_PROXY_COOKIE_SECRET fallback

# After stabilization, verify cluster health
# Both replicas should be synchronized
```

---

## ROLLBACK PLAN (If Issues Encountered)

### Immediate Rollback
```bash
# On affected replica:
docker-compose pull
git checkout main~3  # Go back to before security fixes
git pull origin main~3
docker-compose up -d
```

### Gradual Rollback
If one replica fails during deployment:
1. Leave it stopped/isolated
2. Keep other replica running
3. Implement changes one-by-one on failed replica
4. Validate before re-enabling in load balancer

---

## POST-DEPLOYMENT VERIFICATION (24 hours)

### Cluster Health
```bash
# On both replicas
docker-compose ps | wc -l  # Should be 22 (21 services + header)
docker-compose ps | grep -v "Up" | wc -l  # Should be 1 (header only)

# Check for restarts
docker-compose ps | grep -v "0$"  # Should only show header, no restart counts

# Verify no high CPU/memory
docker stats --no-stream | awk 'NR>1 {if ($3 > 50 || $5 > 50) print}'  # Should be empty
```

### Security Hardening Validation
```bash
# Redis password enforcement (all clients should authenticate)
docker logs session-broker | grep -i redis_password  # Should show usage
docker logs oauth2-proxy-portal | grep -i redis_password  # Should show usage

# Non-root running confirmed
docker ps --format "table {{.Names}}\t{{.Config.User}}" | grep -E "ollama|jaeger|loki"
# Should show:
# ollama                     1001:1001
# jaeger                     10001:10001
# loki                       10001:10001

# GitHub Actions secret scanning active
git log --all | grep "secret-scanning.yml" | head -1

# Pre-commit hook installation ready
cat scripts/setup/install-git-secrets.sh | grep "git-secrets --install" | head -1
```

### Application Functionality
```bash
# Test application endpoints
curl -s https://ide.kushnir.cloud/api/health -k | jq .status  # Should be "ok"

# Test code-server
curl -s https://ide.kushnir.cloud/ -k | grep -q "code-server" && echo "✓ code-server running"

# Test OAuth portal (if applicable)
curl -s https://kushnir.cloud/api/health -k | jq .status  # Should be "ok"
```

---

## ISSUE CLOSURE

After successful deployment to both replicas:

```bash
# Close GitHub issues
gh issue close 968 --repo kushin77/code-server --comment "P0 #968 resolved: Cookie secret removed from .env.defaults. Verified on both replicas (94c45ef5)."
gh issue close 969 --repo kushin77/code-server --comment "P0 #969 resolved: All containers running non-root (ollama:1001, jaeger:10001, loki:10001). Caddy capabilities restricted. Verified on both replicas."
gh issue close 971 --repo kushin77/code-server --comment "P0 #971 resolved: Redis authentication enforced across all clients. Verified on both replicas."
gh issue close 998 --repo kushin77/code-server --comment "P0 #998 resolved: All hardcoded fallback values removed from docker-compose.yml. Verified on both replicas."
gh issue close 980 --repo kushin77/code-server --comment "P0 #980 resolved: GitHub Actions secret scanning (TruffleHog) + git-secrets pre-commit hook deployed. Ready for use on all developer machines."
```

---

## ENVIRONMENT VARIABLES REQUIRED

These 8 secrets MUST be provided from Google Secret Manager or Vault:

```
OAUTH2_PROXY_COOKIE_SECRET=<32-char hex from GSM>
POSTGRES_PASSWORD=<from GSM>
POSTGRES_USER=postgres
POSTGRES_DB=codeserver
REDIS_PASSWORD=<from GSM>
SLACK_SIGNING_SECRET=<from GSM>
SLACK_BOT_TOKEN=<from GSM>
REGISTRY_AUTH_TOKEN_SECRET=<from GSM>
```

**Retrieval** (from GSM):
```bash
gcloud secrets versions access latest --secret=oauth2-proxy-cookie-secret
gcloud secrets versions access latest --secret=postgres-password
gcloud secrets versions access latest --secret=redis-password
gcloud secrets versions access latest --secret=slack-signing-secret
gcloud secrets versions access latest --secret=slack-bot-token
gcloud secrets versions access latest --secret=registry-auth-token-secret
```

---

## NOTES

- All changes are backward compatible (existing deployments continue working)
- P0 #980 requires developer machines to run: `bash scripts/setup/install-git-secrets.sh`
- No database migrations required
- No downtime expected (graceful container restart)
- Changes are idempotent (safe to re-deploy multiple times)

**Created**: April 23, 2026  
**Status**: Ready for Execution on Linux/WSL with SSH Access
