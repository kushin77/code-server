# Performance Optimization & Tuning Guide

**Document Version**: 1.0  
**Last Updated**: April 29, 2026  
**Status**: READY FOR OPERATIONS  
**Maintained By**: Operations Team / Performance Engineer  

---

## Executive Summary

This guide provides optimization procedures to maximize platform performance while maintaining stability. Topics include:
- ✅ PostgreSQL query optimization
- ✅ Database indexing strategies
- ✅ Connection pooling configuration
- ✅ Caching optimization
- ✅ Network optimization
- ✅ CPU/Memory tuning
- ✅ Baseline and benchmark procedures

**Current Performance Baselines**:
- API Response Time: 100-150ms (p95 < 200ms)
- Query Latency: 20-50ms (p99 < 100ms)
- Cache Hit Ratio: 98%+
- Error Rate: < 0.05%
- CPU Utilization: 50-65% average
- Memory Utilization: 55-65% average

---

## Part 1: PostgreSQL Optimization

### 1.1 Query Performance Tuning

**Step 1: Identify Slow Queries**

```sql
-- View top 10 slowest queries
SELECT 
  query,
  calls,
  total_time,
  mean_time,
  max_time,
  stddev_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- Result interpretation:
-- - mean_time > 1000 (ms) = Slow query
-- - max_time > 5000 = Outlier query
-- - calls > 1000 with high mean = Frequently slow query
```

**Step 2: Analyze Execution Plan**

```sql
-- Understand query execution
EXPLAIN ANALYZE SELECT ... /* paste slow query */;

-- Look for:
-- - Seq Scan (full table scan) = missing index
-- - Sort nodes = missing index or inefficient join order
-- - Hash Join on large tables = memory pressure
-- - High total cost = inefficient query plan

-- Optimization opportunities:
-- > 10,000: Critical (rewrite or index)
-- > 1,000: High priority (optimize soon)
-- > 100: Medium priority (monitor)
-- < 100: Acceptable
```

**Step 3: Create Missing Indexes**

```sql
-- Find missing indexes
SELECT schemaname, tablename, indexname 
FROM pg_indexes 
WHERE tablename = 'your_table'
ORDER BY indexname;

-- Create index on frequently filtered column
CREATE INDEX CONCURRENTLY idx_table_column 
  ON public.table_name(column_name) 
  WHERE active = true;
  -- CONCURRENTLY: doesn't lock table during creation

-- Validate index created
SELECT * FROM pg_stat_user_indexes 
WHERE relname = 'idx_table_column';
-- idx_scan > 0 means index is being used
-- idx_tup_read should be << idx_tup_fetch (high selectivity)
```

**Step 4: Update Table Statistics**

```sql
-- Vacuum and analyze tables
VACUUM ANALYZE public.large_table;
-- VACUUM: removes dead tuples, reclaims space
-- ANALYZE: updates planner statistics (improves query plans)

-- Check table bloat
SELECT 
  schemaname, 
  tablename,
  round((n_dead_tup::float / (n_live_tup + n_dead_tup) * 100)::numeric, 2) as dead_ratio
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY dead_ratio DESC;
-- If dead_ratio > 10%, run VACUUM FULL (requires exclusive lock)
```

### 1.2 Connection Pooling

**Purpose**: Reuse database connections instead of creating new ones

**Current Configuration**:
```yaml
# docker-compose.enterprise.yml
services:
  code-server-postgres:
    environment:
      POSTGRES_INITDB_ARGS: |
        -c max_connections=100
        -c max_wal_senders=10
```

**Implement PgBouncer** (connection pool):

```yaml
# Add pgbouncer service to docker-compose.enterprise.yml
services:
  pgbouncer:
    image: pgbouncer:1.17
    ports:
      - "6432:6432"
    environment:
      PGBOUNCER_ADMIN_USERS: postgres
      PGBOUNCER_USERS: replication:password
    volumes:
      - ./pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini
    depends_on:
      - code-server-postgres
```

**PgBouncer Configuration** (`pgbouncer.ini`):

```ini
[databases]
code_server_db = host=code-server-postgres port=5432 dbname=code_server_db

[pgbouncer]
pool_mode = transaction  # Reuse connections per transaction
max_client_conn = 1000
default_pool_size = 25
min_pool_size = 10
reserve_pool_size = 5
reserve_pool_timeout = 3
max_db_connections = 100
max_user_connections = 100
server_lifetime = 3600
server_idle_timeout = 600
```

**Benefits**:
- Reduced connection overhead (~100x)
- Better resource utilization
- Faster query execution
- Improved under load

### 1.3 Buffer Cache Optimization

```sql
-- Tune shared_buffers (cache for table/index pages)
-- Current: 16 GB
-- Tuning: 25% of RAM (recommended)

-- For 64 GB RAM: shared_buffers = 16 GB ✓ (current is optimal)

-- Check cache efficiency
SELECT 
  sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit) as heap_hit,
  sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;
-- Ratio > 99% = good cache usage
-- Ratio < 90% = increase shared_buffers or reduce queries

-- Tune work_mem (temporary memory per sort/hash operation)
-- Current: 64 MB
-- Tuning: RAM / (num_connections * 2)
-- For 64 GB, 100 connections: 64 GB / 200 = 327 MB (conservative: 256 MB)

ALTER SYSTEM SET work_mem = '256MB';
```

---

## Part 2: Redis Optimization

### 2.1 Memory Optimization

```bash
# Check Redis memory usage breakdown
docker exec code-server-redis redis-cli INFO memory

# Output interpretation:
# used_memory: 3.5 GB (actual memory used)
# used_memory_human: 3.5G
# peak_memory: 4.0 GB (peak usage)
# mem_fragmentation_ratio: 1.05 (1.0 = good, >1.2 = fragmentation issue)

# If fragmentation ratio > 1.3:
docker exec code-server-redis redis-cli MEMORY DOCTOR
# Provides recommendations
```

### 2.2 Eviction Policy

```bash
# Check current eviction policy
docker exec code-server-redis redis-cli CONFIG GET maxmemory-policy

# Set eviction policy (best for cache data)
docker exec code-server-redis redis-cli CONFIG SET maxmemory-policy 'allkeys-lru'
# allkeys-lru: Evict least recently used keys
# volatile-lru: Evict LRU keys with TTL
# volatile-ttl: Evict keys by TTL (soonest expiring)

# Persist config
docker exec code-server-redis redis-cli CONFIG REWRITE
```

### 2.3 Slow Log Monitoring

```bash
# Get slow Redis commands
docker exec code-server-redis redis-cli SLOWLOG GET 10

# Output:
# 1) ID
# 2) Timestamp
# 3) Duration (microseconds)
# 4) Command

# Result interpretation:
# Duration > 10,000 microseconds (10ms) = slow
# Common culprits: KEYS *, FLUSHDB, SCAN on large dataset
```

---

## Part 3: Network Optimization

### 3.1 Network Latency Tuning

```bash
# Measure latency between hosts
for i in {1..100}; do ping -c 1 -W 1 192.168.168.42; done | \
  grep 'time=' | awk -F'time=' '{print $2}' | \
  awk '{sum+=$1; count++} END {print "Avg: " sum/count " ms"}'

# Target: < 2 ms (local network)
# Warning: 2-5 ms (acceptable)
# Critical: > 10 ms (investigate network)
```

### 3.2 Bandwidth Optimization

```bash
# Check network utilization
docker stats --no-stream --format 'table {{.Container}}\t{{.NetIO}}'

# Optimize replication bandwidth
# On primary:
ALTER SYSTEM SET wal_compression = 'on';
# Compresses WAL, reduces replication bandwidth ~50%

# Reload PostgreSQL
docker restart code-server-postgres
```

### 3.3 TCP Tuning

```bash
# Optimize TCP windows for replication
ssh akushnir@192.168.168.31 "
sudo sysctl -w net.ipv4.tcp_window_scaling=1
sudo sysctl -w net.ipv4.tcp_rmem='4096 87380 33554432'
sudo sysctl -w net.ipv4.tcp_wmem='4096 65536 33554432'
"

# Make persistent
echo 'net.ipv4.tcp_window_scaling=1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem=4096 87380 33554432' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem=4096 65536 33554432' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## Part 4: CPU & Memory Optimization

### 4.1 CPU Utilization

**Current Baseline**:
```
Primary: 12/16 cores allocated (75%)
Replica: 13/16 cores allocated (81%)
Average: 50-65% usage
```

**Optimization**:
```bash
# Check CPU utilization per container
docker stats --no-stream --format 'table {{.Container}}\t{{.CPUPerc}}' | \
  sort -t '%' -k2 -rn | head -10

# If uneven distribution:
# - Container A: 40%
# - Container B: 8%
# - Container C: 5%

# Option 1: Move Container A to another host
# Option 2: Implement CPU limits for heavy services
# Option 3: Optimize application code (reduce CPU usage)
```

### 4.2 Memory Tuning

**Current Baseline**:
```
Primary: ~35 GB / 64 GB (55%)
Replica: ~36 GB / 64 GB (56%)
Headroom: 29 GB available
```

**Optimization**:
```bash
# Identify high memory containers
docker stats --no-stream --format 'table {{.Container}}\t{{.MemUsage}}\t{{.MemLimit}}' | \
  sort -t 'G' -k2 -rn | head -10

# If container near limit:
# Option 1: Increase container memory limit
docker-compose -f docker-compose.enterprise.yml down
# Edit docker-compose.enterprise.yml (increase mem_limit)
docker-compose -f docker-compose.enterprise.yml up -d

# Option 2: Reduce cache sizes in application
# Option 3: Enable swap (last resort)
```

---

## Part 5: Caching Strategy

### 5.1 Redis Cache Tuning

```bash
# Monitor cache effectiveness
docker exec code-server-redis redis-cli INFO stats

# Key metrics:
# keyspace_hits: Cache hits
# keyspace_misses: Cache misses
# evicted_keys: Keys removed due to memory pressure

# Calculate hit ratio
HITS=1000
MISSES=50
RATIO=$((HITS * 100 / (HITS + MISSES)))
echo "Cache hit ratio: $RATIO%" 

# Target: 95%+
# < 90%: Increase cache size or optimize cache key strategy
```

### 5.2 HTTP Caching (Caddy)

```caddy
# Caddyfile optimization for caching
{
  cache {
    rule {
      path /api/public/*
      default_max_age 1h
      default_max_stale 24h
    }
  }
}

# Browser caching headers
handle /api/public/* {
  header Cache-Control "public, max-age=3600"
}

handle /api/dynamic/* {
  header Cache-Control "no-cache, must-revalidate"
}
```

---

## Part 6: Baseline & Benchmarking

### 6.1 Establish Performance Baseline

**Day 1 After Deployment**:

```bash
#!/bin/bash
# baseline_performance.sh

echo "=== Performance Baseline Snapshot ===" | tee baseline-$(date +%Y%m%d).log

# Database metrics
docker exec code-server-postgres psql -U postgres -c '
  SELECT 
    datname,
    pg_database_size(datname) / 1024 / 1024 / 1024 as size_gb,
    numbackends as connections
  FROM pg_stat_database;
' | tee -a baseline-$(date +%Y%m%d).log

# Query performance baseline
docker exec code-server-postgres psql -U postgres -c '
  SELECT 
    query,
    mean_time as mean_ms,
    calls
  FROM pg_stat_statements
  WHERE calls > 100
  ORDER BY mean_time DESC
  LIMIT 20;
' | tee -a baseline-$(date +%Y%m%d).log

# System resources baseline
docker stats --no-stream | tee -a baseline-$(date +%Y%m%d).log
df -h | tee -a baseline-$(date +%Y%m%d).log
free -h | tee -a baseline-$(date +%Y%m%d).log

# Redis baseline
docker exec code-server-redis redis-cli INFO stats | tee -a baseline-$(date +%Y%m%d).log

echo "✅ Baseline snapshot complete" | tee -a baseline-$(date +%Y%m%d).log
```

### 6.2 Benchmark Tests

**Load Testing Procedure**:

```bash
# Use hey for HTTP benchmarking
# Install: go get -u github.com/rakyll/hey

# Load test endpoint (e.g., API health check)
hey -n 10000 -c 100 -m GET http://192.168.168.31:8086/health

# Output interpretation:
# - Average latency: current state
# - 95th percentile: worst case
# - Requests/sec: throughput
# - Status distribution: error rate

# Compare against baseline
# If latency +50% → investigate (query change, data growth, etc.)
```

### 6.3 Monthly Performance Report

```
MONTHLY PERFORMANCE REPORT - APRIL 2026
========================================

Database Performance:
- Average query latency: 45 ms (baseline: 42 ms)
- 95th percentile: 180 ms (target: 200 ms)
- 99th percentile: 420 ms (baseline: 400 ms)
- Replication lag: avg 2.1 sec (target: <5 sec)
- Cache hit ratio: 98.5% (baseline: 98.3%)

API Performance:
- Average response time: 125 ms (baseline: 120 ms)
- 95th percentile: 185 ms (target: 200 ms)
- Throughput: 1,250 req/sec (baseline: 1,240 req/sec)
- Error rate: 0.03% (target: <0.1%)

Resource Utilization:
- Average CPU: 58% (baseline: 55%)
- Average memory: 60% (baseline: 58%)
- Disk usage: 42% (baseline: 40%)
- Network: 52% (baseline: 48%)

Trends:
✅ Query latency: STABLE
✅ API throughput: +0.8% (normal growth)
⚠️  Memory usage: +3% (monitor)
✅ Replication lag: STABLE

Recommendations:
1. Database optimization completed (new index on users table)
2. Continue monitoring memory trend
3. Scale to 3rd host if CPU > 70% sustained

Sign-off: _____________________ Date: __________
```

---

## Part 7: Performance Tuning Checklist

**Monthly Performance Review**:

```
PERFORMANCE OPTIMIZATION CHECKLIST
==================================

Database:
- [ ] Run ANALYZE on all tables (update statistics)
- [ ] Check for slow queries (> 1s mean_time)
- [ ] Review index usage (unused indexes can be dropped)
- [ ] Check table bloat (vacuum if > 10% dead tuples)
- [ ] Verify replication lag < 5 seconds
- [ ] Review query cache hit ratio (target > 95%)

Cache:
- [ ] Check Redis memory usage (< 80% of limit)
- [ ] Review cache hit ratio (target > 95%)
- [ ] Clear expired keys (MEMORY DOCTOR)
- [ ] Verify eviction policy appropriate

Network:
- [ ] Check latency between hosts (< 2 ms)
- [ ] Verify bandwidth usage (< 70%)
- [ ] Review replication bandwidth (optimize if high)
- [ ] Check for packet loss (< 0.1%)

System:
- [ ] CPU utilization (target 50-70%)
- [ ] Memory utilization (target 50-75%)
- [ ] Disk I/O latency (< 5 ms 95th percentile)
- [ ] Disk space (maintain > 20% free)

Applications:
- [ ] API response time (target < 200ms p95)
- [ ] Error rate (target < 0.1%)
- [ ] Container restart frequency (target 0 per day)
- [ ] Active connections trending (watch for leaks)

Completed By: _____________________ Date: __________
Issues Found: (describe any)
_________________________________________________________
Actions Taken: (describe fixes)
_________________________________________________________

Sign-off: _____________________ Date: __________
```

---

## Quick Reference: Common Tuning Parameters

| Parameter | Current | Recommended | Impact |
|-----------|---------|-------------|--------|
| shared_buffers | 16 GB | 16 GB | Moderate |
| work_mem | 64 MB | 256 MB | Moderate |
| max_connections | 100 | 100 | Low |
| wal_compression | off | on | High |
| max_wal_senders | 10 | 10 | Low |
| Redis maxmemory | 8 GB | 8 GB | High |
| PgBouncer pool_size | N/A | 25 | High |
| Caddy cache_age | N/A | 1h | Moderate |

**Apply Changes**:
```bash
# 1. Stop services
docker-compose -f docker-compose.enterprise.yml down

# 2. Update docker-compose.enterprise.yml

# 3. Restart services
docker-compose -f docker-compose.enterprise.yml up -d

# 4. Verify changes
docker exec code-server-postgres psql -U postgres -c 'SHOW shared_buffers;'
```

---

**Document History**

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | April 29, 2026 | Initial performance optimization guide |

---

**Related Documents**:
- MONITORING_OBSERVABILITY_GUIDE.md (Detect performance issues)
- CAPACITY_PLANNING_SCALING_GUIDE.md (When to scale)
- ADVANCED_TROUBLESHOOTING_SCENARIOS.md (Diagnosis)
