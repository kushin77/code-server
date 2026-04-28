# OAuth2 Authorization Server

**Issue:** #1545 Week 1 - Enterprise SSO Portal  
**Status:** ✅ IMPLEMENTATION COMPLETE  
**Framework:** FastAPI + SQLAlchemy + PostgreSQL + Redis  
**Python:** 3.11+

## Overview

OAuth2 Authorization Server implementation for ElevatedIQ enterprise SSO portal. Provides centralized authentication and authorization for all enterprise applications with support for:

- **External OAuth2 Providers**: GitHub, Google, Microsoft, Okta
- **Authorization Code Flow** with PKCE support (OAuth 2.0 public client security)
- **Refresh Tokens** for long-lived sessions (30 days)
- **JWT Access Tokens** (RS256 signing, 15-minute expiry)
- **Multi-tenant** architecture with organizations and teams
- **Role-Based Access Control** (RBAC) with permission model
- **Audit Logging** for compliance and security

## Architecture

### Core Components

#### 1. **OAuth2Server** (`oauth2_server.py`)
- Authorization code generation and verification
- Access token (JWT) generation with RS256 signing
- Refresh token management
- PKCE code verifier validation
- Provider registration and configuration

#### 2. **Database Models** (`models.py`)
- `OAuthProvider`: External provider configuration (GitHub, Google, etc.)
- `AuthorizationCode`: Authorization codes (10-minute expiry, single-use)
- `OAuthToken`: Access, refresh, and ID tokens
- `OAuthConnection`: User ↔ Provider mapping
- `OAuthClient`: Registered applications
- `OAuthAuditLog`: Audit trail for compliance

#### 3. **Configuration** (`config.py`)
- Environment-driven configuration (pydantic-settings)
- Support for production, development, and local environments
- Validation on startup (required fields, HTTPS enforcement, etc.)

### API Endpoints

```
GET  /oauth/authorize                    # Authorization request
POST /oauth/token                        # Token exchange
GET  /.well-known/jwks.json             # JWKS (JWT public keys)
GET  /oauth/{provider}/callback         # OAuth provider callback
GET  /health                            # Health check
```

## Getting Started

### Prerequisites

- Python 3.11+
- PostgreSQL 14+
- Redis 7+
- Docker & Docker Compose

### Installation

1. **Install dependencies**:
```bash
cd apps/auth-server
pip install -r requirements.txt
```

2. **Create database schema**:
```bash
alembic upgrade head
```

3. **Configure environment**:
```bash
cp .env.example .env
# Edit .env with your OAuth provider secrets
```

### Running Locally

```bash
# Development (with reload)
cd apps/auth-server
uvicorn src.oauth2_server:app --reload --host 0.0.0.0 --port 8001

# Or via Docker Compose
docker compose -f docker-compose.yml -f docker/oauth2-service.yml up auth-server
```

### Health Check

```bash
curl http://localhost:8001/health
```

## OAuth2 Flows

### Authorization Code Flow (Standard)

```
1. Client → User redirects to /oauth/authorize
   GET /oauth/authorize?client_id=app&redirect_uri=...&scope=openid+profile&state=xyz

2. Authorization Server → User sees login/consent screen

3. User → Grants permission

4. Authorization Server → Redirects to client with code
   302 redirect to https://app.example.com/callback?code=AUTH_CODE&state=xyz

5. Client → Exchanges code for tokens
   POST /oauth/token with code, client_id, client_secret

6. Authorization Server → Returns access token
   {
     "access_token": "eyJhbGc...",
     "token_type": "Bearer",
     "expires_in": 900,
     "refresh_token": "refresh_token_xyz",
     "scope": "openid profile email"
   }
```

### PKCE Flow (For Public Clients)

```
1. Client generates code_verifier (cryptographically random string)
   code_verifier = "random_string_43_chars_min"

2. Client computes code_challenge
   code_challenge = BASE64URL(SHA256(code_verifier))

3. Client → Authorization Server with code_challenge
   GET /oauth/authorize?...&code_challenge=...&code_challenge_method=S256

4. Authorization Server stores code_challenge with authorization code

5. Client exchanges code with code_verifier
   POST /oauth/token with code, code_verifier

6. Server validates: BASE64URL(SHA256(code_verifier)) == stored_code_challenge
```

### Refresh Token Flow

```
1. Client has expired access_token and refresh_token

2. Client exchanges refresh_token for new access_token
   POST /oauth/token?grant_type=refresh_token&refresh_token=...

3. Authorization Server returns new access_token
```

## JWT Token Structure

### Access Token Payload

```json
{
  "sub": "user-id",           // Subject (user ID)
  "email": "user@example.com",
  "org_id": "org-123",        // Organization
  "teams": ["team-1", "team-2"],
  "permissions": ["read", "write", "admin"],
  "iss": "https://auth.kushnir.cloud",    // Issuer
  "aud": "https://api.kushnir.cloud",     // Audience
  "iat": 1234567890,          // Issued at
  "exp": 1234568790           // Expires at (15 minutes)
}
```

### Token Signing

- **Algorithm**: RS256 (RSA SHA256)
- **Key Size**: 2048 bits
- **Public Keys**: Available at `/.well-known/jwks.json`

## Configuration

### Environment Variables

```bash
# Service
AUTH_SERVER_PORT=8001
AUTH_SERVER_HOST=0.0.0.0
ENVIRONMENT=production
DEPLOYMENT_ID=primary

# Database
DATABASE_URL=postgresql://user:pass@postgres:5432/elevatediq
DATABASE_POOL_SIZE=20

# Redis
REDIS_URL=redis://redis:6379/1

# JWT
JWT_ISSUER=https://auth.kushnir.cloud
JWT_AUDIENCE=https://api.kushnir.cloud
JWT_EXPIRY_SECONDS=900

# OAuth Providers
GITHUB_CLIENT_ID=your_github_client_id
GITHUB_CLIENT_SECRET=your_github_client_secret
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret

# Email (for user verification)
SENDGRID_API_KEY=your_sendgrid_api_key
EMAIL_FROM_ADDRESS=noreply@kushnir.cloud
```

## Security Features

### 1. **PKCE Support**
- Prevents authorization code interception attacks
- Required for public clients (mobile, SPAs)
- Code verifier validation with SHA256

### 2. **Authorization Code**
- Single-use only (deleted after token exchange)
- 10-minute expiry
- Cannot be reused or replayed

### 3. **Refresh Token Rotation**
- Refresh tokens expire after 30 days
- Can be revoked manually
- Stored encrypted in database

### 4. **JWT Security**
- Signed with RS256 (asymmetric)
- Public key verification without private key
- Short expiry (15 minutes)
- Issuer and audience validation

### 5. **Audit Logging**
- All authorization events logged
- User IP address and user agent tracked
- Success/failure status recorded
- Compliance-ready audit trail

## Testing

### Run Unit Tests

```bash
cd apps/auth-server

# All tests
pytest tests/

# With coverage
pytest --cov=src tests/

# Specific test class
pytest tests/unit/test_oauth2_server.py::TestAccessTokenGeneration

# Verbose output
pytest -v tests/
```

### Test Coverage

- OAuth2 Server: ✅ 95%+ coverage
- Authorization code generation and verification
- JWT token generation and claims validation
- PKCE code verifier validation
- Refresh token flow
- Key management and JWKS endpoint

## Production Deployment

### Requirements Checklist

- [ ] PostgreSQL 14+ with automatic backups
- [ ] Redis 7+ with persistence and replication
- [ ] TLS/SSL certificates (Let's Encrypt)
- [x] OAuth provider credentials configured
- [x] Email service (SendGrid) configured
- [x] Database connection pooling (20+ connections)
- [x] Request logging and monitoring
- [x] Audit log retention policy (>1 year)

### Phase 3 Enhancements (Shared Module Migration)

- [x] Migrated to `apps._shared.python.logging` (CodeServerLogger)
  - All modules now use centralized logging: oauth2_server.py, request_logging.py, audit_logging.py, email_service.py
  - Supports JSON/text/structured formats with ANSI colors
  - Consistent logging across all auth-server components

- [x] Integrated `apps._shared.python.exceptions`
  - oauth2_server.py: Uses InvalidToken, TokenExpired, AuthenticationFailure, MissingConfig
  - request_logging.py: Compatible with exception hierarchy
  - audit_logging.py: Uses DatabaseException, ServiceException
  - email_service.py: Uses EmailServiceError, ServiceException
  - All exceptions include error codes for tracking and monitoring

### Docker Deployment

```bash
docker compose -f docker-compose.yml -f docker/oauth2-service.yml up auth-server
```

### Monitoring

- Health endpoint: `/health`
- Prometheus metrics endpoint (planned Week 2)
- Grafana dashboard (planned Week 2)
- Audit logs in PostgreSQL

## Next Steps

### Week 2: Integration & User Management
- User provisioning from OAuth providers
- User profile management API
- Email verification workflows
- Account linking (multiple providers)

### Week 3: Team & Organization Management
- Team API with CRUD operations
- Organization settings
- Multi-tenant isolation
- Permission inheritance

### Week 4: Advanced Features
- Single Sign-Out (SLO)
- Account recovery flows
- Two-Factor Authentication (2FA)
- Device management

### Week 5: API Gateway Integration
- OAuth token validation middleware
- Permission enforcement
- Rate limiting per user
- API key management

## Troubleshooting

### Authorization code expired error
- Authorization codes expire after 10 minutes
- Generate new code if still in authorization flow

### Invalid client_id error
- Verify client_id matches registered application
- Check client_id in environment variables

### PKCE validation failed
- Ensure code_verifier matches code_challenge
- Use S256 method (SHA256) recommended
- Check URL encoding of code_challenge

### JWT signature verification failed
- Verify token using public key from `/.well-known/jwks.json`
- Check JWT algorithm matches RS256
- Ensure token is not expired

## References

- [RFC 6749 - OAuth 2.0 Authorization Framework](https://tools.ietf.org/html/rfc6749)
- [RFC 7636 - PKCE](https://tools.ietf.org/html/rfc7636)
- [RFC 7519 - JWT](https://tools.ietf.org/html/rfc7519)
- [OpenID Connect](https://openid.net/connect/)

## License

Proprietary - ElevatedIQ Enterprise
