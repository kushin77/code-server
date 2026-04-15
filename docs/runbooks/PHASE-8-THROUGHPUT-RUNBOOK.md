# Phase 8: Throughput SLO Runbook

**SLO**: Throughput >= 100 req/s (minimum sustained load)  
**Alert Trigger**: < 1 req/s for 1 minute (service down)  
**Severity**: CRITICAL  
**Impact**: Service completely unavailable

---

## Quick Response

### 1. Verify Service Status
```bash
# Check all services running
docker-compose ps | grep -E "Up|Exit"

# Any services not up?
docker-compose ps | grep "Exit"
```

### 2. Check Current Throughput
```bash
# Get request rate (req/s)
curl -s http://localhost:9090/api/v1/query?query='rate(http_requests_total[1m])' | jq '.data.result[] | {job: .metric.job, rps: .value[1]}'

# Get by service
curl -s http://localhost:9090/api/v1/query?query='sum(rate(http_requests_total[1m])) by (service)' | jq
```

### 3. Check Web Server (Caddy/code-server)
```bash
# Check if listening on port 8080/443
docker-compose exec caddy netstat -tlnp | grep -E ':80|:443'

# Test connectivity
curl -v http://localhost:8080 2>&1 | head -20
```

### 4. Check Load Balancer (HAProxy)
```bash
# Verify HAProxy is running
docker-compose ps haproxy

# Check HAProxy status page
curl http://localhost:8404/stats

# Check backend health
docker-compose exec haproxy echo "show stat" | socat stdio /var/run/haproxy.sock
```

---

## Root Cause Analysis

### If Service Completely Down (< 1 req/s)

```bash
# 1. Check DNS resolution
nslookup code-server
nslookup code-server.192.168.168.31.nip.io

# 2. Check if listening
docker-compose exec code-server netstat -tlnp | grep 8080

# 3. Check logs
docker-compose logs code-server | tail -200

# 4. Check application status
docker-compose exec code-server curl http://localhost:8080/healthz
```

### If Low Throughput (1-50 req/s, but not zero)

```bash
# Possible causes:
# 1. Slow requests blocking thread pool
# 2. Database queries are slow
# 3. Cache is failing (high latency)
# 4. Rate limiting too strict

# Check request latency
curl -s http://localhost:9090/api/v1/query?query='histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[1m]))' | jq '.data.result[].value'

# If latency > 1 second: requests are being blocked
# Check database/cache as per Latency Runbook

# Check rate limits
docker-compose exec caddy curl -s http://localhost:2019/admin/config/apps/http | jq '.routes' | grep rate_limit
```

### If High Spikes (>1000 req/s suddenly)

```bash
# Not a problem if sustainable
# Just indicates legitimate traffic

# Check resource usage
docker stats --no-stream

# If CPU/memory maxed:
# 1. Auto-scale horizontally (add more code-server containers)
# 2. Check for connection leaks
# 3. Review recent code changes
```

---

## Remediation Actions

### Restart Failed Service
```bash
# If code-server not responding
docker-compose restart code-server

# If caddy not responding
docker-compose restart caddy

# If database connectivity broken
docker-compose restart postgres
```

### Clear Connection Pools
```bash
# If stuck connections blocking throughput
docker-compose exec pgbouncer psql -d pgbouncer << EOF
DISCONNECT;
EOF

docker-compose restart pgbouncer
```

### Emergency Failover
```bash
# If primary completely down:
ssh akushnir@192.168.168.30

# On replica (192.168.168.30):
docker-compose ps

# Promote replica to primary
docker-compose exec postgres psql << EOF
SELECT pg_wal_replay_resume();
SELECT pg_promote();
EOF

# Update primary's docker-compose.yml to point to new primary
# docker-compose.yml: POSTGRES_HOST=192.168.168.30
docker-compose restart code-server
```

### Scale Horizontally (if needed)
```bash
# Add more code-server instances
# docker-compose.yml:
#   code-server-2:
#     image: code-server:...
#     environment:
#       PROXY_DOMAIN: code-server-2.192.168.168.31.nip.io

docker-compose up -d code-server-2

# Update HAProxy to load balance across instances
# haproxy.cfg:
#   server code-server-1 code-server:8080
#   server code-server-2 code-server-2:8080

docker-compose restart haproxy
```

---

## Monitoring During Recovery

```bash
# Monitor throughput recovery
watch -n 2 'curl -s http://localhost:9090/api/v1/query?query="rate(http_requests_total[1m])" | jq'

# Monitor error rate (shouldn't spike)
watch -n 2 'curl -s http://localhost:9090/api/v1/query?query="rate(http_requests_total{status=\"500\"}[1m])" | jq'

# Monitor resource usage
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

---

## Recovery Validation

```bash
# Confirm service is responding
curl -v http://localhost:8080/healthz

# Confirm throughput > 100 req/s
curl -s http://localhost:9090/api/v1/query?query='rate(http_requests_total[1m])' | jq '.data.result[0].value[1]'
# Should see >= 100

# Confirm error rate normal
curl -s http://localhost:9090/api/v1/query?query='rate(http_requests_total{status="500"}[1m])' | jq
# Should see ~0 or very low
```

---

## Load Testing (Verify Capacity)

```bash
# Install Apache Bench if needed
sudo apt-get install apache2-utils

# Test at current throughput (100 req/s)
ab -c 10 -n 1000 -t 60 http://localhost:8080/

# Expected: ~1000 requests in 60 seconds = 16.7 req/s per connection
# With 10 connections: 167 req/s total

# Test at 2x load (200 req/s)
ab -c 20 -n 2000 -t 60 http://localhost:8080/

# Test at 5x load (500 req/s)
ab -c 50 -n 5000 -t 60 http://localhost:8080/

# Check for errors
# Errors should remain < 0.1%
```

---

**Related**: [Availability Runbook](PHASE-8-AVAILABILITY-RUNBOOK.md), [Latency Runbook](PHASE-8-LATENCY-RUNBOOK.md), [Error Rate Runbook](PHASE-8-ERROR-RATE-RUNBOOK.md)
