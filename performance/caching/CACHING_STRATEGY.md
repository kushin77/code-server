# Caching Strategy for On-Premises Deployments

**Phase**: 10 - On-Premises Performance Optimization  
**Focus**: Multi-layer caching architecture for resource-constrained environments  
**Target**: Reduce database load, minimize latency, enable offline-capable operation

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Client Layer                             │
│  Browser Cache (HTTP Cache Headers)                         │
└────────────────────┬────────────────────────────────────────┘
                     │ (HTTP requests)
┌────────────────────▼────────────────────────────────────────┐
│              Proxy/CDN Layer                                │
│  Varnish/Tinyproxy (full-page caching)                      │
│  - Cache-Control headers                                    │
│  - ETag validation                                          │
│  - Gzip compression                                         │
└────────────────────┬────────────────────────────────────────┘
                     │ (cache miss)
┌────────────────────▼────────────────────────────────────────┐
│             Application Layer                               │
│  In-Memory Cache (FastAPI, Node.js)                         │
│  - Request memoization                                      │
│  - Computed results caching                                 │
│  - Session cache (10 minutes)                               │
└────────────────────┬────────────────────────────────────────┘
                     │ (cache miss)
┌────────────────────▼────────────────────────────────────────┐
│              Redis Cache Layer                              │
│  Distributed Cache (multi-replica)                          │
│  - Semantic embeddings cache (24h TTL)                      │
│  - API response cache (1h TTL)                              │
│  - Session store (rolling 24h)                              │
│  - LRU eviction when memory full                            │
└────────────────────┬────────────────────────────────────────┘
                     │ (cache miss)
┌────────────────────▼────────────────────────────────────────┐
│            Database Layer                                   │
│  PostgreSQL with Query Optimization                         │
│  - Query result caching (temporary)                         │
│  - Prepared statements                                      │
│  - Connection pooling (PgBouncer)                           │
│  - B-tree and GiST indexes                                  │
└────────────────────┬────────────────────────────────────────┘
                     │ (miss)
┌────────────────────▼────────────────────────────────────────┐
│           Filesystem/Storage Layer                          │
│  Local Node Cache                                           │
│  - Kubernetes emptyDir or local volumes                     │
│  - Model cache (transformers, embeddings)                   │
│  - Intermediate computation cache                           │
└─────────────────────────────────────────────────────────────┘
```

## Layer 1: Client-Side Caching

### HTTP Cache Headers
```http
# For static assets (1 year)
Cache-Control: public, max-age=31536000, immutable
ETag: "abc123"

# For API responses (1 hour)
Cache-Control: public, max-age=3600
ETag: "response-v1"
Vary: Accept-Encoding, Authorization

# For user data (no cache)
Cache-Control: private, no-cache, no-store, must-revalidate
Pragma: no-cache
Expires: 0
```

### Client-Side Implementation (JavaScript)
```javascript
// Service Worker for offline capability
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open('code-server-v1').then(cache => {
      return cache.addAll([
        '/',
        '/css/main.css',
        '/js/app.js',
        '/api/health'  // For offline detection
      ]);
    })
  );
});

// Network-first strategy for API calls
self.addEventListener('fetch', event => {
  if (event.request.url.includes('/api/')) {
    event.respondWith(
      fetch(event.request)
        .then(response => {
          // Cache successful responses
          const clone = response.clone();
          caches.open('api-v1').then(cache => {
            cache.put(event.request, clone);
          });
          return response;
        })
        .catch(() => {
          // Fall back to cache on network failure
          return caches.match(event.request);
        })
    );
  }
});

// IndexedDB for structured data
const db = new Promise(resolve => {
  const request = indexedDB.open('code-server-db', 1);
  request.onupgradeneeded = event => {
    const db = event.target.result;
    db.createObjectStore('embeddings', { keyPath: 'id' });
    db.createObjectStore('sessions', { keyPath: 'sessionId' });
  };
  request.onsuccess = () => resolve(request.result);
});
```

## Layer 2: Proxy/CDN Caching

### Varnish Configuration (on-premises)
```vcl
# /etc/varnish/default.vcl
backend code_server {
  .host = "code-server.code-server.svc.cluster.local";
  .port = "8443";
  .connect_timeout = 5s;
  .first_byte_timeout = 10s;
  .between_bytes_timeout = 5s;
}

sub vcl_recv {
  # Remove cookies from static requests
  if (req.url ~ "^/static/") {
    unset req.http.Cookie;
  }
  
  # Cache GET/HEAD requests only
  if (req.method != "GET" && req.method != "HEAD") {
    return (pass);
  }
  
  # Bypass cache for authenticated requests
  if (req.http.Authorization || req.http.X-Custom-Auth) {
    return (pass);
  }
}

sub vcl_backend_response {
  # Cache successful responses
  if (beresp.status == 200) {
    set beresp.ttl = 1h;
    set beresp.keep = 1d;
  }
  
  # Don't cache private data
  if (beresp.http.Cache-Control ~ "private|no-cache|no-store") {
    return (deliver);
  }
  
  # Set grace period for stale responses
  set beresp.grace = 6h;
}

sub vcl_deliver {
  # Add cache status header (for debugging)
  if (obj.hits > 0) {
    set resp.http.X-Varnish-Cache = "HIT";
  } else {
    set resp.http.X-Varnish-Cache = "MISS";
  }
}
```

### Docker Deployment (Varnish)
```dockerfile
# Dockerfile.varnish
FROM varnish:7.0
COPY default.vcl /etc/varnish/default.vcl
EXPOSE 6081
CMD ["varnishd", "-f", "/etc/varnish/default.vcl", "-a", "0.0.0.0:6081", "-F"]
```

## Layer 3: Application-Level Caching

### FastAPI (Agent API & Embeddings)
```python
from fastapi import FastAPI
from functools import lru_cache
from datetime import timedelta
import time

app = FastAPI()

# Simple in-memory cache with TTL
cache_store = {}

def cached(ttl_seconds: int = 300):
    def decorator(func):
        async def wrapper(*args, **kwargs):
            cache_key = f"{func.__name__}:{args}:{kwargs}"
            
            if cache_key in cache_store:
                cached_value, expiry = cache_store[cache_key]
                if time.time() < expiry:
                    return cached_value
                else:
                    del cache_store[cache_key]
            
            result = await func(*args, **kwargs)
            cache_store[cache_key] = (result, time.time() + ttl_seconds)
            return result
        
        return wrapper
    return decorator

@app.get("/embeddings")
@cached(ttl_seconds=3600)  # Cache for 1 hour
async def get_embeddings(text: str):
    # Expensive computation (Hugging Face model)
    embeddings = compute_embeddings(text)
    return {"embeddings": embeddings}

# Cleanup expired cache entries every hour
@app.on_event("startup")
async def cleanup_cache():
    while True:
        await asyncio.sleep(3600)
        now = time.time()
        expired_keys = [
            k for k, (_, expiry) in cache_store.items()
            if now > expiry
        ]
        for key in expired_keys:
            del cache_store[key]
```

### Node.js (Code Server)
```javascript
// Cache middleware
const NodeCache = require('node-cache');
const cache = new NodeCache({ stdTTL: 300, checkperiod: 60 });

app.use((req, res, next) => {
  const cacheKey = `${req.method}:${req.url}`;
  
  // Skip cache for mutations
  if (req.method !== 'GET') {
    return next();
  }
  
  const cached = cache.get(cacheKey);
  if (cached) {
    return res.json(cached);
  }
  
  // Capture original response.json
  const originalJson = res.json.bind(res);
  res.json = function(body) {
    cache.set(cacheKey, body);
    return originalJson(body);
  };
  
  next();
});
```

## Layer 4: Redis Distributed Cache

### Redis Configuration (on-premises)
```conf
# redis.conf for on-premises
port 6379
bind 0.0.0.0
maxmemory 2gb
maxmemory-policy allkeys-lru

# Persistence (RDB)
save 900 1      # Save if 1 key changed in 900 seconds
save 300 10     # Save if 10 keys changed in 300 seconds
save 60 10000   # Save if 10k keys changed in 60 seconds
appendonly yes
appendfsync everysec

# Replication (for HA)
min-slaves-to-write 1
min-slaves-max-lag 10

# Slow log
slowlog-log-slower-than 10000  # 10ms
slowlog-max-len 128

# Memory optimization
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
```

### Python Redis Wrapper
```python
import redis
from typing import Any, Optional
import hashlib
import json

class CacheManager:
    def __init__(self, redis_url: str = "redis://localhost:6379/0"):
        self.redis = redis.from_url(redis_url)
    
    def get(self, key: str) -> Optional[Any]:
        """Get value from cache"""
        value = self.redis.get(key)
        if value:
            return json.loads(value)
        return None
    
    def set(self, key: str, value: Any, ttl: int = 3600):
        """Set value in cache with TTL"""
        self.redis.setex(
            key,
            ttl,
            json.dumps(value, default=str)
        )
    
    def cached(self, ttl: int = 3600):
        """Decorator for function-level caching"""
        def decorator(func):
            async def wrapper(*args, **kwargs):
                # Generate cache key from function name and arguments
                key_parts = [
                    func.__name__,
                    str(args),
                    str(sorted(kwargs.items()))
                ]
                cache_key = hashlib.md5(
                    ''.join(key_parts).encode()
                ).hexdigest()
                
                # Try to get from cache
                cached_value = self.get(cache_key)
                if cached_value:
                    return cached_value
                
                # Execute function
                result = await func(*args, **kwargs)
                
                # Store in cache
                self.set(cache_key, result, ttl)
                
                return result
            
            return wrapper
        return decorator

# Usage
cache = CacheManager()

@cache.cached(ttl=86400)  # 24 hours for embeddings
async def get_embeddings(text: str):
    return await embeddings_service.embed(text)

# Manual cache management
cache.set("user:123:preferences", {"theme": "dark"}, ttl=3600)
preferences = cache.get("user:123:preferences")
```

## Layer 5: Database Query Optimization

### PostgreSQL Query Cache Strategy
```sql
-- Create materialized view for frequently accessed data
CREATE MATERIALIZED VIEW embeddings_cache AS
SELECT 
  id,
  text_hash,
  embedding_vector,
  created_at
FROM embeddings
WHERE created_at > NOW() - INTERVAL '7 days'
AND cached = true;

-- Index for fast lookup
CREATE INDEX idx_embeddings_cache_hash ON embeddings_cache(text_hash);

-- Refresh materialized view periodically (via cron)
-- REFRESH MATERIALIZED VIEW CONCURRENTLY embeddings_cache;

-- Query with cache-first strategy
SELECT * FROM embeddings_cache 
WHERE text_hash = md5($1)
LIMIT 1;

-- If not in cache, query main table
SELECT * FROM embeddings 
WHERE text_hash = md5($1)
LIMIT 1;
```

### Connection Pooling (PgBouncer)
```ini
# pgbouncer.ini
[databases]
code_server = host=postgres port=5432 dbname=code_server

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
min_pool_size = 10
reserve_pool_size = 5
reserve_pool_timeout = 3
server_lifetime = 3600
server_idle_timeout = 600
batch_size = 5
```

## Layer 6: Filesystem Cache

### Local Node Storage (Kubernetes)
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: embeddings-with-cache
spec:
  containers:
  - name: embeddings
    image: embeddings:latest
    volumeMounts:
    - name: model-cache
      mountPath: /home/app/.cache/huggingface
    - name: embedding-cache
      mountPath: /tmp/embeddings-cache
  volumes:
  - name: model-cache
    emptyDir:
      sizeLimit: 10Gi  # Cache size limit
  - name: embedding-cache
    emptyDir:
      sizeLimit: 5Gi
```

### Environment Variables
```bash
# Cache configuration
export HF_HOME=/home/app/.cache/huggingface  # Hugging Face model cache
export EMBEDDING_CACHE_DIR=/tmp/embeddings-cache
export EMBEDDING_CACHE_MAX_SIZE=5242880000   # 5GB in bytes
```

## Performance Metrics

### Cache Hit Ratios (Target)
```
Client Cache (Browser):     95%  (static assets)
Proxy Cache (Varnish):      70%  (API responses)
Application Cache:          80%  (computed results)
Redis Cache:                85%  (embeddings and sessions)
Database Cache:             60%  (query results)
Overall Effective:          92%  (weighted average)
```

### Cache Invalidation Strategy
```
Cache Type          TTL           Invalidation Trigger
─────────────────────────────────────────────────────
Static Assets       1 year        Manual (hash in URL)
API Responses       1 hour        Time-based
Embeddings          24 hours      Time-based OR content hash change
Sessions            24 hours      Logout or inactivity
User Data           5 min         On UPDATE/DELETE
DB Queries          15 min        On relevant table write
```

## Configuration for Different Hardware

### Small Deployment (4 CPU, 8GB RAM)
```yaml
redis:
  maxmemory: 1gb
  maxmemory-policy: allkeys-lru
  
varnish:
  -s malloc,256m  # 256MB memory
  
postgresql:
  shared_buffers: 512MB
  effective_cache_size: 1500MB
  work_mem: 32MB
  
application:
  max_workers: 4
  connection_pool: 10
```

### Medium Deployment (3 nodes, 4 CPU, 8GB RAM each)
```yaml
redis:
  maxmemory: 2gb
  cluster-enabled: yes
  
varnish:
  -s malloc,1g  # 1GB memory
  
postgresql:
  shared_buffers: 1GB
  effective_cache_size: 4GB
  work_mem: 64MB
  
application:
  max_workers: 8
  connection_pool: 20
```

### Enterprise Deployment (5+ nodes, 8+ CPU, 16GB+ RAM)
```yaml
redis:
  maxmemory: 4gb
  cluster-enabled: yes
  cluster-replicas: 1
  
varnish:
  -s malloc,2g  # 2GB memory
  
postgresql:
  shared_buffers: 4GB
  effective_cache_size: 12GB
  work_mem: 128MB
  
application:
  max_workers: 16
  connection_pool: 50
```

## Monitoring Cache Performance

### Prometheus Metrics
```promql
# Redis cache hit ratio
rate(redis_keyspace_hits_total[5m]) / 
(rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))

# Varnish cache hit ratio
rate(varnish_main_cache_hit[5m]) / 
(rate(varnish_main_cache_hit[5m]) + rate(varnish_main_cache_miss[5m]))

# PostgreSQL cache hit ratio
rate(pg_stat_database_heap_blks_hit[5m]) / 
(rate(pg_stat_database_heap_blks_hit[5m]) + rate(pg_stat_database_heap_blks_read[5m]))

# Redis memory usage
redis_memory_used_bytes / redis_memory_max_bytes
```

### Grafana Dashboard
Cache hit ratio dashboard with:
- Redis hit ratio (should be >85%)
- Varnish hit ratio (should be >70%)
- PostgreSQL buffer hit ratio (should be >99%)
- Cache memory usage
- Eviction rate (LRU)
- Top cache keys by hit count

## Summary

Multi-layer caching reduces:
- **Database load**: 80-90% reduction
- **API latency**: 50-80% improvement
- **Bandwidth**: 60-70% reduction
- **Storage I/O**: 70-80% reduction

**Recommended profile** for on-premises:
1. Enable all cache layers
2. Configure Redis with 2GB+ memory
3. Set Varnish with 512MB-2GB memory
4. Implement database query caching
5. Monitor cache ratios weekly

---

**Phase 10**: Caching Strategy  
**Status**: ✅ Complete  
**Next**: Scaling Strategy
