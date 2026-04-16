# Phase 8: Latency SLO Runbook

**SLO**: p99 Latency < 500ms  
**Alert Trigger**: > 750ms for 2 minutes  
**Severity**: CRITICAL  
**Impact**: User experience degradation

---

## Quick Response

### 1. Identify Slow Endpoint
```bash
# Get slowest endpoints (last 5 minutes)
curl -s http://localhost:9090/api/v1/query?query='topk(5, http_request_duration_seconds_bucket{le="5"})' | jq
```

### 2. Check PostgreSQL Query Performance
```bash
docker-compose exec -T postgres psql -U codeserver -d codeserver << EOF
-- Find slow queries
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
WHERE mean_time > 100 
ORDER BY mean_time DESC 
LIMIT 10;

-- Check active queries
SELECT pid, now() - query_start, query 
FROM pg_stat_activity 
WHERE query NOT LIKE '%pg_stat%' 
ORDER BY query_start;

-- Kill slow query if needed
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid = <pid>;
EOF
```

### 3. Check Redis Performance
```bash
docker exec redis redis-cli INFO stats

# Monitor commands
redis-cli MONITOR | head -100

# Check key distribution
redis-cli --bigkeys
```

### 4. Check Network Latency
```bash
# Ping replica
ping 192.168.168.42

# Check DNS resolution time
time nslookup code-server
```

---

## Root Cause Analysis

### If Database Query Slow
```bash
# Analyze slow query
EXPLAIN ANALYZE <query>;

# Create index if needed
CREATE INDEX idx_name ON table(column);

# Update statistics
ANALYZE;
```

### If Cache Miss
```bash
# Check hit rate
redis-cli INFO stats | grep hit

# Pre-warm cache
# Reload frequently-accessed data

# Increase cache TTL
# Review cache eviction strategy
```

### If Network Congestion
```bash
# Check network interface
iftop -n

# Check packet loss
mtr 192.168.168.42

# Monitor disk I/O
iostat -x 1 5
```

---

## Optimization Actions

### Scale Database (Vertical)
```bash
# Increase resources in docker-compose.yml
# postgres:
#   deploy:
#     resources:
#       limits:
#         memory: 8G (was 4G)
#         cpus: '2' (was '1')

docker-compose up -d postgres
```

### Scale Cache (Horizontal)
```bash
# Add Redis replica for read scaling
# Update docker-compose.yml to add redis-replica

docker-compose up -d redis-replica
```

### Connection Pooling
```bash
# Check pgbouncer connection pool
docker-compose exec pgbouncer psql -U postgres -d pgbouncer << EOF
SHOW POOLS;
SHOW CLIENTS;
EOF

# Adjust pool_size in pgbouncer.ini
# pool_size = 20 (was 10)
```

---

## Monitoring

### Set Up Latency Alerting
```bash
# Prometheus recording rule
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

### Create Latency Dashboard
- p50, p95, p99 latencies
- Request distribution heatmap
- Slow endpoints (top 10)
- Dependency latencies (DB, cache)

---

## Post-Optimization Validation

```bash
# Load test to verify improvement
ab -c 100 -n 10000 http://localhost/healthz

# Monitor latency
watch -n 1 'curl -s http://localhost:9090/api/v1/query?query="slo:latency:p99" | jq'
```

---

**Related**: [Error Rate Runbook](PHASE-8-ERROR-RATE-RUNBOOK.md), [Throughput Runbook](PHASE-8-THROUGHPUT-RUNBOOK.md)
