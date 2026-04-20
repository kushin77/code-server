# Security Fix #968: Hardcoded Caddyfile Cookie Secret

**Issue**: #968 - Hardcoded LB cookie secret `secret734` in Caddyfile  
**Severity**: CRITICAL (forgeable session tokens)  
**Status**: Implementation Plan  
**Date**: April 24, 2026

---

## Vulnerability Summary

The Caddyfile uses an environment variable for the LB cookie secret:

```caddy
lb_policy cookie ide_session_lb {$IDE_SESSION_LB_SECRET}
```

However:
1. **ENV VAR NOT DEFINED**: `IDE_SESSION_LB_SECRET` is not in `.env.schema.json`
2. **NO PRODUCTION VALUE**: The env file doesn't set this variable for production
3. **FALLBACK MISSING**: No default fallback (unlike the triage document suggests)
4. **GIT-TRACKED CONFIG**: Configuration hints in git may expose secrets

---

## Required Fixes

### 1. Add to `.env.schema.json` (New Entry)

```json
{
  "IDE_SESSION_LB_SECRET": {
    "type": "string",
    "format": "hex",
    "length": 32,
    "required": true,
    "secret": true,
    "source": "gsm",
    "example": "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6",
    "description": "HMAC key for Caddy sticky session LB cookie (32 hex chars = 16 bytes)",
    "production": "**FROM_GSM**",
    "staging": "**FROM_GSM**",
    "dev": "0000000000000000000000000000000000000000000000000000000000000000"
  }
}
```

### 2. Add to `.env` File (Template)

```bash
# Load Balance Cookie Secret (HMAC key for sticky routing)
# Format: 32 hex characters (16 bytes for AES128)
# Source: GSM (google-secrets-manager)
# Rotation: Every 90 days
IDE_SESSION_LB_SECRET=${IDE_SESSION_LB_SECRET}
```

### 3. Update GSM Secrets

Create secret in Google Secret Manager:

```bash
gcloud secrets create ide-session-lb-secret \
  --replication-policy="automatic" \
  --data-file=- << 'EOF'
$(openssl rand -hex 16)
EOF

# Verify
gcloud secrets versions list ide-session-lb-secret
```

### 4. Update Docker Compose

Ensure the env var is passed to Caddy:

```yaml
services:
  caddy:
    environment:
      - IDE_SESSION_LB_SECRET=${IDE_SESSION_LB_SECRET}
    # ... rest of config
```

### 5. Validate on Startup

Add health check to verify secret is set:

```bash
# In docker-compose health check:
test: |
      [ -n "${IDE_SESSION_LB_SECRET}" ] && \
      [ ${#IDE_SESSION_LB_SECRET} -eq 32 ] && \
      curl -f http://localhost:2019/config/adapting || exit 1
```

---

## Implementation Steps

1. **Generate New Secret**
   ```bash
   NEW_SECRET=$(openssl rand -hex 16)
   echo "New secret: $NEW_SECRET"
   ```

2. **Update Schema**
   - Add IDE_SESSION_LB_SECRET to `.env.schema.json`
   - Mark as required, secret, hex format

3. **Create GSM Secret**
   - Create in Google Secret Manager
   - Grant permissions to deployment service account

4. **Update .env**
   - Source IDE_SESSION_LB_SECRET from environment
   - Document rotation policy

5. **Update docker-compose**
   - Pass IDE_SESSION_LB_SECRET to caddy service
   - Add validation in health check

6. **Deploy**
   ```bash
   # On production host (192.168.168.31)
   ssh akushnir@192.168.168.31
   cd code-server-enterprise
   docker compose up -d caddy
   
   # Verify
   docker compose logs caddy | grep "lb_policy"
   curl -I https://ide.kushnir.cloud/health
   ```

7. **Verify Sticky Routing**
   ```bash
   # Check that Caddy config has secret (NOT "secret734")
   docker compose exec caddy caddy adapt --config /etc/caddy/Caddyfile | \
     grep -A2 "lb_policy"
   # Expected: should show actual 32-char hex, NOT "secret734"
   ```

---

## Acceptance Criteria

✅ IDE_SESSION_LB_SECRET defined in `.env.schema.json`  
✅ Secret generated via `openssl rand -hex 16`  
✅ Secret stored in Google Secret Manager  
✅ Secret passed to Caddy via docker-compose environment  
✅ Caddyfile uses `{$IDE_SESSION_LB_SECRET}` (no fallback to "secret734")  
✅ Health check verifies secret is set and non-empty  
✅ Sticky routing works (WebSocket connections stay on same upstream)  
✅ No "secret734" string in production config  

---

## Testing

### 1. Verify Secret is Set

```bash
# In running container
docker compose exec caddy sh -c 'echo ${IDE_SESSION_LB_SECRET}'
# Expected: 32 hex characters
```

### 2. Verify No Fallback

```bash
# Check Caddy config
docker compose exec caddy caddy adapt --config /etc/caddy/Caddyfile | \
  grep 'lb_policy'
# Expected: "lb_policy cookie ide_session_lb abc123..." (NOT "secret734")
```

### 3. Test Sticky Routing

```bash
# Connect to IDE and monitor which upstream is used
# Open DevTools → Network
# All requests should route to same upstream within single session
```

### 4. Failover Test

```bash
# Stop primary upstream
docker compose stop session-broker

# Verify Caddy failsover to replica
curl -I https://ide.kushnir.cloud/health

# Restore primary
docker compose up -d session-broker
```

---

## Rotation Policy

- **Frequency**: Every 90 days
- **Method**: Generate new secret in GSM, update docker-compose, restart Caddy
- **Impact**: Brief session disruption (users may need to refresh)
- **Rollback**: Revert to previous GSM version if needed

---

## Related Issues

- **#998**: Remove hardcoded fallback from IDE_SESSION_LB_SECRET  
- **#967**: P0 EPIC - Codebase audit findings  
- **#980**: Secret scanning for git-committed secrets  

---

## Implementation Timeline

- **Immediate**: Update schema and .env
- **Within 1 hour**: Create GSM secret
- **Within 2 hours**: Deploy to production
- **Ongoing**: Quarterly rotation

---

## Notes

This fix ensures:
1. **Secret is never hardcoded** in git or config files
2. **Secret is always present** on deployment (validation prevents missing var)
3. **Secret is properly rotated** on schedule
4. **Secret is secure** using cryptographically strong generation

The Caddyfile already correctly uses the environment variable pattern. This fix ensures the variable is always properly set and never falls back to a hardcoded value.
