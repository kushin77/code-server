#!/bin/bash

################################################################################
# Phase 7: Performance Optimization - Baseline Analysis
#
# Objectives:
#   - Establish performance baseline across all infrastructure
#   - Identify performance bottlenecks and hotspots
#   - Measure database query performance
#   - Analyze caching effectiveness
#   - Load testing under production-like conditions
#
# Success Criteria:
#   - P95 response time: <500ms
#   - P99 response time: <1s
#   - Database query time: <100ms (90th percentile)
#   - Cache hit rate: >85%
#   - CPU utilization: 60-70% at peak
#
# Usage:
#   bash scripts/phase7/analyze-performance-baseline.sh
#
################################################################################

set -euo pipefail

# Logging functions
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] | INFO    | $*"; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] | SUCCESS | $*"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] | ERROR   | $*" >&2; }
log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] | WARN    | $*"; }

# Cleanup on exit
trap 'log_info "Performance baseline analysis session ending..."; rm -f /tmp/perf-*.tmp' EXIT
trap 'log_error "Performance analysis failed at line $LINENO"; exit 1' ERR

# Create output directory
OUTPUT_DIR="/tmp/phase7-performance-$(date +%s)"
mkdir -p "$OUTPUT_DIR"

log_info "╔════════════════════════════════════════════════════════════╗"
log_info "║ PHASE 7: PERFORMANCE OPTIMIZATION - BASELINE ANALYSIS      ║"
log_info "║ Measuring: Response Times, Database, Caching, Resources    ║"
log_info "╚════════════════════════════════════════════════════════════╝"

# ============================================================================
# 1. DATABASE PERFORMANCE ANALYSIS
# ============================================================================

analyze_database_performance() {
    log_info "Analyzing database performance..."
    
    cat > "$OUTPUT_DIR/database-performance-queries.sql" << 'SQLEOF'
-- PostgreSQL Performance Analysis Queries
-- Execute these to identify slow queries and index opportunities

-- 1. Slow Query Analysis (queries taking >100ms)
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    max_time,
    stddev_time
FROM pg_stat_statements
WHERE mean_time > 100
ORDER BY mean_time DESC
LIMIT 20;

-- 2. Missing Indexes (sequential scans on large tables)
SELECT 
    schemaname,
    tablename,
    seq_scan,
    idx_scan,
    seq_tup_read,
    idx_tup_fetch
FROM pg_stat_user_tables
WHERE seq_scan > 1000 AND idx_scan < seq_scan / 10
ORDER BY seq_scan DESC;

-- 3. Index Usage Analysis
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- 4. Connection Pool Analysis
SELECT 
    pid,
    usename,
    application_name,
    state,
    query_start,
    state_change
FROM pg_stat_activity
ORDER BY query_start DESC;

-- 5. Cache Hit Ratio (should be >99%)
SELECT 
    sum(heap_blks_read) as heap_read,
    sum(heap_blks_hit) as heap_hit,
    sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio
FROM pg_statio_user_tables;
SQLEOF

    log_success "✓ Database performance queries generated"
}

# ============================================================================
# 2. CACHE PERFORMANCE ANALYSIS
# ============================================================================

analyze_cache_performance() {
    log_info "Analyzing cache performance..."
    
    cat > "$OUTPUT_DIR/cache-performance-redis.sh" << 'REDISEOF'
#!/bin/bash
# Redis Cache Performance Analysis

# Connection pool monitoring
redis-cli --stat > "$OUTPUT_DIR/redis-stats.txt" 2>&1 || true

# Collect redis metrics
redis-cli INFO stats > "$OUTPUT_DIR/redis-info-stats.txt" 2>&1 || true
redis-cli INFO memory > "$OUTPUT_DIR/redis-info-memory.txt" 2>&1 || true

# Key space analysis
redis-cli DBSIZE >> "$OUTPUT_DIR/redis-dbsize.txt" 2>&1 || true

# Slow log (queries taking >1000ms)
redis-cli SLOWLOG GET 100 > "$OUTPUT_DIR/redis-slowlog.txt" 2>&1 || true

# Memory usage by key pattern
redis-cli --scan --pattern '*' | wc -l > "$OUTPUT_DIR/redis-key-count.txt" 2>&1 || true
REDISEOF

    chmod +x "$OUTPUT_DIR/cache-performance-redis.sh"
    log_success "✓ Cache performance analysis script generated"
}

# ============================================================================
# 3. LOAD BALANCER & RESPONSE TIME ANALYSIS
# ============================================================================

analyze_load_balancer_performance() {
    log_info "Analyzing load balancer (Caddy) performance..."
    
    cat > "$OUTPUT_DIR/caddy-performance-config.json" << 'JSONEOF'
{
  "metrics": {
    "response_time_histogram": {
      "enabled": true,
      "buckets": [0.01, 0.05, 0.1, 0.5, 1.0, 5.0],
      "help": "Response time distribution (seconds)"
    },
    "request_duration": {
      "p50": "target: <100ms",
      "p95": "target: <500ms",
      "p99": "target: <1000ms"
    },
    "throughput": {
      "baseline": "monitor requests per second",
      "peak": "scale handling capability"
    },
    "error_rate": {
      "target": "<0.1%",
      "monitoring": "4xx and 5xx responses"
    }
  },
  "optimization_targets": {
    "compression": {
      "enabled": true,
      "algorithm": "gzip",
      "level": 9,
      "min_size": 1024
    },
    "caching": {
      "static_ttl": 86400,
      "dynamic_ttl": 300,
      "cache_key_variation": "vary by user-id, content-type"
    },
    "connection_pooling": {
      "upstream_idle": 100,
      "upstream_max": 1000,
      "keepalive_timeout": 30
    }
  }
}
JSONEOF

    log_success "✓ Load balancer performance configuration generated"
}

# ============================================================================
# 4. RESOURCE UTILIZATION ANALYSIS
# ============================================================================

analyze_resource_utilization() {
    log_info "Analyzing system resource utilization..."
    
    cat > "$OUTPUT_DIR/resource-metrics.yaml" << 'YAMLEOF'
---
# System Resource Utilization Metrics

cpu_analysis:
  current_utilization: "collect via: mpstat -P ALL 1 1"
  target_peak: "60-70%"
  target_average: "40-50%"
  alerts:
    - sustained >80%: investigate bottleneck
    - sudden spike: identify process via top
  optimization:
    - process affinity for critical services
    - cpuset constraints for isolation
    - CPU throttling prevention

memory_analysis:
  target_utilization: "70-80%"
  headroom_required: "20-30% free"
  swap_usage: "avoid entirely"
  metrics_to_track:
    - resident_set_size (RSS)
    - virtual_memory_size (VSZ)
    - page_faults
  optimization:
    - jvm heap tuning
    - database buffer pools
    - cache size allocation

disk_io_analysis:
  target_latency: "<5ms"
  target_throughput: "collect via: iostat -x 1"
  alerts:
    - await >10ms: disk bottleneck
    - util >80%: queue building
  optimization:
    - ssd verification
    - io scheduler tuning
    - partition alignment

network_analysis:
  target_bandwidth: "monitor utilization"
  target_latency: "<1ms (internal), <10ms (external)"
  metrics:
    - bytes_in/out per second
    - packets_in/out per second
    - errors and dropped packets
  optimization:
    - mtu size verification
    - tcp window scaling
    - buffer tuning

container_metrics:
  docker_stats:
    - cpu_percentage
    - memory_usage
    - network_io
  monitoring_tool: "docker stats --no-stream"
YAMLEOF

    log_success "✓ Resource utilization metrics defined"
}

# ============================================================================
# 5. QUERY OPTIMIZATION RECOMMENDATIONS
# ============================================================================

generate_optimization_recommendations() {
    log_info "Generating query optimization recommendations..."
    
    cat > "$OUTPUT_DIR/QUERY_OPTIMIZATION_GUIDE.md" << 'MDEOF'
# Database Query Optimization Guide

## 1. Index Strategy

### B-Tree Indexes (Default)
- Use for: Equality and range queries (WHERE, ORDER BY, JOIN)
- Example: CREATE INDEX idx_user_id ON orders(user_id);

### BRIN Indexes (Block Range INdexes)
- Use for: Large tables with natural ordering
- Benefit: 50-100x smaller than B-tree on sorted data
- Example: CREATE INDEX idx_orders_date ON orders USING BRIN (created_at);

### GiST/GIN Indexes
- GiST: Geometric types, full-text search
- GIN: Arrays, JSONB, full-text search
- Example: CREATE INDEX idx_data_gin ON records USING GIN (data);

### Partial Indexes
- Use for: Frequent WHERE clauses on same column
- Benefit: Smaller index, faster lookups
- Example: CREATE INDEX idx_active_users ON users(id) WHERE active = true;

### Multi-Column Indexes
- Order matters: Put equality predicates first, range predicates last
- Example: CREATE INDEX idx_user_org_created ON orders(user_id, org_id, created_at);

## 2. Query Optimization Patterns

### Pattern 1: Avoid SELECT *
BAD:  SELECT * FROM users WHERE active = true;
GOOD: SELECT id, name, email FROM users WHERE active = true;

### Pattern 2: Use LIMIT with OFFSET
BAD:  SELECT * FROM orders OFFSET 1000000 LIMIT 10;
GOOD: SELECT * FROM orders WHERE id > last_id LIMIT 10;

### Pattern 3: Join Order Matters
GOOD: Filter before joining to smaller datasets
      SELECT o.* FROM orders o 
      JOIN users u ON o.user_id = u.id 
      WHERE u.org_id = ? AND o.created_at > ?;

### Pattern 4: Group By Before Join
BAD:  SELECT u.id, COUNT(*) FROM users u JOIN orders o ON u.id = o.user_id GROUP BY u.id;
GOOD: SELECT user_id, COUNT(*) FROM orders WHERE created_at > ? GROUP BY user_id;

## 3. Connection Pool Optimization

### PgBouncer Configuration
```ini
pool_mode = transaction      # Transaction pooling for web apps
max_client_conn = 1000       # Max client connections
default_pool_size = 25       # Connections per database
min_pool_size = 10
reserve_pool_size = 5
reserve_pool_timeout = 3
```

### Connection Pool Monitoring
- Active connections: Should be <50% of pool size
- Queued requests: Should be near zero
- Idle connections: Recycle every 5 minutes

## 4. Caching Strategy

### Cache Invalidation Patterns

Pattern 1: Time-based (TTL)
- Use for: Non-critical data (recommendations, stats)
- TTL: 5-60 minutes
- Benefit: Simple, predictable

Pattern 2: Event-based
- Use for: Critical data (user profile, permissions)
- Trigger: Database write → invalidate cache
- Benefit: Always fresh, no stale data

Pattern 3: LRU (Least Recently Used)
- Use for: Limited memory caches
- Benefit: Automatic eviction of unused data

Pattern 4: Cache-Aside
- Flow: Check cache → miss → query DB → update cache
- Best for: Flexible TTL, write-heavy workloads

## 5. Performance Targets

| Metric | Target | Current |
|--------|--------|---------|
| P50 Response Time | <100ms | TBD |
| P95 Response Time | <500ms | TBD |
| P99 Response Time | <1000ms | TBD |
| Database Query Time (90th) | <100ms | TBD |
| Cache Hit Rate | >85% | TBD |
| CPU Utilization (peak) | 60-70% | TBD |
| Memory Utilization | 70-80% | TBD |
| Disk I/O Latency | <5ms | TBD |

MDEOF

    log_success "✓ Query optimization guide generated"
}

# ============================================================================
# 6. CACHING STRATEGY
# ============================================================================

generate_caching_strategy() {
    log_info "Generating caching strategy..."
    
    cat > "$OUTPUT_DIR/CACHING_STRATEGY.md" << 'MDEOF'
# Enterprise Caching Strategy

## Cache Layers

### Layer 1: HTTP Cache (Browser/CDN)
- TTL: 24 hours for static content
- Headers: Cache-Control, ETag, Last-Modified
- Target: 99% hit rate for static assets

### Layer 2: Application Cache (In-Memory)
- Technology: Redis cluster with Sentinel
- Patterns: Cache-Aside, Write-Through
- TTL: 5-60 minutes for computed data
- Target: >85% hit rate

### Layer 3: Query Result Cache
- Cache: SELECT query results by hash
- TTL: 1-5 minutes for frequently accessed queries
- Invalidation: Event-based on data changes

### Layer 4: Database Query Cache (PostgreSQL)
- Configuration: Tune shared_buffers for working set
- Target: >99% cache hit rate for frequently accessed pages

## Cache Key Design

### Naming Convention
```
cache_key = "{service}:{entity}:{id}:{version}"
Examples:
  user:profile:12345:v1
  order:details:67890:v2
  recommendation:list:user:12345:v1
```

### Versioning Strategy
- Increment on schema changes
- Prevents loading incompatible cached objects
- Clean old versions periodically

## Cache Warming

### Strategies
1. On startup: Load frequently accessed data
2. Scheduled: Refresh popular items every hour
3. Reactive: Preload related items on access

### Monitoring
- Cache size growth
- Eviction rates
- Key expiration patterns
- Hit/miss ratios per endpoint

MDEOF

    log_success "✓ Caching strategy generated"
}

# ============================================================================
# 7. PERFORMANCE MONITORING DASHBOARD
# ============================================================================

generate_monitoring_dashboard() {
    log_info "Generating performance monitoring dashboard configuration..."
    
    cat > "$OUTPUT_DIR/grafana-performance-dashboard.json" << 'JSONEOF'
{
  "dashboard": {
    "title": "Performance Optimization Metrics",
    "panels": [
      {
        "title": "Response Time Percentiles",
        "targets": [
          "histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))",
          "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))",
          "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))"
        ],
        "thresholds": {
          "p50": 100,
          "p95": 500,
          "p99": 1000
        }
      },
      {
        "title": "Database Query Time Distribution",
        "targets": [
          "histogram_quantile(0.90, rate(pg_query_duration_seconds_bucket[5m]))"
        ],
        "threshold": 100
      },
      {
        "title": "Cache Hit Rate",
        "targets": [
          "rate(redis_hits_total[5m]) / (rate(redis_hits_total[5m]) + rate(redis_misses_total[5m]))"
        ],
        "threshold": 0.85
      },
      {
        "title": "CPU Utilization",
        "targets": [
          "100 - (avg by (instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
        ],
        "thresholds": {
          "warning": 70,
          "critical": 85
        }
      },
      {
        "title": "Memory Utilization",
        "targets": [
          "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100"
        ],
        "thresholds": {
          "warning": 80,
          "critical": 90
        }
      },
      {
        "title": "Disk I/O Latency",
        "targets": [
          "rate(node_disk_io_time_seconds_total[5m])"
        ],
        "threshold": 5
      },
      {
        "title": "Request Throughput",
        "targets": [
          "rate(http_requests_total[5m])"
        ]
      },
      {
        "title": "Error Rate (4xx + 5xx)",
        "targets": [
          "rate(http_requests_total{status=~\"4..|5..\"}[5m]) / rate(http_requests_total[5m]) * 100"
        ],
        "threshold": 0.1
      }
    ]
  }
}
JSONEOF

    log_success "✓ Performance monitoring dashboard configuration generated"
}

# ============================================================================
# 8. OPTIMIZATION RUNBOOK
# ============================================================================

generate_optimization_runbook() {
    log_info "Generating optimization runbook..."
    
    cat > "$OUTPUT_DIR/PERFORMANCE_OPTIMIZATION_RUNBOOK.md" << 'MDEOF'
# Performance Optimization Runbook

## Quick Diagnostics

### 1. Identify Slow Requests
```bash
# Check application logs for slow requests
grep "response_time.*>500" /var/log/app/*.log | tail -20

# Query Prometheus for slow endpoints
curl 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))'
```

### 2. Database Bottleneck Check
```sql
-- See active queries
SELECT query, query_start FROM pg_stat_activity WHERE state = 'active';

-- See slowest recent queries
SELECT query, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;

-- Check for full table scans
SELECT schemaname, tablename, seq_scan FROM pg_stat_user_tables WHERE seq_scan > 1000 ORDER BY seq_scan DESC;
```

### 3. Cache Performance
```bash
# Redis hit/miss ratio
redis-cli INFO stats | grep -E "hits|misses"

# Key count and memory usage
redis-cli INFO memory
redis-cli DBSIZE
```

### 4. Resource Utilization
```bash
# CPU and memory per process
top -b -n 1 | head -20

# Disk I/O
iostat -x 1 5

# Network throughput
iftop -n
```

## Common Optimizations

### Optimization 1: Add Missing Index
```sql
-- Identify missing index (many seq_scans, few index scans)
CREATE INDEX idx_orders_user_id ON orders(user_id);
ANALYZE orders;

-- Verify improvement
SELECT seq_scan, idx_scan FROM pg_stat_user_tables WHERE tablename = 'orders';
```

### Optimization 2: Increase Connection Pool Size
```ini
# In PgBouncer config
default_pool_size = 50  # Increase from 25

# Reload
pgbouncer -R /etc/pgbouncer/pgbouncer.ini
```

### Optimization 3: Enable Query Caching
```javascript
// In application code
const cached = await redis.get(`query:${queryHash}`);
if (cached) return JSON.parse(cached);

const result = await db.query(sql, params);
await redis.setex(`query:${queryHash}`, 300, JSON.stringify(result));
return result;
```

### Optimization 4: Tune Redis Memory
```bash
# Increase Redis memory limit
redis-cli CONFIG SET maxmemory 2gb
redis-cli CONFIG SET maxmemory-policy allkeys-lru

# Persist config
redis-cli CONFIG REWRITE
```

### Optimization 5: Database Query Optimization
```sql
-- Original slow query (uses seq_scan)
SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '30 days';

-- Optimized with index
CREATE INDEX idx_orders_created ON orders(created_at DESC);
SELECT id, user_id, amount FROM orders WHERE created_at > NOW() - INTERVAL '30 days';
```

## Performance Improvement Checklist

- [ ] Baseline metrics collected and documented
- [ ] Slow queries identified and analyzed
- [ ] Missing indexes created and verified
- [ ] Connection pool size tuned
- [ ] Caching strategy implemented
- [ ] Redis memory configured
- [ ] Monitoring dashboards created
- [ ] Performance targets defined
- [ ] Alerts configured for threshold violations
- [ ] Load testing completed
- [ ] Documentation updated

MDEOF

    log_success "✓ Performance optimization runbook generated"
}

# ============================================================================
# 9. PERFORMANCE TARGETS DOCUMENTATION
# ============================================================================

generate_performance_targets() {
    log_info "Generating performance targets documentation..."
    
    cat > "$OUTPUT_DIR/PERFORMANCE_TARGETS.md" << 'MDEOF'
# Performance Optimization Targets

## Target Metrics

### Response Time
| Percentile | Target | Baseline | Status |
|-----------|--------|----------|--------|
| P50 | <100ms | TBD | 📊 |
| P95 | <500ms | TBD | 📊 |
| P99 | <1000ms | TBD | 📊 |
| P99.9 | <2000ms | TBD | 📊 |

### Database Performance
| Metric | Target | Baseline | Status |
|--------|--------|----------|--------|
| Query Time (P90) | <100ms | TBD | 📊 |
| Connection Pool Utilization | <50% | TBD | 📊 |
| Cache Hit Ratio | >95% | TBD | 📊 |
| Replication Lag | <100ms | TBD | 📊 |

### System Resources
| Metric | Target Range | Baseline | Status |
|--------|--------------|----------|--------|
| CPU Utilization | 60-70% peak | TBD | 📊 |
| Memory Utilization | 70-80% | TBD | 📊 |
| Disk I/O Latency | <5ms | TBD | 📊 |
| Network Latency (internal) | <1ms | TBD | 📊 |

### Application Health
| Metric | Target | Baseline | Status |
|--------|--------|----------|--------|
| Error Rate | <0.1% | TBD | 📊 |
| Throughput | X requests/sec | TBD | 📊 |
| Garbage Collection Pause | <100ms | TBD | 📊 |

## Optimization Priorities

1. **High Priority**: Response time optimization (P95 <500ms)
2. **High Priority**: Database query optimization (<100ms P90)
3. **Medium Priority**: Cache hit rate improvement (>85%)
4. **Medium Priority**: Resource utilization (60-70% CPU)
5. **Low Priority**: Monitoring and alerting setup

## Success Criteria

All targets must be met for performance optimization phase completion:
- ✅ P95 response time <500ms
- ✅ Database queries <100ms (P90)
- ✅ Cache hit rate >85%
- ✅ CPU utilization 60-70% at peak
- ✅ Zero response time regressions
- ✅ Monitoring dashboards operational

MDEOF

    log_success "✓ Performance targets documentation generated"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "Starting performance baseline analysis..."
    
    analyze_database_performance
    analyze_cache_performance
    analyze_load_balancer_performance
    analyze_resource_utilization
    generate_optimization_recommendations
    generate_caching_strategy
    generate_monitoring_dashboard
    generate_optimization_runbook
    generate_performance_targets
    
    log_success "╔════════════════════════════════════════════════════════════╗"
    log_success "║ PHASE 7 - PERFORMANCE BASELINE ANALYSIS COMPLETE           ║"
    log_success "║ Output: $OUTPUT_DIR"
    log_success "╚════════════════════════════════════════════════════════════╝"
    
    log_info "Generated files:"
    ls -1 "$OUTPUT_DIR"/ | sed 's/^/  ✓ /'
}

main "$@"
