# Phase 2.1: OIDC Issuer Configuration
# Enables oauth2-proxy to act as an OIDC provider for workload identity federation
# GitHub Actions and Kubernetes ServiceAccounts can request tokens from this issuer

# Docker Compose amendment for oauth2-oidc-issuer service
# This is a NEW service alongside the existing oauth2-proxy service

oauth2-oidc-issuer:
  image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1
  container_name: oauth2-oidc-issuer
  restart: unless-stopped
  user: "101"
  networks:
    - net-edge
    - net-app
  expose:
    - "4182"
  environment:
    # OIDC Issuer Configuration
    OAUTH2_PROXY_PROVIDER: "oidc"
    OAUTH2_PROXY_OIDC_ISSUER_URL: "https://ide.kushnir.cloud/.well-known/openid-configuration"
    
    # JWT Token Issuance
    OAUTH2_PROXY_JWT_ISSUERS: "https://ide.kushnir.cloud"
    OAUTH2_PROXY_JWT_ISSUER_KEY: "${OIDC_ISSUER_SIGNING_KEY}"
    OAUTH2_PROXY_JWT_SIGNING_METHOD: "RS256"
    
    # Token Configuration
    OAUTH2_PROXY_JWT_CLAIMS_GROUPS: "${OIDC_JWT_CLAIMS_GROUPS:-true}"
    OAUTH2_PROXY_JWT_CLAIMS_AUDIENCE: "${OIDC_JWT_AUDIENCE:-code-server,api,github-actions,kubernetes}"
    
    # Allowed OAuth Clients (for token requests)
    OAUTH2_PROXY_OIDC_ALLOWED_AUDIENCES: "code-server,api,github-actions,kubernetes"
    
    # HTTP Configuration
    OAUTH2_PROXY_HTTP_ADDRESS: "0.0.0.0:4182"
    OAUTH2_PROXY_PROXY_PREFIX: "/.well-known"
    
    # Logging
    OAUTH2_PROXY_REQUEST_LOGGING: "true"
    OAUTH2_PROXY_AUTH_LOGGING: "true"
  
  healthcheck:
    test: ["CMD-SHELL", "curl -fsS http://localhost:4182/.well-known/openid-configuration || exit 1"]
    interval: 30s
    timeout: 5s
    retries: 3
    start_period: 30s
  
  depends_on:
    - redis
    - postgres

---

# Caddy Configuration Amendment (Caddyfile)
# Route /.well-known/openid-configuration to oauth2-oidc-issuer service

# Add to :80 block:
# Health check endpoint (already exists)
@health path /health /healthz /ping
respond @health "OK" 200

# OIDC Configuration endpoint (NEW)
@oidc_config path /.well-known/openid-configuration /.well-known/jwks.json
reverse_proxy @oidc_config oauth2-oidc-issuer:4182 {
    header_up Host ide.kushnir.cloud
    header_up X-Forwarded-Proto https
    header_up X-Real-IP {remote_host}
}

# OAuth2-proxy gate (existing)
reverse_proxy 172.28.1.2:4180 {
    header_up Host ide.kushnir.cloud
    header_up X-Forwarded-Proto https
    header_up X-Real-IP {remote_host}
}

---

# Required Environment Variables (to add to .env)
# These are the minimum required to enable OIDC issuer mode

# RSA Key Pair for JWT Signing (generate with: openssl genrsa -out private.pem 4096)
OIDC_ISSUER_SIGNING_KEY="-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----"
OIDC_ISSUER_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0...\n-----END PUBLIC KEY-----"

# JWT Configuration
OIDC_JWT_AUDIENCE="code-server,api,github-actions,kubernetes"
OIDC_JWT_CLAIMS_GROUPS="true"
OIDC_JWT_EXPIRATION="3600"  # 1 hour

# GitHub Actions OIDC Federation
GITHUB_OIDC_SUBJECT_CLAIM="sub"
GITHUB_OIDC_ACTOR_CLAIM="actor"

# Kubernetes OIDC Federation
KUBERNETES_OIDC_SUBJECT_CLAIM="sub"
KUBERNETES_OIDC_GROUPS_CLAIM="groups"

---

# Implementation Steps

## Step 1: Generate RSA Key Pair
ssh akushnir@192.168.168.31
openssl genrsa -out /home/akushnir/code-server-enterprise/oidc-signing-key.pem 4096
openssl rsa -in /home/akushnir/code-server-enterprise/oidc-signing-key.pem -pubout -out /home/akushnir/code-server-enterprise/oidc-signing-key.pub

## Step 2: Update .env with Keys
# Add OIDC_ISSUER_SIGNING_KEY and OIDC_ISSUER_PUBLIC_KEY to .env
cat oidc-signing-key.pem  # Copy content to .env
cat oidc-signing-key.pub  # Copy content to .env

## Step 3: Update docker-compose.yml
# Add oauth2-oidc-issuer service
# Update Caddyfile routing for /.well-known/* endpoints

## Step 4: Restart Services
docker-compose down
docker-compose up -d

## Step 5: Verify OIDC Endpoint
curl -s https://kushnir.cloud/.well-known/openid-configuration | jq .
curl -s https://kushnir.cloud/.well-known/jwks.json | jq .

## Step 6: Test Token Issuance
curl -X POST https://kushnir.cloud/oauth2/token \
  -d "grant_type=client_credentials&client_id=github-actions&client_secret=secret"

---

# Testing Checklist

- [ ] .well-known/openid-configuration endpoint responds (200 OK)
- [ ] JWKS endpoint responds with public keys
- [ ] JWT tokens can be requested for workload identities
- [ ] Tokens contain required claims (sub, aud, iss, iat, exp)
- [ ] GitHub Actions OIDC flow works end-to-end
- [ ] Kubernetes ServiceAccount OIDC flow works end-to-end
- [ ] Token expiration and refresh work correctly
- [ ] Health check endpoint is operational

---

# Blockers and Assumptions

1. **oauth2-proxy version limitation**: Current v7.5.1 may not have full OIDC issuer support
   - May need to upgrade to v7.6.0 or higher
   - Check: https://github.com/oauth2-proxy/oauth2-proxy/releases

2. **Key storage**: RSA keys currently in .env file
   - Phase 3: Move to Google Secret Manager
   - Phase 4: Implement automatic key rotation

3. **Token validation**: Needs to be implemented in each consuming service
   - Code-server: Add JWT validation middleware
   - API services: Add token verification

---

# Related Issues & PRs
- Issue #388: Identity & Workload Authentication Standardization
- Issue #1017: REDEPLOY-001 (infrastructure recovery) - COMPLETE
- Issue #1018: P1 Phase 2.1 OIDC Issuer Deployment (THIS ISSUE)
