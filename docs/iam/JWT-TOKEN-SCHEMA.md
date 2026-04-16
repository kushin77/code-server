# JWT Token Schema - Standard Claims & Custom Extensions

**Status**: Phase 1 Reference (April 22, 2026)  
**Compliance**: OpenID Connect (OIDC) standard claims + custom extensions  
**Scope**: All service-to-service and user authentication  

---

## Standard OIDC Claims (RFC 5807)

All tokens MUST include these claims:

| Claim | Type | Example | Purpose |
|-------|------|---------|---------|
| `iss` | string | `https://accounts.google.com` | Token issuer |
| `sub` | string | `117829634571892340923` | Unique subject identifier |
| `aud` | string | `[code-server, appsmith, backstage]` | Intended audience |
| `exp` | number | `1713607199` | Expiration time (Unix timestamp) |
| `iat` | number | `1713603599` | Issued at (Unix timestamp) |
| `auth_time` | number | `1713603599` | User authentication time |
| `email` | string | `alice@example.com` | Primary email address |
| `email_verified` | boolean | `true` | Email verification status |
| `name` | string | `Alice Chen` | Human-readable name |

---

## Required Custom Claims

**Service Authorization**:

| Claim | Type | Example | Purpose |
|-------|------|---------|---------|
| `roles` | string[] | `["admin", "operator"]` | Application roles |
| `org` | string | `acme-corp` | Organization/tenant ID |
| `github_username` | string | `alice-chen` | GitHub identity (if federated) |
| `github_teams` | string[] | `["platform", "security"]` | GitHub team membership |

**Audit & Tracing**:

| Claim | Type | Example | Purpose |
|-------|------|---------|---------|
| `correlation_id` | string | `req-2026-04-22-a1b2c3d4` | Request correlation ID |
| `requested_scopes` | string | `openid profile email` | Scopes used during auth |
| `session_id` | string | `sess-xyz789` | Browser session identifier |
| `client_id` | string | `backstage-service` | OAuth2 client identifier |

---

## Optional Claims (Extended Attributes)

For Appsmith approval workflows:

```json
{
  "approved_resources": ["deployment-prod", "incident-drill"],
  "approval_level": "ops-lead",
  "approval_groups": ["deploy-approvers", "incident-commanders"]
}
```

For AI Gateway access:

```json
{
  "model_access": ["llama2", "codellama"],
  "rate_limit_tier": "standard",
  "max_tokens_per_day": 10000000
}
```

---

## Token Lifetime & Refresh

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Access Token TTL | 15 minutes | Short-lived, lower blast radius |
| Refresh Token TTL | 7 days | Reasonable session duration |
| ID Token TTL | 1 hour | Matches session timeout |
| Refresh Interval | 5 minutes before expiry | Automatic transparent refresh |

---

## Example JWT Payload (Decoded)

```json
{
  "iss": "https://accounts.google.com",
  "sub": "117829634571892340923",
  "aud": ["code-server", "appsmith", "backstage"],
  "exp": 1713607199,
  "iat": 1713603599,
  "auth_time": 1713603599,
  "email": "alice@example.com",
  "email_verified": true,
  "name": "Alice Chen",
  "roles": ["admin", "operator"],
  "org": "acme-corp",
  "github_username": "alice-chen",
  "github_teams": ["platform", "security"],
  "correlation_id": "req-2026-04-22-a1b2c3d4",
  "requested_scopes": "openid profile email roles",
  "session_id": "sess-xyz789",
  "client_id": "code-server-web",
  "model_access": ["llama2", "codellama"],
  "rate_limit_tier": "standard"
}
```

---

## Token Validation Checklist

Every service receiving a JWT MUST validate:

- [ ] **Signature**: Valid ED25519 or RS256 signature from issuer's public key
- [ ] **Issuer**: Matches expected `iss` claim (Google or Keycloak endpoint)
- [ ] **Audience**: Service is listed in `aud` claim
- [ ] **Expiration**: Current time < `exp` (with 60s clock skew tolerance)
- [ ] **Subject**: Not null/empty
- [ ] **Custom Claims**: Required roles/org present
- [ ] **Blacklist**: Check revocation list (if implemented)

---

## Service-to-Service Tokens

For service-to-service auth (e.g., Backstage → GitHub), use:

```
Authorization: Bearer <jwt>
X-Correlation-ID: <correlation_id>
X-Service-ID: <service-name>
```

**Workload Identity Claims**:
```json
{
  "sub": "backstage@acme-corp.iam.gserviceaccount.com",
  "aud": "github.com",
  "iss": "https://keycloak.192.168.168.31/realms/acme-corp"
}
```

---

## Emergency Access (Break-Glass) Token

For break-glass scenarios, issue time-limited, high-privilege tokens:

```json
{
  "sub": "incident-responder",
  "roles": ["emergency_admin"],
  "exp": "<now + 30 minutes>",
  "break_glass_justification": "incident-123",
  "audit_required": true
}
```

All break-glass access MUST:
- [ ] Be logged with full context
- [ ] Expire automatically (max 30 minutes)
- [ ] Require post-incident review
- [ ] Trigger security team notification

---

## Implementation Checklist

- [ ] All JWTs signed with service private key (ED25519 preferred)
- [ ] Token issuer's public key cached with 1-hour TTL
- [ ] All validation failures logged with correlation ID
- [ ] Rejected tokens don't cause service errors
- [ ] Rate limiting on failed validation attempts
- [ ] Metrics tracked: valid, expired, invalid_sig, wrong_aud

---

**Reference**: [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)  
**Next Phase**: Phase 2 - Service-to-service authentication implementation
