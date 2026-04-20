## Severity: CRITICAL (two independent findings combined)

---

## Finding 1 — Redis has no authentication (docker-compose.yml:480)

### Evidence
```yaml
redis:
  image: redis:7-alpine@sha256:...
  command: redis-server --appendonly yes
  # No --requirepass, no ACL configuration
```

### Risk
Every container on `net-app` can read/write all oauth2-proxy session data via direct Redis protocol.
- `redis-cli -h redis KEYS '*'` lists every active session token
- `GET <token>` returns full session payload including user identity
- `DEL <token>` logs out any user without authentication

An attacker who gains access to **any** container on `net-app` (e.g., a compromised sidecar) owns every active user session.

### Required Fix
1. Add `--requirepass ${REDIS_PASSWORD}` to the Redis `command:` in docker-compose.yml
2. Provision `REDIS_PASSWORD` via GSM: `gcloud secrets create redis-password --replication-policy=automatic`
3. Update both oauth2-proxy services: `OAUTH2_PROXY_REDIS_CONNECTION_URL: "redis://:${REDIS_PASSWORD}@redis:6379"`
4. Update session-broker Redis client to pass authentication credentials
5. Add `REDIS_PASSWORD` to `.env.schema.json` as a required variable

---

## Finding 2 — Shared `CODE_SERVER_PASSWORD` across all user sessions (apps/session-broker/src/index.ts:192)

### Evidence
```typescript
codeServerPassword: readRequiredEnv('CODE_SERVER_PASSWORD'),  // line ~192
```
The same single password is injected into every code-server container launched by session-broker.

### Risk
If a user discovers their own session password (e.g., via browser dev tools), they can authenticate to **any other user's** code-server container if they know the URL. Container URLs are predictable from session ID or container hostname patterns.

### Required Fix
1. Generate a cryptographically random per-session password in session-broker:
   ```typescript
   import { randomBytes } from 'crypto';
   const sessionPassword = randomBytes(32).toString('hex');
   ```
2. Pass this per-session password only to the specific container being launched (Docker `--env` at spawn time)
3. Store the password encrypted in the session record in PostgreSQL (AES-256-GCM with a GSM-backed encryption key)
4. Expose it only to the authenticated session owner via the session-broker proxy
5. Remove `CODE_SERVER_PASSWORD` as a global env var from docker-compose

---

## Definition of Done
- [ ] Redis requires authentication from all clients
- [ ] `REDIS_PASSWORD` sourced from GSM, injected via `.env`
- [ ] Both oauth2-proxy services pass credentials in `REDIS_CONNECTION_URL`
- [ ] Per-session code-server passwords generated with `crypto.randomBytes(32)`
- [ ] Global `CODE_SERVER_PASSWORD` removed from docker-compose env
- [ ] Per-session passwords stored encrypted in Postgres
- [ ] Penetration test: `redis-cli -h redis KEYS '*'` fails without auth from any container
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
