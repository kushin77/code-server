# Phase 2: Service-to-Service Authentication
# Implementation Design for Issue #388 Phase 2

## Overview

Phase 2 implements JWT-based authentication between services in the code-server-enterprise infrastructure. Services use tokens issued by the oauth2-oidc-issuer (Phase 2.1) to authenticate requests to each other.

## Architecture

### Token Flow

```
┌─────────────────┐
│   Client Service│
└────────┬────────┘
         │
         │ 1. POST /oauth2/token
         │    (with client credentials)
         ▼
┌─────────────────────────────┐
│  oauth2-oidc-issuer (4182)  │
│  - Validates credentials    │
│  - Issues RS256 JWT         │
└────────┬────────────────────┘
         │
         │ 2. JWT Token
         ▼
┌─────────────────┐
│   Client Service│
│   (stores token)│
└────────┬────────┘
         │
         │ 3. GET /api/service
         │    Authorization: Bearer <JWT>
         ▼
┌──────────────────────────┐
│  Protected Service       │
│  - Validates JWT         │
│  - Uses public key (JWKS)│
│  - Returns resource      │
└──────────────────────────┘
```

### Components

**1. Client Credentials**
- Service account per calling service
- Stored in Google Secret Manager
- Format: `client_id:client_secret`

**2. JWT Tokens**
- Algorithm: RS256 (public key verification)
- Issuer: https://ide.kushnir.cloud
- Audience: code-server,api,github-actions,kubernetes
- Expiry: 3600 seconds (1 hour)
- Claims: sub, aud, iss, iat, exp, groups, actor

**3. Token Validation**
- Fetch JWKS from /.well-known/jwks.json
- Verify signature using public key
- Check expiry and time skew
- Cache JWKS for 1 hour (reduce network calls)

**4. Protected Services**
- code-server: Accept JWT in Authorization header
- API gateway: Validate all incoming requests
- Internal microservices: Validate peer tokens

## Implementation Tasks

### Task 1: Service Account Creation
- [ ] Create service accounts for:
  - api-server (internal API)
  - code-server-internal (code-server → API calls)
  - github-actions (external CI/CD)
  - kubernetes (K8s ServiceAccounts)
- [ ] Store credentials in Google Secret Manager
- [ ] Export as environment variables in docker-compose

### Task 2: JWT Validation Library
- [ ] Create/import JWT validation library
- [ ] Implement JWKS caching (1-hour TTL)
- [ ] Add time skew tolerance (±30 seconds)
- [ ] Create reusable middleware/decorator
- [ ] Support multiple token sources:
  - Authorization: Bearer <token>
  - X-Authorization-Token: <token>
  - Custom header per service

### Task 3: code-server Integration
- [ ] Implement JWT middleware in code-server
- [ ] Routes requiring JWT:
  - /api/* (all API endpoints)
  - /extensions/* (custom extensions)
  - /auth/* (authentication endpoints)
- [ ] Routes skipping JWT:
  - /health, /healthz (health checks)
  - /static/* (assets)
  - /login (initial login)
- [ ] Extract claims into request context:
  - User ID (sub)
  - Groups (groups)
  - Actor (actor - for GitHub Actions)

### Task 4: API Service Authentication
- [ ] Implement JWT validation middleware
- [ ] Create internal API endpoints for:
  - GET /api/services/health (no auth)
  - GET /api/services/{service}/status (JWT required)
  - POST /api/services/{service}/command (JWT + action auth)
- [ ] Service-to-service calls:
  - code-server calls API for metrics/logs
  - API calls code-server for workspace info

### Task 5: Token Caching & Refresh
- [ ] Implement token refresh mechanism:
  - Check expiry before making request
  - If < 300 seconds remaining: request new token
  - Cache tokens in Redis for 1 hour
  - Invalidate on refresh
- [ ] Create token management utility:
  - get_service_token(service_name)
  - refresh_token_if_expired(token)
  - invalidate_token_cache(service_name)

### Task 6: Testing & Validation
- [ ] Unit tests for JWT validation:
  - Valid token acceptance
  - Expired token rejection
  - Invalid signature rejection
  - Missing claims rejection
  - Time skew tolerance
- [ ] Integration tests:
  - Service-to-service communication
  - Token refresh flow
  - JWKS cache invalidation
  - Concurrent token requests
- [ ] End-to-end tests:
  - GitHub Actions token flow
  - Kubernetes ServiceAccount flow
  - Token expiration and refresh

### Task 7: Documentation & Rollout
- [ ] Update API documentation with auth requirements
- [ ] Create service account provisioning guide
- [ ] Document token acquisition process
- [ ] Monitor token usage and errors
- [ ] Gradual rollout to services:
  - Phase 2a: Logging only (no enforcement)
  - Phase 2b: Optional enforcement (service opt-in)
  - Phase 2c: Full enforcement

## Success Criteria

- [ ] All services can acquire JWT tokens from oauth2-oidc-issuer
- [ ] code-server validates tokens on protected endpoints
- [ ] Service-to-service communication works with JWT
- [ ] Token refresh works automatically before expiry
- [ ] JWKS caching reduces API calls by >90%
- [ ] No token validation errors in logs
- [ ] E2E tests pass for all flows
- [ ] Documentation complete and reviewed

## Timeline Estimate

- Task 1 (Service Accounts): 1-2 hours
- Task 2 (JWT Library): 2-3 hours
- Task 3 (code-server): 3-4 hours
- Task 4 (API Service): 2-3 hours
- Task 5 (Caching): 2-3 hours
- Task 6 (Testing): 3-4 hours
- Task 7 (Docs): 1-2 hours
- **Total: 14-21 hours**

## Related Issues

- Issue #388: Identity & Workload Authentication Standardization (P1)
- Issue #1018: Phase 2.1 OIDC Issuer Deployment (completed)
- Issue #1017: Infrastructure Recovery & Redeployment (completed)

## Implementation Status

- [ ] Started
- [ ] In Progress
- [ ] Testing
- [ ] Complete
