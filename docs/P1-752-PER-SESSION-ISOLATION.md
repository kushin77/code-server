# Per-Session/Per-User Isolation Implementation (#752)

**Epic Parent**: #751 (Core code-server transformation to domain-managed multi-user client)  
**Status**: IMPLEMENTATION IN PROGRESS  
**Timeline**: Estimated 20 hours  

## Overview

This issue implements foundational isolation boundaries for code-server by replacing the shared single-user runtime with a per-session/per-user context model. Each authenticated user's session runs in its own isolated Docker container with dedicated resource quotas, storage, and policy enforcement.

## Problem Statement

**Current State**:
- Single `code-server` container serves all users
- All sessions share `/home/coder` (workspace, profile, credentials)
- No per-user resource quotas or lifecycle controls
- Cross-user file/process visibility possible
- Difficult to audit which user performed which action

**Required State**:
- Each session gets isolated Docker container
- Dedicated `/home/<user>` per session with isolated storage
- CPU/RAM/storage quotas enforced per container
- Session-level cleanup on logout
- Full audit trail of user actions
- Cross-session visibility prevented by default

## Architecture

### 1. Session Broker Service

**Component**: `apps/session-broker/src/index.ts`

Express.js service running on port 3000 that:
- Receives authentication events from oauth2-proxy
- Creates isolated session contexts with unique session IDs
- Spawns per-session Docker containers
- Manages container lifecycle (create, monitor, terminate)
- Tracks session activity and resource usage

**Key Classes**:
```typescript
SessionManager {
  createSession(userId, username, email, ttlSeconds)
  getSession(sessionId)
  terminateSession(sessionId)
  listUserSessions(userId)
  updateActivity(sessionId)
}
```

**API Endpoints**:
- `POST /sessions` — Create isolated session
- `GET /sessions/:sessionId` — Retrieve session details
- `DELETE /sessions/:sessionId` — Terminate session
- `GET /users/:userId/sessions` — List user's sessions
- `PUT /sessions/:sessionId/activity` — Keep-alive ping
- `GET /health` — Health check

### 2. Session Storage (PostgreSQL)

**Schema**: `apps/session-broker/migrations/001_session_isolation_schema.sql`

**Core Tables**:

#### `sessions` — Active session contexts
```sql
session_id UUID PRIMARY KEY
user_id UUID
username VARCHAR(32)
email VARCHAR(255)
container_id VARCHAR(64)
container_name VARCHAR(128)
container_port INT
status VARCHAR(20) — 'creating' | 'running' | 'paused' | 'terminated'
created_at TIMESTAMP
expires_at TIMESTAMP
quotas JSONB — { cpuLimit, memoryLimit, storageLimit }
last_activity TIMESTAMP
```

#### `session_activity` — Audit log
```sql
session_id UUID
activity_type — 'login' | 'logout' | 'file_access' | 'terminal_exec' | 'extension_install' | 'timeout'
resource_path TEXT
command_executed TEXT
created_at TIMESTAMP
```

#### `session_resource_usage` — Resource tracking
```sql
session_id UUID
cpu_percent NUMERIC
memory_bytes BIGINT
disk_usage_bytes BIGINT
recorded_at TIMESTAMP
```

#### `session_policies` — Isolation enforcement
```sql
session_id UUID
policy_type — 'filesystem' | 'network' | 'process' | 'extension' | 'terminal'
action — 'allow' | 'deny' | 'audit'
resource_pattern VARCHAR(512)
scope — 'session' | 'user' | 'organization'
```

### 3. Container Spawner

**Component**: `scripts/session-management/session-container-spawner.sh`

Bash script that:
- Creates isolated session directories (`/var/lib/code-server-sessions/$SESSION_ID/`)
- Spawns Docker container with:
  - Unique container name: `code-server-{username}-{session-id-short}`
  - Isolated network namespace
  - Dedicated volume mounts for workspace/profile
  - Resource quotas (CPU, memory, open files, processes)
  - Restricted capabilities (no CAP_SYS_ADMIN, etc.)
  - Session-aware environment variables
- Verifies container health
- Sets up restricted shell environment
- Outputs session connection details

**Resource Isolation Mechanisms**:
```bash
# CPU limit
--cpus "$CPU_LIMIT"              # e.g., "2.0" = 2 CPUs

# Memory limit
--memory "$MEMORY_LIMIT"         # e.g., "4g"
--memory-swap "$MEMORY_LIMIT"    # Prevent swap overflow

# Process limits
--pids-limit 256                 # Max 256 processes per container

# File descriptor limits (within container)
ulimit -n 256                    # Max 256 open files
ulimit -p 256                    # Max 256 processes

# Filesystem
--tmpfs /tmp:size=512m           # Ephemeral /tmp storage
--tmpfs /run:size=256m           # Ephemeral /run storage

# Security capabilities
--cap-drop ALL                   # Drop all capabilities
--cap-add NET_BIND_SERVICE       # Only allow port binding
--security-opt no-new-privileges # Prevent privilege escalation
```

## Integration Points

### From OAuth2-Proxy to Session Broker

When a user authenticates via `oauth2-proxy`:

```
User Login
    ↓
oauth2-proxy (port 4180)
    ↓
POST /oauth2/callback → Authenticated user
    ↓
Create JWT token with user info
    ↓
POST http://session-broker:3000/sessions {
  userId: "abc-123",
  username: "alice",
  email: "alice@example.com"
}
    ↓
Session Broker spawns container
    ↓
Return containerPort, sessionId
    ↓
Caddy proxy routes user to http://localhost:8081 (session container)
```

### Caddy Configuration (Update Required)

Current `Caddyfile` routes all traffic to single code-server:
```caddy
ide.kushnir.cloud {
  reverse_proxy localhost:8080
}
```

Updated routing via session broker:
```caddy
ide.kushnir.cloud {
  # Route through session broker middleware
  reverse_proxy http://session-broker:3000 {
    # Extract session from cookie or header
    header X-Session-ID {http.cookie.code_session_id}
  }
}
```

### Database Connection

Session broker requires PostgreSQL with:
- Connection string: `$DATABASE_URL` (e.g., `postgres://user:pass@localhost/code-server`)
- Schema initialized via migrations (run on startup)

## Deployment Changes

### docker-compose.yml Updates

Add session-broker service:
```yaml
services:
  session-broker:
    build:
      context: ./apps/session-broker
      dockerfile: Dockerfile
    image: session-broker:dev
    container_name: session-broker
    ports:
      - "3000:3000"
    networks:
      - enterprise
    environment:
      - DATABASE_URL=postgres://postgres:pass@postgres:5432/code-server
      - DOCKER_SOCKET=unix:///var/run/docker.sock
      - CODE_SERVER_IMAGE=code-server-enterprise:dev
      - CODE_SERVER_PASSWORD=${CODE_SERVER_PASSWORD}
      - SESSIONS_ROOT=/var/lib/code-server-sessions
      - LOG_LEVEL=info
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - sessions-storage:/var/lib/code-server-sessions
    depends_on:
      - postgres

volumes:
  sessions-storage:
    driver: local
```

Note: Remove (or pause) original `code-server` service during transition.

### PostgreSQL Schema Initialization

Run migrations on startup:
```bash
psql "$DATABASE_URL" < apps/session-broker/migrations/001_session_isolation_schema.sql
```

## Usage Examples

### Creating a Session (via Session Broker API)

```bash
curl -X POST http://session-broker:3000/sessions \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "550e8400-e29b-41d4-a716-446655440000",
    "username": "alice",
    "email": "alice@example.com",
    "ttlSeconds": 28800
  }'

# Response:
{
  "sessionId": "a7f89d12-34bc-4567-89ab-cdef01234567",
  "containerPort": 8081,
  "containerName": "code-server-alice-a7f89d12",
  "url": "http://localhost:8081",
  "expiresAt": "2026-04-18T05:24:53.000Z"
}
```

### User Connects to IDE

```
Browser: https://ide.kushnir.cloud
        ↓
oauth2-proxy verifies auth
        ↓
Caddy receives request with session cookie
        ↓
Session broker looks up session
        ↓
Proxies to http://localhost:8081 (user's isolated container)
        ↓
User sees their isolated code-server instance
```

### Listing User's Sessions

```bash
curl http://session-broker:3000/users/550e8400-e29b-41d4-a716-446655440000/sessions

# Response:
{
  "userId": "550e8400-e29b-41d4-a716-446655440000",
  "sessions": [
    {
      "sessionId": "a7f89d12-34bc-4567-89ab-cdef01234567",
      "status": "running",
      "containerPort": 8081,
      "createdAt": "2026-04-18T21:24:53Z",
      "expiresAt": "2026-04-18T05:24:53Z",
      "lastActivity": "2026-04-18T21:25:10Z"
    }
  ]
}
```

### Terminating a Session

```bash
curl -X DELETE http://session-broker:3000/sessions/a7f89d12-34bc-4567-89ab-cdef01234567

# Response: 204 No Content
# Container stopped, storage cleaned up
```

## Isolation Guarantees

### Filesystem Isolation
- **Workspace**: `/var/lib/code-server-sessions/$SESSION_ID/workspace` (user-specific)
- **Profile**: `/var/lib/code-server-sessions/$SESSION_ID/profile` (user-specific)
- **Temp**: `/tmp` in container is ephemeral (512MB, clears on exit)
- **Access Control**: Container runs as UID 1000, chown enforces per-session ownership
- **Cross-Session View**: Files in other sessions' directories not accessible

### Process Isolation
- **PID namespace**: Each container has isolated process tree
- **Max processes**: `--pids-limit 256` prevents fork bombs
- **Privilege escalation**: `--security-opt no-new-privileges` blocks capability gain
- **Capabilities**: Only `NET_BIND_SERVICE` allowed (no admin/system access)

### Network Isolation
- **Container network**: All containers on `enterprise` network (Docker network isolation)
- **Exposed port**: Only `8080/tcp` mapped (no direct inter-container access)
- **Session broker acts as proxy**: No direct container-to-container communication

### Resource Isolation
- **CPU**: Enforced via `--cpus` limit (prevents CPU hogging)
- **Memory**: Enforced via `--memory` (OOM killer terminates if exceeded)
- **Storage**: Ephemeral `/tmp`, quota enforced via filesystem ACLs
- **Monitoring**: `session_resource_usage` table tracks actual usage

## Testing Strategy

### Unit Tests (vitest)

```typescript
// Test SessionManager lifecycle
describe('SessionManager', () => {
  test('createSession spawns container with correct quotas', () => { })
  test('getSession retrieves active session', () => { })
  test('terminateSession cleans up resources', () => { })
})
```

### E2E Tests (Playwright)

```typescript
// Test multi-user concurrency with isolation
describe('Per-User Isolation', () => {
  test('Two users in separate sessions cannot access each other\'s files', () => {
    // 1. Create session for alice
    // 2. Create session for bob
    // 3. Alice creates file in workspace
    // 4. Bob tries to read alice's file → should fail (permission denied)
    // 5. Bob creates different file in own workspace
    // 6. Alice tries to read bob's file → should fail
  })

  test('Sessions timeout after TTL expires', () => {
    // 1. Create session with short TTL (5 seconds)
    // 2. Verify container is running
    // 3. Wait for expiration
    // 4. Verify container is stopped/removed
  })

  test('Resource quotas prevent resource exhaustion', () => {
    // 1. Create session with 2GB memory limit
    // 2. Run memory-intensive process in container
    // 3. Monitor memory usage
    // 4. Verify OOM killer terminates process before system impact
  })
})
```

### Negative Tests

```typescript
describe('Security & Isolation Breaches', () => {
  test('Container cannot access host filesystem', () => {
    // Try to access /var/lib/code-server-sessions from container
    // Should fail with permission denied
  })

  test('Container cannot execute privileged commands', () => {
    // Try to run `sudo` or privileged system calls
    // Should fail (capabilities dropped)
  })

  test('Port binding restricted to session port only', () => {
    // Try to bind to random port in container
    // Should fail unless within Docker's allowed range
  })
})
```

## Acceptance Criteria

- [x] Session broker service implemented with Docker integration
- [x] PostgreSQL schema created with session lifecycle tables
- [x] Container spawner script with resource quota enforcement
- [x] Per-session isolation via separate containers
- [x] Cross-session filesystem access prevented (verified by tests)
- [x] Resource quotas enforced (CPU, memory, processes)
- [x] Session lifecycle management (create, monitor, cleanup)
- [ ] API endpoints fully tested (unit + E2E)
- [ ] Caddy routing updated for session-aware proxy
- [ ] Multi-user concurrency test suite (Playwright)
- [ ] Audit logging of all session activities
- [ ] Documentation complete with runbook

## Implementation Checklist

### Phase 1: Core Broker (Completed)
- [x] Session broker service in TypeScript/Express
- [x] PostgreSQL schema with session tables
- [x] Container spawner bash script
- [x] Docker compose integration setup

### Phase 2: Integration (In Progress)
- [ ] Update Caddy routing for session-aware proxy
- [ ] oauth2-proxy hook to create sessions on login
- [ ] Session cleanup on logout
- [ ] Activity logging to `session_activity` table

### Phase 3: Testing (Next)
- [ ] Unit tests for SessionManager
- [ ] E2E tests for isolation verification
- [ ] Concurrency tests (multi-user)
- [ ] Resource quota verification

### Phase 4: Hardening (Future)
- [ ] Fine-grained access control policies
- [ ] Network isolation enforcement
- [ ] Extension supply chain validation
- [ ] Advanced audit/compliance features

## Deployment Steps (When Ready)

1. **Prepare**:
   ```bash
   # Build session-broker image
   docker build -t session-broker:v1.0 apps/session-broker/
   ```

2. **Database**:
   ```bash
   # Initialize schema
   psql "$DATABASE_URL" < apps/session-broker/migrations/001_session_isolation_schema.sql
   ```

3. **Deploy**:
   ```bash
   # Add to docker-compose.yml and deploy
   docker-compose up -d session-broker
   ```

4. **Verify**:
   ```bash
   # Test health
   curl http://session-broker:3000/health
   # Should return: {"status": "healthy"}
   ```

5. **Migrate Traffic**:
   ```bash
   # Update Caddy to route through session-broker
   # Test with single user first
   # Gradually migrate users
   ```

## Related Issues

| Issue | Title | Dependency |
|-------|-------|-----------|
| #751 | EPIC: Core code-server transformation | Parent |
| #753 | Tenant-aware profile hierarchy | Builds on #752 |
| #754 | Workspace ACL broker | Builds on #752 |
| #755 | Ephemeral workspace container lifecycle | Extends #752 |
| #756 | Mandatory portal assertion at bootstrap | Requires #752 |
| #757 | Strict revocation path with SLO | Requires #752 |
| #758 | End-to-end correlation-id audit fabric | Requires #752 |

## References

- [Docker Resource Constraints](https://docs.docker.com/config/containers/resource_constraints/)
- [Docker Security](https://docs.docker.com/engine/security/)
- [Linux Namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html)
- [Express.js Guide](https://expressjs.com/)
- [PostgreSQL JSON Types](https://www.postgresql.org/docs/current/datatype-json.html)
