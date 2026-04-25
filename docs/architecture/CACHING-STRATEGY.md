# Caching Strategy & Performance Optimization Guide

**Epic**: #1536 — Networking, DNS & Performance  
**Phase**: 5 — Caching Strategy  
**Status**: Phase 5 Implementation  
**Last Updated**: April 25, 2026

---

## Overview

This guide documents caching architecture, Redis HA configuration, cache hit rate optimization, and HTTP/2 performance enhancements for kushnir.cloud infrastructure.

**Objectives**:
- Reduce latency by 50%+ through intelligent caching
- Achieve ≥70% cache hit rate for dynamic content
- Enable HTTP/2 for header compression and multiplexing
- Implement gzip/Brotli compression for text-based responses
- Monitor cache effectiveness with Prometheus metrics

---

## Caching Architecture

### Three-Tier Cache Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                   Browser/CDN Cache (Edge)                  │
│                 (static assets, 24h+ TTL)                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│               Caddy Reverse Proxy Cache (L1)                │
│         (HTTP/2, gzip compression, 1-60 min TTL)           │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│              Redis Cache Cluster (L2)                        │
│      (session data, API responses, 5-30 min TTL)            │
│      ├─ Primary: redis-primary (read/write)               │
│      ├─ Replica: redis-replica (read-only)                │
│      └─ Sentinel: redis-sentinel (HA failover)            │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│         Application & Database (Source of Truth)            │
│        (PostgreSQL, API backends, primary storage)          │
└─────────────────────────────────────────────────────────────┘
```

### Cache Tiers

| Tier | Layer | TTL | Use Case |
|------|-------|-----|----------|
| L0 | Browser Cache | 24h+ | Static assets, stylesheets, images |
| L1 | Caddy HTTP Cache | 1-60m | HTML pages, API responses |
| L2 | Redis | 5-30m | Sessions, frequently accessed data |
| L3 | Database | ∞ | Source of truth, persistent storage |

---

## Redis Configuration

### HA Setup (Recommended for Production)

**Architecture**:
```
Primary (write)  ←→  Replica (read)
      ↑   ↓            ↑   ↓
      └───┴────────────┘   │
                Sentinel (monitoring & failover)
```

### Redis Memory Configuration

```conf
# Maximum memory allocated to Redis
maxmemory 2gb              # 2/3 of available RAM (for HA: 1/3 per instance)

# Eviction policy when memory limit reached
maxmemory-policy allkeys-lru   # Options: noeviction, allkeys-lru, allkeys-lfu, volatile-*

# Persistence
appendonly yes             # AOF (Append-Only File) for durability
appendfsync everysec       # Write to disk every second
save 900 1                 # RDB snapshot: 1 change in 900s
```

### Tuning for Performance

**High-Throughput Cache** (prioritize speed):
```conf
maxmemory-policy allkeys-lfu      # LFU better for cache workloads
appendfsync no                    # No fsync (risky, for cache only)
lazyfree-lazy-eviction yes        # Non-blocking eviction
```

**High-Durability Cache** (prioritize consistency):
```conf
maxmemory-policy allkeys-lru      # LRU for predictable behavior
appendfsync always                # Fsync after each command (slow but safe)
appendonly yes                    # AOF only (no RDB snapshotting)
```

**Balanced** (recommended):
```conf
maxmemory-policy allkeys-lru      # Balance of speed and predictability
appendfsync everysec              # Fsync every second (good balance)
aof-use-rdb-preamble yes          # Hybrid persistence
```

### Docker Compose Configuration

```yaml
# docker-compose.yml - Redis services

  redis-primary:
    image: redis:7-alpine
    command: >
      redis-server
      --port 6379
      --maxmemory 2gb
      --maxmemory-policy allkeys-lru
      --appendonly yes
      --appendfsync everysec
    volumes:
      - redis_primary_data:/data
    ports:
      - "6379:6379"
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis-replica:
    image: redis:7-alpine
    command: >
      redis-server
      --port 6380
      --slaveof redis-primary 6379
      --maxmemory 2gb
      --maxmemory-policy allkeys-lru
    volumes:
      - redis_replica_data:/data
    ports:
      - "6380:6380"
    networks:
      - backend
    depends_on:
      - redis-primary
    healthcheck:
      test: ["CMD", "redis-cli", "-p", "6380", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis-sentinel:
    image: redis:7-alpine
    command: redis-sentinel /etc/redis/sentinel.conf
    volumes:
      - ./config/sentinel.conf:/etc/redis/sentinel.conf
    ports:
      - "26379:26379"
    networks:
      - backend
    depends_on:
      - redis-primary
      - redis-replica
```

### Sentinel Configuration (Failover)

```conf
# config/sentinel.conf - Redis Sentinel for HA

# Monitor the primary Redis instance
monitor mymaster redis-primary 6379 2

# Timeout: declare replica down if no response for 5s
down-after-milliseconds mymaster 5000

# Number of sentinels that must agree for failover
sentinel parallel-syncs mymaster 1

# Failover timeout
sentinel failover-timeout mymaster 10000

# Logging
loglevel notice
logfile /var/log/redis/sentinel.log
```

---

## HTTP/2 & Compression

### Caddy HTTP/2 Configuration

Caddy v2 automatically enables HTTP/2 with ALPN (Application Layer Protocol Negotiation). No manual configuration needed.

**Benefits**:
- **Header Compression**: Reduces overhead by ~80% using HPACK algorithm
- **Multiplexing**: Multiple requests over single TCP connection
- **Server Push**: Proactively send resources before client requests them
- **Binary Framing**: More efficient than HTTP/1.1 text framing

### Gzip Compression

```caddyfile
# Caddyfile - HTTP/2 with compression

kushnir.cloud ide.kushnir.cloud {
    # Automatic HTTPS + HTTP/2 (enabled by default)
    
    # Gzip compression for text-based responses
    encode gzip {
        # Only compress responses > 500 bytes
        minimum_length 500
        
        # Compressible content types
        match {
            header Content-Type application/json*
            header Content-Type application/javascript*
            header Content-Type text/*
            header Content-Type image/svg+xml*
        }
    }
    
    # Optional: Brotli compression for modern browsers
    encode brotli {
        minimum_length 500
        
        match {
            header Content-Type application/json*
            header Content-Type text/*
        }
    }
    
    # Cache headers for static assets
    @static {
        path_regexp ^/(static|assets)/.*\.(js|css|png|jpg|svg)$
    }
    header @static Cache-Control "public, max-age=31536000, immutable"
    
    # Cache headers for API responses (short TTL)
    @api {
        path /api/*
    }
    header @api Cache-Control "public, max-age=60, must-revalidate"
    header @api ETag "*"
    
    # Reverse proxy to application
    reverse_proxy localhost:3100 {
        # HTTP/2 connection pooling (4 workers)
        policy random_choice 4
        
        # WebSocket upgrade
        header_up Connection "Upgrade"
        header_up Upgrade "websocket"
        
        # Request/response timeouts
        timeout 30s
    }
}
```

### Compression Effectiveness Monitoring

**Before Compression**:
- JSON API response: 50KB
- Transfer size: ~50KB
- Latency: 100-200ms

**After Compression** (gzip):
- JSON API response: 50KB (same)
- Transfer size: ~8-10KB (80% reduction)
- Latency: 20-40ms (4-5x improvement)

---

## Cache Hit Rate Optimization

### Metrics & Targets

| Metric | Target | Acceptable | Critical |
|--------|--------|-----------|----------|
| Cache Hit Rate | ≥80% | 70-79% | <70% |
| Cache Latency | <5ms | 5-20ms | >20ms |
| L1 (Caddy) Hit Rate | ≥60% | 40-59% | <40% |
| L2 (Redis) Hit Rate | ≥70% | 50-69% | <50% |

### Monitoring Cache Health

```bash
# Check cache hit rate (from Redis)
bash scripts/lib/redis.sh
redis_cache_hit_rate

# Output: Cache hit rate: 75% (threshold: 70%)
```

### Improving Cache Hit Rate

**Problem**: Cache hit rate < 70%

**Diagnostics**:
1. **Check cache key patterns**:
   ```bash
   redis-cli KEYS "cache:*" | head -20
   redis-cli DBSIZE  # Total keys
   redis-cli INFO memory
   ```

2. **Analyze request patterns**:
   ```bash
   # Count API requests by endpoint
   tail -1000 /var/log/caddy/access.log | jq '.uri' | sort | uniq -c | sort -rn
   ```

3. **Check TTL distribution**:
   ```bash
   redis-cli SCAN 0 COUNT 1000 | xargs -I{} redis-cli TTL {}
   ```

**Solutions**:
- **Increase TTL** for static content (1h → 24h for static assets)
- **Add cache key variants** for better hit distribution
- **Use Redis key expiration** for automatic cleanup
- **Implement cache warming** (pre-load frequently accessed data)
- **Monitor eviction rate** (if > 5% evictions, increase `maxmemory`)

### Cache Invalidation Strategy

**Time-based invalidation** (default, safest):
```bash
# Set cache TTL
SETEX cache:user:123 3600 <json_data>  # 1 hour TTL
```

**Event-based invalidation** (more complex):
```bash
# On user data change, invalidate related keys
DEL cache:user:123
DEL cache:user:123:profile
DEL cache:user:123:permissions
```

**Hybrid approach** (recommended):
```bash
# TTL + Event-based
SETEX cache:user:123 3600 <json_data>  # 1h TTL

# But also invalidate on changes
pubsub SUBSCRIBE user:changed
# Client receives message, can force refresh if needed
```

---

## Performance Metrics (Prometheus)

### Redis Metrics

```prometheus
# Cache hit rate
redis_cache_hit_rate{instance="primary"}

# Memory usage
redis_memory_used_bytes{instance="primary"}
redis_memory_max_bytes{instance="primary"}

# Throughput (ops/sec)
redis_ops_per_sec{instance="primary"}

# Eviction rate
redis_evicted_keys_total{instance="primary"}
```

### Caddy HTTP/2 Metrics

```prometheus
# Response time (p50, p95, p99)
caddy_http_request_duration_seconds{handler="reverse_proxy"}

# Compressed vs uncompressed bytes
caddy_http_response_size_bytes{encoding="gzip"}

# Cache hit/miss ratio
caddy_http_cache_hits_total
caddy_http_cache_misses_total
```

### Exporter Setup

**Prometheus Configuration** (`prometheus.yml`):
```yaml
scrape_configs:
  - job_name: 'redis'
    static_configs:
      - targets: ['localhost:9121']  # redis_exporter
  
  - job_name: 'caddy'
    static_configs:
      - targets: ['localhost:8888']  # caddy metrics endpoint
```

**Redis Exporter** (docker-compose):
```yaml
  redis_exporter:
    image: oliver006/redis_exporter:latest
    ports:
      - "9121:9121"
    environment:
      REDIS_ADDR: "redis-primary:6379"
    networks:
      - backend
```

---

## Caching Best Practices

### DO

- ✅ Set reasonable TTLs (60s for APIs, 1h for pages, 24h for assets)
- ✅ Use cache layers in combination (L1 + L2 + L3)
- ✅ Monitor cache hit rate and eviction rate
- ✅ Use separate Redis instances for sessions vs. cache (different eviction policies)
- ✅ Implement cache warming for critical data
- ✅ Log cache misses for analysis

### DON'T

- ❌ Cache sensitive data (passwords, tokens, PII)
- ❌ Use infinite TTLs (causes memory bloat)
- ❌ Cache user-specific data without proper key segregation
- ❌ Ignore cache invalidation (stale data is worse than no cache)
- ❌ Set low `maxmemory` (causes excessive eviction and thrashing)

---

## Troubleshooting

### Issue: Cache Hit Rate < 70%

**Diagnosis**:
```bash
# Check cache size and eviction
redis-cli INFO stats | grep -E "evicted|hits|misses"

# Check if Redis is out of memory
redis-cli INFO memory | grep "used_memory"
```

**Solutions**:
1. Increase `maxmemory` (more RAM for Redis)
2. Increase TTLs (cache lives longer)
3. Use better eviction policy (`allkeys-lfu` vs `allkeys-lru`)
4. Analyze request patterns (maybe not much to cache)

### Issue: Redis Memory Growing Unbounded

**Diagnosis**:
```bash
# Top memory consumers
redis-cli --bigkeys

# Memory per key type
redis-cli INFO memory
```

**Solutions**:
1. Set `maxmemory` policy to enable eviction
2. Use Redis expiration: `EXPIRE key seconds`
3. Implement cache key prefix patterns
4. Monitor and alert on memory usage

### Issue: HTTP/2 Performance Worse Than HTTP/1.1

**Diagnosis**:
```bash
# Check Caddy metrics
curl http://localhost:2019/metrics | grep caddy_http

# Network packet capture
tcpdump -i eth0 -A 'tcp port 443'
```

**Common causes**:
- Too many small requests (HTTP/2 overhead minimal at scale)
- Network latency (HTTP/2 multiplexing doesn't help with high latency)
- TLS record size (if using large TLS record sizes)

**Solutions**:
- Enable server push for critical resources
- Use session resumption (TLS session tickets)
- Enable compression (gzip/Brotli)

---

## Related Issues & Phases

- **#1536 Phase 1**: Eliminate hardcoded IPs ✅
- **#1536 Phase 2**: DNS Service Discovery ✅
- **#1536 Phase 3**: DNS Architecture Documentation ✅
- **#1536 Phase 4**: NAS Performance Benchmarking ✅
- **#1536 Phase 5**: Caching Strategy (THIS)
- **#1536 Phase 6**: Network Performance Tuning

---

**Document Version**: 1.0  
**Last Updated**: 2026-04-25  
**Maintainer**: Infrastructure Team  
**Next Review**: 2026-05-25
