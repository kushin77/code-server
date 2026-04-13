# Tier 2: Advanced Performance & Caching (Implementation Plan)

**Status**: Ready for Implementation  
**Target Capacity**: 100 → 500+ concurrent users  
**Estimated Effort**: 8-12 hours  
**Expected ROI**: 4-5x capacity increase + better latency consistency

---

## Tier 2a: Redis Cache Layer (2-4 hours)

### Objective
Reduce latency for repeated requests, session caching, and code analysis results.

**Expected Impact**: 40% latency reduction for reads, 20% throughput increase

### Implementation

#### 1. Add Redis Container to docker-compose.yml

```yaml
redis:
  image: redis:7-alpine
  container_name: redis-cache
  restart: unless-stopped
  networks:
    - enterprise
  expose:
    - "6379"
  command:
    - "--maxmemory=512m"
    - "--maxmemory-policy=allkeys-lru"
  healthcheck:
    test: ["CMD", "redis-cli", "ping"]
    interval: 10s
    timeout: 3s
    retries: 3
  deploy:
    resources:
      limits:
        memory: 512m
        cpus: '0.5'
      reservations:
        memory: 256m
        cpus: '0.1'
```

#### 2. Code-Server Integration

```javascript
// config/cache-client.js - New cache client wrapper
const redis = require('redis');
const client = redis.createClient({
  host: process.env.REDIS_HOST || 'redis',
  port: parseInt(process.env.REDIS_PORT || 6379),
  retryStrategy: (options) => {
    if (options.total_retry_time > 1000 * 60 * 60) {
      return new Error('Redis retry time exhausted');
    }
    return Math.min(options.attempt * 100, 3000);
  }
});

module.exports = {
  get: (key) => client.getAsync(key),
  set: (key, value, ttl) => client.setexAsync(key, ttl, value),
  del: (key) => client.delAsync(key),
  clear: () => client.flushdbAsync(),
};
```

#### 3. Cached Endpoints (Priority)

```javascript
// Cache frequently accessed endpoints
app.get('/health', cacheMiddleware(60), healthHandler);
app.get('/extensions', cacheMiddleware(300), extensionsHandler); 
app.get('/config', cacheMiddleware(600), configHandler);
app.get('/workspace-files', cacheMiddleware(120), fileListHandler);
```

**Cache Strategy**:
- Health checks: 60s TTL
- Extension metadata: 5 min TTL
- Configuration: 10 min TTL
- File listings: 2 min TTL
- Code completions: 1 hour TTL

### Monitoring

```bash
# Monitor Redis usage
docker exec redis-cache redis-cli INFO memory
docker exec redis-cache redis-cli --stat  # Real-time stats

# Test cache hit rate
timeout 30 ab -n 1000 -c 50 http://localhost:3000/health
redis-cli INFO stats | grep hits
```

---

## Tier 2b: Content Delivery Network (CDN) Integration (1-2 hours)

### Objective
Serve static assets from edge locations, reducing latency for geo-distributed users.

**Expected Impact**: 50-70% latency reduction for static assets, 30-40% bandwidth reduction

### CloudFlare Integration

#### 1. Create Caching Rules

```yaml
# CloudFlare page rules (via API or UI)
rules:
  - path: "/static/*"
    cache_ttl: 86400  # 24 hours
    compress: true
    
  - path: "/assets/*"
    cache_ttl: 31536000  # 1 year (versioned)
    compress: true
    
  - path: "/health"
    cache_ttl: 0  # Never cache
    
  - path: "/api/*"
    cache_ttl: 0
```

#### 2. Add Cache Headers in Caddyfile

```caddy
@staticAssets path /static/* /assets/*
header @staticAssets Cache-Control "public, max-age=31536000, immutable"
header @staticAssets ETag "{http.request.uri.path}_{http.time.now}"

@api path /api/* /rpc*
header @api Cache-Control "no-store, no-cache, must-revalidate"
header @api Pragma "no-cache"
header @api Expires "0"
```

#### 3. Verify CDN Configuration

```bash
# Check cache headers
curl -I https://your-domain.com/static/bundle.js | grep -E "Cache-Control|CF-Cache-Status"

# Expected: CF-Cache-Status: HIT
```

---

## Tier 2c: Request Batching (3-4 hours)

### Objective
Allow clients to batch multiple requests into single HTTP request, reducing overhead.

**Expected Impact**: 30% throughput increase for batch workloads, 40% request count reduction

### Batch Endpoint Implementation

```javascript
// POST /api/batch
// Request body:
{
  "requests": [
    { "method": "GET", "path": "/api/extensions" },
    { "method": "GET", "path": "/api/config" },
    { "method": "POST", "path": "/api/workspace", "body": {...} }
  ]
}

// Response:
{
  "responses": [
    { "status": 200, "data": {...} },
    { "status": 200, "data": {...} },
    { "status": 201, "data": {...} }
  ]
}
```

### Middleware Implementation

```javascript
app.post('/api/batch', async (req, res) => {
  const { requests } = req.body;
  
  try {
    // Execute requests in parallel (up to 10 concurrent)
    const responses = await Promise.all(
      requests.map((req) => executeRequest(req))
    );
    
    // Return results
    res.json({ responses });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

async function executeRequest(req) {
  try {
    // Route to appropriate handler
    const response = await handleRequest(req.method, req.path, req.body);
    return { status: 200, data: response };
  } catch (err) {
    return { status: err.status || 500, error: err.message };
  }
}
```

### Client Usage Example

```javascript
// Before: 3 sequential requests (~150ms)
const ext = await fetch('/api/extensions');
const cfg = await fetch('/api/config');
const ws = await fetch('/api/workspace');

// After: 1 batched request (~50ms)
const batch = await fetch('/api/batch', {
  method: 'POST',
  body: JSON.stringify({
    requests: [
      { method: 'GET', path: '/api/extensions' },
      { method: 'GET', path: '/api/config' },
      { method: 'GET', path: '/api/workspace' }
    ]
  })
});
const { responses } = await batch.json();
```

---

## Tier 2d: Circuit Breaker Pattern (2 hours)

### Objective
Graceful degradation under sustained overload, preventing cascading failures.

**Expected Impact**: Maintain 95%+ success rate up to 300 concurrent users, even during CPU spikes

### Implementation

```javascript
// middlewares/circuit-breaker.js
const CircuitBreaker = require('opossum');

// Create circuit breaker for expensive operations
const breaker = new CircuitBreaker(expensiveOperation, {
  timeout: 3000,        // 3 second timeout
  errorThresholdPercentage: 50,  // Open at 50% error rate
  resetTimeout: 30000   // Try to recover after 30 seconds
});

breaker.fallback(() => ({ cached: true, shortcut: true }));

app.get('/api/expensive-operation', async (req, res) => {
  try {
    const result = await breaker.fire(req.query);
    res.json(result);
  } catch (err) {
    // Circuit is open - respond with cached/default data
    res.status(503).json({ 
      error: 'Service temporarily unavailable',
      retry_after: breaker.stats.resetTimeout / 1000
    });
  }
});
```

### Rate Limiting

```javascript
// Sliding window rate limiter (per IP/user)
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({
  windowMs: 60 * 1000,  // 1 minute window
  max: 600,              // 600 requests per minute per IP
  keyGenerator: (req) => req.ip,
  skip: (req) => req.user?.admin,  // Exempt admins
  handler: (req, res) => {
    res.status(429).json({
      error: 'Too many requests',
      retryAfter: req.rateLimit.resetTime
    });
  }
});

app.use('/api/', limiter);
```

---

## Deployment Strategy

### Step 1: Redis Cache (Non-Breaking)
```bash
# Deploy Redis
docker-compose up -d redis

# Add cache client library
npm install redis redis-promise-wrapper

# Gradually enable caching on endpoints (behind feature flag)
```

### Step 2: CDN Configuration (No Code Change)
```bash
# Update CloudFlare page rules
# Update Caddyfile headers
# Monitor cache hit rate

# Verify: curl -I https://domain/static/bundle.js
```

### Step 3: Request Batching (New Endpoint)
```bash
# Add /api/batch endpoint
# No impact on existing endpoints
# Client adoption is voluntary

# Test with: curl -X POST /api/batch -H "Content-Type: application/json" -d '...'
```

### Step 4: Circuit Breaker (Middleware)
```bash
# Add circuit breaker for expensive operations
# Set thresholds based on production metrics
# Monitor breaker state via /metrics endpoint
```

---

## Testing & Validation

### Performance Benchmarks

```bash
# After Tier 2 deployment
bash scripts/stress-test-suite.sh 192.168.168.31

# Expected results:
# - 500+ concurrent users at p99 < 100ms
# - 600+ req/s throughput
# - 50% reduction in bandwidth
# - 95%+ success rate under sustained load
```

### Cache Hit Rate Monitoring

```bash
# Redis stats
redis-cli INFO stats
# Look for: hits, misses, evicted_keys

# Cache effectiveness
(hits / (hits + misses)) * 100  # Should be >70% for health/config
```

### CDN Performance

```bash
# Check cache status header
curl -I https://domain/static/bundle.js | grep CF-Cache-Status
# Should show: HIT from edge

# Measure latency improvement
time curl https://domain/static/bundle.js > /dev/null
```

---

## Tier 2 Rollout Timeline

| Task | Effort | Duration | Dependencies |
|------|--------|----------|--------------|
| Redis setup | 2h | Day 1-2 | docker-compose |
| Redis integration | 2h | Day 2-3 | Redis |
| CDN setup | 1h | Day 3 | CloudFlare account |
| Request batching | 3.5h | Day 4-5 | Code review |
| Circuit breaker | 2h | Day 5-6 | Rate limiter |
| Testing & validation | 2h | Day 6 | All components |
| **Total** | **12.5h** | **~1 week** | Sequential |

---

## Success Criteria

✅ Redis deployed with health checks  
✅ Cache hit rate >70% for read endpoints  
✅ CDN cache headers present and working  
✅ /api/batch endpoint functional  
✅ Circuit breaker protecting expensive operations  
✅ Stress test shows 500+ concurrent user capacity  
✅ 95%+ success rate under sustained load  
✅ p99 latency <60ms @ 200 concurrent users  

---

## Monitoring & Alerts

```bash
# Key metrics to track
- redis_memory_used_bytes (should stay <450MB)
- cache_hit_ratio (target >75%)
- circuit_breaker_state (0=closed, 1=open)
- rate_limit_exceeded_count (should be <5/min)
- p99_latency (should trend downward)
- error_rate (target <0.5%)
```

---

**Next Steps:**
1. Review this plan with team
2. Create GitHub issues for each sub-task (2a-2d)
3. Start with Tier 2a (Redis) - least risky, highest impact
4. Deploy each component, test independently, then integrate
5. After Tier 2 complete, plan Tier 3 (Kubernetes)

