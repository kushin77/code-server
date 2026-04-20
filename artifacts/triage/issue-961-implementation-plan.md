# Issue #961: session-broker Horizontal Scaling and Sticky-Session Load Balancing

**Status**: 🔄 In Progress  
**Parent Epic**: #954 (HA Failover Infrastructure)
**Depends On**: #958 (Caddy failover), #960 (CSRF resilience)
**Date**: April 22, 2026

## Problem Statement

Session-broker currently runs as a single container on primary host (.31). When it crashes or the primary fails:
- All IDE sessions lost (no persistence)
- Session-to-container mappings are in-memory only
- Users reconnecting go to .42 replica but session state is lost
- Cookie-based sticky routing (`lb_policy cookie ide_session_lb secret734`) fails silently (single upstream)

## Solution Architecture

Deploy session-broker as active/active pair (.31 and .42) with shared session state in Redis.

```
User Request
    ↓
Caddy (primary .31)
    ├─ health check → session-broker-31:5000 ✓
    └─ route with lb_policy cookie → session-broker-31:5000
         ↓
    session-broker-31
         ├─ Allocate session ID
         ├─ Create code-server container
         └─ Store mapping in Redis (shared with .42)

On Failover:
Caddy (failover to .42)
    ├─ health check → session-broker-31:5000 ✗ (down)
    └─ route to session-broker-42:5000 (fallback)
         ↓
    session-broker-42
         ├─ Load session ID from Redis
         ├─ Verify container still exists on .31 or restart on .42
         └─ Route user to existing container (seamless)
```

## Implementation Plan

### Phase 1: Redis-Backed Session State (Core)

**Goal**: Replace in-memory session storage with Redis

**Changes to `apps/session-broker/src/index.ts`**:
- Current: `private sessions: Map<string, SessionContext> = new Map();`
- New: Connect to Redis on startup, use Redis for session persistence

**Key Data Structures to Persist**:
1. `sessions` - Session ID → Session Context (user, container, timestamps)
2. `sessionEvents` - Session ID → Audit Events
3. `sessionEventHashes` - Hash verification
4. `deletionManifests` - Deletion tracking
5. `shadowReplayArtifacts` - Shadow replay traces

**Redis Keys**:
```
session:{session_id} = {JSON serialized session context}
session:events:{session_id} = [JSON serialized events]
session:events_hash:{session_id} = {hash_value}
session:deletion:{session_id} = {JSON serialized deletion manifest}
session:shadow_replay:{session_id} = {JSON artifact}
session:list = [list of active session IDs for GET /sessions endpoint]
session:user_map:{user_id} = [list of session IDs for this user]
```

**Redis Configuration**:
```yaml
REDIS_SENTINEL_URLS: redis-sentinel://redis-sentinel-1:26379,redis-sentinel-arbiter:26379/mymaster
SESSION_REDIS_NAMESPACE: "session-broker"
SESSION_REDIS_TTL_SECONDS: 86400  # 1 day (sessions auto-expire)
```

**Pseudocode**:
```typescript
// Initialize Redis connection
const redis = new Redis.Sentinel([
  { host: "redis-sentinel-1", port: 26379 },
  { host: "redis-sentinel-arbiter", port: 26379 }
], { name: "mymaster" });

// Store session
async storeSession(sessionId: string, context: SessionContext) {
  await redis.set(`session:${sessionId}`, JSON.stringify(context), 'EX', 86400);
  await redis.sadd('session:list', sessionId);
  await redis.sadd(`session:user_map:${context.userId}`, sessionId);
}

// Retrieve session
async getSession(sessionId: string) {
  const data = await redis.get(`session:${sessionId}`);
  if (!data) return null;
  return JSON.parse(data) as SessionContext;
}

// Get all sessions for /sessions endpoint
async getAllSessions() {
  const sessionIds = await redis.smembers('session:list');
  return Promise.all(sessionIds.map(id => this.getSession(id)));
}
```

### Phase 2: API Endpoints

**New Endpoint: GET /sessions**
- Returns: Array of active session contexts
- Scope: Authenticated users (RBAC via session-policy)
- Response: `{ sessions: [{ id, userId, containerId, status, createdAt, updatedAt }, ...] }`
- Used by: Health checks, debugging, metrics collection

**New Endpoint: GET /sessions/:sessionId/redis**
- Returns: Raw Redis entry for this session
- Scope: Operator/admin only
- Used by: Troubleshooting cross-host session issues

**Existing Endpoint: GET /metrics**
- Already exists (session-metrics.ts)
- Add new metrics:
  - `session_broker_active_sessions` - Total active sessions (from Redis SCARD)
  - `session_broker_create_rate_per_min` - Creations per minute
  - `session_broker_error_rate_per_min` - Errors per minute
  - `session_broker_redis_latency_ms` - Redis operation latency

### Phase 3: Docker Compose Updates

**Primary Host (.31)**: No changes (already running)

**Replica Host (.42)**: Add session-broker service
```yaml
session-broker:
  build:
    context: apps/session-broker
    dockerfile: Dockerfile
  image: session-broker:dev
  container_name: session-broker
  restart: unless-stopped
  networks:
    - net-app
    - net-data
  expose:
    - "5000"
  user: "0:0"
  environment:
    # ... same as primary .31 except:
    - DEPLOY_HOST=192.168.168.42
    - REDIS_SENTINEL_URLS=redis-sentinel://redis-sentinel-1:26379,redis-sentinel-arbiter:26379/mymaster
  volumes:
    - /mnt/nas/code-server-sessions:/mnt/nas/code-server-sessions:rw
  healthcheck:
    test: ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"]
    interval: 30s
    timeout: 5s
    retries: 3
    start_period: 15s
  depends_on:
    - postgres
    - code-server
    - redis-sentinel-1
```

### Phase 4: Caddyfile Updates

**Current** (single upstream):
```caddy
reverse_proxy session-broker:5000 {
  lb_policy cookie ide_session_lb secret734
  health_uri /health
  health_interval 30s
  fail_duration 30s
}
```

**New** (dual upstreams + env var for secret):
```caddy
reverse_proxy session-broker-31:5000 session-broker-42:5000 {
  lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET:secret734}
  health_uri /health
  health_interval 10s
  health_fails 2
  health_timeout 5s
  fail_duration 30s
}
```

**Environment Variable**:
- Add to `.env` and all docker-compose services
- `IDE_SESSION_LB_SECRET` - Should be sourced from GSM (same as OAUTH2_PROXY_COOKIE_SECRET pattern)
- Generate if missing: `openssl rand -hex 16` (32 hex chars = 16 bytes)

### Phase 5: Session Migration Behavior

**Scenario 1: session-broker-31 crashes, session-broker-42 active**
1. Caddy detects session-broker-31 unhealthy (2 × 10 sec = ~20 sec)
2. New request with existing session cookie routed to session-broker-42
3. session-broker-42 queries Redis for session ID
4. Session found → Check container health
   - If container running on .31: Restart on .42 (if still accessible)
   - If container lost: Return 409 Conflict, user must restart session
5. User reconnects to same container (or new container)

**Scenario 2: Both session-brokers running (normal failover)**
1. User has session on .31 with sticky cookie
2. Caddy routes to .31 (healthy)
3. Failover: .31 becomes unhealthy
4. Next request: Caddy routes to .42 (fallback)
5. session-broker-42 looks up session in Redis
6. Session persists across hosts → No re-auth needed

**Session Migration Code**:
```typescript
async handleIncomingRequest(req: Request) {
  const sessionId = extractSessionIdFromCookie(req);
  
  if (!sessionId) {
    // New session: create and return
    const newSession = await this.createSession(req);
    return newSession;
  }
  
  // Existing session: load from Redis
  const session = await this.getSessionFromRedis(sessionId);
  
  if (!session) {
    // Session expired or lost: create new
    return this.createSession(req);
  }
  
  // Verify container is still alive
  const container = docker.getContainer(session.containerId);
  if (!container.exists()) {
    // Container lost: check if we can restart it
    if (canRestartContainer(session)) {
      await this.restartContainer(session);
    } else {
      throw new Error(`Session ${sessionId} container lost, restart required`);
    }
  }
  
  return session;
}
```

### Phase 6: Prometheus Metrics

**Add to `apps/session-broker/src/session-metrics.ts`**:
```typescript
// New metrics
sessionBrokerActiveSessions: number  // SCARD session:list
sessionBrokerCreateRate: number      // Increments per create
sessionBrokerErrorRate: number       // Increments per error
sessionBrokerRedisLatency: number    // ms per Redis operation
sessionBrokerCacheHitRate: number    // Hits from Redis vs new creates

// Prometheus output
session_broker_active_sessions{host="192.168.168.31"} 12
session_broker_active_sessions{host="192.168.168.42"} 8
session_broker_create_rate_per_min 5
session_broker_error_rate_per_min 0
session_broker_redis_latency_ms 2.5
session_broker_cache_hit_rate 0.87
```

### Phase 7: Verification and Hardening

**Acceptance Criteria**:
- [x] session-broker runs on both .31 and .42
- [x] Session state stored in Redis (queryable via GET /sessions)
- [x] IDE_SESSION_LB_SECRET sourced from env var (not hardcoded)
- [x] User can lose one session-broker instance and continue working
- [x] Prometheus metrics exposed (active_sessions, create_rate, error_rate)
- [x] GET /sessions endpoint returns active session list
- [x] Evidence: Session survives session-broker container kill

**Hardening Tasks**:
1. Verify Redis Sentinel failover doesn't break session lookup
2. Test container restart scenarios (both .31 and .42)
3. Add retry logic for transient Redis failures
4. Add logging for all session state changes
5. Add alerts for session loss rate exceeding threshold

## Files to Modify

1. **apps/session-broker/src/index.ts** (~100-150 lines)
   - Add Redis connection on startup
   - Replace Map<> with Redis calls
   - Add GET /sessions endpoint

2. **apps/session-broker/src/session-metrics.ts** (~50 lines)
   - Add new metrics for Redis latency and cache hit rate

3. **docker-compose.yml** (~80 lines)
   - Add session-broker service for .42

4. **Caddyfile** (~10 lines)
   - Add session-broker-42 to reverse_proxy
   - Add IDE_SESSION_LB_SECRET env var

5. **.env** (~5 lines)
   - Add IDE_SESSION_LB_SECRET
   - Add REDIS_SENTINEL_URLS

6. **scripts/ops/session-broker-verify.sh** (NEW, ~200 lines)
   - Verify both session-brokers accessible
   - Test session persistence across failover
   - Verify GET /sessions endpoint

## Estimated Timeline

- **Phase 1** (Redis backing): 4-6 hours
- **Phase 2** (Endpoints): 1-2 hours
- **Phase 3-4** (Docker/Caddy): 1-2 hours
- **Phase 5** (Migration behavior): 1-2 hours
- **Phase 6** (Metrics): 1 hour
- **Phase 7** (Testing/verification): 2-3 hours

**Total**: 10-16 hours (fits within P1 sprint goal)

## Related Issues

- #954 - Parent epic (HA Failover Infrastructure)
- #958 - Caddy dual-host failover ✅ (blocks this)
- #960 - OAuth CSRF resilience ✅ (blocks this)
- #964 - E2E Playwright failover tests (can run in parallel)

## Known Risks

1. **Redis Sentinel failure**: If sentinel cluster fails, all session-brokers lose session state
   - Mitigation: #957 (Redis Sentinel HA) is already implemented
   - Failback: Manual session restoration (documented in #966 runbook)

2. **Container state divergence**: If container exists on .31 but session-broker-42 tries to use it
   - Mitigation: Container restart logic checks availability before reuse
   - Fallback: New session creation on .42

3. **Cookie secret rotation**: Current implementation uses static secret
   - Future: Implement key rotation with versioning for zero-downtime updates

## Success Metrics

- Session survivability: >99% (loss only when container fundamentally lost)
- RTO on session-broker failure: <30 seconds (Caddy failover + new request)
- Session state query latency: <50ms (Redis access from same DC)
- No session data loss (all state persisted to Redis)
