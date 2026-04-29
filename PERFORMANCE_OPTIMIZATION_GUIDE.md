# Performance Optimization Guide - Phase 10

**Date**: April 29, 2026  
**Phase**: 10 (Performance Optimization)  
**Status**: 🟢 IMPLEMENTATION READY  

---

## Executive Summary

Phase 10 establishes comprehensive performance optimization procedures, baseline collection, and tuning guidelines for the ElevatedIQ platform.

### Performance Objectives
- Establish performance baselines and SLOs
- Identify and eliminate bottlenecks
- Implement caching and optimization strategies
- Provide load testing procedures
- Document tuning recommendations
- Enable continuous performance monitoring

---

## Phase 10A: Performance Baseline Collection

### System Metrics Collection

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/collect-performance-baseline.sh
# Collect comprehensive performance baseline

set -e

REPORT_DIR="/var/logs/performance-baseline"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$REPORT_DIR"

echo "Collecting performance baseline..."
echo "Timestamp: $TIMESTAMP"
echo ""

# CPU and Memory
echo "=== CPU Metrics ===" >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
nproc >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
grep "model name" /proc/cpuinfo | head -1 >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
top -bn1 | head -n 20 >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"

# Memory
echo "" >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
echo "=== Memory Metrics ===" >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
free -h >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"

# Disk
echo "" >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
echo "=== Disk Metrics ===" >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
df -h / >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"

# Docker
echo "" >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
echo "=== Docker Metrics ===" >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"

# Network
echo "" >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
echo "=== Network Metrics ===" >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"
ss -s >> "$REPORT_DIR/baseline_${TIMESTAMP}.txt"

echo "✅ Baseline collected: $REPORT_DIR/baseline_${TIMESTAMP}.txt"
```

### Database Performance Baseline

```sql
-- PostgreSQL performance baseline queries

-- Current connections
SELECT count(*) as active_connections FROM pg_stat_activity;

-- Cache hit ratio
SELECT 
  sum(heap_blks_read) as heap_read, 
  sum(heap_blks_hit) as heap_hit, 
  sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;

-- Index usage
SELECT 
  schemaname,
  tablename,
  indexname,
  idx_scan as number_of_scans,
  idx_tup_read as tuples_read,
  idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Slow queries
SELECT
  query,
  mean_exec_time,
  max_exec_time,
  calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Table sizes
SELECT 
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname != 'pg_catalog'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### Application Performance Baseline

```python
# Collect application metrics baseline

from prometheus_client import CollectorRegistry, Counter, Histogram, Gauge
import time

# Performance metrics
request_duration = Histogram(
    'request_duration_seconds',
    'Request duration',
    buckets=[0.01, 0.05, 0.1, 0.5, 1, 2, 5]
)

db_query_duration = Histogram(
    'db_query_duration_seconds',
    'Database query duration',
    buckets=[0.001, 0.01, 0.05, 0.1, 0.5]
)

cache_operations = Counter(
    'cache_operations_total',
    'Total cache operations',
    ['operation', 'result']
)

# Baseline metrics
def record_baseline():
    """Record application performance baseline"""
    baseline = {
        'avg_response_time': 0.1,  # seconds
        'p95_response_time': 0.5,
        'p99_response_time': 1.0,
        'error_rate': 0.001,       # < 0.1%
        'cache_hit_rate': 0.85,    # 85%
        'db_connection_pool_utilization': 0.5
    }
    return baseline
```

---

## Phase 10B: Bottleneck Identification

### Performance Profiling Tool

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/profile-bottlenecks.sh
# Identify performance bottlenecks

set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Performance Bottleneck Analysis                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

PRIMARY="192.168.168.31"
REPORT_DIR="/var/logs/performance-analysis"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$REPORT_DIR"

# Check CPU usage
echo "CPU Analysis:"
ssh akushnir@$PRIMARY top -bn1 | grep "Cpu(s)" | awk '{print "  CPU Usage:", $2}'

# Check Memory
echo "Memory Analysis:"
ssh akushnir@$PRIMARY free -h | awk 'NR==2 {printf "  Memory: %s used / %s total (%.1f%%)\n", $3, $2, $3/$2*100}'

# Check Disk I/O
echo "Disk I/O Analysis:"
ssh akushnir@$PRIMARY iostat -dx 1 2 | tail -10

# Check Network
echo "Network Analysis:"
ssh akushnir@$PRIMARY ss -s | grep -E "TCP:|UDP:"

# Database Performance
echo ""
echo "Database Performance:"
ssh akushnir@$PRIMARY docker exec code-server-postgres psql -U postgres -c \
  "SELECT
    mean_exec_time,
    query
   FROM pg_stat_statements
   ORDER BY mean_exec_time DESC
   LIMIT 5;" 2>/dev/null | head -15 || echo "  (database stats unavailable)"

# Container Resource Usage
echo ""
echo "Container Resource Usage:"
ssh akushnir@$PRIMARY docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -10

echo ""
echo "Report saved to: $REPORT_DIR/bottleneck_${TIMESTAMP}.txt"
```

### Slow Query Detection

```sql
-- Enable pg_stat_statements
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Reset statistics
SELECT pg_stat_statements_reset();

-- Run application workload for 5-10 minutes

-- Identify slow queries
SELECT
  query,
  calls,
  total_time,
  mean_time,
  max_time,
  stddev_time
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
  AND mean_time > 100  -- queries averaging > 100ms
ORDER BY mean_time DESC;
```

---

## Phase 10C: Caching Optimization

### Query Result Caching

```python
from functools import wraps
import redis
import json
import hashlib

redis_client = redis.from_url("redis://redis:6379/0")

def cache_query_result(ttl=3600):
    """Cache database query results"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            # Generate cache key from function and arguments
            key_data = f"{func.__name__}:{str(args)}:{str(kwargs)}"
            cache_key = f"query:{hashlib.md5(key_data.encode()).hexdigest()}"
            
            # Try cache
            cached = redis_client.get(cache_key)
            if cached:
                return json.loads(cached)
            
            # Execute function
            result = func(*args, **kwargs)
            
            # Store in cache
            redis_client.setex(cache_key, ttl, json.dumps(result, default=str))
            
            return result
        return wrapper
    return decorator

@cache_query_result(ttl=3600)
def get_user_profile(user_id):
    """Get user profile with caching"""
    # Database query
    pass
```

### Connection Pooling Optimization

```python
from sqlalchemy import create_engine
from sqlalchemy.pool import QueuePool
import os

# Optimized connection pool
engine = create_engine(
    os.getenv("DATABASE_URL"),
    poolclass=QueuePool,
    pool_size=10,          # Connections to keep in pool
    max_overflow=20,       # Additional connections if needed
    pool_recycle=3600,     # Recycle connections after 1 hour
    pool_pre_ping=True,    # Verify connections before use
    echo_pool=False,       # Disable debug output
    connect_args={
        "connect_timeout": 10,
        "statement_timeout": 30000,  # 30 second query timeout
    }
)

# Redis connection pooling
import redis
redis_pool = redis.ConnectionPool(
    host='redis',
    port=6379,
    db=0,
    max_connections=50,
    decode_responses=True
)
redis_client = redis.Redis(connection_pool=redis_pool)
```

### Batch Operations

```python
# Instead of N queries, use 1 batch query

# ❌ Slow: N queries
for user_id in user_ids:
    user = db.session.query(User).filter_by(id=user_id).first()
    process_user(user)

# ✅ Fast: 1 batch query
users = db.session.query(User).filter(User.id.in_(user_ids)).all()
for user in users:
    process_user(user)
```

---

## Phase 10D: Database Optimization

### Index Creation Strategy

```sql
-- Add indexes for frequently queried columns
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_logs_created_at ON logs(created_at);

-- Composite index for common filters
CREATE INDEX idx_orders_user_created ON orders(user_id, created_at DESC);

-- Partial index for common conditions
CREATE INDEX idx_active_users ON users(id) WHERE active = true;

-- Analyze index usage
ANALYZE;

SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

### Query Optimization

```sql
-- Use EXPLAIN ANALYZE to optimize queries

EXPLAIN ANALYZE
SELECT u.id, u.name, COUNT(o.id) as order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.created_at > NOW() - INTERVAL '30 days'
GROUP BY u.id, u.name;

-- Add index if needed
CREATE INDEX idx_orders_user_created_at 
ON orders(user_id, created_at);

-- Consider denormalization for high-volume queries
CREATE MATERIALIZED VIEW user_stats AS
SELECT
  user_id,
  COUNT(*) as order_count,
  SUM(total) as total_spent
FROM orders
WHERE created_at > NOW() - INTERVAL '90 days'
GROUP BY user_id;

REFRESH MATERIALIZED VIEW user_stats;
```

---

## Phase 10E: Load Testing

### Apache JMeter Load Test Plan

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/run-load-test.sh
# Execute load testing with Apache JMeter

set -e

echo "Setting up load testing environment..."

# Install JMeter if not present
if ! command -v jmeter &> /dev/null; then
  echo "Installing Apache JMeter..."
  apt-get update && apt-get install -y jmeter
fi

# Create test plan
cat > /tmp/load-test-plan.jmx << 'JMETER_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan">
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments"/>
      <stringProp name="TestPlan.name">ElevatedIQ Load Test</stringProp>
    </TestPlan>
    <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup">
      <elementProp name="ThreadGroup.main_controller" elementType="LoopController">
        <stringProp name="LoopController.loops">10</stringProp>
      </elementProp>
      <stringProp name="ThreadGroup.num_threads">50</stringProp>
      <stringProp name="ThreadGroup.ramp_time">60</stringProp>
    </ThreadGroup>
    <HTTPSampler guiclass="HttpTestSampleGui" testclass="HTTPSampler">
      <stringProp name="HTTPSampler.domain">192.168.168.31</stringProp>
      <stringProp name="HTTPSampler.path">/health</stringProp>
      <stringProp name="HTTPSampler.protocol">http</stringProp>
      <stringProp name="HTTPSampler.port">8080</stringProp>
    </HTTPSampler>
  </hashTree>
</jmeterTestPlan>
JMETER_EOF

# Run load test
echo "Running load test (50 threads, 600 requests)..."
jmeter -n -t /tmp/load-test-plan.jmx -l /tmp/results.jtl -j /tmp/jmeter.log

# Analyze results
echo ""
echo "Load Test Results:"
grep -E "Throughput|Average|Median" /tmp/jmeter.log || true

echo "✅ Load test complete"
```

### k6 Load Testing

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 50,
  duration: '10m',
  thresholds: {
    http_req_duration: ['p(95)<200', 'p(99)<500'],
    http_req_failed: ['rate<0.1'],
  },
};

export default function () {
  // Test health endpoint
  let res = http.get('http://192.168.168.31:8080/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 200ms': (r) => r.timings.duration < 200,
  });

  sleep(1);

  // Test API endpoint
  res = http.get('http://192.168.168.31:8080/api/v1/status');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(1);
}
```

---

## Phase 10F: Performance Tuning

### Linux Kernel Tuning

```bash
#!/bin/bash
# /home/akushnir/code-server/scripts/ops/tune-kernel-parameters.sh

# TCP tuning for high throughput
sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535
sysctl -w net.ipv4.ip_local_port_range="1024 65535"

# Connection pooling
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.tcp_fin_timeout=30

# Memory tuning
sysctl -w vm.swappiness=10
sysctl -w vm.dirty_ratio=15
sysctl -w vm.dirty_background_ratio=5

# Persistence
echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 65535" >> /etc/sysctl.conf

sysctl -p
```

### Docker Container Tuning

```yaml
# Optimized container resource limits
services:
  application:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
    
    # CPU affinity (pin to specific cores)
    cpuset: '0-1'
    
    # Memory limits
    environment:
      - JAVA_OPTS=-Xms1G -Xmx1G
      - NODE_OPTIONS=--max-old-space-size=1024
```

### Database Configuration Tuning

```ini
# PostgreSQL - postgresql.conf tuning

# Memory allocation
shared_buffers = 256MB           # 25% of total RAM for dedicated server
effective_cache_size = 1GB       # Total RAM available to DB
maintenance_work_mem = 64MB      # For VACUUM, CREATE INDEX

# Connection settings
max_connections = 200
max_prepared_transactions = 100

# Query planning
random_page_cost = 1.1           # For SSD storage
effective_io_concurrency = 200

# WAL settings (if using replication)
wal_buffers = 16MB
min_wal_size = 1GB
max_wal_size = 2GB

# Checkpoint tuning
checkpoint_timeout = 15min
checkpoint_completion_target = 0.9

# Logging for performance analysis
log_min_duration_statement = 1000  # Log queries > 1 second
log_statement = 'mod'              # Log DML statements
```

---

## Phase 10G: Performance Monitoring

### Prometheus Performance Queries

```promql
# Request latency percentiles
histogram_quantile(0.95, rate(request_duration_seconds_bucket[5m]))
histogram_quantile(0.99, rate(request_duration_seconds_bucket[5m]))

# Error rate
rate(request_failures_total[5m])

# Throughput
rate(requests_total[1m])

# CPU usage
rate(container_cpu_usage_seconds_total[5m]) * 100

# Memory usage
container_memory_usage_bytes / 1024 / 1024

# Database connection pool utilization
active_db_connections / max_db_connections
```

### SLO Definition

```markdown
# Performance Service Level Objectives (SLOs)

## Response Time SLOs
- p50 (median): < 100ms
- p95: < 200ms
- p99: < 500ms

## Throughput SLOs
- Minimum: 1000 requests/second
- Sustained: > 500 requests/second

## Error Rate SLOs
- Target: < 0.1% error rate
- Critical: > 1% error rate triggers alert

## Availability SLOs
- Availability: 99.9% (43.2 minutes downtime/month)
- Health check success: > 99.99%

## Database SLOs
- Query p95: < 100ms
- Connection pool utilization: < 80%
- Replication lag: < 100ms
```

---

## Phase 10H: Performance Recommendations

### Caching Strategy
✅ Cache frequently accessed data (>10 requests/sec)
✅ Use TTL-based expiration (balance freshness vs load)
✅ Implement cache warming for critical data
✅ Monitor cache hit rates (target: > 80%)

### Database Strategy
✅ Add indexes for filtered columns
✅ Use composite indexes for common query patterns
✅ Archive old data (>1 year) to separate tables
✅ Regular VACUUM and ANALYZE
✅ Monitor slow queries (> 1 second)

### Application Strategy
✅ Implement connection pooling
✅ Use batch operations where possible
✅ Async/background processing for long operations
✅ Circuit breaker pattern for external dependencies
✅ Request debouncing and deduplication

### Infrastructure Strategy
✅ Horizontal scaling for stateless services
✅ Load balancing across instances
✅ CDN for static content
✅ Database read replicas for reporting
✅ Separate analytics workloads

---

## Phase 10I: Performance Troubleshooting Guide

### High CPU Usage
1. Check top processes: `top -o %CPU`
2. Identify slow queries: `pg_stat_statements`
3. Look for inefficient loops in code
4. Check for lock contention in database

### High Memory Usage
1. Check container memory: `docker stats`
2. Check memory leaks in application
3. Review cache TTL settings
4. Look for unbounded data structures

### Slow Response Times
1. Check database latency: `pg_stat_statements`
2. Check cache hit rates
3. Review network latency
4. Check for resource contention

### Connection Pool Issues
1. Monitor active connections: `SELECT count(*) FROM pg_stat_activity`
2. Check for long-running transactions
3. Verify pool configuration
4. Check for connection leaks

---

## Summary

Phase 10 provides:
- ✅ Performance baseline collection procedures
- ✅ Bottleneck identification tools and processes
- ✅ Caching optimization strategies
- ✅ Database optimization guidelines
- ✅ Load testing procedures
- ✅ Performance tuning configurations
- ✅ SLO definitions and monitoring
- ✅ Troubleshooting guides

**Status**: 🟢 PHASE 10 IMPLEMENTATION READY

---

**Next Phase Options:**
1. Phase 11 - Multi-region Deployment
2. Phase 12 - Advanced Features
3. Phase 13+ - Extended Capabilities

