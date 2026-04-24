# Kushnir.cloud Production Deployment Runbook (Simplified)

**Version**: 1.0  
**Last Updated**: April 24, 2026  
**Scope**: Production cluster on-prem deployment (192.168.168.31 and 192.168.168.42)  

---

## 1. OVERVIEW

This runbook documents the simplified, idempotent deployment procedure for the Kushnir.cloud production cluster. The procedure is designed to be:

- **Idempotent**: Safe to run multiple times without side effects
- **Deterministic**: Same inputs always produce same outputs
- **Parallel-Friendly**: Both replicas deploy simultaneously
- **Low-Risk**: Uses docker-compose with runtime override pattern (no rebuilds)

**Deployment Time**: 5-10 minutes total  
**Verification Time**: 2-3 minutes  
**Total Time**: 8-13 minutes (both replicas)  

---

## 2. PRE-DEPLOYMENT CHECKLIST

Before starting deployment:

- [ ] **Git Commit**: Verify commit SHA is production-locked (usually 4bfcaa2a)
- [ ] **SSH Keys**: Ensure `~/.ssh/id_rsa_onprem` is present and has permissions 600
- [ ] **Network**: Verify connectivity to both replicas and NAS
- [ ] **Backups**: Database backup completed in last 24 hours
- [ ] **Status Page**: Check if any ongoing incidents or maintenance windows
- [ ] **Team**: Notify team before starting deployment
- [ ] **Monitoring**: Have Grafana and health checks open during deployment

**Quick Pre-Check**:

```bash
# Verify SSH key exists and has correct permissions
ls -la ~/.ssh/id_rsa_onprem  # Should show "-rw-------"

# Test SSH connectivity to both replicas
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "date"  # Should return current date
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "date"  # Should return current date

# Verify NAS is reachable
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "mount | grep /export"  # Should list mounts
```

---

## 3. SIMPLIFIED DEPLOYMENT PROCEDURE

### Step 1: Pull Latest Code (2 min)

On your local machine (Windows host):

```bash
# Navigate to code-server-enterprise directory
cd c:\code-server-enterprise

# Pull latest code from main branch
git pull origin main

# Verify commit SHA
git rev-parse --short HEAD  # Should be 4bfcaa2a (or latest production commit)
```

### Step 2: Sync Code to Both Replicas (2 min)

This step ensures both replicas have identical code:

```bash
# Sync code-server-enterprise directory to both replicas in parallel
scp -i ~/.ssh/id_rsa_onprem -r code-server-enterprise akushnir@192.168.168.31:code-server-enterprise &
scp -i ~/.ssh/id_rsa_onprem -r code-server-enterprise akushnir@192.168.168.42:code-server-enterprise &
wait  # Wait for both transfers to complete

# Verify sync
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "git -C code-server-enterprise rev-parse --short HEAD"  # Should be 4bfcaa2a
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "git -C code-server-enterprise rev-parse --short HEAD"  # Should be 4bfcaa2a
```

### Step 3: Deploy to Both Replicas (5 min)

Deploy docker-compose services to both replicas **in parallel**:

```bash
# Deploy to Replica 31 (R31: 192.168.168.31)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d' &

# Deploy to Replica 42 (R42: 192.168.168.42)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose -f docker-compose.yml -f docker-compose.runtime-override.yml up -d' &

# Wait for both deployments to complete
wait

echo "Deployment to both replicas complete. Waiting for service stabilization..."
sleep 180  # Wait 3 minutes for services to fully start
```

**What This Does:**

1. Pulls latest images from registry (minimal pull if already cached)
2. Creates missing containers (no-op if already exist)
3. Starts all 20 services on each replica
4. Applies runtime configuration via docker-compose.runtime-override.yml
5. Services start with auto-restart policy (safe for repeated runs)

**Important**: This is **not** a rebuild - images are pre-built and pinned. The override file provides deterministic runtime config.

### Step 4: Verify Deployment (3 min)

Verify all services started successfully on both replicas:

```bash
# Check service count on both replicas (should be 20 each)
echo "=== REPLICA 31 SERVICE COUNT ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker ps -q | wc -l"  # Should output: 20

echo "=== REPLICA 42 SERVICE COUNT ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker ps -q | wc -l"  # Should output: 20

# Check git commit on both replicas (should be same)
echo "=== GIT PARITY ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "git -C code-server-enterprise rev-parse --short HEAD"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "git -C code-server-enterprise rev-parse --short HEAD"
# Both should show: 4bfcaa2a

# Test health endpoints (both should return 200 or 403 auth redirect)
echo "=== HEALTH CHECKS ==="
curl -k https://192.168.168.31/health -I  # HTTP 200 or 403 expected
curl -k https://192.168.168.42/health -I  # HTTP 200 or 403 expected

# Check Grafana dashboard for cluster status
# Navigate to: https://grafana.kushnir.cloud/d/cluster-health-production
# Expected: Both replicas showing HEALTHY (green)
```

### Step 5: Post-Deployment Verification (2 min)

Run comprehensive verification to ensure deployment succeeded:

```bash
# Test user functionality
curl -k https://ide.kushnir.cloud/health -I  # Should return 200 OK (load balanced)

# Check both replicas are accepting traffic
echo "=== REQUEST DISTRIBUTION ==="
for i in {1..5}; do
  echo "Request $i:" && curl -k https://ide.kushnir.cloud/health -H "User-Agent: DeploymentTest" -s | head -1
done

# Verify no critical errors in logs
echo "=== ERROR LOG CHECK ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker logs caddy 2>&1 | grep -i error | tail -3" || echo "No recent errors on R31"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker logs caddy 2>&1 | grep -i error | tail -3" || echo "No recent errors on R42"

# Check Redis HA is synchronized
echo "=== REDIS HA STATUS ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker exec redis-sentinel-1 redis-cli -p 26379 SENTINEL masters 2>/dev/null | head -10" || echo "Redis Sentinel not available"

# Check PostgreSQL replication lag
echo "=== DATABASE REPLICATION LAG ==="
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "docker exec postgres psql -U postgres -c 'SELECT slot_name, restart_lsn FROM pg_replication_slots;' 2>/dev/null" || echo "Database not available"
```

---

## 4. DEPLOYMENT VERIFICATION CHECKLIST

After completing deployment steps, verify:

| Check | Expected | Command |
|-------|----------|---------|
| R31 Services | 20 running | `ssh ... akushnir@192.168.168.31 "docker ps -q \| wc -l"` |
| R42 Services | 20 running | `ssh ... akushnir@192.168.168.42 "docker ps -q \| wc -l"` |
| R31 Git Commit | 4bfcaa2a | `ssh ... akushnir@192.168.168.31 "git -C code-server-enterprise rev-parse --short HEAD"` |
| R42 Git Commit | 4bfcaa2a | `ssh ... akushnir@192.168.168.42 "git -C code-server-enterprise rev-parse --short HEAD"` |
| Health Endpoint | 200/403 | `curl -k https://ide.kushnir.cloud/health -I` |
| Grafana Status | Green (both) | Navigate to Grafana cluster dashboard |
| Error Logs | None | `ssh ... docker logs caddy \| grep error` |
| Load Balancer | Both UP | `curl http://LOADBALANCER:8080/stats` |

---

## 5. IDEMPOTENCY PROOF

This deployment procedure is **idempotent** - it's safe to run multiple times:

```bash
# Example: Deploy twice in a row (should have identical result)

# First deployment
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose up -d'

# Immediate second deployment (same command)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose up -d'

# Result: Both produce identical output, no errors, no data loss
# Expected docker-compose output: "Container X Running" (no recreates)
```

**Why It's Idempotent:**

1. **No Destructive Operations**: docker-compose doesn't remove volumes or data
2. **Version Pinning**: All images are pinned to specific SHA256 digest
3. **Git Lock**: Code is locked to specific commit (immutable)
4. **Config Separation**: Runtime config via .runtime-override.yml (deterministic)
5. **No State Mutations**: Deployment only starts/restarts, doesn't modify

---

## 6. TROUBLESHOOTING

### Problem: Services Don't Start (Still Showing Old Count)

**Cause**: Docker containers not starting properly

**Solution**:

```bash
# Check container logs
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker logs <container_name> | tail -50"

# Restart individual container
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose restart <container_name>"

# If still failing, force recreate
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose down <container_name> && docker-compose up -d <container_name>"
```

### Problem: Health Check Fails (503 or Timeout)

**Cause**: Services still starting or configuration issue

**Solution**:

```bash
# Wait longer for services to stabilize
sleep 300  # Wait 5 more minutes

# Re-check health
curl -k https://192.168.168.31/health -v

# Check auth proxy logs
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker logs oauth2-proxy | tail -30"

# Check Caddy logs
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "docker logs caddy | tail -30"
```

### Problem: SSH Key Not Found

**Cause**: SSH key path incorrect or permissions wrong

**Solution**:

```bash
# Verify key exists
ls ~/.ssh/id_rsa_onprem  # Should exist

# Fix permissions if needed
chmod 600 ~/.ssh/id_rsa_onprem

# Test SSH explicitly
ssh -v -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "date"

# If still fails, check on-prem host for corresponding public key in authorized_keys
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cat ~/.ssh/authorized_keys"
```

### Problem: Git Commit Diverges Between Replicas

**Cause**: Code sync incomplete or network interruption

**Solution**:

```bash
# Verify current commit on both
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "git -C code-server-enterprise status"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "git -C code-server-enterprise status"

# If diverged, force sync to latest main
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && git fetch origin main && git reset --hard origin/main"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "cd code-server-enterprise && git fetch origin main && git reset --hard origin/main"

# Redeploy
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose up -d' &
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose up -d' &
wait
```

---

## 7. EMERGENCY ROLLBACK

If deployment introduces critical issues, rollback to previous working state:

```bash
# Stop services on both replicas
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose down'
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose down'

# Revert to last known good commit (usually 4bfcaa2a)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && git reset --hard 4bfcaa2a'
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cd code-server-enterprise && git reset --hard 4bfcaa2a'

# Restart services
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose up -d' &
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose up -d' &
wait

# Verify health
curl -k https://ide.kushnir.cloud/health
```

---

## 8. DEPLOYMENT CHECKLIST TEMPLATE

Print and use during deployments:

```
DEPLOYMENT CHECKLIST - Kushnir.cloud Production
Date: ___________  Deployed by: ___________

PRE-DEPLOYMENT (5 min)
 ☐ SSH key verified (ls -la ~/.ssh/id_rsa_onprem)
 ☐ Network connectivity confirmed (ping both replicas)
 ☐ Latest code pulled locally (git pull origin main)
 ☐ Git commit verified (4bfcaa2a)
 ☐ Team notified via #infrastructure Slack channel

DEPLOYMENT (10 min)
 ☐ Code synced to R31 and R42
 ☐ docker-compose deployed to both replicas (parallel)
 ☐ Waited 3 minutes for service stabilization

POST-DEPLOYMENT VERIFICATION (3 min)
 ☐ R31 service count = 20/20
 ☐ R42 service count = 20/20
 ☐ Health endpoint responds (200/403)
 ☐ Grafana shows both replicas HEALTHY
 ☐ No error messages in container logs
 ☐ Load balancer shows both replicas UP

TOTAL TIME: _____ minutes
STATUS: ☐ SUCCESS  ☐ NEEDS REVIEW  ☐ ROLLBACK

Notes: _________________________________
_________________________________
```

---

## 9. CONTACT & ESCALATION

**Normal Deploy Issues**: Platform Ops Team  
**Network/SSH Issues**: Infrastructure Lead  
**Service-Specific Failures**: Component Owner  

---

**Document Version**: 1.0  
**Last Reviewed**: April 24, 2026  
**Next Review**: May 24, 2026
