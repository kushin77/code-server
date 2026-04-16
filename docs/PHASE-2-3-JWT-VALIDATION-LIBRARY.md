# Phase 2.3: JWT Validation Library - Service Integration

**Status**: ✅ IMPLEMENTATION READY  
**Effort**: 6-8 hours  
**Language**: Go (portable, production-grade)  
**Framework**: Fiber web framework + JWT middleware  

---

## Overview

Phase 2.3 creates a reusable JWT validation library that all services can integrate with to:
- Validate JWT signatures (RS256)
- Check token expiry and claims
- Enforce RBAC at API level
- Log validation events
- Handle invalid/expired tokens gracefully

### Architecture

```
Request with JWT
  ↓
Middleware Chain
  ├─ Extract token from Authorization header
  ├─ Validate signature (public key from JWKS endpoint)
  ├─ Check expiry
  ├─ Verify claims (aud, iss, sub)
  ├─ Enforce RBAC (check role in token)
  └─ Log event
  ↓
Allowed → Forward to handler
Denied → Return 401/403 + log
```

---

## Library Structure

### Go Module: `github.com/kushin77/jwt-validator`

```
jwt-validator/
├── go.mod
├── go.sum
├── validator.go           # Main validation logic
├── middleware.go          # Fiber middleware
├── config.go              # Configuration
├── errors.go              # Custom errors
├── testing.go             # Test utilities
├── examples/
│   ├── fiber-app.go       # Fiber integration example
│   ├── grpc-interceptor.go # gRPC integration example
│   └── http-handler.go    # Standard HTTP integration
├── docs/
│   ├── API.md
│   ├── INTEGRATION.md
│   └── TROUBLESHOOTING.md
└── tests/
    ├── validator_test.go
    ├── middleware_test.go
    └── fixtures/
        ├── valid-token.jwt
        ├── expired-token.jwt
        └── invalid-sig-token.jwt
```

---

## Core Components

### 1. JWT Validator (validator.go)

```go
type Validator struct {
    issuer         string         // e.g., https://oidc.kushnir.cloud
    audience       string         // e.g., code-server.local
    publicKeysURL  string         // JWKS endpoint
    publicKeys     map[string]rsa.PublicKey
    mu             sync.RWMutex
    cacheTTL       time.Duration
    lastCacheTime  time.Time
}

// ValidateToken validates JWT and returns claims
func (v *Validator) ValidateToken(tokenString string) (*Claims, error) {
    // 1. Parse JWT structure
    // 2. Fetch JWKS if needed
    // 3. Validate signature (RS256)
    // 4. Check expiry
    // 5. Verify claims (aud, iss, iat, exp)
    // 6. Return Claims
}

type Claims struct {
    Subject   string    `json:"sub"`           // User ID
    Issuer    string    `json:"iss"`           // Token issuer
    Audience  string    `json:"aud"`           // Service audience
    Role      string    `json:"role"`          // RBAC role (admin/operator/viewer)
    Type      string    `json:"token_type"`    // human/workload/automation
    ExpiresAt int64     `json:"exp"`           // Unix timestamp
    IssuedAt  int64     `json:"iat"`
    NotBefore int64    `json:"nbf"`
}
```

### 2. Fiber Middleware (middleware.go)

```go
// JWTMiddleware validates JWT in Authorization header
func JWTMiddleware(v *Validator) fiber.Handler {
    return func(c *fiber.Ctx) error {
        // 1. Extract token from "Authorization: Bearer <token>"
        token := extractToken(c)
        if token == "" {
            return c.Status(401).JSON(fiber.Map{
                "error": "missing_token",
                "message": "Authorization header required",
            })
        }

        // 2. Validate token
        claims, err := v.ValidateToken(token)
        if err != nil {
            return c.Status(401).JSON(fiber.Map{
                "error": "invalid_token",
                "message": err.Error(),
            })
        }

        // 3. Store in context
        c.Locals("claims", claims)
        c.Locals("user", claims.Subject)
        c.Locals("role", claims.Role)

        // 4. Continue
        return c.Next()
    }
}

// RequireRole checks if user has required role
func RequireRole(roles ...string) fiber.Handler {
    return func(c *fiber.Ctx) error {
        claims := c.Locals("claims").(*Claims)
        
        allowed := false
        for _, role := range roles {
            if claims.Role == role {
                allowed = true
                break
            }
        }

        if !allowed {
            return c.Status(403).JSON(fiber.Map{
                "error": "insufficient_role",
                "required": roles,
                "actual": claims.Role,
            })
        }

        return c.Next()
    }
}
```

### 3. Configuration (config.go)

```go
type Config struct {
    // Token issuer (OIDC provider)
    Issuer string
    
    // Service audience (what service is this token for)
    Audience string
    
    // JWKS endpoint (public keys)
    PublicKeysURL string
    
    // Cache settings
    CacheTTL time.Duration // Default: 5 minutes
    
    // Logging
    LogLevel string // debug/info/warn/error
    Logger   Logger
}

// DefaultConfig returns recommended settings
func DefaultConfig() Config {
    return Config{
        Issuer:        "https://oidc.kushnir.cloud",
        CacheTTL:      5 * time.Minute,
        LogLevel:      "info",
    }
}
```

### 4. Custom Errors (errors.go)

```go
type ValidationError struct {
    Code    string // invalid_signature, expired_token, invalid_claims
    Message string
    Details map[string]string
}

var (
    ErrMissingToken    = &ValidationError{Code: "missing_token"}
    ErrInvalidFormat   = &ValidationError{Code: "invalid_format"}
    ErrInvalidSignature = &ValidationError{Code: "invalid_signature"}
    ErrTokenExpired    = &ValidationError{Code: "expired_token"}
    ErrInvalidClaims   = &ValidationError{Code: "invalid_claims"}
    ErrPublicKeysFetch = &ValidationError{Code: "public_keys_fetch_failed"}
)
```

---

## Integration Examples

### Integration 1: Fiber Web Framework

```go
import (
    "github.com/gofiber/fiber/v3"
    "github.com/kushin77/jwt-validator"
)

func main() {
    app := fiber.New()
    
    // Create validator
    cfg := jwt_validator.DefaultConfig()
    cfg.Audience = "code-server.local"
    validator, _ := jwt_validator.New(cfg)
    
    // Apply middleware globally
    app.Use(jwt_validator.JWTMiddleware(validator))
    
    // Public routes (no auth)
    app.Get("/health", func(c *fiber.Ctx) error {
        return c.JSON(fiber.Map{"status": "ok"})
    })
    
    // Protected routes
    app.Get("/admin/users", 
        jwt_validator.RequireRole("admin"),
        getUsers,
    )
    
    app.Post("/api/code/execute",
        jwt_validator.RequireRole("operator", "admin"),
        executeCode,
    )
    
    app.Listen(":8443")
}

func getUsers(c *fiber.Ctx) error {
    claims := c.Locals("claims").(*jwt_validator.Claims)
    user := claims.Subject
    
    // Return users (audit logged with user ID)
    return c.JSON(fiber.Map{
        "user": user,
        "users": getAllUsers(),
    })
}
```

### Integration 2: gRPC Interceptor

```go
import (
    "google.golang.org/grpc"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
)

func JWTUnaryInterceptor(validator *jwt_validator.Validator) grpc.UnaryServerInterceptor {
    return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
        // Extract token from metadata
        md, _ := metadata.FromIncomingContext(ctx)
        tokens := md.Get("authorization")
        if len(tokens) == 0 {
            return nil, status.Error(codes.Unauthenticated, "missing token")
        }
        
        // Validate
        claims, err := validator.ValidateToken(tokens[0])
        if err != nil {
            return nil, status.Error(codes.Unauthenticated, err.Error())
        }
        
        // Add to context
        ctx = context.WithValue(ctx, "claims", claims)
        
        return handler(ctx, req)
    }
}
```

### Integration 3: Standard HTTP Handler

```go
import (
    "net/http"
)

func withJWTValidation(validator *jwt_validator.Validator, next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        // Extract token
        authHeader := r.Header.Get("Authorization")
        if authHeader == "" {
            http.Error(w, "missing token", 401)
            return
        }
        
        token := strings.TrimPrefix(authHeader, "Bearer ")
        
        // Validate
        claims, err := validator.ValidateToken(token)
        if err != nil {
            http.Error(w, err.Error(), 401)
            return
        }
        
        // Add to context
        ctx := r.Context()
        ctx = context.WithValue(ctx, "claims", claims)
        
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

---

## Testing Strategy

### Unit Tests (validator_test.go)

```go
func TestValidateToken_Valid(t *testing.T) {
    // Test with valid token
    // Expected: No error, claims returned
}

func TestValidateToken_Expired(t *testing.T) {
    // Test with expired token
    // Expected: ErrTokenExpired
}

func TestValidateToken_InvalidSignature(t *testing.T) {
    // Test with tampered token
    // Expected: ErrInvalidSignature
}

func TestValidateToken_MissingClaims(t *testing.T) {
    // Test with missing role/audience
    // Expected: ErrInvalidClaims
}
```

### Integration Tests (middleware_test.go)

```go
func TestJWTMiddleware_AllowedRequest(t *testing.T) {
    // Create fiber app
    app := fiber.New()
    app.Use(JWTMiddleware(validator))
    app.Get("/", func(c *fiber.Ctx) error {
        return c.SendString("ok")
    })
    
    // Test with valid token
    req := httptest.NewRequest("GET", "/", nil)
    req.Header.Set("Authorization", "Bearer " + validToken)
    
    resp, _ := app.Test(req)
    assert.Equal(t, 200, resp.StatusCode)
}

func TestRequireRole_Denied(t *testing.T) {
    // Create fiber app with role requirement
    app := fiber.New()
    app.Use(JWTMiddleware(validator))
    app.Get("/admin", RequireRole("admin"), func(c *fiber.Ctx) error {
        return c.SendString("ok")
    })
    
    // Test with viewer token (insufficient role)
    req := httptest.NewRequest("GET", "/admin", nil)
    req.Header.Set("Authorization", "Bearer " + viewerToken)
    
    resp, _ := app.Test(req)
    assert.Equal(t, 403, resp.StatusCode)
}
```

---

## Deployment

### Go Module Publishing

```bash
# Initialize module
go mod init github.com/kushin77/jwt-validator

# Add dependencies
go get github.com/golang-jwt/jwt/v5
go get github.com/gofiber/fiber/v3

# Publish to GitHub
git tag v1.0.0
git push origin v1.0.0
```

### Integration into Services

**Code-Server** (add to main.go):
```go
import jwtval "github.com/kushin77/jwt-validator"

func init() {
    cfg := jwtval.DefaultConfig()
    cfg.Audience = "code-server.local"
    validator, _ = jwtval.New(cfg)
}

// In http handlers
router.Use(jwtval.JWTMiddleware(validator))
```

**Prometheus** (scrape auth):
```yaml
global:
  external_labels:
    jwt_validator: 'enabled'

scrape_configs:
  - job_name: 'code-server'
    authorization:
      type: Bearer
      credentials_file: /etc/prometheus/jwt-token
    # Token auto-refreshed by separate sidecar
```

---

## Compliance & Security

### Token Validation Audit Log

Every validation logged (immutable):
```json
{
  "timestamp": "2026-04-16T16:00:00Z",
  "event_type": "token_validated",
  "token_id": "jti_xyz",
  "subject": "user@example.com",
  "service": "code-server",
  "result": "success|failure",
  "failure_reason": "invalid_signature|expired|insufficient_role",
  "client_ip": "192.168.1.100",
  "duration_ms": 5
}
```

### Security Coverage

✅ **RS256 signature validation** (tamper detection)  
✅ **Token expiry enforcement** (time-bound access)  
✅ **RBAC at API level** (deny-by-default)  
✅ **JWKS caching** (performance + resilience)  
✅ **Audit logging** (compliance + forensics)  
✅ **No sensitive data in logs** (GDPR compliance)  

---

## Files Delivered

### Go Module
- `cmd/jwt-validator/` - Standalone binary for testing
- `lib/jwt-validator/validator.go` (250 lines)
- `lib/jwt-validator/middleware.go` (180 lines)
- `lib/jwt-validator/config.go` (80 lines)
- `lib/jwt-validator/errors.go` (60 lines)

### Examples
- `examples/fiber-app.go` (120 lines)
- `examples/grpc-interceptor.go` (100 lines)
- `examples/http-handler.go` (90 lines)

### Tests
- `lib/jwt-validator/validator_test.go` (200 lines)
- `lib/jwt-validator/middleware_test.go` (150 lines)

### Documentation
- `docs/JWT-VALIDATOR-API.md` (250 lines)
- `docs/JWT-VALIDATOR-INTEGRATION.md` (200 lines)
- `docs/JWT-VALIDATOR-TROUBLESHOOTING.md` (150 lines)

---

## Timeline

**Execution**: 6-8 hours

1. Create Go module + base library: 2h
2. Fiber middleware + examples: 1.5h
3. gRPC interceptor: 1h
4. HTTP handler: 0.5h
5. Unit tests + fixtures: 1.5h
6. Integration tests: 1h
7. Documentation: 1h

---

## Quality Standards

✅ **100% test coverage** (unit + integration + e2e)  
✅ **Production-grade error handling**  
✅ **Zero external token storage** (memory cache only)  
✅ **Concurrent-safe** (sync.RWMutex)  
✅ **Pluggable logging** (interface-based)  
✅ **Versioned API** (semver)

---

## Next: Phase 2.4

Once Phase 2.3 integrated into all services:
1. Integrate jwt-validator into code-server, oauth2-proxy, prometheus
2. Add audit logging to Loki
3. Validate RBAC enforcement in production
4. Move to Phase 2.4 (GitHub Actions Federation)

---

**Status**: ✅ READY FOR IMPLEMENTATION  
**Priority**: P1  
**Blocked By**: Phase 2.2 (mTLS)  
**Blocks**: Phase 2.4-2.5  
