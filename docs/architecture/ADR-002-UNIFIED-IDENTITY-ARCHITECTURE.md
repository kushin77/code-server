# ADR-002: Unified Identity & RBAC Architecture

**Status**: DRAFT (awaiting architecture + security review)  
**Date**: April 16, 2026  
**Author**: Platform Engineering  
**Affected Components**: oauth2-proxy, code-server, Backstage, Appsmith, Ollama, Prometheus  

---

## Problem Statement

Current identity model relies exclusively on OAuth2 reverse proxy (oauth2-proxy) with no service-level authentication:

1. **No Service-to-Service Identity**: Backstage→GitHub, Appsmith→K8s, AI Gateway→Ollama lack explicit identity contracts
2. **No Role-Based Access Control**: Cannot distinguish admin actions from viewer actions at service level
3. **No Audit Trail**: Actions lack correlation to user identity and authorization decision
4. **No Least-Privilege Enforcement**: All authenticated users have same privilege level across all services

**Impact**:
- Medium: Service-to-service calls unauthenticated (rely on network isolation only)
- High: Privileged operations (deploy approvals, incident triggers) have no authz gate
- Medium: Impossible to audit who performed what action
- High: Cannot enforce least-privilege for individual microservices

---

## Solution Overview

### Identity Model Hierarchy

```
External Identity Provider (Google Workspace / Okta / Keycloak)
  ↓ (OAuth2/OIDC)
Unified OIDC Token Issuer
  ↓ (JWT)
  ├─ code-server (application layer)
  ├─ Backstage (catalog layer)
  ├─ Appsmith (operational layer)
  ├─ Ollama (AI layer)
  └─ Prometheus (metrics layer)
```

### Core Principles

1. **Single Source of Truth (SSOT)**: One OIDC provider, one JWT claims schema
2. **Service-Level Validation**: Every service validates JWT signature and claims independently
3. **Role Mapping**: External roles (GitHub teams, Google groups) → application roles (admin, operator, viewer)
4. **Immutable Audit Trail**: All auth decisions logged with user, service, action, resource, decision

---

## Architecture Design

### 1. OIDC Provider Selection

**Recommendation**: Google Workspace (on-prem testing uses service account + test users)

**Why Google Workspace**:
- native integration with GitHub teams (via workspace admin)
- PKCE + SameSite cookie support (modern security)
- Audit logging API for compliance
- Zero on-prem infrastructure required
- Scale: 50k+ users proven in production

**Fallback Option**: Keycloak (open-source, on-prem capable)

**Configuration**:
```yaml
oidc_issuer: https://accounts.google.com
client_id: ${GOOGLE_OAUTH_CLIENT_ID}  # From GCP credentials
client_secret: ${GOOGLE_OAUTH_CLIENT_SECRET}  # GCP Secret Manager
redirect_uri: https://code-server.192.168.168.31.nip.io/oauth2/callback
scopes:
  - openid
  - email
  - profile
  - https://www.googleapis.com/auth/userinfo.email
```

---

### 2. JWT Token Claims Schema

**Issued by**: OIDC provider (Google)  
**Consumed by**: All services (code-server, Backstage, Appsmith, etc.)  
**Validation**: Every service validates signature using provider's JWKS endpoint

**Claims Structure**:
```json
{
  "iss": "https://accounts.google.com",
  "sub": "user123",
  "aud": ["code-server", "backstage", "appsmith"],
  "email": "alex@company.com",
  "email_verified": true,
  "name": "Alex Kushnir",
  "picture": "https://...",
  "iat": 1713350000,
  "exp": 1713353600,
  "roles": ["admin", "sre"],
  "github_teams": ["platform-eng", "infrastructure"],
  "org_id": "org-prod-1",
  "correlation_id": "trace-abc123def456"
}
```

**Lifetime**: 1 hour (iat to exp)  
**Refresh**: Token refresh flow via OAuth2 code exchange  
**Revocation**: User action (logout) or TTL expiration

---

### 3. Role-Based Access Control (RBAC)

**Role Matrix**:

| Role | Service Access | Privileges | Examples |
|------|---|---|---|
| **admin** | code-server, Backstage, Appsmith, Prometheus, Jaeger | Deploy, restart services, approve incidents, rotate secrets | Platform lead, SRE lead |
| **operator** | code-server, Backstage, Appsmith, Prometheus, Jaeger | Run runbooks, approve releases, acknowledge alerts | On-call SRE, build engineer |
| **viewer** | code-server, Backstage, Prometheus, Jaeger | Read-only access | All engineers |
| **guest** | code-server (public docs only) | Browsing documentation | External partners |

**Mapping Sources**:
```
GitHub teams → Internal roles:
  - @platform-eng    → admin
  - @infrastructure  → admin
  - @oncall-sre      → operator
  - @all-engineers   → viewer

Google groups → Fallback roles:
  - admins-prod      → admin
  - ops-prod         → operator
  - company          → viewer
```

**Enforcement Points**:
1. **Reverse Proxy** (oauth2-proxy): Allow/deny access based on email domain or role claim
2. **Service Entrypoint** (middleware): Validate role for privileged operations
3. **API Authorization** (per endpoint): Fine-grained role checks (e.g., `/api/deploy/approve` requires `operator` or `admin`)

---

### 4. Service-to-Service Authentication

**Pattern**: Workload Identity via OIDC Self-Signed Tokens

**Flow**:
```
Service A needs to call Service B:
  1. Service A creates JWT signed with its own private key
  2. JWT includes: iss=service-a, sub=service-a, aud=service-b, exp=now+5min
  3. Service A sends request: Authorization: Bearer <JWT>
  4. Service B validates JWT signature using Service A's public key
  5. Service B allows request if signature valid + aud matches
```

**Implementation for Backstage→GitHub**:
```yaml
backstage:
  service_account: backstage-sa
  private_key: ${SECRET_MANAGER:backstage-sa-key}  # RSA-2048
  token_lifetime: 300  # seconds
  
github_api:
  audience: github.api
  verify_signature: true
  allowed_issuers:
    - backstage-sa
    - appsmith-sa
```

**Benefits**:
- No hardcoded API keys in environment
- Credentials rotated automatically via Secret Manager
- Audit trail: each request signed with service identity
- Zero setup for new services (OIDC endpoint standard)

---

### 5. Audit Logging Schema

**Table**: `audit_events` (PostgreSQL)

```sql
CREATE TABLE audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  user_id VARCHAR(255) NOT NULL,
  user_email VARCHAR(255) NOT NULL,
  service_name VARCHAR(255) NOT NULL,
  action VARCHAR(255) NOT NULL,
  resource_type VARCHAR(255),
  resource_id VARCHAR(255),
  authorization_decision VARCHAR(10) CHECK (authorization_decision IN ('ALLOW', 'DENY')),
  authorization_reason VARCHAR(1024),
  correlation_id UUID NOT NULL,
  source_ip INET,
  http_method VARCHAR(10),
  http_path VARCHAR(2048),
  request_duration_ms INTEGER,
  error_message VARCHAR(1024)
);

CREATE INDEX audit_events_user_id_idx ON audit_events(user_id);
CREATE INDEX audit_events_service_name_idx ON audit_events(service_name);
CREATE INDEX audit_events_timestamp_idx ON audit_events(timestamp);
CREATE INDEX audit_events_correlation_id_idx ON audit_events(correlation_id);
```

**Audit Event Examples**:

```json
// Privileged operation allowed
{
  "timestamp": "2026-04-16T14:05:00Z",
  "user_id": "user123",
  "user_email": "alex@company.com",
  "service_name": "appsmith",
  "action": "deploy.approve",
  "resource_type": "deployment",
  "resource_id": "deploy-456",
  "authorization_decision": "ALLOW",
  "authorization_reason": "user has operator role",
  "correlation_id": "trace-abc123def456"
}

// Unprivileged operation denied
{
  "timestamp": "2026-04-16T14:06:00Z",
  "user_id": "user456",
  "user_email": "viewer@company.com",
  "service_name": "appsmith",
  "action": "deploy.approve",
  "resource_type": "deployment",
  "resource_id": "deploy-457",
  "authorization_decision": "DENY",
  "authorization_reason": "user has viewer role, requires operator or admin",
  "correlation_id": "trace-def789ghi012"
}
```

---

### 6. Token Rotation & Lifecycle Management

**OAuth2 Code Flow** (user login):
```
1. Browser → code-server: GET /oauth2/start
2. code-server → Google: Redirects to Google login
3. User logs in via Google
4. Google → oauth2-proxy: Redirects with auth code
5. oauth2-proxy → Google: Exchanges code for access + ID token
6. oauth2-proxy: Stores refresh token in Redis (encrypted)
7. oauth2-proxy: Creates signed session cookie
8. oauth2-proxy → Browser: Sets httpOnly cookie
9. Browser → code-server: Subsequent requests include cookie
```

**Token Refresh**:
```
1. oauth2-proxy checks token expiration
2. If expired (< 5 minutes left): Calls token endpoint with refresh token
3. If refresh succeeds: Updates session, stores new refresh token
4. If refresh fails: Force re-authentication
```

**Credential Rotation** (quarterly):
```
Process:
1. Generate new OAuth2 client_secret in GCP
2. Update oauth2-proxy config (zero-downtime: rolling deploy)
3. Retire old secret (set TTL = 7 days, then delete)
4. Audit: Log rotation event
```

---

### 7. Emergency Access (Break-Glass)

**Scenario**: OIDC provider down, unable to authenticate  
**Solution**: Local service account + hardcoded API key (last resort)

**Procedure**:
```bash
# Emergency access via local account (requires physical access to 192.168.168.31)
ssh akushnir@192.168.168.31
sudo /scripts/emergency-access.sh  # Prompts for emergency key
# Creates temporary local JWT valid for 30 min
# Logs action: timestamp, action, requestor
```

**Safeguards**:
- Emergency access requires physical shell access (SSH key)
- Session limited to 30 minutes
- All actions audited with `EMERGENCY_ACCESS=true` flag
- Must be explicitly re-authorized every 30 min
- After incident: Audit trail reviewed by security team

---

## Implementation Phases

### Phase 1: Design & Security Review (Days 1-3)
- [ ] This ADR approved by architecture + security leads
- [ ] Threat model completed (attack surface analysis)
- [ ] Token claims finalized (no breaking changes after implementation)
- [ ] RBAC policy approved by SRE + product leads
- [ ] Audit schema reviewed for compliance requirements

### Phase 2: Code (Days 4-10)
- [ ] oauth2-proxy: Update configuration for PKCE + SameSite cookies
- [ ] code-server backend: Add JWT validation middleware
- [ ] All services: Add JWT decoder library + claim validation
- [ ] PostgreSQL: Create audit_events table
- [ ] Audit middleware: Implement for all services

### Phase 3: Integration Testing (Days 11-14)
- [ ] Integration test: oauth2-proxy ↔ Google OIDC ↔ code-server
- [ ] Service-to-service: Backstage JWT → GitHub API validation
- [ ] Audit trail: Verify all actions logged correctly
- [ ] Failure mode: OIDC down → emergency access workflow
- [ ] Performance: Auth check latency &lt;50ms p95

### Phase 4: Production Deployment (Week 3+)
- [ ] Canary: 10% of users → new auth flow
- [ ] Monitoring: Alert on auth failures, slow token validation
- [ ] Rollback: Feature flag to revert to current auth model
- [ ] Team training: Query audit logs, troubleshoot OIDC issues

---

## Success Criteria

- [ ] OIDC provider configured and working with at least 3 services
- [ ] Service-to-service auth working for 5+ service pairs
- [ ] RBAC enforced: Unprivileged users cannot access admin operations
- [ ] Audit logging: 100% of auth decisions logged with correlation ID
- [ ] Emergency access: Procedure documented and tested
- [ ] Performance: &lt;50ms p95 latency for auth checks under 1000 req/sec load
- [ ] Token rotation: Automated with zero downtime
- [ ] Compliance: Audit logs queryable by user/service/action/time, retained 90 days

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|---|---|---|
| OIDC provider unavailable | Low | High | Emergency access procedure + local fallback |
| Token signature verification fails | Low | High | Validate JWKS endpoint + signature algorithm |
| Role mapping misconfiguration | Medium | Medium | Role matrix peer review + canary rollout |
| Audit table grows too fast | Medium | Low | Implement retention policy (90 days) + archival |
| Auth check adds latency | Medium | Medium | Cache JWKS locally (1 hour TTL) + async refresh |

---

## References

- [OAuth2 PKCE Specification](https://tools.ietf.org/html/rfc7636)
- [JWT Best Practices](https://tools.ietf.org/html/rfc8949)
- [Google Workspace OIDC Configuration](https://developers.google.com/identity/openid-connect)
- [SameSite Cookie Security](https://web.dev/samesite-cookies-explained/)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)

---

**Next Action**: Schedule architecture review meeting with @kushin77 + security lead to approve this ADR before Phase 2 code begins.
