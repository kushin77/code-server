# Runbook: Container Restart Loop

**Alert**: `ContainerRestartLoop` / `ContainerCrashLoop`  
**Severity**: WARNING (RestartLoop) / CRITICAL (CrashLoop)  
**Time to Resolution**: < 5 minutes  
**Recovery Time Target**: < 2 minutes  

---

## Symptoms

- Docker container repeatedly restarting
- `docker ps` shows container with "Up X minutes (restarted Y times))"
- `docker logs` shows startup failures or segfaults
- Alert: "Container has restarted 2+ times in 10 minutes" (WARNING)
- Alert: "Container has restarted 5+ times in 10 minutes" (CRITICAL)

---

## Root Causes

1. **Out of memory** - Container killed by OOMKiller
2. **Port conflict** - Another process using container's port
3. **Health check failing** - Container marked unhealthy, restarted by Docker
4. **Configuration error** - Invalid env var or config file
5. **Dependency not ready** - Database/service not accessible on startup
6. **Segmentation fault** - Binary crash (uncommon in containers)
7. **Resource limits** - CPU/memory limits causing throttling/crashes

---

## Immediate Diagnosis

### Step 1: Identify Affected Container

```bash
ssh akushnir@primary.prod.internal

# List all containers with restart counts
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"

# Example output:
# code-server    Up 2 minutes (restarted 8 times in 1m10s)   ← CRASH LOOP
# postgres       Up 5 hours
# redis          Up 5 hours
```

### Step 2: Check Recent Logs

```bash
# View last 50 lines of logs
docker logs <container_name> --tail 50

# View logs with timestamps
docker logs <container_name> --timestamps --tail 100

# Example error lines to look for:
# "OOMKilled" → Out of memory
# "bind: Address already in use" → Port conflict
# "Connection refused" → Dependency not ready
# "Segmentation fault" → Binary crash
# "error: config not found" → Configuration issue
```

### Step 3: Check System Resources

```bash
# View memory/CPU usage
docker stats <container_name> --no-stream

# Check host resources
free -h
df -h

# If host memory/disk < 10%, see disk/memory runbooks
```

---

## Troubleshooting by Symptom

### Symptom: "OOMKilled" in logs

```bash
# 1. Increase memory limit
docker inspect <container_name> | grep -A 5 "Memory"

# 2. Increase in docker-compose.yml:
# services:
#   <container>:
#     mem_limit: 2g  # Increase from current value

# 3. Restart with new limit
docker-compose restart <container>

# 4. Monitor for 5 minutes
docker logs <container_name> --follow
```

### Symptom: "Address already in use" or Port conflict

```bash
# Find process using the port
PORT=8080  # Example, replace with actual port
sudo lsof -i :$PORT
# or
sudo ss -tulpn | grep :$PORT

# Kill conflicting process (if not Docker)
sudo kill -9 <PID>

# Or restart conflicting container
docker-compose restart <container_name>
```

### Symptom: "Connection refused" (dependency not ready)

```bash
# Check if dependency container is running
docker ps | grep postgres  # Example
docker ps | grep redis

# If not running, start it
docker-compose start postgres
docker-compose start redis

# Check connectivity from failing container
docker exec <failing_container> ping postgres  # Should work
docker exec <failing_container> nc -zv postgres 5432  # Should succeed

# If still failing, check .env for correct hostname
grep DATABASE_URL /home/akushnir/.env
# Should be: DATABASE_URL=postgres://user:pass@postgres:5432/db
```

### Symptom: "Config not found" or Environment variable missing

```bash
# Check env vars in container
docker exec <container_name> env | grep -i config

# Check .env file
cat /home/akushnir/code-server-enterprise/.env | grep -i config

# If missing, add to .env and reload:
docker-compose config | grep CONFIG  # Verify it's loaded
docker-compose restart <container_name>
```

### Symptom: Segmentation Fault (rare)

```bash
# Check if it's a known issue with image version
docker inspect <container_name> | grep Image

# Try rolling back image version
# Edit docker-compose.yml:
# services:
#   <container>:
#     image: <image>:previous-version

docker-compose restart <container_name>
```

---

## Advanced Debugging

### Enable Debug Logging

```bash
# For most containers, enable debug mode in env:
export DEBUG=true
export LOG_LEVEL=debug
docker-compose restart <container_name>

docker logs <container_name> --follow | head -100
```

### Inspect Container Startup Command

```bash
# See the exact command container runs on startup
docker inspect <container_name> | jq '.Config.Cmd'
# or
docker inspect <container_name> | jq '.Config.Entrypoint'
```

### Run Container Interactively

```bash
# Start container without auto-restart to diagnose
docker run -it --entrypoint /bin/bash <image>:<tag>

# Inside container:
echo $DATABASE_URL  # Check env vars
curl http://postgres:5432  # Check connectivity
ps aux  # Check processes
```

---

## Resolution

### For Restart Loop (Warning)

1. ✅ Check logs for root cause (see "Troubleshooting by Symptom")
2. ✅ Apply fix (increase memory, fix config, restart dependency)
3. ✅ Restart container: `docker-compose restart <container>`
4. ✅ Monitor logs for 5 minutes: `docker logs <container> --follow`
5. ✅ Alert should auto-clear when restart count drops

### For Crash Loop (Critical)

1. ⚠️ **IMMEDIATE**: Stop the crashing container to prevent cascading failures
   ```bash
   docker stop <container_name>
   ```

2. ✅ Diagnose root cause (see "Troubleshooting by Symptom")

3. ✅ Apply fix

4. ✅ Test startup in isolation:
   ```bash
   docker start <container_name>
   docker logs <container_name> --follow
   # Monitor for 2 minutes, should stay up
   ```

5. ✅ If successful, resume normal operation:
   ```bash
   docker-compose up -d
   ```

---

## Prevention

### 1. Set Appropriate Resource Limits

```yaml
# In docker-compose.yml
services:
  code-server:
    mem_limit: 2g
    cpus: 2.0
    memswap_limit: -1  # Unlimited swap
```

### 2. Configure Health Checks

```yaml
# In docker-compose.yml
services:
  postgres:
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 20s
```

### 3. Monitor Restart Events

```bash
# Subscribe to Docker events
docker events --filter 'type=container' --filter 'action=die' --format 'json' | \
  jq 'select(.Actor.Attributes.exitCode != "0") | {container: .Actor.Attributes.name, exitCode: .Actor.Attributes.exitCode}'
```

---

## Related Alerts

- `HostMemoryUsageHigh` - Often precedes OOMKill crashes
- `HostCPUUsageHigh` - Container throttling can cause timeouts
- `PostgreSQLDown`, `RedisDown` - Dependency failures cause restart loops
- `DiskSpaceRunningOut` - Disk full can cause container crashes

---

*Last Updated: April 18, 2026*  
*On-Call Contact: @infrastructure-team*
