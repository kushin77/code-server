#!/usr/bin/env pwsh
# Batch issue creation from full codebase audit April 20 2026

Set-Location c:\code-server-enterprise

# ── Issue 970: Redis auth + per-session password ──────────────────────────────
$b970 = @'
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
An attacker who gains access to **any** container on `net-app` (e.g., a compromised sidecar) owns every user session.

### Required Fix
1. Add `--requirepass ${REDIS_PASSWORD}` to the Redis `command:` in docker-compose.yml
2. Provision `REDIS_PASSWORD` via GSM: `gcloud secrets create redis-password --replication-policy=automatic`
3. Update both oauth2-proxy services:
   ```yaml
   OAUTH2_PROXY_REDIS_CONNECTION_URL: "redis://:${REDIS_PASSWORD}@redis:6379"
   ```
4. Update session-broker Redis client to pass authentication credentials
5. Add `REDIS_PASSWORD` to `.env.schema.json` as a required variable

---

## Finding 2 — Shared `CODE_SERVER_PASSWORD` across all user sessions (apps/session-broker/src/index.ts:192)

### Evidence
```typescript
// apps/session-broker/src/index.ts line ~192
codeServerPassword: readRequiredEnv('CODE_SERVER_PASSWORD'),
```
```yaml
# docker-compose.yml line ~327
- CODE_SERVER_PASSWORD=${CODE_SERVER_PASSWORD:?...}
```
The same single password is injected into every code-server container launched by session-broker.

### Risk
If a user discovers their own session password (e.g., via browser developer tools inspecting the injected config), they can directly authenticate to **any other user's** code-server container if they know the URL. The URL is predictable from the session ID or container hostname pattern.

### Required Fix
1. Generate a cryptographically random per-session password in session-broker:
   ```typescript
   import { randomBytes } from 'crypto';
   const sessionPassword = randomBytes(32).toString('hex');
   ```
2. Pass this per-session password only to the specific container being launched (Docker `--env` at spawn time)
3. Store the password encrypted in the session record in PostgreSQL (use AES-256-GCM with a GSM-backed encryption key)
4. Expose it only to the authenticated session owner via the session-broker proxy; never in browser-accessible JS
5. Remove `CODE_SERVER_PASSWORD` as a global env var from docker-compose

---

## Definition of Done
- [ ] Redis requires authentication from all clients
- [ ] `REDIS_PASSWORD` sourced from GSM, injected via `.env`
- [ ] Both oauth2-proxy services pass credentials in `REDIS_CONNECTION_URL`
- [ ] Per-session code-server passwords generated with `crypto.randomBytes(32)`
- [ ] Global `CODE_SERVER_PASSWORD` removed from docker-compose env
- [ ] Per-session passwords stored encrypted in Postgres
- [ ] Penetration test: `redis-cli -h redis KEYS '*'` fails from any container without auth
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
'@

gh issue create --repo kushin77/code-server --title "P0 SECURITY: Redis has no authentication + shared code-server password across all user sessions" --label P0 --label security --assignee kushin77 --body "$b970"
Write-Host "970 done"
