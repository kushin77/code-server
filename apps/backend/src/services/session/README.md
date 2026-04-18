# Session Versioning & Migration

Transparent server-side session schema migration. Users never need to clear cookies when session structure changes.

## Problem

Before this module, any structural change to the `_oauth2_proxy_ide` session cookie required manual user action:
- Users told to clear cookies manually
- All active sessions invalidated simultaneously
- Poor production UX and support burden

This is a **FAANG anti-pattern** identified in #346 (self-healing sessions epic): cookie structure changed → app assumes specific shape → no fallback → users suffer.

## Solution

Session payloads now include a top-level version field (`v`). When the server reads an old-version session:

1. **Detect**: Compare `session.v` to `CURRENT_SESSION_VERSION`
2. **Migrate**: Run migration functions from current version → target version
3. **Update**: If migrated, issue new Set-Cookie with updated session
4. **Log**: Emit structured migration event for observability

Users remain logged in seamlessly; session is silently upgraded.

## Architecture

```
Browser                OAuth2-Proxy         Session Middleware        Code-Server
   |                        |                       |                      |
   |---(request + cookie)----|                      |                      |
   |                        |---(deserialize)-------|                      |
   |                        |   session from Redis  |                      |
   |                        |                   migrateSession()           |
   |                        |<--(dirty? true)------|                      |
   |                        |   (updated session)   |                      |
   |                        |                   Set-Cookie header          |
   |                        |<--(new session)------|                      |
   |                        |---(forward with X-Auth headers)-----|        |
   |                        |                       |              response |
   |<-------(200 + Set-Cookie)----(updated)--------|              |        |
```

## Usage

### Basic Migration

```typescript
import { migrateSession, CURRENT_SESSION_VERSION } from '@/services/session';

// In auth middleware (after deserializing from Redis):
const raw = JSON.parse(redisData);
const { result, event } = migrateSession(raw);

// Structured logging (send to observability stack)
logger.info("session_event", event);

// If dirty, save and return Set-Cookie
if (result.dirty) {
  await redis.setex(`_oauth2_proxy_ide:${sessionId}`, ttl, JSON.stringify(result.session));
  response.setHeader('Set-Cookie', `_oauth2_proxy_ide=${serialize(result.session)}; ...`);
}

// Forward to upstream with migrated session
request.headers['X-Auth-Request-User'] = result.session.sub;
```

### Activity Tracking

```typescript
import { updateSessionActivity, isSessionStale } from '@/services/session';

// After each successful request:
const updated = updateSessionActivity(session);
await redis.setex(`_oauth2_proxy_ide:${sessionId}`, ttl, JSON.stringify(updated));

// Check staleness in health checks:
if (isSessionStale(session, 30)) { // 30 min threshold
  logger.warn("stale_session", { user: session.sub });
  // Trigger re-auth redirect
}
```

## Schema Versions

### V1 (Legacy)
```typescript
{
  "v": 1,
  "sub": "user@example.com",
  "iat": 1713000000,
  "exp": 1713086400,
  "google_id_token": "..."
}
```

### V2
Added user preferences extensibility:
```typescript
{
  "v": 2,
  ...,
  "user_prefs": {
    "theme": "dark",
    "language": "en",
    ...
  }
}
```

### V3 (Current)
Added MFA verification and activity tracking:
```typescript
{
  "v": 3,
  ...,
  "mfa_verified": boolean,
  "last_activity": number  // unix timestamp
}
```

## Adding a New Version

When session schema changes:

1. **Update `types.ts`**:
   - Increment `CURRENT_SESSION_VERSION`
   - Add new `SessionVN` interface
   - Update `Session` interface with new fields

2. **Add migration function in `migration.ts`**:
   ```typescript
   MIGRATIONS: {
     ...existing,
     N: (session: SessionVN) => ({
       ...session,
       v: N+1,
       newField: defaultValue,
     }),
   }
   ```

3. **Add tests in `__tests__/migration.test.ts`**:
   - Test v(N-1) → current migration
   - Test field preservation
   - Test edge cases

4. **Ensure backward compatibility**:
   - All new fields must have defaults
   - Never remove fields (mark deprecated if needed)
   - Migration functions must be idempotent

## Rollback Safety

If a new version causes issues:

1. **Revert code** to previous version (decrements `CURRENT_SESSION_VERSION`)
2. **Existing new-version sessions** are accepted as-is (unknown fields ignored)
3. **No session loss** — only forward migration, never forced downgrade
4. **Gradual rollback**: Monitor `session_migrated` metric before/after revert

## Observability

### Metrics
- `session_migrated_total` (counter): Sessions upgraded by version (labels: from_v, to_v)
- `session_migration_ms` (histogram): Migration duration in milliseconds
- `session_invalid_total` (counter): Corrupt/unparseable sessions
- `session_activity_updated_total` (counter): Activity timestamp updates

### Structured Logging

Each migration emits a `SessionMigrationEvent`:

```json
{
  "event": "session_migrated",
  "from_v": 1,
  "to_v": 3,
  "user_hash": "a1b2c3d4",
  "timestamp": 1713123456789
}
```

Sensitive data (email) is hashed with SHA256 and truncated to 8 chars.

## Performance

- **P99 latency**: < 2ms per migration (on-memory operation)
- **Migration complexity**: O(n) where n = number of migrations (typically 1-2 per session read)
- **No database writes** during migration (only on dirty, which is write anyway)

## Testing

Run all tests:
```bash
npm test -- backend/src/services/session
```

Tests cover:
- ✅ V1 → V3 migration
- ✅ V2 → V3 migration
- ✅ Current version (no migration)
- ✅ Missing version field (assume V1)
- ✅ Corrupt/invalid sessions
- ✅ Activity tracking
- ✅ Staleness detection
- ✅ Expiration checks
- ✅ PII hashing in events
- ✅ All migration functions implemented for version gaps

## Deployment

1. **Feature flag** (optional): Deploy with `SESSION_MIGRATION_ENABLED=false`, then flip to true
2. **Canary**: Monitor `session_migrated_total` metric for 1h before full rollout
3. **Health check**: Verify error rate on `session_invalid_total` stays < 0.1%
4. **Rollback**: Revert PR if issues detected; old sessions auto-accepted

## Related Issues

- #332: This feature (Versioned cookie/session schema)
- #333: Proactive client-side session refresh (depends on this)
- #334: BroadcastChannel multi-tab sync (depends on this)
- #346: FAANG-style session self-healing (epic)

---

**Version**: v3 (current)  
**Last updated**: 2026-04-16  
**Status**: In review (PR #XXX)
