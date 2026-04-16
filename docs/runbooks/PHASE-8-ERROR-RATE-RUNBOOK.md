# Phase 8: Error Rate SLO Runbook

**SLO**: Error Rate < 0.1% (< 1 error per 1000 requests)  
**Alert Trigger**: > 0.2% for 2 minutes  
**Severity**: CRITICAL  
**Budget**: ~86 errors per day

---

## Quick Response

### 1. Identify Error Type
```bash
# Get error breakdown (5xx vs 4xx)
curl -s http://localhost:9090/api/v1/query?query='increase(http_requests_total{status=~"5.."}[5m])' | jq

# Get specific error codes
curl -s http://localhost:9090/api/v1/query?query='topk(5, increase(http_requests_total{status=~"5.."}[5m]))' | jq
```

### 2. Get Error Logs
```bash
# Check all service logs for errors
docker-compose logs --tail=500 | grep -i "error\|exception\|500\|500"

# Specific service logs
docker-compose logs -f code-server | grep -i error
docker-compose logs -f postgres | grep -i error
docker-compose logs -f redis | grep -i error
```

### 3. Check Service Status
```bash
# Get health status
docker-compose ps

# Check database connectivity
docker-compose exec -T code-server curl -s http://postgres:5432 || echo "DB connection failed"

# Check cache connectivity
docker-compose exec -T code-server redis-cli -h redis ping
```

---

## Root Cause Analysis

### If Database Connection Error
```bash
# Check PostgreSQL status
docker-compose ps postgres

# Check logs
docker-compose logs postgres | tail -100

# Test connection
docker-compose exec -T code-server psql -h postgres -U codeserver -d codeserver -c "SELECT 1;"

# Check connection pool
docker-compose exec -T pgbouncer psql -d pgbouncer -c "SHOW POOLS;"
```

### If Cache Connection Error
```bash
# Check Redis status
docker-compose ps redis

# Test connection
docker-compose exec -T code-server redis-cli -h redis ping

# Check memory/capacity
docker exec redis redis-cli INFO memory
```

### If Application Logic Error
```bash
# Get stack trace from logs
docker-compose logs code-server | grep -A 20 "Exception\|Error\|Traceback"

# Identify affected endpoint
curl -s http://localhost:9090/api/v1/query?query='topk(5, increase(http_requests_total{status="500"}[5m]) by (endpoint))' | jq

# Check recent code changes
git log --oneline -10

# Review if deploy needed rollback
git revert <commit-sha>
git push origin main
docker-compose restart code-server
```

### If Rate Limiting (429)
```bash
# Check rate limit rules
curl http://localhost:2019/admin/config/apps/http/routes | jq '.[]' | grep -i rate

# Increase rate limit if legitimate
# Edit Caddyfile: rate_limit 1000 per minute (was 100)
docker-compose exec caddy caddy reload
```

---

## Error Rate Reduction Actions

### Increase Logging (Temporarily)
```bash
# Set log level to DEBUG
docker-compose exec code-server \
  sed -i 's/LOG_LEVEL=INFO/LOG_LEVEL=DEBUG/' /etc/environment

# Restart to capture full error context
docker-compose restart code-server
```

### Implement Retry Logic
```bash
# For transient errors (connection timeout, etc.)
# Add exponential backoff in code
# Retry up to 3 times with 100ms, 200ms, 400ms delays
```

### Circuit Breaker (if dependent service failing)
```bash
# Fail fast if database unavailable
# Return 503 Service Unavailable instead of 500 Internal Error
# Gives proper error signal to clients
```

### Database Connection Pool Tuning
```bash
# Increase pool size if maxed out
# pgbouncer.ini:
# pool_size = 25 (from 20)

docker-compose restart pgbouncer
```

---

## Error Budget Tracking

```bash
# Calculate remaining error budget for the day
# Daily budget: 86.4 errors
# If 45 errors already occurred: 41.4 remaining
# Rate: 45 / (hours_passed) = X errors/hour

# If trending to exceed budget:
# 1. Increase on-call response speed
# 2. Prioritize error reduction
# 3. Schedule urgent fix/deploy
```

---

## Post-Incident

```bash
# Verify error rate returned to normal
watch -n 5 'curl -s http://localhost:9090/api/v1/query?query="slo:error_rate:ratio" | jq'

# Document root cause
cat > incident-error-$(date +%Y%m%d).md << EOF
## Error Rate Incident

**Duration**: HH:MM - HH:MM
**Peak Rate**: X% (vs 0.1% target)
**Total Errors**: X

**Root Cause**: [description]
**Resolution**: [fix applied]
**Prevention**: [improvements]
EOF
```

---

**Related**: [Availability Runbook](PHASE-8-AVAILABILITY-RUNBOOK.md), [Latency Runbook](PHASE-8-LATENCY-RUNBOOK.md)
