# Phase 2b Troubleshooting Guide

## Quick Reference

| Issue | Symptom | Resolution Time |
|-------|---------|-----------------|
| Checksum Mismatch | `docker-compose.enterprise.yml` differs between hosts | 5-10 min |
| Config Divergence | Invariant settings (puma, db, memory) differ | 10-15 min |
| GitLab Unhealthy | Health check failing on primary/replica | 5-15 min |
| HTTP Endpoint Down | Port 8101 unreachable on one/both hosts | 5-10 min |
| Container Restart Loop | GitLab container keeps restarting | 15-30 min |
| Network Connectivity | SSH or HTTP connectivity between hosts | 10-20 min |

---

## Issue 1: Checksum Mismatch

### Symptom
```
docker-compose-enterprise.yml checksums differ:
  PRIMARY: abc123def456...
  REPLICA: xyz789uvw012...
```

### Root Causes
- Manual edits to `docker-compose.enterprise.yml` on one host
- Incomplete file copy during deployment
- Git pull divergence between hosts
- Non-idempotent compose modifications

### Diagnosis

**Step 1: Verify checksum difference**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.31 \
  "cd ~/code-server-enterprise && sha256sum docker-compose.enterprise.yml"

ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "cd ~/code-server-enterprise && sha256sum docker-compose.enterprise.yml"
```

**Step 2: Check for manual edits**
```bash
# On both hosts
diff -u <(git show origin/HEAD:docker-compose.enterprise.yml) \
       ~/code-server-enterprise/docker-compose.enterprise.yml
```

**Step 3: Identify diverged sections**
```bash
# Compare specific sections
diff <(ssh akushnir@PRIMARY grep -A5 "environment:" docker-compose.enterprise.yml) \
     <(ssh akushnir@REPLICA grep -A5 "environment:" docker-compose.enterprise.yml)
```

### Resolution

**Option A: Sync from PRIMARY to REPLICA (Recommended)**
```bash
# Copy canonical version from PRIMARY
scp -o BatchMode=yes \
  akushnir@192.168.168.31:~/code-server-enterprise/docker-compose.enterprise.yml \
  /tmp/docker-compose.enterprise.yml.primary

# Backup REPLICA version
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "cp ~/code-server-enterprise/docker-compose.enterprise.yml \
      ~/code-server-enterprise/docker-compose.enterprise.yml.backup-$(date +%s)"

# Copy PRIMARY version to REPLICA
scp -o BatchMode=yes \
  /tmp/docker-compose.enterprise.yml.primary \
  akushnir@192.168.168.42:~/code-server-enterprise/docker-compose.enterprise.yml

# Verify checksum match
bash scripts/ops/check-gitlab-compose-parity.sh
```

**Option B: Revert from Git**
```bash
# On both hosts
ssh -o BatchMode=yes akushnir@192.168.168.31 \
  "cd ~/code-server-enterprise && git checkout docker-compose.enterprise.yml"

ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "cd ~/code-server-enterprise && git checkout docker-compose.enterprise.yml"

# Verify
bash scripts/ops/check-gitlab-compose-parity.sh
```

### Prevention

1. **Never edit `docker-compose.enterprise.yml` manually**
2. **Always make changes via Git + deploy**
3. **Use GitOps workflow for all compose changes**
4. **Automated diff checking in CI/CD**

---

## Issue 2: Configuration Divergence (Invariant Mismatch)

### Symptoms
```
Invariant validation failed:
  ✗ DB_NAME interpolation missing on REPLICA
  ✗ puma worker_processes != 0 on PRIMARY
  ✗ Memory limit < 4G on REPLICA
```

### Common Invariants to Check

**DB Name Interpolation:**
```bash
# Should have interpolation
grep "DB_NAME" docker-compose.enterprise.yml

# PRIMARY (correct)
gitlab_rails['db_database'] = '${DB_NAME:-gitlabdb}'

# REPLICA (incorrect - hardcoded)
gitlab_rails['db_database'] = 'gitlabdb'
```

**Puma Worker Configuration:**
```bash
# Should be set to 0
grep -A2 "puma\['worker_processes'\]" docker-compose.enterprise.yml

# Correct
puma['worker_processes'] = 0

# Incorrect
puma['worker_processes'] = 2 # or any non-zero value
```

**Memory Settings:**
```bash
# Should have 4G limit
grep -E "memory.*:|cpus:" docker-compose.enterprise.yml | head -5

# Correct
cpus: '2'
memory: '4G'
memswap_limit: '4G'

# Incorrect
cpus: '1'
memory: '2G'
```

**Redis Overrides (should NOT exist):**
```bash
# Verify Redis settings are removed
! grep "redis_host\|redis_port\|redis_database" docker-compose.enterprise.yml
echo $?  # Should output: 0 (no matches found)
```

### Resolution

**Step 1: Get canonical version from PRIMARY**
```bash
scp -o BatchMode=yes akushnir@192.168.168.31:~/code-server-enterprise/docker-compose.enterprise.yml /tmp/canonical.yml
```

**Step 2: Compare invariants**
```bash
echo "=== PRIMARY invariants ===" && \
ssh akushnir@192.168.168.31 "grep -E 'DB_NAME|worker_processes|memory|redis_' ~/code-server-enterprise/docker-compose.enterprise.yml | grep -v '#'"

echo "=== REPLICA invariants ===" && \
ssh akushnir@192.168.168.42 "grep -E 'DB_NAME|worker_processes|memory|redis_' ~/code-server-enterprise/docker-compose.enterprise.yml | grep -v '#'"
```

**Step 3: Sync and restart**
```bash
# Copy canonical to REPLICA
scp -o BatchMode=yes /tmp/canonical.yml akushnir@192.168.168.42:~/code-server-enterprise/docker-compose.enterprise.yml

# Restart GitLab on REPLICA
ssh -o BatchMode=yes akushnir@192.168.168.42 "cd ~/code-server-enterprise && docker-compose -f docker-compose.enterprise.yml up -d gitlab"

# Wait for health check
sleep 30

# Verify
bash scripts/ops/check-gitlab-compose-parity.sh
```

---

## Issue 3: GitLab Container Unhealthy

### Symptoms
```
REPLICA GitLab health: unhealthy (or starting)
Health check failed: curl http://localhost:8101/help returned 502
```

### Root Causes
- Memory/CPU pressure
- Database connection issues
- Port conflicts
- Configuration corruption
- Missing environment variables

### Diagnosis

**Step 1: Check container status**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker inspect code-server-gitlab --format '
    Status={{.State.Status}}
    Health={{.State.Health.Status}}
    RestartCount={{.RestartCount}}
    OOMKilled={{.State.OOMKilled}}'
  "
```

**Step 2: Check recent logs**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker logs code-server-gitlab 2>&1 | tail -100"
```

**Step 3: Check resource usage**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker stats code-server-gitlab --no-stream"
```

**Step 4: Attempt health check manually**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "curl -v http://localhost:8101/help 2>&1 | head -30"
```

### Resolution

**Option A: Restart Container**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker restart code-server-gitlab"

# Wait for health check
sleep 60

# Verify
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker inspect code-server-gitlab --format '{{.State.Health.Status}}'"
```

**Option B: Full Recreate (if restart fails)**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "cd ~/code-server-enterprise && \
   docker-compose -f docker-compose.enterprise.yml up -d gitlab --force-recreate"

# Wait for stabilization
sleep 120

# Verify
bash scripts/ops/check-gitlab-compose-parity.sh
```

**Option C: Check Environment Variables**
```bash
# Verify .env files are sourced correctly
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "cd ~/code-server-enterprise && \
   bash -c 'source .env; source .env.production; printenv | grep GITLAB' | head -20"
```

---

## Issue 4: HTTP Endpoint Unreachable

### Symptoms
```
curl http://localhost:8101/help
curl: (7) Failed to connect to localhost port 8101: Connection refused
```

### Root Causes
- GitLab container not running
- Port mapping misconfigured
- Firewall blocking port 8101
- Docker daemon issue

### Diagnosis

**Step 1: Check if container is running**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker ps --filter name=code-server-gitlab"
```

**Step 2: Check port mapping**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker port code-server-gitlab | grep 8101"
```

Expected output:
```
8101/tcp -> 0.0.0.0:8101
```

**Step 3: Test local connectivity**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "curl -v http://127.0.0.1:8101/help 2>&1 | grep -E 'Connected|HTTP|refused|refused'"
```

**Step 4: Check firewall**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "sudo firewall-cmd --list-all 2>/dev/null | grep 8101 || echo 'Firewall not detected'"
```

### Resolution

**If container not running:**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "cd ~/code-server-enterprise && docker-compose -f docker-compose.enterprise.yml up -d gitlab"
```

**If port mapping issue:**
```bash
# Remove and recreate container
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker rm -f code-server-gitlab && \
   cd ~/code-server-enterprise && \
   docker-compose -f docker-compose.enterprise.yml up -d gitlab"
```

**If firewall blocking:**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "sudo firewall-cmd --permanent --add-port=8101/tcp && \
   sudo firewall-cmd --reload"
```

---

## Issue 5: Container Restart Loop

### Symptoms
```
docker ps output shows: "Restarting (X) seconds ago" repeatedly
```

### Root Causes
- Corrupt GitLab configuration
- Missing or invalid environment variables
- Database initialization failure
- Memory pressure (OOMKilled)

### Diagnosis

**Step 1: Check restart count**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker inspect code-server-gitlab --format '{{.RestartCount}}'"
```

**Step 2: Check exit code**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker inspect code-server-gitlab --format '{{.State.ExitCode}}'"
```

Exit codes:
- 0: Normal shutdown
- 1: General error
- 137: OOMKilled
- 139: Segmentation fault

**Step 3: View container logs**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker logs code-server-gitlab 2>&1 | tail -200"
```

**Step 4: Check OOM status**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "docker inspect code-server-gitlab --format '{{.State.OOMKilled}}'"
```

### Resolution

**If OOMKilled (exit 137):**
```bash
# Increase memory allocation
# Edit docker-compose.enterprise.yml:
# memory: '4G' (or increase from current value)
# memory_reservation: '2G'

# Then recreate
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "cd ~/code-server-enterprise && \
   docker-compose -f docker-compose.enterprise.yml up -d gitlab --force-recreate"
```

**If config corruption:**
```bash
# Restore from backup or PRIMARY
scp -o BatchMode=yes akushnir@192.168.168.31:~/code-server-enterprise/docker-compose.enterprise.yml \
  akushnir@192.168.168.42:~/code-server-enterprise/docker-compose.enterprise.yml

# Recreate
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "cd ~/code-server-enterprise && \
   docker-compose -f docker-compose.enterprise.yml up -d gitlab --force-recreate"
```

---

## Issue 6: Network Connectivity Issues

### Symptoms
```
ssh: connect to host 192.168.168.42 port 22: Connection refused
curl: Failed to connect to PRIMARY_IP:8101
```

### Diagnosis

**Step 1: Test SSH connectivity**
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 akushnir@192.168.168.42 "echo ok"
```

**Step 2: Test networking from host**
```bash
ping -c 3 192.168.168.42
```

**Step 3: Check firewall on target host**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "sudo firewall-cmd --list-ports" 2>/dev/null || echo "No firewall or not sudo"
```

### Resolution

**If fail2ban is blocking:**
```bash
# Check fail2ban status (may require sudo on remote)
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "sudo fail2ban-client status sshd 2>/dev/null | grep -i banned"

# Unblock if needed (requires host-side action)
# Ask infrastructure team or manually unblock via console
```

**If firewall blocking:**
```bash
ssh -o BatchMode=yes akushnir@192.168.168.42 \
  "sudo firewall-cmd --permanent --add-port=22/tcp && \
   sudo firewall-cmd --permanent --add-port=8101/tcp && \
   sudo firewall-cmd --reload"
```

---

## Verification Checklist

After applying any fix, verify Phase 2b:

```bash
#!/bin/bash
set -e

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"

echo "=== Phase 2b Verification Checklist ==="
echo ""

# 1. Checksums
echo -n "1. Checksums match... "
PRIMARY_SUM=$(ssh -o BatchMode=yes akushnir@$PRIMARY_HOST "cd ~/code-server-enterprise && sha256sum docker-compose.enterprise.yml | awk '{print \$1}'")
REPLICA_SUM=$(ssh -o BatchMode=yes akushnir@$REPLICA_HOST "cd ~/code-server-enterprise && sha256sum docker-compose.enterprise.yml | awk '{print \$1}'")
if [ "$PRIMARY_SUM" == "$REPLICA_SUM" ]; then echo "✅"; else echo "❌"; fi

# 2. GitLab Health
echo -n "2. PRIMARY GitLab health... "
ssh -o BatchMode=yes akushnir@$PRIMARY_HOST "docker inspect code-server-gitlab --format '{{.State.Health.Status}}'"

echo -n "3. REPLICA GitLab health... "
ssh -o BatchMode=yes akushnir@$REPLICA_HOST "docker inspect code-server-gitlab --format '{{.State.Health.Status}}'"

# 3. HTTP Endpoints
echo -n "4. PRIMARY HTTP endpoint... "
ssh -o BatchMode=yes akushnir@$PRIMARY_HOST "curl -s -o /dev/null -w '%{http_code}' http://localhost:8101/help" && echo ""

echo -n "5. REPLICA HTTP endpoint... "
ssh -o BatchMode=yes akushnir@$REPLICA_HOST "curl -s -o /dev/null -w '%{http_code}' http://localhost:8101/help" && echo ""

# 4. Full parity check
echo -n "6. Full Phase 2b parity check... "
bash scripts/ops/check-gitlab-compose-parity.sh >/dev/null 2>&1 && echo "✅" || echo "❌"

echo ""
echo "=== Verification Complete ==="
```

---

## Escalation Path

If Phase 2b issues persist:

1. **Check:** Is the issue in Phase 2b or underlying infrastructure?
   - Run Phase 2b: `bash scripts/ops/check-gitlab-compose-parity.sh`
   - Check Docker: `docker ps`, `docker stats`
   - Check Network: `ping`, `ssh`, `curl`

2. **Document:** Collect diagnostic information
   ```bash
   # Gather diagnostics
   mkdir -p /tmp/phase-2b-diagnostics
   bash scripts/ops/check-gitlab-compose-parity.sh > /tmp/phase-2b-diagnostics/parity-check.log 2>&1
   docker inspect code-server-gitlab > /tmp/phase-2b-diagnostics/gitlab-inspect.json 2>&1
   docker logs code-server-gitlab > /tmp/phase-2b-diagnostics/gitlab-logs.txt 2>&1
   ```

3. **Escalate:** Share diagnostics with infrastructure team

4. **Track:** Create GitHub issue with diagnostic bundle attached

---

**Status:** Ready for Production  
**Last Updated:** April 30, 2026  
**Owner:** Operations Team

