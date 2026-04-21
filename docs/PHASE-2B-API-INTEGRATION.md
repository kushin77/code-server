# Phase 2B: API Integration Guide

**Status**: 🔄 IN PROGRESS  
**Scope**: Integrate JWT authentication into code-server and session-broker APIs  
**Effort**: 7-13 hours total (Phase 2B-2D)  
**Parent Issue**: #1019 (Phase 2 - Service-to-Service Authentication)  

## Overview

Phase 2B focuses on integrating the JWT authentication framework (created in Phase 2A) into the actual API endpoints of code-server and session-broker. This involves:

1. Adding JWT validation middleware to incoming API routes
2. Updating outbound service-to-service calls to use JWT bearer tokens
3. Configuring service credentials (client_id, client_secret) from Google Secret Manager
4. Maintaining backward compatibility with existing oauth2-proxy authentication

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 2B: API Integration                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Service A (code-server)                                        │
│  ├─ JwtTokenClient (acquires tokens)                            │
│  │  └─ POST /oauth2/token → OIDC issuer                         │
│  │     Response: { access_token, expires_in }                  │
│  │                                                              │
│  └─ Outbound API calls                                          │
│     ├─ GET /api/sessions                                        │
│     │  Header: Authorization: Bearer <JWT>                      │
│     │                                                           │
│     └─ POST /api/workspace/create                               │
│        Header: Authorization: Bearer <JWT>                      │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Service B (session-broker)                                     │
│  ├─ JwtValidator + JwtAuth Middleware (validates tokens)        │
│  │  └─ Incoming: Authorization: Bearer <JWT>                    │
│  │     Extracts and verifies claims                             │
│  │     Attaches req.jwt.claims to request                       │
│  │                                                              │
│  ├─ Incoming API routes                                         │
│  │  ├─ POST /api/sessions                                       │
│  │  │  Body: { ... }                                            │
│  │  │  Response: { sessionId, containerPort, ... }              │
│  │  │                                                           │
│  │  └─ GET /api/sessions/:sessionId                             │
│  │     Response: { status, containerId, ... }                   │
│  │                                                              │
│  └─ Outbound calls (to code-server, workspace service, etc.)    │
│     Header: Authorization: Bearer <JWT>                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Steps

### Step 1: Update Service Dependencies

Ensure all services have the required JWT libraries in `package.json`:

```bash
# In apps/backend/
pnpm add jose@catalog: jsonwebtoken@catalog: jwks-rsa@catalog:

# In apps/session-broker/
pnpm add jose@catalog: jsonwebtoken@catalog: jwks-rsa@catalog:
```

**Status**: ✅ Already added (see Phase 2A)

### Step 2: Configure Service Credentials in GSM

Each service that will make outbound API calls needs credentials registered in Google Secret Manager:

```bash
# Register code-server service credentials
gcloud secrets create code-server-client-id --replication-policy=automatic
echo -n "code-server" | gcloud secrets versions add code-server-client-id --data-file=-

gcloud secrets create code-server-client-secret --replication-policy=automatic
openssl rand -hex 32 | gcloud secrets versions add code-server-client-secret --data-file=-

# Register session-broker service credentials
gcloud secrets create session-broker-client-id --replication-policy=automatic
echo -n "session-broker" | gcloud secrets versions add session-broker-client-id --data-file=-

gcloud secrets create session-broker-client-secret --replication-policy=automatic
openssl rand -hex 32 | gcloud secrets versions add session-broker-client-secret --data-file=-

# Register other services similarly
gcloud secrets create workspace-service-client-id --replication-policy=automatic
gcloud secrets create workspace-service-client-secret --replication-policy=automatic
```

**Status**: 🔄 TODO - Requires credentials to be created on both hosts

### Step 3: Update docker-compose.yml

Add environment variables to each service so they can load credentials from GSM:

```yaml
# In docker-compose.yml

code-server:
  environment:
    # JWT Configuration
    OIDC_ISSUER_URL: http://oauth2-oidc-issuer:4182
    SERVICE_CLIENT_ID: ${CODE_SERVER_CLIENT_ID:-code-server}
    SERVICE_CLIENT_SECRET: ${CODE_SERVER_CLIENT_SECRET}
    JWT_AUDIENCE: https://code-server/api
    JWT_ENABLED: "true"

session-broker:
  environment:
    # JWT Configuration
    OIDC_ISSUER_URL: http://oauth2-oidc-issuer:4182
    SERVICE_CLIENT_ID: ${SESSION_BROKER_CLIENT_ID:-session-broker}
    SERVICE_CLIENT_SECRET: ${SESSION_BROKER_CLIENT_SECRET}
    JWT_AUDIENCE: https://session-broker/api
    JWT_ENABLED: "true"

workspace-service:
  environment:
    # JWT Configuration
    OIDC_ISSUER_URL: http://oauth2-oidc-issuer:4182
    SERVICE_CLIENT_ID: ${WORKSPACE_SERVICE_CLIENT_ID:-workspace-service}
    SERVICE_CLIENT_SECRET: ${WORKSPACE_SERVICE_CLIENT_SECRET}
    JWT_AUDIENCE: https://workspace-service/api
    JWT_ENABLED: "true"
```

**Status**: 🔄 TODO - Requires merge to docker-compose.yml

### Step 4: Integrate JWT Auth into code-server

Update the code-server application to:
1. Initialize JwtTokenClient at startup
2. Add JWT bearer token to outbound API calls
3. Add JWT validation middleware (optional, if code-server also receives service-to-service calls)

**Reference**: See `apps/backend/src/services/auth/integration-example.ts`

**Steps**:
1. Import JwtTokenClient and initialize at startup
2. Wrap all outbound fetch/axios calls to add `Authorization: Bearer <token>` header
3. Cache tokens locally to avoid token acquisition on every request
4. Handle token refresh automatically when approaching expiry

**Status**: 🔄 TODO - Requires code-server Express app identification and integration

### Step 5: Integrate JWT Auth into session-broker

Update the session-broker Express app to accept JWT tokens from the OIDC issuer:

**Reference**: See `apps/session-broker/src/jwt-auth-integration.ts`

**Steps**:
1. Create `SessionBrokerJwtAuth` adapter (already provided)
2. Add JWT middleware BEFORE route handlers:
   ```typescript
   const jwtAuth = new SessionBrokerJwtAuth({
     oidcIssuerUrl: process.env.OIDC_ISSUER_URL,
     audience: 'https://session-broker/api',
     clientId: process.env.SERVICE_CLIENT_ID,
     clientSecret: process.env.SERVICE_CLIENT_SECRET,
     fallbackToProxy: true, // Maintain backward compatibility
   });

   app.use(jwtAuth.middleware());
   ```
3. Update route handlers to use `req.authUser` or `req.jwt.claims`
4. Add optional claim-based authorization (e.g., require 'admin' group for sensitive operations)

**Status**: 🔄 TODO - Requires session-broker middleware integration

### Step 6: Add Observability (Phase 2D)

Add metrics and alerts for JWT token operations:

**Metrics to track**:
- Token acquisition latency (mean, p95, p99)
- Token cache hit rate
- JWKS cache hit rate
- Token validation failures (by reason)
- Token refresh frequency

**Alerts to configure**:
- Token acquisition latency > 500ms (warning)
- JWKS fetch failures (critical)
- Token validation failure rate > 5% (warning)
- Service unable to acquire tokens (critical)

**Status**: 🔄 TODO - Phase 2D scope

## Configuration Reference

### Environment Variables

```bash
# OIDC Issuer Configuration
OIDC_ISSUER_URL=http://oauth2-oidc-issuer:4182
OIDC_JWKS_CACHE_TTL_SECONDS=3600

# Service Credentials (from GSM)
SERVICE_CLIENT_ID=code-server
SERVICE_CLIENT_SECRET=<secret from GSM>

# JWT Configuration
JWT_AUDIENCE=https://code-server/api
JWT_ENABLED=true
JWT_TOKEN_CACHE_TTL_SECONDS=3600
JWT_REFRESH_BUFFER_SECONDS=300

# Redis Configuration (optional, for distributed caching)
REDIS_URL=redis://redis:6379
JWT_REDIS_ENABLED=true
```

### JWT Claims Format

Tokens issued by the OIDC issuer contain:

```json
{
  "sub": "code-server",           // Service name
  "aud": "https://session-broker/api",  // Target audience
  "iss": "http://oauth2-oidc-issuer:4182",
  "iat": 1713700000,              // Issued at
  "exp": 1713703600,              // Expires in 1 hour
  "groups": ["services", "core"],  // Optional: group membership
  "actor": "github-actions"        // Optional: actor (for GitHub Actions)
}
```

### Service Audiences

Each service should use a unique audience in their JwtTokenClient:

```
code-server       → https://code-server/api
session-broker    → https://session-broker/api
workspace-service → https://workspace-service/api
settings-service  → https://settings-service/api
```

## Validation Checklist

- [ ] All services have GSM credentials created
- [ ] docker-compose.yml updated with JWT environment variables
- [ ] code-server initialized with JwtTokenClient
- [ ] code-server outbound calls include JWT bearer tokens
- [ ] session-broker middleware validates incoming JWT tokens
- [ ] session-broker outbound calls include JWT bearer tokens
- [ ] Backward compatibility with oauth2-proxy headers maintained
- [ ] Token refresh works correctly (test with 5-minute refresh buffer)
- [ ] Outbound token acquisition cached to avoid performance impact
- [ ] Metrics collected for token operations (latency, cache hit rate)
- [ ] Alerts configured for token validation failures
- [ ] E2E test: service-to-service call with JWT succeeds
- [ ] E2E test: invalid token rejected with 401
- [ ] E2E test: failover between hosts maintains JWT auth

## Testing Strategy

### Unit Tests
- Token validation with valid/expired/invalid tokens
- Token caching and refresh behavior
- Bearer token extraction from Authorization header

### Integration Tests
- Service A → Service B call with JWT
- Service B validates JWT and returns data
- Token refresh during long-running operation
- Fallback to oauth2-proxy headers works

### E2E Tests
- Browser login → code-server → session-broker call → session created
- Verify JWT used for service-to-service communication
- Failover: primary down, replica handles service-to-service call with same JWT

## Rollout Plan

1. **Canary (1 service)**: Deploy JWT auth to session-broker first (non-breaking)
2. **Staged (remaining services)**: Deploy to code-server, workspace-service, settings-service
3. **GA (all services)**: All service-to-service calls use JWT
4. **Deprecate**: Mark oauth2-proxy headers as deprecated (keep for 1 release)
5. **Remove**: Remove oauth2-proxy header support after sufficient runway

## Related Issues

- #1018: Phase 2.1 OIDC Issuer Deployment (COMPLETE)
- #388: Identity & Workload Authentication Standardization (P1)
- #1017: Infrastructure Recovery & Redeployment (resolved)

## Next Steps

1. **Phase 2B (API Integration)**: This document - integrate JWT into APIs
2. **Phase 2C (Deployment)**: Deploy to both production hosts
3. **Phase 2D (Observability)**: Add metrics, alerts, Grafana dashboards
4. **Phase 2E (E2E Testing)**: Write comprehensive E2E tests
5. **Phase 2F (Cleanup)**: Deprecate and remove oauth2-proxy headers

## Implementation Resources

**Code Examples**:
- Integration example: `apps/backend/src/services/auth/integration-example.ts`
- Session-broker adapter: `apps/session-broker/src/jwt-auth-integration.ts`

**Architecture Docs**:
- Phase 2 Overview: `docs/PHASE-2-SERVICE-TO-SERVICE-AUTH.md`
- JWT Validator Details: `apps/backend/src/services/auth/jwt-validator.ts`
- JWT Token Client Details: `apps/backend/src/services/auth/jwt-token-client.ts`

## Definition of Done

- [x] Integration example created (code-server, session-broker)
- [x] JWT adapter for session-broker created
- [ ] Service credentials created in GSM (code-server, session-broker, others)
- [ ] docker-compose.yml updated with JWT environment variables
- [ ] code-server Express app identified and integrated
- [ ] session-broker middleware integrated
- [ ] Backward compatibility with oauth2-proxy verified
- [ ] Token caching verified to not impact performance
- [ ] Phase 2C deployment procedures documented
- [ ] Phase 2D observability metrics identified

## Progress Summary

**Phase 2A**: ✅ COMPLETE - JWT validator, client, middleware, Redis cache, tests, docs  
**Phase 2B**: 🔄 IN PROGRESS - API integration  
**Phase 2C**: 🔄 PENDING - Deployment to hosts  
**Phase 2D**: 🔄 PENDING - Observability setup  
**Phase 2E**: 🔄 PENDING - E2E testing  

**Estimated Time to Complete Phase 2**: 7-13 hours
