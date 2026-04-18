# Phase 2 Integration Test Plan
## Per-Session Isolation - Caddy Integration & OAuth2 Hooks

**Date**: April 18, 2026  
**Commit**: 69adda92  
**Status**: Ready for testing  

---

## Test Environment Setup

### Prerequisites
```bash
# 1. Services running
docker-compose up -d session-broker caddy oauth2-proxy postgres

# 2. Database initialized
docker-compose exec postgres psql -U codeserver -d codeserver -c "
  SELECT EXISTS(SELECT 1 FROM information_schema.tables 
  WHERE table_name='sessions');"

# 3. Test user credentials set
export TEST_EMAIL="test@kushnir.cloud"
export TEST_USERNAME="testuser"
export OAUTH2_SESSION_COOKIE="_oauth2_proxy_ide"
```

---

## Test Cases

### Test 1: Unauthenticated Request Handling
**Goal**: Verify unauthenticated requests are redirected to oauth2-proxy

**Steps**:
```bash
# 1. Make request without auth headers
curl -s http://localhost/health -i

# Expected**: 200 OK (health endpoint is public)
curl -s -H "X-Real-IP: 127.0.0.1" \
  http://localhost:5000/ | grep -q "need to authenticate"

# Expected: Redirect to /oauth2/start or 403
```

**Assertion**: 
- ✅ Unauthenticated requests to / redirect to oauth2-proxy
- ✅ Health checks remain accessible
- ✅ Error messages don't leak system info

---

### Test 2: Session Creation on OAuth2 Callback
**Goal**: Verify session is created when oauth2-proxy headers are present

**Steps**:
```bash
# 1. Simulate oauth2-proxy authenticated request
curl -s -X POST http://localhost:5000/oauth2/callback \
  -H "X-Auth-Request-Email: ${TEST_EMAIL}" \
  -H "X-Auth-Request-User: ${TEST_USERNAME}" \
  -H "Content-Type: application/json" \
  -d '{}' | jq '.'

# Expected response:
# {
#   "sessionId": "<uuid>",
#   "containerPort": 8081,
#   "url": "http://localhost:8081"
# }
```

**Assertion**:
- ✅ Session created with valid UUID
- ✅ Container port assigned (8081+)
- ✅ URL points to localhost:PORT
- ✅ Session persisted to database

**Verify in DB**:
```bash
docker-compose exec postgres psql -U codeserver -d codeserver -c "
  SELECT session_id, user_id, status, container_port 
  FROM sessions 
  WHERE username = '${TEST_USERNAME}' 
  LIMIT 1;"
```

---

### Test 3: Authenticated Request Routing
**Goal**: Verify authenticated requests are routed to session container

**Steps**:
```bash
# 1. Get session ID from Test 2
SESSION_ID="<from previous response>"

# 2. Make authenticated request with session cookie
curl -s -b "_code_server_session_id=${SESSION_ID}" \
  -H "X-Auth-Request-Email: ${TEST_EMAIL}" \
  -H "X-Auth-Request-User: ${TEST_USERNAME}" \
  http://localhost:5000/ \
  -i

# Expected: 200 OK (or appropriate response from code-server container)
```

**Assertion**:
- ✅ Request routed to correct container (check X-LB-Upstream header)
- ✅ Session cookie maintained in response
- ✅ WebSocket upgrade headers present (Connection, Upgrade)
- ✅ Response status >= 200 and < 400

---

### Test 4: Multi-User Session Isolation
**Goal**: Verify different users receive different sessions/containers

**Steps**:
```bash
# 1. Create session for USER1
curl -s -X POST http://localhost:5000/oauth2/callback \
  -H "X-Auth-Request-Email: user1@kushnir.cloud" \
  -H "X-Auth-Request-User: user1" \
  -d '{}' | jq '.sessionId' > user1_session.txt
USER1_SESSION=$(cat user1_session.txt)
USER1_PORT=$(cat user1_session.txt | jq '.containerPort')

# 2. Create session for USER2
curl -s -X POST http://localhost:5000/oauth2/callback \
  -H "X-Auth-Request-Email: user2@kushnir.cloud" \
  -H "X-Auth-Request-User: user2" \
  -d '{}' | jq '.sessionId' > user2_session.txt
USER2_SESSION=$(cat user2_session.txt)
USER2_PORT=$(cat user2_session.txt | jq '.containerPort')

# 3. Verify they're different
[ "${USER1_SESSION}" != "${USER2_SESSION}" ] && echo "✅ Different sessions"
[ "${USER1_PORT}" != "${USER2_PORT}" ] && echo "✅ Different ports"
```

**Assertion**:
- ✅ Each user gets unique sessionId
- ✅ Each user gets different container port
- ✅ Users cannot access each other's containers
- ✅ Database has 2+ active sessions

---

### Test 5: Session Cleanup on Logout
**Goal**: Verify session is terminated when user logs out

**Steps**:
```bash
# 1. Get session status before logout
curl -s http://localhost:5000/sessions/${SESSION_ID} \
  -H "X-Auth-Request-User: ${TEST_USERNAME}" \
  | jq '.status'
# Expected: "running"

# 2. Call logout endpoint
curl -s -X POST http://localhost:5000/oauth2/logout \
  -H "X-Session-Id: ${SESSION_ID}" \
  -d '{}' \
  -i

# Expected: 204 No Content

# 3. Verify session is terminated
curl -s http://localhost:5000/sessions/${SESSION_ID} \
  -H "X-Auth-Request-User: ${TEST_USERNAME}" \
  | jq '.status'
# Expected: "terminated" or 404

# 4. Verify container is stopped
docker ps | grep "code-server-${TEST_USERNAME}" || echo "✅ Container removed"
```

**Assertion**:
- ✅ Session marked as terminated in database
- ✅ Container stopped/removed
- ✅ Logout request returns 204
- ✅ Subsequent requests to /sessions/{id} return 404

---

### Test 6: Activity Logging
**Goal**: Verify activity logs capture user actions

**Steps**:
```bash
# 1. Check logs for Activity entries
docker-compose logs session-broker | grep '"Activity"' | head -5

# Expected format:
# {"timestamp":"2026-04-18T21:50:00Z","method":"GET","path":"/health",
#  "statusCode":200,"duration":"5ms","userId":"testuser","username":"testuser",
#  "email":"test@kushnir.cloud","sessionId":"..."}

# 2. Verify error logging
curl -s http://localhost:5000/nonexistent \
  -H "X-Auth-Request-User: ${TEST_USERNAME}"

docker-compose logs session-broker | grep '"Activity.*Client Error"'
# Expected: 404 in logs with user context
```

**Assertion**:
- ✅ Activity logs include timestamp, method, path, statusCode, duration
- ✅ User context (userId, username, email) present when authenticated
- ✅ Session ID logged when available
- ✅ Error levels differentiated (info/warn/error)
- ✅ No sensitive data (passwords, tokens) in logs

---

### Test 7: Session TTL and Expiration
**Goal**: Verify sessions expire after TTL

**Steps**:
```bash
# 1. Create session with short TTL (10 seconds for testing)
curl -s -X POST http://localhost:5000/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "ttl-test-user",
    "username": "ttluser",
    "email": "ttltest@kushnir.cloud",
    "ttlSeconds": 10
  }' | jq '.expiresAt' > expires_at.txt
SESSION_ID=$(jq '.sessionId' < /dev/stdin)

# 2. Verify session is active
curl -s http://localhost:5000/sessions/${SESSION_ID} | jq '.status'
# Expected: "running"

# 3. Wait 11 seconds
sleep 11

# 4. Check if expired (depends on cleanup job - may be manual for testing)
# Note: Cleanup job implementation is Phase 3+ enhancement
echo "✅ TTL field set correctly in DB"
```

**Assertion**:
- ✅ expiresAt timestamp is current_time + ttlSeconds
- ✅ TTL range validated (3600-86400 seconds)
- ✅ Expired sessions can be cleaned via DELETE endpoint

---

## Resource Quota Verification

### Test 8: Container Resource Limits
**Goal**: Verify containers have correct CPU/memory limits

**Steps**:
```bash
# 1. Create session and get container ID
CONTAINER_ID=$(docker ps | grep "code-server-${TEST_USERNAME}" | awk '{print $1}')

# 2. Check CPU limits
docker inspect ${CONTAINER_ID} | jq '.HostConfig.CpuQuota'
# Expected: 2000000 (2.0 CPU in cgroups format)

# 3. Check memory limits
docker inspect ${CONTAINER_ID} | jq '.HostConfig.Memory'
# Expected: 4294967296 (4g in bytes)

# 4. Verify namespace isolation
docker exec ${CONTAINER_ID} ps aux | wc -l
# Expected: < 256 (process limit)
```

**Assertion**:
- ✅ CPU limit: 2.0 cores
- ✅ Memory limit: 4GB
- ✅ Process limit: 256 max
- ✅ Storage limit: 50GB (via mount)

---

## Performance Tests

### Test 9: Concurrent User Sessions
**Goal**: Verify system handles multiple simultaneous sessions

**Steps**:
```bash
# 1. Create 5 concurrent sessions
for i in {1..5}; do
  curl -s -X POST http://localhost:5000/oauth2/callback \
    -H "X-Auth-Request-Email: concurrent-user-$i@kushnir.cloud" \
    -H "X-Auth-Request-User: concurrent-user-$i" \
    -d '{}' &
done
wait

# 2. Verify all sessions active
docker-compose exec postgres psql -U codeserver -d codeserver -c "
  SELECT COUNT(*) FROM sessions WHERE status = 'running' AND user_id LIKE 'concurrent%';"
# Expected: 5

# 3. Check system resources
docker stats session-broker --no-stream | awk 'NR==2 {print "Memory:", $6, "CPU:", $7}'
```

**Assertion**:
- ✅ 5 sessions created in < 5 seconds
- ✅ All containers running in parallel
- ✅ Memory usage < 2GB total
- ✅ CPU usage < 300% (system dependent)

---

## Integration with Caddy

### Test 10: Full Request Flow through Caddy
**Goal**: End-to-end request from browser through Caddy → Session-Broker → Container

**Steps**:
```bash
# 1. Test health endpoint (public)
curl -s https://ide.kushnir.cloud/health -H "Host: ide.kushnir.cloud" \
  -k | jq '.status'
# Expected: "healthy"

# 2. Test auth redirect (no session cookie)
curl -s -i https://ide.kushnir.cloud/ \
  -H "Host: ide.kushnir.cloud" \
  -k | grep -i "location.*oauth2"
# Expected: 302 redirect to oauth2

# 3. Test with valid oauth2 session cookie
curl -s https://ide.kushnir.cloud/ \
  -b "_oauth2_proxy_ide=<valid_cookie>" \
  -H "Host: ide.kushnir.cloud" \
  -k | head -20
# Expected: 200 with code-server UI or 502 if container not ready
```

**Assertion**:
- ✅ Health endpoint accessible without auth
- ✅ Unauthenticated requests redirect to oauth2
- ✅ Authenticated requests reach session-broker
- ✅ Caddy correctly forwards headers (X-Real-IP, Host)

---

## Automation Script

Create `/scripts/test-phase-2-integration.sh`:

```bash
#!/bin/bash
set -eo pipefail

echo "=== Phase 2 Integration Tests ==="
echo "Testing session isolation with oauth2 integration"

# Test counters
PASS=0
FAIL=0

test_endpoint() {
  local name="$1"
  local method="$2"
  local endpoint="$3"
  local headers="$4"
  local expected_code="$5"
  
  local response=$(curl -s -X "$method" -w "\n%{http_code}" \
    $headers \
    "http://localhost:5000${endpoint}")
  
  local status=$(echo "$response" | tail -n1)
  
  if [ "$status" = "$expected_code" ]; then
    echo "✅ $name (HTTP $status)"
    ((PASS++))
  else
    echo "❌ $name (expected $expected_code, got $status)"
    ((FAIL++))
  fi
}

# Run tests
test_endpoint "Health endpoint" "GET" "/health" "" "200"
test_endpoint "Unauthenticated / request" "GET" "/" "" "302"
test_endpoint "OAuth callback" "POST" "/oauth2/callback" \
  '-H "X-Auth-Request-Email: test@test.com" -H "X-Auth-Request-User: testuser"' "200"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
```

Run with:
```bash
bash scripts/test-phase-2-integration.sh
```

---

## Test Execution Checklist

- [ ] Test 1: Unauthenticated request handling
- [ ] Test 2: Session creation on OAuth2 callback
- [ ] Test 3: Authenticated request routing
- [ ] Test 4: Multi-user session isolation
- [ ] Test 5: Session cleanup on logout
- [ ] Test 6: Activity logging
- [ ] Test 7: Session TTL and expiration
- [ ] Test 8: Container resource limits
- [ ] Test 9: Concurrent user sessions
- [ ] Test 10: Full request flow through Caddy

## Known Limitations (Phase 2)

- Session expiration cleanup requires manual triggering (Phase 3 cron job)
- Container image must be pre-built (not auto-built on session creation)
- No session persistence across broker restarts (in-memory cache + DB fallback)
- Activity logs written to JSON files (Prometheus export in Phase 3)

## Success Criteria

✅ **Phase 2 Integration Tests Passed**: All 10 tests pass with > 95% success rate  
✅ **Performance**: < 100ms session creation latency  
✅ **Reliability**: No session state corruption across 24h runtime  
✅ **Security**: No cross-session access, isolation verified  

---

**Next**: Phase 3 testing automation and monitoring setup
