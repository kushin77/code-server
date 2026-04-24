# P0 #1163 Implementation Guide: IDE_SESSION_LB_SECRET Deployment

## Overview

This guide documents the implementation and deployment of P0 issue #1163: provisioning the `IDE_SESSION_LB_SECRET` environment variable to production hosts to replace the hardcoded `secret734` fallback.

**Status**: Implementation ready for execution  
**Estimated Duration**: 10-15 minutes  
**Risk Level**: Low (environment variable addition, non-breaking)

---

## Prerequisites

- SSH access to 192.168.168.31 (primary) as `akushnir`
- SSH access to 192.168.168.42 (replica) as `akushnir`
- Docker Compose running on both hosts
- Git repository current and clean

---

## Implementation Steps

### Step 1: Dry-Run (Validate without changes)

```bash
cd /path/to/code-server-enterprise
bash scripts/ops/deploy-p0-1163-secret.sh --dry-run
```

**Expected Output**:
```
[INFO] Generating 32-char secret...
[INFO] Deploying to PRIMARY (192.168.168.31)...
[DRY RUN] Would execute on 192.168.168.31:
  1. Backup .env: cp .env .env.bak
  2. Add secret: echo 'IDE_SESSION_LB_SECRET=...' >> .env
  3. Verify: grep -q 'IDE_SESSION_LB_SECRET=' .env && echo 'OK'
  4. Restart: docker compose up -d
...
```

### Step 2: Deploy to Primary Host

```bash
bash scripts/ops/deploy-p0-1163-secret.sh --primary
```

**What this does**:
1. Generates a 32-character random secret using openssl
2. SSHes to 192.168.168.31
3. Backs up `.env` with timestamp
4. Adds `IDE_SESSION_LB_SECRET=<value>` to `.env`
5. Removes any existing `IDE_SESSION_LB_SECRET` to prevent duplicates
6. Restarts Docker Compose services
7. Verifies secret is in `.env`
8. Verifies no hardcoded `secret734` in Caddyfile

**Expected Output**:
```
✓ Deployment to 192.168.168.31 successful
✓ Verification on 192.168.168.31 successful
```

### Step 3: Deploy to Replica Host

```bash
bash scripts/ops/deploy-p0-1163-secret.sh --replica
```

This uses the same secret generated in Step 2 to ensure both hosts have identical session state.

### Step 4: Verify Both Hosts (Combined)

```bash
bash scripts/ops/deploy-p0-1163-secret.sh
```

This deploys to both hosts and verifies both in one command.

---

## Verification Commands

After deployment, manually verify the implementation:

### On Primary (192.168.168.31):

```bash
ssh akushnir@192.168.168.31

# 1. Check secret exists
grep "^IDE_SESSION_LB_SECRET=" ~/code-server-enterprise/.env

# 2. Verify no hardcoded secret734
grep -i "secret734" ~/code-server-enterprise/Caddyfile || echo "✓ No hardcoded secret found"

# 3. Check services healthy
cd ~/code-server-enterprise && docker compose ps

# 4. Test login flow
curl -s https://kushnir.cloud/health | jq .
```

### On Replica (192.168.168.42):

```bash
ssh akushnir@192.168.168.42
# Same commands as above
```

---

## Rollback (if needed)

Each deployment creates a timestamped backup of `.env`:

```bash
ssh akushnir@192.168.168.31
cd ~/code-server-enterprise

# List backups
ls -la .env.*.bak

# Restore if needed
cp .env.20260421-124530.bak .env
docker compose up -d
```

---

## Integration with CI/CD

To automate this in a future deployment pipeline:

```yaml
# .github/workflows/p0-secret-deployment.yml
name: P0 #1163 - Deploy IDE_SESSION_LB_SECRET

on:
  workflow_dispatch:  # Manual trigger

jobs:
  deploy:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Deploy P0 #1163
        run: |
          bash scripts/ops/deploy-p0-1163-secret.sh
```

---

## Success Criteria

✅ **All of the following must be true**:

1. `.env` on both hosts contains `IDE_SESSION_LB_SECRET=<value>`
2. `Caddyfile` uses `{$IDE_SESSION_LB_SECRET}` (NOT hardcoded `secret734`)
3. No hardcoded `secret734` remains in Caddyfile
4. Docker Compose services restarted and healthy
5. Login flow works end-to-end (OAuth2 Proxy → Caddyfile → code-server)
6. No errors in Docker logs
7. Session cookies are signed with the new secret

---

## Failure Recovery

If deployment fails:

### Scenario: SSH connection fails
**Solution**: Verify network connectivity
```bash
ping 192.168.168.31
ssh -v akushnir@192.168.168.31  # Debug SSH
```

### Scenario: Docker Compose fails to restart
**Solution**: Manually restart on the host
```bash
ssh akushnir@192.168.168.31
cd ~/code-server-enterprise
docker compose down
docker compose up -d
docker compose logs --tail=50
```

### Scenario: Services don't become healthy
**Solution**: Check logs and rollback
```bash
ssh akushnir@192.168.168.31
cd ~/code-server-enterprise

# Check logs
docker compose logs caddy
docker compose logs oauth2-proxy
docker compose logs code-server

# Rollback if needed
cp .env.<timestamp>.bak .env
docker compose restart
```

---

## Post-Deployment

After successful deployment, update issue #1163:

```bash
gh issue comment 1163 --repo kushin77/code-server --body \
  "✓ P0 #1163 RESOLVED - IDE_SESSION_LB_SECRET deployed to both hosts
  
  **Deployment Details**:
  - Primary (192.168.168.31): ✓ Verified
  - Replica (192.168.168.42): ✓ Verified
  - No hardcoded secrets: ✓ Verified
  - Services healthy: ✓ Verified
  
  **Evidence**: Both hosts now use environment-based secret management."

gh issue close 1163 --repo kushin77/code-server \
  --comment "Resolved: IDE_SESSION_LB_SECRET provisioned to production"
```

---

## Timeline

| Step | Duration | Notes |
|------|----------|-------|
| Dry-run validation | 1 min | Non-breaking, shows what will happen |
| Deploy to primary | 3-5 min | SSH + docker restart |
| Deploy to replica | 3-5 min | Same secret, synchronized state |
| Verification | 2-3 min | Manual checks + curl tests |
| Close issue | 1 min | Document resolution |
| **Total** | **10-15 min** | Production-ready timeline |

---

## Files Modified

- `scripts/ops/deploy-p0-1163-secret.sh` — New deployment script
- `.env` on 192.168.168.31 — Add IDE_SESSION_LB_SECRET
- `.env` on 192.168.168.42 — Add IDE_SESSION_LB_SECRET
- Docker containers — Restart with new environment

## Related Issues

- **#1163** - Secret rotation (this issue)
- **#1220** - Trivy false positive (already closed)
- **#1188** - Incident correlation (blocked by this)
- **#1189** - Extended platform features (blocked by this)

---

**Ready for execution. Next step: `bash scripts/ops/deploy-p0-1163-secret.sh --dry-run`**
