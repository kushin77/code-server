# Cluster Sync Fixes - Deployment Guide

**Generated**: April 25, 2026  
**Status**: Ready for Deployment  
**Governance**: GOV-002 Compliant  

---

## Overview

Three critical cluster synchronization fixes have been implemented and are ready for deployment to replica nodes (192.168.168.42):

### Fix #1: Standardized File Mounts (Deterministic)
- **File**: docker-compose.yml (3 changes)
- **Status**: ✅ Committed
- **Downtime**: ~2 minutes (docker compose restart required)

### Fix #2: Cluster Validation Script (Immutable + Audited)
- **File**: scripts/ci/validate-cluster-sync.sh (456 lines)
- **Status**: ✅ Committed
- **Downtime**: None (read-only validation)

### Fix #3: Continuous Sync Daemon (Idempotent + Ephemeral)
- **File**: scripts/ops/cluster-sync-daemon.sh (394 lines)
- **Status**: ✅ Committed
- **Downtime**: None (background cron job)

---

## Pre-Deployment Checklist

✅ All three fixes implemented and tested on primary (192.168.168.31)  
✅ All bash scripts pass syntax validation  
✅ docker-compose.yml validated  
✅ Commit created: 74e56225  
✅ Feature branch created: feat/cluster-sync-fixes  
✅ All files committed to git  

---

## Deployment Instructions

### Method 1: Automated Deployment (via deploy-cluster-sync-fixes.sh)

On the **primary node (192.168.168.31)**:

```bash
cd /code-server-enterprise

# Set environment variables
export PRIMARY_HOST=192.168.168.31
export REPLICA_HOST=192.168.168.42
export NAS_HOST=192.168.168.56
export APEX_DOMAIN=example.com  # Update as needed

# Execute deployment (interactive - SSH credentials required)
bash scripts/ops/deploy-cluster-sync-fixes.sh \
  --target 192.168.168.42 \
  --branch feat/cluster-sync-fixes

# Or do a dry-run first
bash scripts/ops/deploy-cluster-sync-fixes.sh \
  --target 192.168.168.42 \
  --branch feat/cluster-sync-fixes \
  --dry-run
```

### Method 2: Manual Deployment (step-by-step)

On the **replica node (192.168.168.42)**, execute these steps:

#### Step 1: Pull Latest Code

```bash
cd /code-server-enterprise
git fetch origin
git checkout feat/cluster-sync-fixes
git pull origin feat/cluster-sync-fixes
```

#### Step 2: Validate Cluster Sync Status

```bash
bash scripts/ci/validate-cluster-sync.sh --verbose

# Expected output:
# ✅ Git commits match between nodes
# ✅ Config file checksums match
# ✅ Service image versions are pinned
# ✅ Critical directories exist
# ✅ docker-compose.yml syntax is valid
```

#### Step 3: Restart Services with New Config

```bash
# This will cause ~2 minutes downtime while services restart
docker compose down
sleep 2
docker compose up -d

# Verify services are healthy
docker compose ps
docker compose logs --tail=20 caddy
```

#### Step 4: Install Continuous Sync Daemon

```bash
bash scripts/ops/cluster-sync-daemon.sh --install-cron

# Verify cron job was installed
sudo cat /etc/cron.d/cluster-sync
```

#### Step 5: Verify Deployment

```bash
# Check daemon status
bash scripts/ops/cluster-sync-daemon.sh --status

# Monitor the sync logs (wait ~5 minutes for first cron execution)
tail -f /var/log/cluster-sync.log

# Expected log output (after first sync):
# [2026-04-25 12:55:00] Checking for updates...
# [2026-04-25 12:55:00] No new commits, sync skipped (idempotent)
# [2026-04-25 12:55:00] Sync completed successfully
```

---

## What Gets Deployed

### 1. Docker Compose Changes (docker-compose.yml)

**Before** (problematic - directory mounts):
```yaml
caddy:
  volumes:
    - ./config/caddy:/etc/caddy:ro
```

**After** (fixed - file mounts):
```yaml
caddy:
  volumes:
    - ./config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
```

**Services Affected**:
- caddy (port 443/80 reverse proxy)
- prometheus (metrics at 9090)
- loki (logs at 3100)

**Impact**: Services will now start successfully on replica nodes with predictable file mounts.

### 2. Validation Script (scripts/ci/validate-cluster-sync.sh)

**5-Point Validation Matrix**:
1. Git commits match between primary and replica
2. Config file checksums match
3. Service image versions are pinned (not just tags)
4. Critical directories exist (config/caddy, config/loki, etc.)
5. docker-compose.yml syntax is valid

**Run Before**:
- Any failover test
- Any config update deployment
- Cluster maintenance

**Usage**:
```bash
bash scripts/ci/validate-cluster-sync.sh [--verbose] [--report FILE.json]

# Exit codes:
# 0 = all checks passed
# 1 = some checks failed
# 2 = configuration error
```

### 3. Sync Daemon (scripts/ops/cluster-sync-daemon.sh)

**6-Step Sync Process**:
1. Check for updates: `git fetch origin main`
2. Pull if new commits available: `git pull origin main`
3. Validate configuration: `docker compose config`
4. Restart services: `docker compose up -d`
5. Health check services (caddy, prometheus, grafana, loki, alertmanager)
6. Log results to `/var/log/cluster-sync-audit.json`

**Automatic Execution**: Every 5 minutes via cron (after installation)

**Manual Commands**:
```bash
# Manual sync execution
bash scripts/ops/cluster-sync-daemon.sh --sync

# Check status of last sync
bash scripts/ops/cluster-sync-daemon.sh --status

# Disable auto-sync (emergency stop)
bash scripts/ops/cluster-sync-daemon.sh --disable

# Check logs
tail -f /var/log/cluster-sync.log
tail -f /var/log/cluster-sync-audit.json
```

**Features**:
- ✅ Idempotent: Safe to run multiple times
- ✅ Automatic rollback on failure
- ✅ Mutual exclusion: Lock file prevents concurrent runs
- ✅ Health checks: Verifies services after update
- ✅ Full audit trail: JSON logging for compliance

---

## Expected Post-Deployment Behavior

### Immediate (After Service Restart)

✅ All services running with new file mount configuration  
✅ Services startup time: ~30 seconds  
✅ Health checks passing  
✅ No errors in docker compose logs  

### Within 5 Minutes

✅ First automatic sync executed  
✅ Entries in `/var/log/cluster-sync.log`  
✅ Audit events in `/var/log/cluster-sync-audit.json`  
✅ Status file created at `/var/run/cluster-sync/status.json`  

### Continuous (After First 5 Minutes)

✅ Every 5 minutes: Sync daemon checks for updates  
✅ If updates available: Git pull + docker compose up -d  
✅ If no updates: Sync skipped (idempotent)  
✅ Health checks pass consistently  
✅ Configuration drift prevented  

### On Config Update on Primary

1. Update config file on primary
2. Commit to git
3. Push to origin main
4. Within 5 minutes, replica automatically:
   - Pulls latest config
   - Validates it
   - Restarts affected services
   - Health checks new config
   - Logs success to audit trail

**Result**: Zero-downtime config propagation across cluster

---

## Rollback Procedure

If any issues occur during or after deployment:

### Option 1: Disable Auto-Sync (immediate, keeps deployment)

```bash
bash scripts/ops/cluster-sync-daemon.sh --disable

# Verify it's disabled
sudo cat /etc/cron.d/cluster-sync  # Should be empty or removed
```

### Option 2: Full Rollback (revert all changes)

```bash
# On replica node
cd /code-server-enterprise

# Disable sync daemon first
bash scripts/ops/cluster-sync-daemon.sh --disable

# Reset to previous commit (before cluster-sync fixes)
git reset --hard bbe11238

# Restart services with old config
docker compose down
docker compose up -d

# Verify services are healthy
docker compose ps
```

### Option 3: Selective Service Restart

```bash
# Rollback just the Caddy service (if mount issues)
docker compose down caddy
git checkout HEAD~1 docker-compose.yml
docker compose up -d caddy
```

---

## Verification Tests

### Test 1: File Mount Verification

```bash
# SSH to replica and check mount types
docker inspect caddy-container | grep "Mounts" -A 10

# Expected: Type = "bind", Source = "/code-server-enterprise/config/caddy/Caddyfile"
```

### Test 2: Config Consistency

```bash
# On primary and replica, should return same hash
sha256sum config/caddy/Caddyfile
sha256sum config/prometheus.yml
sha256sum config/loki/loki-config.yaml
```

### Test 3: Git Sync

```bash
# On primary, make a test commit
echo "test" >> test-file.txt
git add test-file.txt
git commit -m "test-sync"
git push origin main

# On replica, verify sync picks it up
# (Check /var/log/cluster-sync.log after 5 minutes)

# Rollback test commit
git reset --hard HEAD~1
git push origin main --force-with-lease
```

### Test 4: Automatic Failover

```bash
# Stop primary node
ssh 192.168.168.31 "docker compose down"

# Verify replica is still serving
curl https://192.168.168.42:443/ --insecure

# After test, restart primary
ssh 192.168.168.31 "docker compose up -d"
```

---

## Monitoring & Observability

### Log Files on Replica

**Sync Operations**:
```bash
tail -f /var/log/cluster-sync.log
```

**Audit Trail (JSON)**:
```bash
tail -f /var/log/cluster-sync-audit.json
```

**Status Report**:
```bash
cat /var/run/cluster-sync/status.json
```

### Expected Log Entries

```json
{
  "event": "sync_completed",
  "timestamp": "2026-04-25T12:55:00Z",
  "status": "success",
  "commits_behind": 0,
  "services_restarted": [],
  "health_check_status": "passed"
}
```

### Grafana Dashboard

Monitor cluster sync via Grafana (http://192.168.168.42:3000):
- Chart: "Cluster Sync Last Success"
- Alert: "Sync Failed for 15+ Minutes"
- Alert: "Config Drift Detected"

---

## Success Criteria

After deployment, all of these should be true:

- ✅ Both replicas have identical git commits
- ✅ All service file mounts are deterministic
- ✅ Sync daemon executes every 5 minutes
- ✅ Config changes propagate automatically
- ✅ No manual `git pull` required on replicas
- ✅ Health checks pass on both nodes
- ✅ Failover test succeeds with both nodes in sync
- ✅ Audit logs are created and rotated
- ✅ Zero configuration drift after 24 hours

---

## Timeline & Downtime

| Phase | Duration | Downtime | Automatic |
|-------|----------|----------|-----------|
| Code pull | 1 min | None | Yes (via deploy script) |
| Validation | 1 min | None | Yes (via deploy script) |
| Service restart | 2 min | **Yes** | Yes (docker compose restart) |
| Daemon install | 30 sec | None | Yes (via deploy script) |
| Verification | 1 min | None | Yes (via deploy script) |
| **Total** | **~5-6 min** | **~2 min** | **Yes** |

**Note**: Downtime is only during Step 3 (service restart). All other steps are non-blocking.

---

## Support & Troubleshooting

### SSH Access to Replica

```bash
# From primary node
ssh root@192.168.168.42

# View deployment script in action
cd /code-server-enterprise
bash scripts/ops/deploy-cluster-sync-fixes.sh --verbose

# Check status
bash scripts/ops/cluster-sync-daemon.sh --status
```

### Common Issues

**Issue**: Sync daemon not running
```bash
# Check if cron job exists
sudo cat /etc/cron.d/cluster-sync

# Check if lock file is stuck
ls -la /var/run/cluster-sync/

# Manual sync to test
bash scripts/ops/cluster-sync-daemon.sh --sync
```

**Issue**: Health checks failing
```bash
# Check service logs
docker compose logs --tail=20 caddy
docker compose logs --tail=20 prometheus

# Restart single service
docker compose up -d caddy
```

**Issue**: Git pull timeout
```bash
# Check git status
git status

# Manual pull with increased timeout
GIT_TIMEOUT=600 git pull origin main

# Check network
ssh root@192.168.168.42 "ping -c 3 github.com"
```

---

## Related Documentation

- **Code Review**: CODE-REVIEW-CLUSTER-SYNC-ISSUES.md
- **Completion Report**: CLUSTER-SYNC-FIXES-COMPLETION-REPORT.md
- **Architecture**: production-cluster-architecture-v2.md
- **Operations**: deployment-runbook.md

---

## Approval & Sign-Off

**Implemented By**: Autonomous Infrastructure Agent  
**Date**: April 25, 2026  
**Status**: ✅ Ready for Deployment  
**Governance**: GOV-002 Compliant ✓  

**Approvals**:
- [ ] Infrastructure Lead: Review deployment plan
- [ ] Release Manager: Approve deployment window
- [ ] Operations: Post-deployment monitoring confirmed

**Deployment Window**: [To be scheduled]  
**Estimated Duration**: 5-6 minutes (2 minutes downtime)  
**Rollback Time**: < 2 minutes if needed  

---

**For questions or issues, contact**: operations@example.com
