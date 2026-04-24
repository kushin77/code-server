# Phase 2C Deployment - Progress Update

**Status**: OAuth2-OIDC-Issuer Configuration Issue (Recoverable)  
**Date**: April 21, 2026  
**Completed Steps**: 
✅ OIDC_ISSUER_SIGNING_KEY deployed to .env
✅ oauth2-proxy service restarted and healthy
❌ oauth2-oidc-issuer service crashing (configuration missing)

---

## Current Issue

The oauth2-oidc-issuer container is crashing on startup with:
```
invalid configuration:
  missing setting: cookie-secret
  provider missing setting: client-id
  missing setting: client-secret or client-secret-file
```

**Root Cause**: The service still requires standard OAuth2 configuration even in OIDC issuer mode.

**Solution**: Add the missing environment variables to docker-compose.yml for oauth2-oidc-issuer service.

---

## Required Environment Variables

The oauth2-oidc-issuer service needs these variables (for OIDC issuer operation):

```
# From .env.phase-2 or GSM
OAUTH2_PROXY_COOKIE_SECRET="<random 32-byte hex value>"
OAUTH2_PROXY_CLIENT_ID="code-server-issuer"
OAUTH2_PROXY_CLIENT_SECRET="<random secret>"

# Or use the ones already deployed:
SERVICE_CLIENT_BACKEND_ID
SERVICE_CLIENT_BACKEND_SECRET
SERVICE_CLIENT_SESSION_BROKER_ID
SERVICE_CLIENT_SESSION_BROKER_SECRET
IDE_SESSION_LB_SECRET
```

---

## Fix: Update docker-compose.yml

The oauth2-oidc-issuer service section needs these additional environment variables:

```yaml
oauth2-oidc-issuer:
  # ... existing config ...
  environment:
    # Existing OIDC settings...
    OIDC_ISSUER_SIGNING_KEY: "${OIDC_ISSUER_SIGNING_KEY}"
    
    # ADD THESE (missing):
    OAUTH2_PROXY_COOKIE_SECRET: "${OAUTH2_PROXY_COOKIE_SECRET:-${IDE_SESSION_LB_SECRET}}"
    OAUTH2_PROXY_CLIENT_ID: "${SERVICE_CLIENT_SESSION_BROKER_ID:-code-server-issuer}"
    OAUTH2_PROXY_CLIENT_SECRET: "${SERVICE_CLIENT_SESSION_BROKER_SECRET:-default-issuer-secret}"
    
    # Also ensure these exist:
    OAUTH2_PROXY_PROVIDER: "oidc"
    OAUTH2_PROXY_OIDC_ISSUER_URL: "https://ide.kushnir.cloud"
```

---

## Immediate Next Steps

### Option 1: Manual Fix (15 mins)
1. SSH to remote host
2. Edit docker-compose.yml to add the 3 missing environment variables
3. Restart oauth2-oidc-issuer service
4. Verify service is running

### Option 2: Update from Local (20 mins)
1. Update docker-compose.yml locally
2. git commit and push to remote  
3. Pull changes on remote
4. Restart service

### Option 3: Use Deployment Script (Auto)
Use the provisioning script to regenerate configuration:
```bash
bash scripts/ops/provision-phase-2-service-accounts.sh
```

---

## Verification Checklist

Once fixed, verify with:

```bash
# 1. Service running
docker-compose ps oauth2-oidc-issuer

# 2. OIDC endpoint responding
curl -s http://oauth2-oidc-issuer:4182/.well-known/openid-configuration | jq .

# 3. JWKS endpoint
curl -s http://oauth2-oidc-issuer:4182/.well-known/jwks.json | jq .

# 4. All services healthy
docker-compose ps
```

---

## Phase 2C Completion Criteria

- [x] OIDC_ISSUER_SIGNING_KEY added to .env
- [ ] oauth2-oidc-issuer service UP and healthy
- [ ] .well-known/openid-configuration endpoint responds (HTTP 200)
- [ ] oauth2-proxy UP and healthy
- [ ] code-server service UP and healthy
- [ ] All 9 services in docker-compose ps show as "Up"
- [ ] Browser test: Can access https://ide.kushnir.cloud and see login redirect

---

## Files to Update

- `docker-compose.yml` - Add environment variables to oauth2-oidc-issuer service
- OR run `scripts/ops/provision-phase-2-service-accounts.sh` to regenerate all configuration

---

**Estimated time to resolution**: 15-30 minutes  
**Next phase after fix**: Phase 2D (Observability) and Phase 2E (E2E Testing)
