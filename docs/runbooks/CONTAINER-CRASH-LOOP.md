# Alert Runbook: Container Crash Loop

**Alerts**: `Container{RestartLoop,CrashLoop}`  
**Severity**: WARNING (2+ restarts/10m), CRITICAL (5+ restarts/10m)  
**SLA**: WARNING (1 hour), CRITICAL (15 minutes)  
**Owner**: DevOps/Application Team  

---

## Problem

A container is crash-looping: restarting every few seconds/minutes without successfully starting. Symptoms:
- `docker-compose ps` shows container with state: "Restarting (exit code X)"
- Container appears in `docker-compose ps` output but `docker logs` is empty or shows errors
- Service is non-functional (health checks failing)
- Resource waste (CPU, memory, disk)

---

## Immediate Investigation (< 2 minutes)

```bash
# Check container status
docker-compose ps | grep -E "restart|exited|up"

# Check recent restarts
docker inspect container_name | grep -i "restart"

# View container logs (last 100 lines)
docker logs container_name --tail 100

# View detailed error
docker logs container_name --tail 20 2>&1 | grep -i "error\|fatal\|panic"

# Check exit code
docker inspect container_name | grep -A 5 "State"
# Exit codes: 0=normal, 1=app error, 127=command not found, 137=OOM kill, 143=term signal
```

---

## Common Root Causes & Fixes

### Cause 1: Application Crashing with Error

**Symptoms**:
- `docker logs container` shows errors before exit
- Exit code: 1 or other non-zero
- Application fails to start

**Fix** (vary by application):
```bash
# Get full error output
docker logs container_name

# Common issues:
# 1. Missing configuration file
#    FIX: Mount config volume, set env vars

# 2. Port already in use
docker-compose down container_name
lsof -i :PORT
docker-compose up -d container_name

# 3. Database/dependency not ready
#    FIX: Add depends_on and healthcheck

# 4. Permission denied on file
docker inspect container_name | grep -i "user"
# May need to run as different user or fix file ownership

# Fix and restart
docker-compose restart container_name
docker logs container_name --follow
```

### Cause 2: Out of Memory (OOM)

**Symptoms**:
- Exit code: 137 (OOM killer)
- Logs show nothing (killed before logging)
- Docker stats shows high memory usage before crash

**Fix**:
```bash
# Check memory limits
docker inspect container_name | grep -i "memory"

# Check actual usage before crash
docker stats container_name --no-stream

# Options to fix:
# 1. Increase memory limit
docker-compose down
# Edit docker-compose.yml:
#   mem_limit: "4g"  (increase from current)
docker-compose up -d

# 2. Reduce memory usage (if possible)
#    - Reduce Prometheus retention
#    - Reduce application cache sizes
#    - Remove unnecessary dependencies

# 3. Monitor recovery
docker stats container_name --no-stream
docker logs container_name --follow
```

### Cause 3: Dependency Not Ready (Database, Network)

**Symptoms**:
- Logs show "Connection refused" or "Cannot resolve hostname"
- Container needs another service that hasn't started yet
- Works after manual restart (race condition)

**Fix**:
```bash
# Ensure dependencies are running
docker-compose ps
# All dependent services should show "Up"

# Add healthcheck and depends_on to docker-compose.yml:
#   postgres:
#     healthcheck:
#       test: ["CMD", "pg_isready"]
#       interval: 10s
#       timeout: 5s
#       retries: 3
#   app:
#     depends_on:
#       postgres:
#         condition: service_healthy

# Restart with dependencies
docker-compose down
docker-compose up -d
docker logs app --follow  # Should wait for postgres

# Alternatively, add retry logic in application startup script
# Or use wait-for-it script
```

### Cause 4: Disk Space Exhausted

**Symptoms**:
- Exit code: 28 (No space left on device)
- Container can't write logs or temporary files
- `df -h /` shows >99% full

**Fix**:
```bash
# First, free space
df -h /
du -sh /* | sort -h

# Delete unnecessary files
find /var/log -type f -mtime +7 -delete
docker system prune -a

# Verify space available
df -h /

# Restart container
docker-compose restart container_name
docker logs container_name --follow
```

### Cause 5: Health Check Misconfigured

**Symptoms**:
- Container starts but healthcheck fails
- Repeated restart due to failed healthcheck
- Logs show container is running fine

**Fix**:
```bash
# Check healthcheck configuration
docker inspect container_name | grep -A 10 "Healthcheck"

# Test healthcheck manually
docker exec container_name /bin/sh -c 'test -f /tmp/health || exit 1'
# Should return 0 if healthy

# Fix healthcheck in docker-compose.yml:
#   healthcheck:
#     test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
#     interval: 30s
#     timeout: 10s
#     retries: 3
#     start_period: 40s  # IMPORTANT: Grace period for app startup

# Restart with better healthcheck
docker-compose down
docker-compose up -d
docker logs container_name --follow
```

### Cause 6: Volume Mount Issues

**Symptoms**:
- Logs show "Permission denied" or "No such file or directory"
- Container can't read mounted volume
- Exit code: 1 with file-not-found errors

**Fix**:
```bash
# Check volume mounts
docker inspect container_name | grep -A 20 "Mounts"

# Verify host path exists
ls -ld /host/path/to/volume
# If doesn't exist, create it:
mkdir -p /host/path/to/volume

# Check permissions
ls -l /host/path/to/volume/
# Ensure container user can read

# If volume is persistent data, restore from backup
# Or recreate if safe

# Restart
docker-compose restart container_name
docker logs container_name --follow
```

---

## Debugging Steps

If root cause not obvious:

```bash
# 1. Get full docker inspect output
docker inspect container_name > /tmp/inspect.json

# 2. Check all environment variables
docker inspect container_name | jq '.[].Config.Env'

# 3. Check entrypoint and command
docker inspect container_name | jq '.[].Config | {Entrypoint, Cmd}'

# 4. Run with interactive debugging
docker run -it --entrypoint=/bin/sh image_name
# Manual test commands inside container

# 5. Check resource constraints
docker stats container_name

# 6. Enable verbose logging
RUST_LOG=debug docker-compose up container_name
# Or equivalent for your application
```

---

## Verification

After fixing, verify container stability:

```bash
# 1. Check container is running and stable
docker-compose ps | grep container_name
# Should show: "Up X seconds"

# 2. Verify logs are clean (no errors)
docker logs container_name --tail 50 | grep -i "error\|warn\|panic"
# Should be minimal/none

# 3. Verify service is healthy
curl -s http://container_name:PORT/health
docker exec container_name healthcheck_command

# 4. Monitor for 5 minutes (no restarts)
watch 'docker-compose ps | grep container_name'

# 5. Check alerts clear
curl -s http://localhost:9093/api/v1/alerts | \
  jq '.data[] | select(.labels.alertname | test("Container"))'
```

---

## Escalation

If container still crashing after 30 minutes:

1. **Check application source code**:
   ```bash
   # Is there a known bug?
   git log --oneline | head -20
   git diff HEAD~1 application_path
   ```

2. **Rollback recent changes**:
   ```bash
   git revert --no-edit HEAD
   docker-compose build && docker-compose up -d
   ```

3. **Run in debug mode**:
   ```bash
   docker run -it --entrypoint=/bin/bash image_name
   # Manually run application with debugging
   ```

4. **Escalate to application team**:
   - Slack: @app-team
   - Include: Crash logs, recent changes, docker inspect output

---

## Prevention

**Add comprehensive healthchecks**:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s  # Give app time to initialize
```

**Set resource limits**:
```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 2G
    reservations:
      cpus: '1'
      memory: 1G
```

**Test startup/shutdown**:
```bash
# Weekly: Manually restart each container and verify recovery
docker-compose restart postgres
docker logs postgres --follow | head -20
# Should show "ready to accept connections"
```

---

**Document**: docs/runbooks/container-crash-loop.md  
**Last Updated**: 2026-04-15  
**Approved By**: DevOps Lead  
