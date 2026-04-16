# OIDC Provider Setup Guide (Phase 1)

**Status**: Production-Ready  
**Target Environment**: 192.168.168.31 (primary) + .42 (replica)  
**Start Date**: April 22, 2026  

---

## Option 1: Google OAuth2 (Recommended for On-Prem)

### Prerequisites
- Google Cloud Project (GCP) or use kushnir.cloud domain
- OAuth2 consent screen already configured
- Admin access to Google Workspace (if using Google Accounts)

### Step 1: Create OAuth2 Credentials

1. Go to [GCP Console](https://console.cloud.google.com/)
2. Navigate to **APIs & Services** → **Credentials**
3. Click **+ Create Credentials** → **OAuth 2.0 Client ID**
4. Application type: **Web application**
5. Authorized redirect URIs:
   ```
   http://192.168.168.31:4180/oauth2/callback
   http://code-server.kushnir.cloud/oauth2/callback
   http://code-server.192.168.168.31.nip.io:4180/oauth2/callback
   ```
6. Click **Create** and note the **Client ID** and **Client Secret**

### Step 2: Configure oauth2-proxy

Copy Client ID and Secret to environment:

```bash
# On 192.168.168.31
ssh akushnir@192.168.168.31

# Set in .env file
export OAUTH2_CLIENT_ID="<client-id-from-gcp>"
export OAUTH2_CLIENT_SECRET="<client-secret-from-gcp>"
export OAUTH2_REDIRECT_URL="http://192.168.168.31:4180/oauth2/callback"

# Update docker-compose environment
cat >> .env <<'EOF'
GOOGLE_OAUTH2_CLIENT_ID=${OAUTH2_CLIENT_ID}
GOOGLE_OAUTH2_CLIENT_SECRET=${OAUTH2_CLIENT_SECRET}
OAUTH2_REDIRECT_URL=${OAUTH2_REDIRECT_URL}
OAUTH2_PROVIDER="google"
OAUTH2_OIDC_ISSUER_URL="https://accounts.google.com"
EOF
```

### Step 3: Deploy oauth2-proxy with OIDC

```bash
# Test configuration locally
docker-compose config | grep -A 20 "oauth2-proxy:"

# Start oauth2-proxy service
docker-compose up -d oauth2-proxy

# Verify startup (should show "listening on...")
docker logs oauth2-proxy | grep -i "listening\|startup\|oidc"

# Test OIDC discovery endpoint
curl -s http://localhost:4180/oauth2/userinfo || echo "Not authenticated yet"
```

### Step 4: Test OAuth2 Flow

1. Navigate to http://192.168.168.31:4180/
2. Should redirect to Google login
3. Authenticate with your Google account
4. Should redirect back to oauth2-proxy with session cookie
5. Call API endpoint to verify token:
   ```bash
   curl -b "oauth2_proxy_<domain>=<session_cookie>" \
     http://localhost:4180/oauth2/userinfo
   ```

Expected response:
```json
{
  "email": "user@example.com",
  "name": "Your Name",
  "sub": "117829634571892340923"
}
```

---

## Option 2: Keycloak (Self-Hosted Fallback)

### Prerequisites
- Docker daemon available on 192.168.168.31
- PostgreSQL for Keycloak database (optional: use H2 embedded)
- CPU & memory for container

### Step 1: Deploy Keycloak

```bash
ssh akushnir@192.168.168.31

cat >> docker-compose.yml <<'EOF'
  keycloak:
    image: bitnami/keycloak:24.0.5
    environment:
      KEYCLOAK_ADMIN_USER: admin
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD:-change-me}
      KEYCLOAK_ADMIN_EMAIL: admin@example.com
      KEYCLOAK_DATABASE_VENDOR: h2
      KEYCLOAK_PROXY_ADDRESS_FORWARDING: "true"
    ports:
      - "8180:8080"
    volumes:
      - keycloak_data:/bitnami/keycloak/data
    networks:
      - code-server
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health/ready"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  keycloak_data:
EOF

docker-compose up -d keycloak

# Wait for startup (may take 2-3 minutes)
docker logs -f keycloak | grep "started in"
```

### Step 2: Configure Keycloak Realm

Access admin console: http://192.168.168.31:8180/admin

1. **Create Realm**: "acme-corp" (or your org name)
2. **Create Client**:
   - Client ID: `code-server-web`
   - Client Protocol: `openid-connect`
   - Access Type: `public`
   - Valid Redirect URIs: `http://192.168.168.31:4180/oauth2/callback`

3. **Configure Scopes**:
   - Standard Scopes: `openid`, `profile`, `email`, `roles`
   - Role Mapper: Add `realm-roles` claim to access token

4. **Create Users**:
   - Username: `alice` (email: alice@example.com, role: admin)
   - Username: `bob` (email: bob@example.com, role: operator)
   - Username: `charlie` (email: charlie@example.com, role: viewer)

### Step 3: Get OIDC Endpoints

```bash
# Keycloak OIDC Discovery URL
curl http://192.168.168.31:8180/realms/acme-corp/.well-known/openid-configuration

# Extract these values:
# - issuer: https://192.168.168.31:8180/realms/acme-corp
# - authorization_endpoint: ...
# - token_endpoint: ...
# - userinfo_endpoint: ...
# - jwks_uri: ...
```

### Step 4: Configure oauth2-proxy for Keycloak

```bash
cat >> .env <<'EOF'
OAUTH2_PROVIDER="oidc"
OAUTH2_OIDC_ISSUER_URL="http://192.168.168.31:8180/realms/acme-corp"
OAUTH2_CLIENT_ID="code-server-web"
OAUTH2_CLIENT_SECRET="<keycloak-client-secret>"
OAUTH2_REDIRECT_URL="http://192.168.168.31:4180/oauth2/callback"
EOF

docker-compose up -d oauth2-proxy
```

---

## Verification Checklist

After deploying either provider:

- [ ] oauth2-proxy is running and healthy
- [ ] Browser redirect to provider works
- [ ] Authentication succeeds (redirects back)
- [ ] Session cookie is set (`oauth2_proxy_<domain>`)
- [ ] `/oauth2/userinfo` returns authenticated user
- [ ] JWT token can be extracted from session
- [ ] Token claims include `email`, `name`, `roles` (if configured)
- [ ] Token expiration is working (should refresh automatically)

### Quick Verification Script

```bash
#!/bin/bash
set -e

echo "=== OIDC Provider Verification ==="

# Check oauth2-proxy is running
docker ps | grep oauth2-proxy || { echo "❌ oauth2-proxy not running"; exit 1; }
echo "✅ oauth2-proxy running"

# Check OIDC discovery
ISSUER=$(grep OAUTH2_OIDC_ISSUER_URL .env | cut -d= -f2)
curl -s "${ISSUER}/.well-known/openid-configuration" | grep -q "issuer" && echo "✅ OIDC discovery working"

# Check oauth2-proxy health
curl -s http://localhost:4180/health | grep -q "ok" && echo "✅ oauth2-proxy health check passing"

# Test redirect to provider
curl -s -L http://localhost:4180/ | grep -q "google\|keycloak" && echo "✅ Provider redirect configured"

echo "=== All checks passed ==="
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "invalid_client" error | Check Client ID/Secret match in .env |
| "redirect_uri_mismatch" | Add all expected URIs in provider settings |
| "Unable to verify signature" | Check public key fetch from issuer |
| Infinite redirect loop | Check `OAUTH2_REDIRECT_URL` matches provider config |
| Session not persisting | Check `oauth2_proxy_*` cookie is being set |

---

## Security Best Practices

- [ ] Rotate Client Secret periodically (quarterly minimum)
- [ ] Use HTTPS in production (Caddy handles this)
- [ ] Store Client Secret in GSM, not git
- [ ] Monitor failed authentication attempts
- [ ] Set cookie `HttpOnly` and `Secure` flags (default in oauth2-proxy)
- [ ] Implement rate limiting on auth endpoints
- [ ] Log all authentication events with correlation IDs

---

**Next**: Proceed to Phase 2 - Service-to-Service Authentication
