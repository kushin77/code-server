# Runbook: Code-Server Down

**Alert**: CodeServerDown  
**Severity**: CRITICAL  
**SLA**: Resolve within 15 minutes  
**Owner**: Platform Team  

## Symptoms

- Alert: "code-server is down"
- Users cannot access code-server via http://192.168.168.31:8080/
- Health check endpoint returns 503 or connection refused

## Root Causes

1. Container crashed (OOM, segfault, exception)
2. Host network unreachable
3. Port binding conflict
4. Configuration error
5. Dependency (postgres, redis) unreachable

## Diagnosis

```bash
# Check container status
docker ps | grep code-server

# Check container logs
docker logs code-server | tail -100

# Check health endpoint
curl -v http://localhost:8080/healthz

# Check port binding
netstat -tuln | grep 8080

# Check resource usage
docker stats code-server
```

## Remediation (In Order)

### Step 1: Check Container Status (1 min)
```bash
docker ps -a | grep code-server
```

**If running**: Go to Step 2  
**If stopped**: Go to Step 3  

### Step 2: Restart Container (2 min)
```bash
docker-compose restart code-server
sleep 10

# Verify restart
curl -I http://localhost:8080/healthz
```

**If healthy**: Alert resolved, continue monitoring  
**If still failing**: Go to Step 3  

### Step 3: Check Dependencies (5 min)
```bash
# Check PostgreSQL
docker exec postgres psql -U postgres -d code_server -c "SELECT 1"

# Check Redis
docker exec redis redis-cli PING

# Check Caddy
curl -I http://localhost:80/health
```

**If dependencies failing**: Restart dependency, then restart code-server  
**If dependencies healthy**: Go to Step 4  

### Step 4: Review Logs (5 min)
```bash
docker logs code-server --tail 200 | grep -i error

# Check system resources
docker stats code-server
```

**Common errors**:
- "Connection refused" → dependency down (Step 3)
- "Out of memory" → resource limits too low
- "port already in use" → kill conflicting process

### Step 5: Full Restart (5 min)
```bash
docker-compose down code-server
sleep 5
docker-compose up -d code-server

# Wait for health
sleep 10
curl -I http://localhost:8080/healthz
```

**If healthy**: Alert resolved  
**If still failing**: Go to Step 6  

### Step 6: Escalate (2 min)
```bash
# Collect diagnostic data
docker logs code-server > /tmp/code-server-$(date +%s).log
docker inspect code-server > /tmp/code-server-inspect.json

# Contact platform lead
# @kushin77 on Slack: "code-server persistent outage, logs in /tmp/"
```

## Prevention

- [ ] Increase memory limit if OOM occurred
- [ ] Configure health check retry logic
- [ ] Add startup probes (wait for dependencies)
- [ ] Set restart policy: `unless-stopped`

## Escalation

If unresolved after 15 minutes:
1. Page platform on-call lead
2. Prepare rollback plan (revert docker-compose changes)
3. Contact infrastructure team

---

**Status**: Ready for production deployment  
**Last Updated**: April 16, 2026  
**Runbook Owner**: Platform Team
