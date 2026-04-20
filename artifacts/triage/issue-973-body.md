## Severity: HIGH (3 findings — session-broker hardening)

---

## Finding 1 — `sessionProxyHost` falls back to `127.0.0.1` (apps/session-broker/src/index.ts:161)

### Evidence
```typescript
sessionProxyHost: process.env.SESSION_PROXY_HOST?.trim()
               || process.env.DEPLOY_HOST?.trim()
               || '127.0.0.1',   // ← silent misconfiguration default
```

### Risk
If both `SESSION_PROXY_HOST` and `DEPLOY_HOST` are unset (e.g., fresh deployment on .42 without .env), all session URLs resolve to `127.0.0.1`. Users see their IDE load but get connection refused on every request. The error is silent — no startup failure, no log warning.

### Fix
Replace with a required env var using `readRequiredEnv` (already defined in the codebase):
```typescript
sessionProxyHost: readRequiredEnv('SESSION_PROXY_HOST'),
```
Add `SESSION_PROXY_HOST` to `.env.schema.json` as required, with validation that it resolves.

---

## Finding 2 — No rate limiting on session creation endpoint (apps/session-broker/src/index.ts)

### Evidence
Session creation routes (`POST /sessions`) have no rate limiting visible in the imports or middleware setup. No `express-rate-limit` import found.

### Risk
The session creation endpoint spawns a new Docker container (`docker run`) per request. An unauthenticated or authenticated attacker can:
- Fork-bomb the host by sending 1000 `POST /sessions` requests
- Exhaust disk space with code-server containers
- DoS the host for all other users

The existing `SESSION_MAX_CONCURRENT_PER_USER` env var suggests intent but doesn't replace HTTP-level rate limiting.

### Fix
```typescript
import rateLimit from 'express-rate-limit';

const sessionCreateLimiter = rateLimit({
  windowMs: 60 * 1000,       // 1 minute
  max: 5,                     // 5 session create attempts per minute per IP
  keyGenerator: (req) => req.user?.email || req.ip,
  message: { error: 'Too many session creation attempts, retry after 60 seconds' }
});

app.post('/sessions', sessionCreateLimiter, sessionCreateHandler);
```

---

## Finding 3 — session-broker image is mutable `:dev` tag (docker-compose.yml:312)

### Evidence
```yaml
session-broker:
  image: session-broker:dev   # mutable local tag
```
The `check-image-immutability.sh` script explicitly **allowlists** this as a local build.

### Risk
- On failover to host .42: the image may be absent or a different version (older build)
- No CI ensures the `:dev` image on .31 and .42 are identical
- Rollback is impossible (no version history)

### Fix
1. Build and push session-broker to a container registry on every merge to main:
   ```yaml
   # .github/workflows/build-session-broker.yml
   - docker build -t ghcr.io/kushin77/session-broker:${GITHUB_SHA} .
   - docker push ghcr.io/kushin77/session-broker:${GITHUB_SHA}
   ```
2. Reference by digest in docker-compose:
   ```yaml
   image: ghcr.io/kushin77/session-broker@sha256:<digest>
   ```
3. Remove the `:dev` allowlist from `check-image-immutability.sh`

---

## Definition of Done
- [ ] `SESSION_PROXY_HOST` is a required env var — startup fails if unset
- [ ] `express-rate-limit` middleware on session create endpoint (5 req/min per user)
- [ ] session-broker image pushed to registry with digest pin in docker-compose
- [ ] `:dev` allowlist removed from immutability check
- [ ] `process.on('unhandledRejection', ...)` handler added (prevents silent crashes)
- [ ] Input validation with Joi schemas confirmed on all route handlers
- [ ] Parent #967 updated with evidence

Fixes #967 (EPIC)
