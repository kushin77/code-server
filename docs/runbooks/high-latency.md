# Runbook: High Latency Response

**Alert**: HighLatency  
**Severity**: WARNING  
**SLA**: Root cause analysis within 30 minutes  
**Owner**: Performance Team  

## Symptoms

- Alert: "High request latency detected"
- p99 request latency > 500ms for > 5 minutes
- Users report slow response times
- Grafana dashboard shows latency spike

## Root Causes

1. Resource exhaustion (CPU > 80%, memory > 90%)
2. Slow database queries
3. External API slowness
4. Network congestion
5. Large request payload

## Diagnosis

```bash
# Check system resources
docker stats --no-stream code-server caddy postgres

# Check container logs for slow operations
docker logs code-server | grep -i "duration\|took\|slow"

# Check database slow query log
docker exec postgres tail /var/log/postgresql/postgresql.log | grep "duration:"

# Check network
iftop -i eth0 -n
```

## Remediation

### Step 1: Identify Slow Service (5 min)
```bash
# Check latency by service
curl http://prometheus:9090/api/v1/query?query='http_request_duration_seconds{quantile="0.99"}'

# Identify which service is slow (code-server, caddy, postgres)
```

### Step 2: Check Resources (5 min)
```bash
docker stats --no-stream code-server caddy postgres

# Check disk I/O
iostat -x 1 2
```

**If CPU > 80%**: Go to Step 3  
**If Memory > 90%**: Restart container  
**If disk I/O high**: Check for large file operations  

### Step 3: Analyze Query Performance (10 min)
```bash
# If code-server latency high, check database
docker exec postgres psql -U postgres -d code_server -c \
  "SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 5"

# Optimize slow queries with EXPLAIN
docker exec postgres psql -U postgres -d code_server -c \
  "EXPLAIN ANALYZE SELECT ..."
```

### Step 4: Scale Resources (5 min)
```bash
# Increase container resource limits if at capacity
# Edit docker-compose.yml:
# services:
#   code-server:
#     deploy:
#       resources:
#         limits:
#           cpus: '2'
#           memory: 4G

docker-compose up -d code-server
```

## Prevention

- [ ] Set resource limits based on baseline
- [ ] Enable slow query logging (postgres: log_min_duration_statement = 1000ms)
- [ ] Review database indexes for missing indexes
- [ ] Implement caching layer (Redis)
- [ ] Consider connection pooling (pgbouncer)
- [ ] Add request timeout protections

## Performance Targets

- p50 latency: < 100ms
- p95 latency: < 200ms
- p99 latency: < 500ms (alert threshold)

---

**Status**: Ready for production deployment  
**Last Updated**: April 16, 2026  
**Runbook Owner**: Performance Team
