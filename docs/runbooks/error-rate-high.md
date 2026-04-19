# Runbook: Error Rate High Response

**Alert**: ErrorRateHigh  
**Severity**: WARNING  
**SLA**: Root cause analysis within 20 minutes  
**Owner**: Engineering Team  

## Symptoms

- Alert: "High error rate detected"
- 5xx error rate > 5% for > 5 minutes
- Users report failures or 500 errors
- Application logs show exceptions

## Root Causes

1. Dependency failure (database, cache, external API)
2. Code exception or panic
3. Resource exhaustion (memory, file descriptors)
4. Invalid input handling
5. Concurrent request issue (race condition)

## Diagnosis

```bash
# Check error logs
docker logs code-server | grep -E "ERROR|panic|exception" | tail -30

# Check error rate by endpoint
curl http://prometheus:9090/api/v1/query?query='rate(http_requests_total{status=~"5.."}[5m])'

# Check specific error codes
curl http://prometheus:9090/api/v1/query?query='http_requests_total{status=~"5.."}'
```

## Remediation

### Step 1: Identify Error Source (5 min)
```bash
# View recent errors
docker logs code-server --since 10m | grep -i error | head -20

# Group by error type
docker logs code-server --since 10m | grep -i error | cut -d: -f1 | sort | uniq -c | sort -rn
```

### Step 2: Check Dependencies (5 min)
```bash
# Test database
docker exec postgres psql -U postgres -d code_server -c "SELECT 1"

# Test cache
docker exec redis redis-cli PING

# Test external services (from logs)
curl -I http://github.com/api
```

**If dependency failing**: Restart dependency  

### Step 3: Review Recent Changes (5 min)
```bash
# Check git log for recent code changes
git log --oneline --since="30 minutes ago"

# View recent deployment
docker-compose config | grep -A5 "code-server:"

# If recent change: consider rollback
git revert HEAD  # Revert last commit
docker-compose up -d code-server
```

### Step 4: Increase Logging (5 min)
```bash
# Enable debug logging to identify root cause
docker exec code-server DEBUG=* npm start

# Monitor in real-time
docker logs -f code-server | grep -i error
```

## Prevention

- [ ] Add request validation (schema validation)
- [ ] Implement circuit breaker for external APIs
- [ ] Add retry logic with exponential backoff
- [ ] Configure error budgets and SLOs
- [ ] Review error logs daily for patterns
- [ ] Add custom metrics for domain-specific errors

## Acceptable Error Rates

- Normal operation: < 0.1% error rate
- Degraded: 0.1% - 1% (investigate)
- Alert threshold: > 5% (immediate action)

---

**Status**: Ready for production deployment  
**Last Updated**: April 16, 2026  
**Runbook Owner**: Engineering Team
