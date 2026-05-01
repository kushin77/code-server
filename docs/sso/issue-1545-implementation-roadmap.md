# Issue #1545 Implementation Roadmap - Enterprise SaaS Portal

**Status**: 🟡 Triage Complete - Ready for Development Sprint  
**Effort**: 40-50 hours over 5 weeks  
**Teams**: Backend (OAuth2 setup, API), Frontend (UI/UX), DevOps (TLS, deployment)  

---

## Milestone 1: OAuth2 Authorization Server (Week 1)

**Goal**: Implement OAuth2/OIDC provider supporting GitHub, Google, Microsoft identity sources

### Tasks

#### 1.1 Project Setup
```bash
# Create OAuth2 service scaffold
mkdir -p apps/saas-api/src/{auth,config,middleware,types}
cd apps/saas-api

# Initialize with FastAPI (Python) or Express (Node.js)
# Option A: FastAPI (Python)
pip install fastapi python-jose[cryptography] passlib[bcrypt] sqlalchemy
# Option B: Express (TypeScript)
npm install express jsonwebtoken jwks-rsa passport-oauth2
```

**Deliverables**:
- [ ] apps/saas-api created with health check endpoint
- [ ] `GET /health` returning `{ "status": "healthy" }`
- [ ] Environment variables schema updated
- [ ] Dockerfile created for saas-api service

#### 1.2 OAuth2 Configuration
```python
# apps/saas-api/src/config/oauth.py
OAUTH_PROVIDERS = {
    'github': {
        'client_id': os.getenv('GITHUB_CLIENT_ID'),
        'client_secret': os.getenv('GITHUB_CLIENT_SECRET'),
        'authorize_url': 'https://github.com/login/oauth/authorize',
        'token_url': 'https://github.com/login/oauth/access_token',
        'scopes': ['user:email', 'read:org'],
    },
    'google': {
        'client_id': os.getenv('GOOGLE_CLIENT_ID'),
        'client_secret': os.getenv('GOOGLE_CLIENT_SECRET'),
        'authorize_url': 'https://accounts.google.com/o/oauth2/v2/auth',
        'token_url': 'https://oauth2.googleapis.com/token',
        'scopes': ['openid', 'email', 'profile'],
    },
    # ... microsoft
}
```

**Deliverables**:
- [ ] OAuth provider configs for GitHub, Google, Microsoft
- [ ] .env.example updated with OAUTH_* variables
- [ ] .env.schema.json includes OAUTH variables

#### 1.3 JWT Token Generation
```python
# apps/saas-api/src/auth/jwt.py
class TokenManager:
    def generate_token(self, user: User, expires_in: int = 900) -> str:
        """Generate signed JWT access token (15 min default)"""
        payload = {
            'sub': str(user.id),
            'email': user.email,
            'org_id': str(user.org_id),
            'iat': datetime.utcnow(),
            'exp': datetime.utcnow() + timedelta(seconds=expires_in),
        }
        return jwt.encode(payload, PRIVATE_KEY, algorithm='RS256')
    
    def verify_token(self, token: str) -> dict:
        """Verify JWT signature and return claims"""
        return jwt.decode(token, PUBLIC_KEY, algorithms=['RS256'])
```

**Deliverables**:
- [ ] JWT token generation working
- [ ] RS256 key pair generated and stored in secrets
- [ ] Token verification middleware implemented
- [ ] `POST /auth/verify-token` endpoint returning claims

#### 1.4 OAuth2 Authorization Flow
```python
# apps/saas-api/src/auth/oauth.py
@app.get('/auth/oauth/authorize/{provider}')
def authorize(provider: str):
    """Redirect user to provider for authorization"""
    state = secrets.token_urlsafe(32)
    # Store state in Redis (expire in 10 min)
    redis.set(f'oauth:state:{state}', provider, ex=600)
    
    params = {
        'client_id': OAUTH_PROVIDERS[provider]['client_id'],
        'redirect_uri': f'{REDIRECT_URL}/auth/oauth/callback',
        'scope': ' '.join(OAUTH_PROVIDERS[provider]['scopes']),
        'state': state,
        'response_type': 'code',
    }
    return RedirectResponse(url=f"{OAUTH_PROVIDERS[provider]['authorize_url']}?{urlencode(params)}")

@app.get('/auth/oauth/callback')
async def oauth_callback(code: str, state: str):
    """Handle OAuth provider callback"""
    # Verify state matches (prevent CSRF)
    provider = redis.get(f'oauth:state:{state}')
    if not provider:
        return JSONResponse({'error': 'Invalid state'}, 401)
    
    # Exchange code for access token
    token_response = requests.post(
        OAUTH_PROVIDERS[provider]['token_url'],
        data={
            'client_id': OAUTH_PROVIDERS[provider]['client_id'],
            'client_secret': OAUTH_PROVIDERS[provider]['client_secret'],
            'code': code,
        }
    )
    
    # Get user info from provider
    user_info = get_provider_user(provider, token_response['access_token'])
    
    # Create or update user in database
    user = User.upsert(
        email=user_info['email'],
        provider=provider,
        provider_id=user_info['id'],
        name=user_info['name'],
        avatar_url=user_info['avatar_url'],
    )
    
    # Generate session token
    access_token = token_manager.generate_token(user)
    refresh_token = token_manager.generate_refresh_token(user)
    
    # Redirect to frontend with token
    return RedirectResponse(
        url=f"{FRONTEND_URL}?access_token={access_token}&refresh_token={refresh_token}"
    )
```

**Deliverables**:
- [ ] `GET /auth/oauth/authorize/{provider}` working
- [ ] `GET /auth/oauth/callback` handling all 3 providers
- [ ] User created in database on first login
- [ ] Session tokens returned to frontend

#### 1.5 Testing
```bash
# Test OAuth flow with GitHub
# 1. Register app at https://github.com/settings/apps
# 2. Set GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET
# 3. Visit http://localhost:3000/auth/oauth/authorize/github
# 4. GitHub redirects back with ?code=... and ?state=...
# 5. Verify callback creates user and returns tokens
```

**Deliverables**:
- [ ] Integration test: `test_oauth_github_flow()`
- [ ] Integration test: `test_oauth_token_refresh()`
- [ ] Manual testing with all 3 providers complete
- [ ] Postman collection for OAuth endpoints

---

## Milestone 2: Frontend Portal & Authentication UI (Week 2)

**Goal**: Build login pages, session management, and protected routes

### Tasks

#### 2.1 Login Page
```tsx
// apps/frontend/pages/auth/login.tsx
import { useNavigate, useSearchParams } from 'react-router-dom';

export default function LoginPage() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const returnTo = searchParams.get('return_to') || '/dashboard';
  
  const loginWith = (provider: 'github' | 'google' | 'microsoft') => {
    window.location.href = `${API_URL}/auth/oauth/authorize/${provider}?return_to=${returnTo}`;
  };
  
  return (
    <div className="login-container">
      <h1>Sign in to Kushnir Cloud</h1>
      <button onClick={() => loginWith('github')}>Sign in with GitHub</button>
      <button onClick={() => loginWith('google')}>Sign in with Google</button>
      <button onClick={() => loginWith('microsoft')}>Sign in with Microsoft</button>
    </div>
  );
}
```

**Deliverables**:
- [ ] Login page with 3 provider buttons
- [ ] Styled with consistent branding
- [ ] Return URL handling (return_to parameter)
- [ ] Error message display

#### 2.2 OAuth Callback Handler
```tsx
// apps/frontend/pages/auth/callback.tsx
import { useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';

export default function CallbackPage() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { setSession } = useAuth();
  
  useEffect(() => {
    const accessToken = searchParams.get('access_token');
    const refreshToken = searchParams.get('refresh_token');
    const returnTo = searchParams.get('return_to') || '/dashboard';
    
    if (!accessToken) {
      navigate('/auth/login?error=missing_token');
      return;
    }
    
    // Store tokens in localStorage and set auth context
    setSession({ accessToken, refreshToken });
    
    // Set httpOnly cookie for subdomain sharing
    // (server-side via Set-Cookie header)
    
    // Redirect to original page
    navigate(returnTo);
  }, [searchParams, navigate, setSession]);
  
  return <div>Loading...</div>;
}
```

**Deliverables**:
- [ ] Callback page extracts token from URL
- [ ] Tokens stored securely (httpOnly cookie for main token)
- [ ] Redirect to return_to or dashboard
- [ ] Error handling for missing/invalid tokens

#### 2.3 Session Management Hook
```tsx
// apps/frontend/hooks/useAuth.ts
import { useState, useEffect, useContext, createContext } from 'react';

interface User {
  id: string;
  email: string;
  name: string;
  avatar_url: string;
  org_id: string;
}

interface AuthContext {
  user: User | null;
  loading: boolean;
  isAuthenticated: boolean;
  logout: () => Promise<void>;
  refreshSession: () => Promise<void>;
}

const AuthCtx = createContext<AuthContext | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  
  useEffect(() => {
    // Check if session is valid on app start
    verifySession();
    
    // Refresh token before expiry (every 10 min for 15 min tokens)
    const interval = setInterval(refreshSession, 600000);
    return () => clearInterval(interval);
  }, []);
  
  const verifySession = async () => {
    try {
      const response = await fetch(`${API_URL}/api/me`, {
        credentials: 'include', // Include session cookie
      });
      if (response.ok) {
        const userData = await response.json();
        setUser(userData);
      } else {
        setUser(null);
      }
    } catch (error) {
      console.error('Session verification failed:', error);
      setUser(null);
    } finally {
      setLoading(false);
    }
  };
  
  const refreshSession = async () => {
    // Call backend to refresh token
    try {
      await fetch(`${API_URL}/auth/refresh`, { method: 'POST' });
    } catch (error) {
      console.error('Token refresh failed:', error);
      setUser(null);
    }
  };
  
  const logout = async () => {
    await fetch(`${API_URL}/auth/logout`, { method: 'POST' });
    setUser(null);
  };
  
  return (
    <AuthCtx.Provider value={{ user, loading, isAuthenticated: !!user, logout, refreshSession }}>
      {children}
    </AuthCtx.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthCtx);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
```

**Deliverables**:
- [ ] AuthProvider wrapping app root
- [ ] useAuth hook for consuming auth state
- [ ] Automatic token refresh mechanism
- [ ] Logout functionality

#### 2.4 Protected Routes
```tsx
// apps/frontend/components/ProtectedRoute.tsx
import { Navigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';

export function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { user, loading, isAuthenticated } = useAuth();
  
  if (loading) return <div>Loading...</div>;
  
  if (!isAuthenticated) {
    return <Navigate to={`/auth/login?return_to=${window.location.pathname}`} replace />;
  }
  
  return children;
}

// Usage in router
<Routes>
  <Route path="/auth/login" element={<LoginPage />} />
  <Route path="/auth/callback" element={<CallbackPage />} />
  <Route path="/dashboard" element={<ProtectedRoute><DashboardPage /></ProtectedRoute>} />
</Routes>
```

**Deliverables**:
- [ ] ProtectedRoute component
- [ ] Unauthenticated users redirected to login
- [ ] Return URL preserved for post-login redirect

#### 2.5 Dashboard Page
```tsx
// apps/frontend/pages/dashboard/index.tsx
import { useAuth } from '@/hooks/useAuth';
import { useTeams } from '@/hooks/useTeams';

export default function DashboardPage() {
  const { user } = useAuth();
  const { teams, loading } = useTeams();
  
  return (
    <div>
      <h1>Welcome, {user?.name}!</h1>
      <div className="stats">
        <p>Teams: {teams.length}</p>
        <p>Organization: {user?.org_id}</p>
      </div>
      <div className="teams-list">
        <h2>Your Teams</h2>
        {teams.map(team => (
          <TeamCard key={team.id} team={team} />
        ))}
      </div>
      <button onClick={() => navigate('/teams/create')}>Create Team</button>
    </div>
  );
}
```

**Deliverables**:
- [ ] Dashboard displays user info
- [ ] Teams list showing user's teams
- [ ] Quick navigation to common actions
- [ ] Logout button

#### 2.6 Testing
```typescript
// tests/auth.spec.ts
describe('Authentication Flow', () => {
  test('should redirect to login when not authenticated', () => {
    const { getByText } = render(<ProtectedRoute><div>Protected</div></ProtectedRoute>);
    expect(window.location.href).toContain('/auth/login');
  });
  
  test('should render protected content when authenticated', () => {
    // Mock useAuth to return user
    const { getByText } = render(<ProtectedRoute><div>Protected</div></ProtectedRoute>);
    expect(getByText('Protected')).toBeInTheDocument();
  });
});
```

**Deliverables**:
- [ ] Unit tests for useAuth hook
- [ ] Integration tests for login flow
- [ ] Protected route tests
- [ ] 80%+ test coverage

---

## Milestone 3: Team Management API (Week 3)

**Goal**: Implement team CRUD, member management, and database schema

### Tasks

#### 3.1 Database Schema
```sql
-- apps/backend/migrations/001_init_schema.sql

CREATE TABLE IF NOT EXISTS orgs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(100) UNIQUE NOT NULL,
  owner_id UUID NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS teams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(100) NOT NULL,
  description TEXT,
  avatar_url TEXT,
  privacy VARCHAR(20) DEFAULT 'private',
  created_by UUID NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP,
  UNIQUE(org_id, slug)
);

CREATE TABLE IF NOT EXISTS team_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(50) NOT NULL CHECK (role IN ('owner', 'admin', 'member')),
  invited_by UUID,
  invited_at TIMESTAMP,
  joined_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(team_id, user_id)
);

CREATE INDEX idx_teams_org_id ON teams(org_id);
CREATE INDEX idx_teams_slug ON teams(slug);
CREATE INDEX idx_team_members_user_id ON team_members(user_id);
```

**Deliverables**:
- [ ] Migration file created
- [ ] Schema reviewed and approved
- [ ] Indexes added for common queries
- [ ] Migration runs successfully

#### 3.2 Team API Endpoints
```python
# apps/saas-api/src/teams/router.py
from fastapi import APIRouter, Depends, HTTPException
from .model import Team, TeamMember
from .repository import TeamRepository

router = APIRouter(prefix='/teams', tags=['teams'])

# GET /teams - List user's teams
@router.get('/')
async def list_teams(current_user: User = Depends(get_current_user)):
    """List all teams the user is a member of"""
    return await TeamRepository.find_by_user(current_user.id)

# POST /teams - Create team
@router.post('/')
async def create_team(
    req: CreateTeamRequest,
    current_user: User = Depends(get_current_user)
):
    """Create a new team"""
    team = Team(
        org_id=current_user.org_id,
        name=req.name,
        slug=req.slug,  # validated to be unique + lowercase
        description=req.description,
        privacy=req.privacy or 'private',
        created_by=current_user.id,
    )
    created = await TeamRepository.save(team)
    
    # Add creator as owner
    await TeamRepository.add_member(
        team_id=created.id,
        user_id=current_user.id,
        role='owner',
    )
    
    return created

# GET /teams/:id - Get team details
@router.get('/{team_id}')
async def get_team(team_id: UUID, current_user: User = Depends(get_current_user)):
    team = await TeamRepository.find_by_id(team_id)
    if not team or team.org_id not in current_user.org_ids:
        raise HTTPException(status_code=404)
    return team

# PATCH /teams/:id - Update team
@router.patch('/{team_id}')
async def update_team(
    team_id: UUID,
    req: UpdateTeamRequest,
    current_user: User = Depends(get_current_user)
):
    team = await TeamRepository.find_by_id(team_id)
    if not team:
        raise HTTPException(status_code=404)
    
    # Check permission: must be admin or owner
    member = await TeamRepository.find_member(team_id, current_user.id)
    if member.role not in ['admin', 'owner']:
        raise HTTPException(status_code=403)
    
    team.name = req.name or team.name
    team.description = req.description or team.description
    team.privacy = req.privacy or team.privacy
    
    return await TeamRepository.save(team)

# DELETE /teams/:id - Delete team
@router.delete('/{team_id}')
async def delete_team(
    team_id: UUID,
    current_user: User = Depends(get_current_user)
):
    team = await TeamRepository.find_by_id(team_id)
    if not team:
        raise HTTPException(status_code=404)
    
    # Check permission: must be owner
    member = await TeamRepository.find_member(team_id, current_user.id)
    if member.role != 'owner':
        raise HTTPException(status_code=403, detail='Only owner can delete team')
    
    await TeamRepository.delete(team_id)
    return { 'status': 'deleted' }
```

**Deliverables**:
- [ ] Team CRUD endpoints implemented
- [ ] Authorization checks on all operations
- [ ] Validation on team name/slug
- [ ] Tests covering happy path + error cases

#### 3.3 Member Management API
```python
# apps/saas-api/src/teams/members.py
# GET /teams/:id/members - List team members
@router.get('/{team_id}/members')
async def list_members(
    team_id: UUID,
    current_user: User = Depends(get_current_user)
):
    team = await TeamRepository.find_by_id(team_id)
    if not team:
        raise HTTPException(status_code=404)
    
    # Check membership
    if not await TeamRepository.find_member(team_id, current_user.id):
        raise HTTPException(status_code=403)
    
    return await TeamRepository.find_members(team_id)

# POST /teams/:id/members - Invite member
@router.post('/{team_id}/members')
async def invite_member(
    team_id: UUID,
    req: InviteMemberRequest,  # email, role
    current_user: User = Depends(get_current_user)
):
    # Check permission: must be admin or owner
    member = await TeamRepository.find_member(team_id, current_user.id)
    if member.role not in ['admin', 'owner']:
        raise HTTPException(status_code=403)
    
    # Create member record with pending status
    invited_member = await TeamRepository.add_member(
        team_id=team_id,
        email=req.email,
        role=req.role,
        invited_by=current_user.id,
    )
    
    # Send email invitation
    await send_invite_email(req.email, team_id)
    
    return invited_member

# PATCH /teams/:id/members/:uid - Change role
@router.patch('/{team_id}/members/{user_id}')
async def update_member_role(
    team_id: UUID,
    user_id: UUID,
    req: UpdateMemberRequest,  # role
    current_user: User = Depends(get_current_user)
):
    # Check permission: only owner can change roles
    member = await TeamRepository.find_member(team_id, current_user.id)
    if member.role != 'owner':
        raise HTTPException(status_code=403)
    
    target_member = await TeamRepository.find_member(team_id, user_id)
    if not target_member:
        raise HTTPException(status_code=404)
    
    target_member.role = req.role
    return await TeamRepository.save(target_member)

# DELETE /teams/:id/members/:uid - Remove member
@router.delete('/{team_id}/members/{user_id}')
async def remove_member(
    team_id: UUID,
    user_id: UUID,
    current_user: User = Depends(get_current_user)
):
    # Check permission
    member = await TeamRepository.find_member(team_id, current_user.id)
    if member.role not in ['admin', 'owner']:
        raise HTTPException(status_code=403)
    
    await TeamRepository.remove_member(team_id, user_id)
    return { 'status': 'removed' }
```

**Deliverables**:
- [ ] Member CRUD endpoints
- [ ] Role-based access control enforced
- [ ] Email invitations working
- [ ] Tests for all operations

#### 3.4 Testing
```python
# tests/test_teams_api.py
@pytest.mark.asyncio
async def test_create_team():
    team = await create_team_request(
        name='Engineering',
        slug='engineering',
        current_user=user1
    )
    assert team.name == 'Engineering'
    assert team.slug == 'engineering'

@pytest.mark.asyncio
async def test_add_member_permission_denied():
    team = await create_team(user1)
    
    with pytest.raises(HTTPException) as exc:
        await invite_member(
            team_id=team.id,
            email='new@example.com',
            current_user=user2  # not a member
        )
    assert exc.value.status_code == 403

@pytest.mark.asyncio
async def test_delete_team_owner_only():
    team = await create_team(user1)
    member2 = await add_member(team.id, user2.id, role='member')
    
    # user2 can't delete
    with pytest.raises(HTTPException) as exc:
        await delete_team(team.id, current_user=user2)
    assert exc.value.status_code == 403
    
    # user1 (owner) can delete
    result = await delete_team(team.id, current_user=user1)
    assert result['status'] == 'deleted'
```

**Deliverables**:
- [ ] 80%+ API test coverage
- [ ] Authorization tests
- [ ] Happy path + error scenarios
- [ ] Performance tests (query optimization)

---

## Milestone 4: Custom Domains & Multi-Tenancy (Week 4)

### Tasks

#### 4.1 Domain Routing Configuration
```yaml
# config/oauth-proxy.yaml (oauth2-proxy)
http_address = "0.0.0.0:8080"
upstreams = ["http://backend:3000"]

# Multi-tenant routing
# Extract tenant from domain and pass as header
provider = "oidc"
oidc_issuer_url = "https://oauth.kushnir.cloud"
client_id = "${OAUTH_CLIENT_ID}"
client_secret = "${OAUTH_CLIENT_SECRET}"

# Set cookie on parent domain
cookie_domain = ".kushnir.cloud"
cookie_secure = true
cookie_httponly = true
cookie_samesite = "Lax"

# Pass tenant context to backend
set_xauthrequest = true
```

**Deliverables**:
- [ ] oauth-proxy configured for multi-tenancy
- [ ] Cookie domain = .kushnir.cloud
- [ ] Tenant header extraction
- [ ] TLS termination

#### 4.2 Tenant Routing Middleware
```python
# apps/saas-api/src/middleware/tenant.py
from fastapi import Request
from contextvars import ContextVar

tenant_context: ContextVar[str] = ContextVar('tenant_id')

@app.middleware("http")
async def extract_tenant(request: Request, call_next):
    # Extract tenant from host header
    host = request.headers.get('host', '')
    
    if host.endswith('.kushnir.cloud'):
        # Extract subdomain: team.kushnir.cloud → team
        tenant = host.split('.')[0]
    else:
        # Custom domain: lookup in database
        custom_domain = await CustomDomain.find_by_domain(host)
        if not custom_domain:
            return JSONResponse({'error': 'Tenant not found'}, 404)
        tenant = custom_domain.team_id
    
    # Set tenant in context for this request
    token = tenant_context.set(tenant)
    
    try:
        response = await call_next(request)
    finally:
        tenant_context.reset(token)
    
    return response

def get_tenant_id() -> str:
    """Helper to get current tenant in route handlers"""
    return tenant_context.get()

# Usage in routes:
@router.get('/api/data')
async def get_data(tenant_id: str = Depends(get_tenant_id)):
    # Automatically scoped to tenant
    data = await Database.query(
        "SELECT * FROM data WHERE org_id = $1",
        tenant_id
    )
    return data
```

**Deliverables**:
- [ ] Tenant routing middleware
- [ ] get_tenant_id() dependency
- [ ] All queries scoped by tenant
- [ ] Tests verifying isolation

#### 4.3 Custom Domain Management API
```python
# apps/saas-api/src/domains/router.py

# POST /teams/:id/domains - Add custom domain
@router.post('/{team_id}/domains')
async def add_custom_domain(
    team_id: UUID,
    req: AddDomainRequest,  # domain: "team.example.com"
    current_user: User = Depends(get_current_user)
):
    team = await TeamRepository.find_by_id(team_id)
    if not team:
        raise HTTPException(status_code=404)
    
    # Check permission: must be owner
    member = await TeamRepository.find_member(team_id, current_user.id)
    if member.role != 'owner':
        raise HTTPException(status_code=403)
    
    # Verify domain ownership via DNS check
    # User must have created CNAME: team.example.com -> teams.kushnir.cloud
    verified = await verify_domain_ownership(req.domain)
    if not verified:
        raise HTTPException(status_code=400, detail='Domain verification failed')
    
    custom_domain = await DomainRepository.save(
        CustomDomain(
            team_id=team_id,
            domain=req.domain,
            verified_at=datetime.utcnow()
        )
    )
    
    return custom_domain
```

**Deliverables**:
- [ ] Custom domain CRUD endpoints
- [ ] DNS verification logic
- [ ] TLS certificate provisioning (Let's Encrypt)
- [ ] Domain validation tests

#### 4.4 Data Isolation Verification
```sql
-- Verify queries are properly scoped to tenant
-- All queries should include org_id filter

-- GOOD:
SELECT * FROM teams WHERE id = $1 AND org_id = $2;

-- BAD (data leak risk):
SELECT * FROM teams WHERE id = $1;  -- Missing org_id filter!

-- Audit: Find all queries and verify tenant scoping
SELECT query_text FROM pg_stat_statements 
WHERE query_text ILIKE '%SELECT%' AND query_text NOT ILIKE '%org_id%'
LIMIT 10;
```

**Deliverables**:
- [ ] Audit all SQL queries for tenant scoping
- [ ] Code review checklist for tenant safety
- [ ] Integration tests verifying data isolation
- [ ] Load test with 100+ tenants

---

## Milestone 5: IDE Integration & Production Hardening (Week 5)

### Tasks

#### 5.1 IDE Authentication Flow
```tsx
// apps/ide/src/auth/session.ts
import { useEffect, useState } from 'react';

export function useIDESession() {
  const [authenticated, setAuthenticated] = useState(false);
  const [user, setUser] = useState(null);
  
  useEffect(() => {
    // IDE checks for session cookie (set by oauth-proxy on .kushnir.cloud)
    fetch(`${API_URL}/api/me`, { credentials: 'include' })
      .then(r => {
        if (r.ok) {
          setUser(r.json());
          setAuthenticated(true);
        } else {
          // Redirect to login
          window.location.href = `${AUTH_URL}/auth/login?return_to=${window.location.href}`;
        }
      })
      .catch(() => {
        window.location.href = `${AUTH_URL}/auth/login?return_to=${window.location.href}`;
      });
  }, []);
  
  return { authenticated, user };
}

// Usage in IDE root
export default function IDE() {
  const { authenticated, user } = useIDESession();
  
  if (!authenticated) return <Spinner />;
  
  return (
    <div>
      <Editor user={user} />
    </div>
  );
}
```

**Deliverables**:
- [ ] IDE redirects to login when session invalid
- [ ] Session cookie shared across subdomains
- [ ] User context available in IDE
- [ ] E2E test: login → IDE access

#### 5.2 RBAC Permission Model
```typescript
// apps/saas-api/src/auth/permissions.ts
interface Permission {
  resource: string;
  action: string;
  roles: string[];
}

const PERMISSIONS: Permission[] = [
  { resource: 'workspace', action: 'read', roles: ['member', 'admin', 'owner'] },
  { resource: 'workspace', action: 'write', roles: ['admin', 'owner'] },
  { resource: 'team', action: 'settings', roles: ['admin', 'owner'] },
  { resource: 'team', action: 'delete', roles: ['owner'] },
  { resource: 'billing', action: 'view', roles: ['owner', 'admin'] },
  { resource: 'members', action: 'manage', roles: ['admin', 'owner'] },
];

function hasPermission(role: string, resource: string, action: string): boolean {
  return PERMISSIONS.some(
    p => p.resource === resource && 
         p.action === action && 
         p.roles.includes(role)
  );
}

// Middleware
function requirePermission(resource: string, action: string) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const userRole = req.user.role;
    if (!hasPermission(userRole, resource, action)) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }
    next();
  };
}

// Usage
app.delete(
  '/teams/:id',
  requirePermission('team', 'delete'),
  deleteTeamHandler
);
```

**Deliverables**:
- [ ] RBAC permission matrix defined
- [ ] Middleware enforcing permissions
- [ ] Tests for all permission combinations
- [ ] Documentation of role definitions

#### 5.3 Security Hardening
```python
# apps/saas-api/src/security.py

# Rate limiting
from slowapi import Limiter
limiter = Limiter(key_func=get_remote_address)

@app.post('/auth/login', dependencies=[Depends(limiter.limit("5/15minute"))])
async def login():
    """Rate limit login to 5 attempts per 15 minutes"""
    pass

# Security headers
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self' 'unsafe-inline'"
    return response

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://kushnir.cloud", "https://*.kushnir.cloud"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Input validation
from pydantic import BaseModel, EmailStr, validator

class CreateTeamRequest(BaseModel):
    name: str
    slug: str
    
    @validator('name')
    def name_length(cls, v):
        if len(v) < 3 or len(v) > 100:
            raise ValueError('Name must be 3-100 characters')
        return v
    
    @validator('slug')
    def slug_format(cls, v):
        if not re.match(r'^[a-z0-9-]{3,50}$', v):
            raise ValueError('Slug must be lowercase alphanumeric with hyphens')
        return v
```

**Deliverables**:
- [ ] Rate limiting on auth endpoints
- [ ] Security headers on all responses
- [ ] CORS configured for multi-domain
- [ ] Input validation on all requests
- [ ] SQL injection tests (all queries parameterized)
- [ ] CSRF token on form submissions

#### 5.4 Monitoring & Logging
```python
# apps/saas-api/src/logging_config.py
import structlog
import logging
from pythonjsonlogger import jsonlogger

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
)

# Audit logging
class AuditLogger:
    @staticmethod
    async def log(
        action: str,
        user_id: UUID,
        resource_type: str,
        resource_id: UUID,
        result: str,  # 'success' or 'failure'
        details: dict = None
    ):
        await AuditLog.create(
            action=action,
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
            result=result,
            details=details or {},
            timestamp=datetime.utcnow()
        )
        
        # Also log to structured logging
        structlog.get_logger().info(
            f"audit.{action}",
            user_id=str(user_id),
            resource_type=resource_type,
            resource_id=str(resource_id),
            result=result,
        )
```

**Deliverables**:
- [ ] Structured JSON logging for all operations
- [ ] Audit trail table for compliance
- [ ] Prometheus metrics exported
- [ ] Grafana dashboard created
- [ ] Log aggregation to Loki

#### 5.5 End-to-End Testing
```bash
# E2E test flow
1. Register new user with GitHub OAuth
2. Create team "My Team"
3. Invite team member via email
4. Accept invitation + join team
5. Switch team role to admin
6. Create custom domain
7. Verify custom domain works
8. Switch to IDE with team context
9. Perform workspace operations
10. Logout + verify session cleared
```

**Deliverables**:
- [ ] E2E tests with Playwright/Cypress
- [ ] Load test: 100 concurrent users
- [ ] Stress test: 1000+ signin attempts
- [ ] Failover test: API server down
- [ ] 99.9% uptime validation

---

## Success Metrics

By end of week 5:
- ✅ 500+ users able to sign in
- ✅ <100ms OAuth flow completion
- ✅ 99.9% API availability
- ✅ Zero data breaches/unauthorized access
- ✅ All endpoints documented (OpenAPI)
- ✅ Production deployment ready

---

## Dependencies & Risks

**Dependencies**:
- TLS certificate provisioning (Let's Encrypt)
- Email service (SendGrid, AWS SES)
- Database migrations (PostgreSQL 14+)

**Risks**:
- OAuth provider API downtime → fallback to email
- TLS renewal failure → setup monitoring/alerts
- Multi-tenant data leak → comprehensive integration tests

**Mitigations**:
- Rate limiting + circuit breakers
- Automated certificate renewal 60 days before expiry
- Quarterly security audits
