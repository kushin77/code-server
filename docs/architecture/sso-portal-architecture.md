# Issue #1545: Enterprise Endpoint & SSO Portal - Technical Triage

**Issue**: Build kushnir.cloud full enterprise SaaS portal with OAuth2 SSO, custom domains, and multi-tenant architecture  
**Priority**: P1 (High)  
**Epic**: DevOS Enterprise Platform  
**Related**: #1534 (Governance), #1536 (Networking)  

## Executive Summary

Implement enterprise-grade authentication, authorization, and SaaS management portal to:
- Centralize user/team/organization management across kushnir.cloud + IDE
- Provide OAuth2/OIDC authentication with single session cookie
- Support custom domain routing and tenant isolation
- Enable self-serve onboarding and team management
- Integrate with GitHub/Google/Microsoft identity providers

**Success Criteria**:
- ✅ Login via OAuth2 (GitHub, Google, Microsoft) flows working
- ✅ Single session cookie valid across kushnir.cloud + ide.kushnir.cloud
- ✅ Multi-tenant architecture with secure data isolation
- ✅ Team/org management UI operational
- ✅ Custom domain support (e.g., team.kushnir.cloud)
- ✅ Production-ready (TLS, audit logging, rate limiting)

---

## Architecture Overview

### Domain Structure

```
┌─────────────────────────────────────────────────────────┐
│ kushnir.cloud (Public Portal + Admin)                  │
│ - Login/signup                                          │
│ - Org management                                        │
│ - Billing/settings                                      │
│ - Public marketplace                                    │
└─────────────────────────────────────────────────────────┘
         │
         ├── oauth-proxy (reverse proxy for auth)
         │
      [OAuth2 Authorization Server]
         │
         └─── ide.kushnir.cloud (IDE Instance)
             - Requires valid session from oauth-proxy
             - Team-scoped permissions
             - Integrations with platform services
```

### Session Architecture

**Single Session Model** (federated cookies):
- User logs in at `kushnir.cloud/auth`
- OAuth2 authorization server mints JWT token
- Session cookie set with domain `.kushnir.cloud` (matches all subdomains)
- IDE instance (`ide.kushnir.cloud`) validates token on each request
- Token refresh handled transparently

**Cookie Configuration**:
```
Set-Cookie: session_token=jwt_token; Domain=.kushnir.cloud; Path=/; 
            Secure; HttpOnly; SameSite=Lax; Max-Age=604800
```

---

## Phase 1: OAuth2 Authorization Server (Weeks 1-2)

### 1.1 OAuth2 Flows to Implement

**Authorization Code Flow** (primary - for browser apps):
```
1. User clicks "Login with GitHub"
2. Redirect to: oauth.kushnir.cloud/oauth/authorize?client_id=...&redirect_uri=...
3. User grants permissions on GitHub
4. GitHub redirects to callback with authorization code
5. Backend exchanges code for access token + refresh token
6. Frontend stores session cookie (JWT)
7. Redirect to requested page
```

**PKCE Support** (for native/mobile apps):
```
1. Generate code_verifier (43-128 chars, random)
2. code_challenge = base64url(sha256(code_verifier))
3. POST /oauth/token with code_challenge
4. Server validates: provided_challenge == sha256(provided_verifier)
```

**Refresh Token Flow**:
```
1. Access token expires (15 minutes)
2. Automatically POST /oauth/refresh with refresh_token
3. Get new access + refresh tokens
4. Update session cookie
```

### 1.2 Identity Provider Integration

**GitHub OAuth2**:
- Consumer key from [github.com/settings/apps](https://github.com/settings/apps)
- Scopes: `user:email`, `read:org`
- Webhook: GitHub notifies on user org changes

**Google OAuth2**:
- Client ID from Google Cloud Console
- Scopes: `openid`, `email`, `profile`
- Redirect URI: `https://oauth.kushnir.cloud/auth/google/callback`

**Microsoft Azure AD**:
- Tenant ID + Client ID from Azure portal
- Scopes: `openid`, `email`, `profile`
- Support for organizational multi-tenancy

### 1.3 Token Format & Security

**JWT Structure**:
```json
{
  "sub": "user:uuid",
  "email": "user@example.com",
  "org_id": "org:uuid",
  "teams": ["team:engineering", "team:product"],
  "permissions": ["read:repos", "write:settings"],
  "iat": 1234567890,
  "exp": 1234571490,
  "iss": "https://oauth.kushnir.cloud"
}
```

**Token Signing**:
- Algorithm: RS256 (RSA 2048 key)
- Public key published at `/.well-known/jwks.json`
- Private key stored in secrets manager (HashiCorp Vault)

---

## Phase 2: Frontend Portal (Weeks 2-3)

### 2.1 Pages & Components

**Public Pages** (no auth required):
- `/` - Landing page
- `/pricing` - Pricing table
- `/docs` - Documentation
- `/blog` - Blog/updates

**Auth Pages** (pre-login):
- `/auth/login` - OAuth2 provider selection
- `/auth/callback` - OAuth2 callback handler
- `/auth/register` - Self-service signup (optional)
- `/auth/forgot-password` - Password reset flow

**Authenticated Pages** (require valid session):
- `/dashboard` - Overview + quicklinks
- `/teams` - Team management
- `/settings` - User preferences
- `/billing` - Subscription + invoices
- `/org` - Organization settings
- `/admin` - System administration (superuser only)

### 2.2 UI Components

**Auth State Management**:
```typescript
// app/hooks/useAuth.ts
export function useAuth() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  
  useEffect(() => {
    // Verify session on mount
    fetch('/api/me').then(r => {
      if (r.ok) setUser(await r.json());
      else logout();
    });
  }, []);
  
  return { user, loading, isAuthenticated: !!user };
}
```

**Protected Route Component**:
```typescript
function ProtectedRoute({ children }) {
  const { isAuthenticated, loading } = useAuth();
  
  if (loading) return <Spinner />;
  if (!isAuthenticated) return <Navigate to="/auth/login" />;
  return children;
}
```

### 2.3 Team Management UI

**Team List Page**:
- Show user's teams + role
- Quick stats (members, repos, usage)
- Create team button
- Leave team action

**Team Detail Page**:
- Members tab (add/remove/change role)
- Settings tab (rename, danger zone)
- Billing tab (usage, payment method)
- Integrations tab (connected services)

**Create Team Modal**:
- Team name (validated, must be unique subdomain)
- Description
- Privacy (public/private)
- Initial members (email invites)

---

## Phase 3: Backend Services (Weeks 3-4)

### 3.1 API Endpoints

**Authentication**:
- `POST /auth/oauth/authorize` - Start OAuth flow
- `POST /auth/oauth/callback` - Handle provider callback
- `POST /auth/refresh` - Refresh access token
- `POST /auth/logout` - Revoke session

**User Management**:
- `GET /api/me` - Get current user
- `PATCH /api/me` - Update profile
- `GET /api/users/:id` - Get user details
- `DELETE /api/users/:id` - Delete user account

**Team Management**:
- `GET /api/teams` - List user's teams
- `POST /api/teams` - Create team
- `GET /api/teams/:id` - Get team details
- `PATCH /api/teams/:id` - Update team
- `DELETE /api/teams/:id` - Delete team
- `GET /api/teams/:id/members` - List members
- `POST /api/teams/:id/members` - Add member
- `PATCH /api/teams/:id/members/:uid` - Change role
- `DELETE /api/teams/:id/members/:uid` - Remove member

**Organization Management**:
- `GET /api/orgs` - List user's orgs
- `POST /api/orgs` - Create org
- `GET /api/orgs/:id` - Get org details
- `PATCH /api/orgs/:id` - Update org
- `DELETE /api/orgs/:id` - Delete org (admin only)

### 3.2 Database Schema

**users table**:
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  name VARCHAR(255),
  avatar_url TEXT,
  provider VARCHAR(50) NOT NULL, -- github, google, microsoft
  provider_id VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_provider ON users(provider, provider_id);
```

**teams table**:
```sql
CREATE TABLE teams (
  id UUID PRIMARY KEY,
  org_id UUID NOT NULL REFERENCES orgs(id),
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(100) UNIQUE NOT NULL,
  description TEXT,
  avatar_url TEXT,
  privacy VARCHAR(20) DEFAULT 'private', -- public, private
  created_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP,
  UNIQUE(org_id, slug)
);
```

**team_members table**:
```sql
CREATE TABLE team_members (
  id UUID PRIMARY KEY,
  team_id UUID NOT NULL REFERENCES teams(id),
  user_id UUID NOT NULL REFERENCES users(id),
  role VARCHAR(50) NOT NULL, -- owner, admin, member
  invited_at TIMESTAMP,
  joined_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(team_id, user_id)
);
```

### 3.3 Rate Limiting & Security

**Rate Limits**:
- Login attempts: 5 attempts per 15 minutes (IP-based)
- API requests: 1000 req/min per user (token-based)
- Signup: 10 accounts per hour per IP
- Password reset: 3 attempts per 24 hours per email

**Security Headers**:
```
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'
```

---

## Phase 4: Multi-Tenant & Custom Domains (Week 4)

### 4.1 Custom Domain Resolution

**DNS Requirements**:
- Team creates CNAME: `team.example.com` → `teams.kushnir.cloud`
- Or uses Kushnir subdomain: `team.kushnir.cloud` (automatic)

**Routing Logic**:
```
1. Request arrives: https://team.example.com/dashboard
2. Reverse proxy (oauth-proxy) checks Host header
3. Lookup custom domain in database
4. Verify TLS certificate (wildcard or per-domain)
5. Route to backend with tenant context
6. Backend uses tenant_id from Host header
7. Response includes tenant-specific data only
```

### 4.2 Data Isolation

**Query Pattern** (all queries filter by tenant):
```sql
SELECT * FROM teams 
WHERE id = $1 AND org_id = $2 AND org_id IN (
  SELECT org_id FROM team_members 
  WHERE user_id = $3
);
```

**Audit Trail**:
```sql
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY,
  org_id UUID NOT NULL,
  user_id UUID NOT NULL,
  action VARCHAR(255) NOT NULL,
  resource_type VARCHAR(100),
  resource_id UUID,
  details JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);
```

---

## Phase 5: IDE Integration (Week 5)

### 5.1 IDE Authentication

**Session Validation Flow**:
```
1. IDE loads: https://ide.kushnir.cloud/?workspace=project-1
2. Frontend checks for session cookie (from .kushnir.cloud domain)
3. If no cookie → redirect to https://kushnir.cloud/auth?return_to=...
4. After login → cookie set, redirect back to IDE
5. IDE validates token at /api/me
6. Display team/workspace context
```

### 5.2 IDE Permission Model

**Role-Based Access Control** (RBAC):
- `owner`: Full access (add/remove members, delete team)
- `admin`: Manage team settings, but not delete
- `member`: Read/write workspace
- `viewer`: Read-only workspace

**Permission Check Middleware**:
```typescript
// backend/middleware/authz.ts
function requirePermission(action: string) {
  return (req: Request, res: Response, next: NextFunction) => {
    const userRole = req.user.role;
    const allowed = PERMISSIONS[action]?.[userRole];
    if (!allowed) return res.status(403).json({ error: 'Forbidden' });
    next();
  };
}

const PERMISSIONS = {
  'workspace:read': { member: true, admin: true, owner: true },
  'workspace:write': { admin: true, owner: true },
  'team:settings': { admin: true, owner: true },
  'team:delete': { owner: true },
};
```

---

## Technology Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| Frontend | React | 18+ | Web UI for portal |
| Auth | next-auth / Auth0 | 5+ | OAuth2 provider |
| Backend | FastAPI / Node.js | 3.11+ / 18+ | REST API |
| Database | PostgreSQL | 14+ | User/team data |
| Cache | Redis | 7+ | Session store |
| Reverse Proxy | oauth2-proxy / Caddy | 7+ | Auth gate + routing |
| TLS | Let's Encrypt | - | HTTPS certificates |
| Logging | Loki + Promtail | Latest | Audit trail |
| Monitoring | Prometheus + Grafana | Latest | Metrics + dashboards |

---

## Work Breakdown Structure

### Week 1: OAuth2 Setup
- [ ] Configure GitHub/Google/Microsoft OAuth apps
- [ ] Implement OAuth2 authorization server
- [ ] JWT token generation + validation
- [ ] Refresh token mechanism
- **Deliverable**: `POST /auth/oauth/callback` working with GitHub

### Week 2: Frontend Portal & Auth UI
- [ ] Login page with provider selection
- [ ] OAuth callback handler
- [ ] Session management (useAuth hook)
- [ ] Protected routes
- **Deliverable**: Login flow working end-to-end

### Week 3: Team Management Backend
- [ ] User/team/org database schema
- [ ] Team CRUD API endpoints
- [ ] Member management (add/remove/role change)
- [ ] Authorization checks
- **Deliverable**: API tests passing (80%+ coverage)

### Week 4: Custom Domains & Multi-Tenancy
- [ ] DNS CNAME validation
- [ ] TLS certificate management (wildcard or per-domain)
- [ ] Tenant routing logic
- [ ] Data isolation verification
- **Deliverable**: Custom domain resolution working

### Week 5: IDE Integration & Production Hardening
- [ ] IDE login redirect flow
- [ ] Session cookie synchronization
- [ ] RBAC permission model
- [ ] Rate limiting + security headers
- [ ] End-to-end testing
- **Deliverable**: Production-ready deployment

---

## File Structure

```
apps/
  saas-api/                    # OAuth2 + team management
    src/
      auth/
        oauth.ts              # OAuth2 flows
        jwt.ts                # JWT generation/validation
        providers/            # GitHub, Google, Microsoft
      teams/
        router.ts             # Team API endpoints
        model.ts              # Team domain logic
        repository.ts         # Database queries
      orgs/
        router.ts
        model.ts
      users/
        router.ts
      middleware/
        authz.ts              # Authorization checks
        rate-limit.ts
  frontend/
    pages/
      auth/
        login.tsx             # Login page
        callback.tsx          # OAuth callback
      dashboard/
        index.tsx
      teams/
        list.tsx              # Team browser
        [id]/
          settings.tsx
          members.tsx
    hooks/
      useAuth.ts              # Session management
      useTeam.ts
    middleware/
      protectedRoute.tsx

docs/
  sso-architecture.md         # This document
  oauth2-flows.md             # Flow diagrams
  api-spec.md                 # OpenAPI spec
```

---

## Acceptance Criteria

- ✅ OAuth2 login with GitHub, Google, Microsoft
- ✅ Session persists across kushnir.cloud + ide.kushnir.cloud
- ✅ Team management CRUD operations working
- ✅ Member invitations sent via email
- ✅ Custom domain routing functional
- ✅ TLS certificates auto-renewing (Let's Encrypt)
- ✅ Audit logs recording all user actions
- ✅ Rate limiting preventing abuse
- ✅ API documented (Swagger/OpenAPI)
- ✅ Load testing validates 10K concurrent users
- ✅ 99.9% uptime SLA target

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Session cookie not shared across subdomains | High | Test domain=.kushnir.cloud early |
| OAuth token refresh race condition | Medium | Implement token refresh queue |
| Custom domain wildcard cert cost | Medium | Use Let's Encrypt (free) |
| N+1 queries on team membership | Medium | Implement connection pooling + caching |
| Token expiration during long sessions | Low | Automatic silent refresh (15min tokens) |

---

## Next Steps

1. **Immediate**: Create OAuth2 authorization server scaffold
2. **This week**: Get GitHub OAuth2 working end-to-end
3. **Next week**: Implement team management API
4. **Week 3**: Deploy to staging + load test
5. **Week 4**: Multi-tenant custom domains
6. **Week 5**: Production hardening + deployment

---

## References

- OAuth2 RFC 6749: https://tools.ietf.org/html/rfc6749
- OpenID Connect: https://openid.net/specs/openid-connect-core-1_0.html
- OWASP Authentication Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html
- nextjs + next-auth example: https://github.com/nextauthjs/next-auth-example
