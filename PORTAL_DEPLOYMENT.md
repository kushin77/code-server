# Multi-Portal Deployment Guide

## Architecture Overview

The upgraded portal system implements a **multi-UI architecture** with three distinct user interfaces sharing a unified authentication backend:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Caddy Reverse Proxy                               │
│                      (ide.kushnir.cloud domain)                             │
├──────────┬──────────────────────┬──────────────┬─────────────────────────────┤
│          │                      │              │                             │
▼          ▼                      ▼              ▼                             ▼
/       /api/*             /appsmith*        /backstage*                      
         /auth/*                                                              
         
oauth2     RBAC API           Appsmith           Backstage                    
proxy      (rbac-api:3001)    (appsmith:80)      (backstage:3000)            
           ├─ JWT Auth        Admin Panel        Developer Portal            
           ├─ OAuth2/OIDC      Low-code UI        Software Catalog           
           ├─ User CRUD        Dashboards         Documentation              
           ├─ Roles/RBAC       Workflows          Plugins                    
           └─ MFA (TOTP)       Integrations       Scaffolder                 

│          │
│          └─────────────────────────────────────────────────────────┐
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
                    PostgreSQL Database
              (appsmith + backstage data store)
```

## Components

### 1. **RBAC API** (`rbac-api:3001`)
**Purpose**: Enterprise authentication and authorization service

**Features**:
- JWT token generation and validation
- OAuth2/OpenID Connect (OIDC) implementation
- User management (CRUD)
- Role-based access control
- Multi-factor authentication (TOTP)
- Email/password authentication

**Endpoints**:
```
POST   /auth/login                                 # Email/password auth
POST   /auth/mfa-verify                           # MFA code verification
POST   /mfa/setup                                 # Generate TOTP secret
POST   /mfa/confirm                               # Enable MFA
GET    /users                                     # List users
POST   /users                                     # Create user
GET    /users/:id                                 # Get user
DELETE /users/:id                                 # Delete user
POST   /users/:userid/roles/:roleid              # Assign role
GET    /roles                                     # List roles
GET    /.well-known/openid-configuration          # OIDC discovery
POST   /auth/authorize                            # OAuth authorization
POST   /auth/token                                # Token exchange
GET    /auth/userinfo                             # User profile
POST   /auth/validate                             # Token validation
POST   /auth/refresh                              # Refresh token
GET    /auth/jwks                                 # JSON Web Key Set
POST   /auth/logout                               # Revoke token
GET    /healthz                                   # Health check
```

**Demo Credentials**:
```
User: admin@example.com
Password: password123
Organization: acme-corp
MFA: Enabled (setup required on first login)
```

### 2. **Appsmith** (`appsmith:80`)
**Purpose**: Low-code admin panel for internal operations

**Features**:
- Visual app builder (no code required)
- REST API integration with RBAC API
- PostgreSQL database connections
- User/role management dashboard
- Organization settings
- Permission management
- Real-time data binding

**Configuration**:
- Database: PostgreSQL (appsmith user/schema)
- Auth: JWT tokens from RBAC API
- Base URL: `https://{DOMAIN}/appsmith`

**Default Credentials**:
```
Email: admin@appsmith.com
Password: appsmith
```

### 3. **Backstage** (`backstage:3000`)
**Purpose**: Developer portal for software catalog and onboarding

**Features**:
- Software catalog (components, systems, APIs)
- TechDocs (markdown documentation)
- Scaffolder (project templates)
- GitHub integration
- Kubernetes integration
- Monitoring (Grafana, SonarQube)
- RBAC-based access control

**Configuration**:
- Database: PostgreSQL (backstage user/schema)
- Auth: via RBAC API with RBAC provider
- Catalog sources: GitHub (kushin77/code-server)
- Base URL: `https://{DOMAIN}/backstage`

### 4. **code-server** (existing IDE)
**Purpose**: Cloud development environment

**Access**: `https://{DOMAIN}` (root path, protected by oauth2-proxy)

**Features**:
- VS Code in the browser
- GitHub Copilot integration
- Extensions marketplace
- Terminal access
- Workspace files

## Deployment Instructions

### Prerequisites
1. Docker and Docker Compose installed
2. Domain name configured (e.g., `ide.kushnir.cloud`)
3. SSL certificates via Let's Encrypt (automatic via Caddy)
4. Environment variables configured in `.env`

### Step 1: Configure Environment

Create `.env` file by copying from `.env.example`:

```bash
cp .env.example .env
```

**Required settings**:
```env
DOMAIN=ide.kushnir.cloud
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-client-secret
OAUTH2_PROXY_COOKIE_SECRET=your-secret
JWT_SECRET=your-jwt-secret
GITHUB_TOKEN=your-github-pat
CODE_SERVER_PASSWORD=your-password
```

### Step 2: Build Services

Build the Docker images:

```bash
# Build RBAC API backend
docker-compose build rbac-api

# Build Caddy with GoDaddy plugin (if needed)
docker-compose build caddy

# Build code-server with Copilot extensions
docker-compose build code-server
```

### Step 3: Initialize PostgreSQL

The PostgreSQL service automatically initializes on first run via `init-postgres.sh`:

```bash
# Creates appsmith and backstage databases
# with appsmith and backstage users
# (runs automatically via entrypoint)
```

### Step 4: Deploy Stack

Start all services:

```bash
docker-compose up -d
```

**Expected service startup order** (managed by depends_on):
1. ollama (LLM server)
2. ollama-init (model puller, waits for ollama)
3. postgres (database)
4. rbac-api (JWT/OAuth backend)
5. oauth2-proxy (Google OAuth sidecar)
6. code-server (web IDE)
7. caddy (reverse proxy, routes traffic)

### Step 5: Verify Deployment

Check service health:

```bash
# Check all services running
docker-compose ps

# View logs
docker-compose logs -f rbac-api
docker-compose logs -f caddy
docker-compose logs -f appsmith
docker-compose logs -f backstage
```

Test OAuth discovery endpoint:

```bash
curl https://{DOMAIN}/auth/.well-known/openid-configuration
```

**Expected response**:
```json
{
  "issuer": "https://{DOMAIN}",
  "authorization_endpoint": "https://{DOMAIN}/auth/authorize",
  "token_endpoint": "https://{DOMAIN}/auth/token",
  "userinfo_endpoint": "https://{DOMAIN}/auth/userinfo",
  "jwks_uri": "https://{DOMAIN}/auth/jwks",
  ...
}
```

### Step 6: Access Portals

1. **code-server (IDE)**: `https://{DOMAIN}`
   - Requires Google OAuth login
   - Protected by oauth2-proxy

2. **Appsmith (Admin)**: `https://{DOMAIN}/appsmith`
   - Low-code admin interface
   - Create apps for user/role management

3. **Backstage (Developer)**: `https://{DOMAIN}/backstage`
   - Software catalog
   - Project scaffolder
   - Documentation

## Testing OAuth Flow

### 1. Test Direct API Call

```bash
# Login and get tokens
curl -X POST https://{DOMAIN}/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "password123",
    "org_slug": "acme-corp"
  }'

# Response includes: access_token, mfa_token, mfa_required
```

### 2. Test OAuth2 Flow

```bash
# Get authorization code
curl "https://{DOMAIN}/auth/authorize?client_id=appsmith&redirect_uri=https://appsmith/auth/callback&response_type=code"

# Exchange code for token
curl -X POST https://{DOMAIN}/auth/token \
  -H "Content-Type: application/json" \
  -d '{
    "grant_type": "authorization_code",
    "code": "auth_code_here",
    "client_id": "appsmith",
    "client_secret": "appsmith_secret"
  }'

# Response: {"access_token": "jwt_token", "token_type": "Bearer", ...}
```

### 3. Test UserInfo Endpoint

```bash
# Get user profile
curl https://{DOMAIN}/auth/userinfo \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs for specific service
docker-compose logs rbac-api

# Common issues:
# - Port conflict: Change PORTS in docker-compose.yml
# - Out of memory: Increase Docker resource limits
# - Network connectivity: Verify 10.0.8.0/24 subnet
```

### OAuth Routes Not Working

```bash
# Verify oauth.ts is imported
grep "import oauthRoutes" backend/src/index.ts

# Verify routes are registered
grep "app.use.*oauth" backend/src/index.ts

# Rebuild container
docker-compose build --no-cache rbac-api
docker-compose up -d rbac-api
```

### Caddy Reverse Proxy Not Routing

```bash
# Validate Caddyfile syntax
docker-compose exec caddy caddy validate --config /etc/caddy/Caddyfile

# Check Caddy logs
docker-compose logs caddy

# Verify routes in Caddyfile
grep "@api\|@appsmith\|@backstage" Caddyfile
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
docker-compose ps postgres

# Verify database initialized
docker-compose exec postgres psql -U postgres -l

# Check appsmith/backstage databases exist
# Expected: appsmith, backstage databases with respective users
```

## Architecture Decisions

### Why Multi-UI?

1. **Different User Personas**:
   - **End Users** → Code-server (developers)
   - **Admins** → Appsmith (non-technical operations)
   - **DevOps/Architects** → Backstage (platform insights)

2. **Separation of Concerns**:
   - Each UI optimized for its audience
   - Shared authentication backend
   - Independent scaling per UI type

3. **Enterprise Standards**:
   - RBAC API follows OAuth2/OIDC specs
   - Standardized token format (JWT)
   - Compatible with industry tools (Okta, Auth0, etc.)

### Why OAuth2 for Appsmith/Backstage?

1. **Zero-trust authentication**
2. **Token-based, not cookie-based**
3. **Supports multiple client types**
4. **Standardized refresh token flow**
5. **Audit trail for access**

### Why Separate Databases?

PostgreSQL provides:
- **Persistence** for Appsmith dashboards
- **Persistence** for Backstage catalog
- **ACID guarantees** for critical data
- **Backup/restore** capabilities
- **Scaling** independently of API

## Security Considerations

### TLS/SSL
- Automatic via Let's Encrypt (Caddy)
- HSTS header enforces HTTPS
- Self-signed certs generated on first run

### Authentication
- JWT tokens with 24h expiration
- MFA via TOTP (optional, enabled for admin)
- Refresh tokens for long-lived sessions
- Password hashing with bcryptjs

### Network Isolation
- Services run on internal network (10.0.8.0/24)
- Database only exposed internally
- Public traffic only through Caddy
- No direct access to internal ports

### RBAC
- All endpoints protected by role checks
- Admin role for user/role management
- User role for self-service operations
- Custom roles via API

## Production Checklist

- [ ] Update JWT_SECRET in .env (generate new)
- [ ] Update GOOGLE_CLIENT_ID/SECRET
- [ ] Update CODE_SERVER_PASSWORD
- [ ] Configure GITHUB_TOKEN for Backstage
- [ ] Test OAuth flow end-to-end
- [ ] Setup database backups (PostgreSQL)
- [ ] Configure log aggregation (optional)
- [ ] Enable MFA for admin accounts
- [ ] Review Appsmith security settings
- [ ] Review Backstage RBAC policies
- [ ] Load test under expected traffic
- [ ] Setup alerting for service failures
- [ ] Document runbooks for on-call

## Next Steps

1. **Create Appsmith Admin App**
   - User management dashboard
   - Role assignment interface
   - Organization settings

2. **Populate Backstage Catalog**
   - Document components
   - Create project templates
   - Add infrastructure resources

3. **Setup Monitoring**
   - Monitor RBAC API (latency, errors)
   - Monitor PostgreSQL connections
   - Monitor Caddy request rates

4. **Database Migration** (Optional)
   - Move from RBAC API in-memory to PostgreSQL
   - Add database migrations framework
   - Setup replication for HA

5. **Custom Plugins** (Optional)
   - Appsmith plugins for internal APIs
   - Backstage plugins for custom integrations
   - OAuth2 integrations with other systems
