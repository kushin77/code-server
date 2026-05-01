#!/bin/bash

#############################################################################
# Phase 12: Performance Tuning & Caching Strategy
#
# Purpose: Optimize platform performance through intelligent caching,
#          query optimization, connection pooling, and resource tuning
#
# Features:
#   - Redis distributed caching
#   - Query result caching
#   - HTTP caching headers
#   - Connection pooling (PgBouncer)
#   - Database query optimization
#   - CPU/Memory tuning
#   - Cache invalidation strategies
#   - Performance monitoring
#############################################################################

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="/var/log/configure-performance-tuning.log"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performance tuning complete"; exit 0' EXIT

log_info() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2; }
log_section() { echo "" | tee -a "$LOG_FILE"; echo "======== $1 ========" | tee -a "$LOG_FILE"; }

#############################################################################
# Redis Distributed Caching
#############################################################################

create_redis_caching_config() {
  log_section "Creating Redis distributed caching configuration"
  
  cat > "${REPO_ROOT}/config/redis-caching-strategy.yaml" << 'REDIS_CONFIG'
redis_caching:
  cluster_mode: true
  sentinel_enabled: true
  
  cache_layers:
    # Layer 1: Application-level cache (fast, in-process)
    layer_1_local:
      type: "in-memory"
      ttl_seconds: 60
      max_entries: 10000
      eviction_policy: "lru"
      targets:
        - "frequently accessed configs"
        - "session tokens"
        - "user preferences"
    
    # Layer 2: Distributed Redis cache (shared across instances)
    layer_2_redis:
      type: "redis-distributed"
      ttl_seconds: 300
      max_memory_mb: 2048
      eviction_policy: "allkeys-lru"
      targets:
        - "API responses"
        - "database query results"
        - "computed analytics"
        - "user profiles"
    
    # Layer 3: Database (source of truth)
    layer_3_database:
      type: "postgresql"
      query_cache_ttl: 3600

  cache_keys:
    # API response caching
    api_responses:
      pattern: "api:v1:{endpoint}:{params}"
      ttl: 300
      invalidate_on: ["POST", "PUT", "DELETE"]
      conditions:
        - "GET requests only"
        - "status == 200"
        - "no Authorization header"
    
    # User profile caching
    user_profiles:
      pattern: "user:{user_id}:profile"
      ttl: 600
      invalidate_on: ["profile_update", "user_logout"]
    
    # Data set caching
    data_queries:
      pattern: "data:{query_hash}"
      ttl: 1800
      invalidate_on: ["data_change", "ETL_complete"]
    
    # Analytics caching
    analytics:
      pattern: "analytics:{metric}:{period}"
      ttl: 3600
      invalidate_on: ["daily_close", "manual_refresh"]

  invalidation_strategies:
    # Time-based invalidation (TTL)
    time_based:
      enabled: true
      aggressive_ttl: 60        # Fast-changing data
      moderate_ttl: 300         # Regular data
      conservative_ttl: 3600    # Slow-changing data
    
    # Event-based invalidation
    event_based:
      enabled: true
      triggers:
        - "database_write"
        - "file_upload"
        - "configuration_change"
      action: "invalidate_related_keys"
    
    # Manual invalidation (admin)
    manual:
      enabled: true
      endpoints:
        - "POST /admin/cache/invalidate/{key}"
        - "POST /admin/cache/clear"

  connection_pooling:
    min_connections: 10
    max_connections: 50
    connection_timeout_ms: 5000
    idle_timeout_ms: 300000

  monitoring:
    metrics:
      - "cache_hit_rate"
      - "cache_miss_rate"
      - "eviction_count"
      - "memory_usage"
      - "connection_pool_utilization"

REDIS_CONFIG

  log_info "Redis caching strategy created"
}

#############################################################################
# Database Query Optimization
#############################################################################

create_database_optimization() {
  log_section "Creating database optimization configuration"
  
  cat > "${REPO_ROOT}/config/postgresql-optimization.conf" << 'PG_OPT'
# PostgreSQL Performance Optimization

# Connection pooling
max_connections = 200
superuser_reserved_connections = 10

# Memory configuration (for 8GB instance)
shared_buffers = 2GB              # 25% of system RAM
effective_cache_size = 6GB        # 75% of system RAM
work_mem = 50MB                   # Per operation memory
maintenance_work_mem = 512MB      # VACUUM, CREATE INDEX

# WAL (Write-Ahead Log) tuning
wal_buffers = 16MB
wal_level = replica
max_wal_senders = 10
wal_keep_size = 1GB

# Query execution
random_page_cost = 1.1            # SSD cost model
effective_io_concurrency = 200
parallel_workers_per_gather = 4
max_parallel_workers = 4
max_parallel_maintenance_workers = 4

# Autovacuum tuning
autovacuum = on
autovacuum_max_workers = 4
autovacuum_naptime = 30s
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_scale_factor = 0.02

# Statistics
default_statistics_target = 100
track_activities = on
track_counts = on

# Logging (for performance analysis)
log_min_duration_statement = 1000  # Log queries > 1 second
log_statement = 'mod'              # Log DML statements
log_duration = on
log_lock_waits = on

PG_OPT

  log_info "PostgreSQL optimization configuration created"
}

#############################################################################
# PgBouncer Connection Pooling
#############################################################################

create_pgbouncer_config() {
  log_section "Creating PgBouncer connection pooling configuration"
  
  cat > "${REPO_ROOT}/config/pgbouncer.ini" << 'PGBOUNCER_CONFIG'
[databases]
# Database connection strings
postgres = host=postgres port=5432 dbname=postgres
code_server = host=postgres port=5432 dbname=code_server
analytics = host=postgres port=5432 dbname=analytics

[pgbouncer]
# PgBouncer configuration
listen_port = 6432
listen_addr = 0.0.0.0
auth_file = /etc/pgbouncer/userlist.txt
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/pgbouncer/pgbouncer.pid

# Connection pooling
pool_mode = transaction          # Transaction-level pooling (most compatible)
max_client_conn = 1000           # Max client connections
default_pool_size = 25           # Connections per database
min_pool_size = 10               # Min connections to keep
reserve_pool_size = 5            # Reserved for timeout handling
reserve_pool_timeout = 3         # Timeout for reserve pool

# Connection lifecycle
server_lifetime = 3600           # Max connection age (seconds)
server_idle_timeout = 600        # Close idle connections
connection_lifetime = 300        # Time before reconnect

# Performance
server_connect_timeout = 15      # Connect timeout
query_timeout = 0                # Query timeout (0 = no limit)
query_wait_timeout = 120         # Wait for available connection

# Advanced
tcp_keepalives = 1
tcp_keepidles = 30
tcp_keepintvl = 30
tcp_user_timeout = 0

# Logging
verbose = 0
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1

PGBOUNCER_CONFIG

  log_info "PgBouncer configuration created"
}

#############################################################################
# HTTP Caching Headers Configuration
#############################################################################

create_http_caching_config() {
  log_section "Creating HTTP caching headers configuration"
  
  cat > "${REPO_ROOT}/config/http-caching-headers.nginx" << 'HTTP_CACHE'
# HTTP Caching Headers for Nginx

# Static content (images, CSS, JS)
location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf)$ {
    expires 30d;
    add_header Cache-Control "public, immutable, max-age=2592000";
    add_header ETag "W/\"${msie}\"";
}

# HTML files (update frequently)
location ~* \.html$ {
    expires 1h;
    add_header Cache-Control "public, max-age=3600, must-revalidate";
    add_header ETag "W/\"${msie}\"";
}

# API endpoints (conditional caching)
location ~ ^/api/v1/ {
    # Conditional caching based on request method
    if ($request_method = GET) {
        add_header Cache-Control "public, max-age=300, must-revalidate";
        add_header Vary "Accept-Encoding, Authorization";
    }
    
    if ($request_method != GET) {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
    }
}

# Private user data (never cache)
location ~ ^/api/v1/user/ {
    add_header Cache-Control "private, no-cache, no-store, must-revalidate";
    add_header Pragma "no-cache";
    add_header Expires "0";
}

# Health checks (no cache)
location /health {
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header Pragma "no-cache";
}

# Default (private cache)
add_header Cache-Control "private, max-age=0, must-revalidate";

HTTP_CACHE

  log_info "HTTP caching headers configuration created"
}

#############################################################################
# Performance Monitoring Configuration
#############################################################################

create_performance_monitoring() {
  log_section "Creating performance monitoring configuration"
  
  cat > "${REPO_ROOT}/config/prometheus-performance.rules" << 'PERF_RULES'
groups:
  - name: performance_metrics
    interval: 30s
    rules:
      # Cache hit ratio
      - record: cache:hit_ratio
        expr: |
          redis_keyspace_hits_total / 
          (redis_keyspace_hits_total + redis_keyspace_misses_total)

      # Query latency
      - record: db:query:p95_latency_ms
        expr: |
          histogram_quantile(0.95, 
            rate(pg_sql_query_duration_seconds_bucket[5m])) * 1000

      # Connection pool utilization
      - record: db:connection:pool_utilization
        expr: |
          pgbouncer_pools_client_active_connections / 
          pgbouncer_pools_pool_size

      # Cache memory usage
      - record: redis:memory:usage_percent
        expr: |
          (redis_memory_used_bytes / redis_memory_max_bytes) * 100

      # Request processing time
      - record: http:request:p95_duration_ms
        expr: |
          histogram_quantile(0.95, 
            rate(http_request_duration_seconds_bucket[5m])) * 1000

      # Alert: High cache miss rate
      - alert: HighCacheMissRate
        expr: cache:hit_ratio < 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Cache hit ratio below 50%"

      # Alert: High query latency
      - alert: HighQueryLatency
        expr: db:query:p95_latency_ms > 1000
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "95th percentile query latency > 1 second"

PERF_RULES

  log_info "Performance monitoring configuration created"
}

#############################################################################
# Tuning Recommendations Script
#############################################################################

create_tuning_recommendations() {
  log_section "Creating performance tuning recommendations"
  
  cat > "${REPO_ROOT}/scripts/generate-performance-recommendations.py" << 'TUNING_PY'
#!/usr/bin/env python3
"""
Generate performance tuning recommendations based on metrics.
"""

import json
from datetime import datetime

class PerformanceOptimizer:
    def __init__(self):
        self.recommendations = []
        self.total_improvement = 0
    
    def analyze_cache_performance(self, hit_ratio, memory_usage):
        """Recommend cache optimizations"""
        if hit_ratio < 0.5:
            self.recommendations.append({
                "category": "Caching",
                "priority": "high",
                "action": "Increase cache TTLs and memory allocation",
                "current_hit_ratio": f"{hit_ratio:.2%}",
                "target_hit_ratio": "80%+",
                "expected_improvement": "30-50% faster responses",
                "implementation_effort": "2 hours",
                "performance_gain": 35
            })
            self.total_improvement += 35
        
        if memory_usage > 0.85:
            self.recommendations.append({
                "category": "Caching",
                "priority": "medium",
                "action": "Implement cache eviction policy (LRU)",
                "current_memory": f"{memory_usage:.1%}",
                "optimization": "Prevent OOM, maintain hit ratio",
                "expected_improvement": "Prevent memory pressure",
                "implementation_effort": "1 hour"
            })
    
    def analyze_database_performance(self, query_latency_p95, pool_util):
        """Recommend database optimizations"""
        if query_latency_p95 > 1000:
            self.recommendations.append({
                "category": "Database",
                "priority": "high",
                "action": "Create missing indexes and analyze query plans",
                "current_p95_latency": f"{query_latency_p95}ms",
                "target_p95_latency": "<200ms",
                "expected_improvement": "5-10x faster queries",
                "implementation_effort": "4 hours",
                "performance_gain": 60
            })
            self.total_improvement += 60
        
        if pool_util > 0.9:
            self.recommendations.append({
                "category": "Database",
                "priority": "high",
                "action": "Increase connection pool size or enable PgBouncer",
                "current_pool_utilization": f"{pool_util:.1%}",
                "optimization": "Reduce connection wait times",
                "expected_improvement": "Eliminate connection timeouts",
                "implementation_effort": "1 hour",
                "performance_gain": 40
            })
            self.total_improvement += 40
    
    def analyze_http_performance(self, response_time_p95):
        """Recommend HTTP optimizations"""
        if response_time_p95 > 500:
            self.recommendations.append({
                "category": "HTTP",
                "priority": "medium",
                "action": "Enable HTTP caching headers and CDN",
                "current_p95_latency": f"{response_time_p95}ms",
                "target_p95_latency": "<100ms",
                "expected_improvement": "5x faster response times",
                "implementation_effort": "2 hours",
                "performance_gain": 80
            })
            self.total_improvement += 80
    
    def generate_report(self):
        """Generate performance optimization report"""
        return {
            "generated_at": datetime.now().isoformat(),
            "recommendations": sorted(
                self.recommendations,
                key=lambda x: x.get("performance_gain", 0),
                reverse=True
            ),
            "summary": {
                "total_recommendations": len(self.recommendations),
                "total_performance_improvement": f"{self.total_improvement}%",
                "critical_actions": sum(
                    1 for r in self.recommendations if r["priority"] == "high"
                ),
                "estimated_implementation_time_hours": 10
            }
        }

if __name__ == '__main__':
    optimizer = PerformanceOptimizer()
    optimizer.analyze_cache_performance(hit_ratio=0.45, memory_usage=0.82)
    optimizer.analyze_database_performance(query_latency_p95=850, pool_util=0.88)
    optimizer.analyze_http_performance(response_time_p95=450)
    
    report = optimizer.generate_report()
    print(json.dumps(report, indent=2))

TUNING_PY

  chmod +x "${REPO_ROOT}/scripts/generate-performance-recommendations.py"
  log_info "Performance recommendations script created"
}

#############################################################################
# Main Execution
#############################################################################

main() {
  log_section "Phase 12: Performance Tuning & Caching Strategy"
  
  create_redis_caching_config
  create_database_optimization
  create_pgbouncer_config
  create_http_caching_config
  create_performance_monitoring
  create_tuning_recommendations
  
  log_section "Phase 12 Configuration Complete"
}

main
