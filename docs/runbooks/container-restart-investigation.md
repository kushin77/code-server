# Runbook: Container Restart Storm (ContainerRestartStorm)

**Alert**: `ContainerRestartStorm` (> 0.1/sec) | `ContainerRestartStormCritical` (> 1/sec)  
**Severity**: WARNING / CRITICAL  
**Component**: Container orchestration  
**Related Issue**: #569

## Overview

This alert fires when a container is restarting too frequently, indicating an application crash loop or health check failure.

## Quick Response

```bash
# 1. Identify which container is restarting
docker-compose ps | grep -v "Up"
docker-compose ps | awk '{print $1}' | xargs -I {} docker inspect {} --format='{{.Name}}: {{.State.Status}}'

# 2. Check recent restart count
docker inspect <container-name> | jq '.State.RestartCount'

# 3. View container logs
docker-compose logs --tail 200 <container-name>

# 4. Check health status
docker inspect <container-name> | jq '.State.Health'
```

## Detailed Investigation

### Step 1: Find the Failing Container

```bash
# List all containers with restart counts
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

# Get restart count for all containers
docker-compose ps -q | xargs docker inspect --format='{{.Name}}: {{.State.RestartCount}} restarts ({{.State.Status}})'
```

### Step 2: Analyze Failure

```bash
# Get full container logs
docker-compose logs <container-name> 2>&1 | tail -100

# Look for common error patterns
docker-compose logs <container-name> | grep -iE "error|failed|panic|exception|segfault"

# Check healthcheck results
docker inspect <container-name> | jq '.State.Health'
```

### Step 3: Common Causes

| Cause | Detection | Fix |
|-------|-----------|-----|
| **OOM Kill** | `docker logs` shows "Killed" or memory error | Increase `docker-compose.yml` memory limit |
| **Unhealthy healthcheck** | `docker inspect State.Health` is unhealthy | Fix healthcheck command or increase timeout |
| **Port conflict** | Logs show "address already in use" | Kill process on that port: `lsof -i :<port>` |
| **Missing dependency** | Logs show connection refused | Ensure dependency (postgres, redis) is running: `docker-compose restart <dep>` |
| **Crash on startup** | Immediate exit after start | Check app configuration, logs, and entrypoint |
| **File permissions** | Logs show permission denied | Fix volume mount: `sudo chown -R <uid>:<gid> <volume>` |

### Step 4: Container-Specific Recovery

**Code-Server**:
```bash
docker-compose logs code-server | grep -iE "memory|crash|signal"
docker-compose restart code-server
# Wait for healthy status
docker-compose exec code-server sh -c "curl -f http://localhost:8080/api/health || echo 'Unhealthy'"
```

**PostgreSQL**:
```bash
docker-compose exec postgres pg_ctl status || docker-compose restart postgres
# Wait 30s for startup
sleep 30 && docker-compose exec postgres psql -U codeserver -d codeserver -c "SELECT 1;" 
```

**Redis**:
```bash
docker-compose exec redis redis-cli ping || docker-compose restart redis
docker-compose exec redis redis-cli INFO stats | grep -E "keyspace|commands|connections"
```

**Ollama**:
```bash
docker-compose exec ollama curl -f http://localhost:11434/api/health || docker-compose restart ollama
docker-compose exec ollama curl http://localhost:11434/api/tags | jq '.models | length'
```

### Step 5: Verify Stability

```bash
# Monitor restart rate for 2 minutes
for i in {1..12}; do
  docker-compose ps | awk '{print $1}' | xargs docker inspect --format='{{.Name}}: {{.State.RestartCount}}'
  sleep 10
done
```

## Prevention

- **Health checks**: Ensure all containers have proper healthcheck configuration
- **Resource limits**: Set appropriate memory/CPU limits in docker-compose
- **Log monitoring**: Watch for startup errors: `docker-compose logs -f <container-name>`
- **Dependency ordering**: Use `depends_on` and `condition: service_healthy` for startup ordering

## Example Healthcheck Fix

```yaml
# Before (may fail during startup)
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 10s
  timeout: 3s
  retries: 1  # Too strict!

# After (more lenient for startup)
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 60s  # Grace period on startup
```

## Escalation

If restart loop continues:
1. Disable auto-restart temporarily: `docker update --restart=no <container-name>`
2. Run container interactively to debug: `docker run -it --rm <image> /bin/bash`
3. Check resource availability: `free -h && df -h`
4. Review application startup logs with verbose mode enabled

## Related Runbooks

- [DiskSpaceWarning](disk-space-cleanup.md) — Check if disk is full  
- [OllamaLatencySpike](ollama-performance-investigation.md) — GPU/resource issues
