# OAuth Consolidation Configuration - Phase 2

**Purpose**: Consolidate oauth2-proxy flows for unified session across .kushnir.cloud subdomains  
**Status**: Implementation Guide  
**Related Issue**: #1678  
**Date**: April 24, 2026

---

## Overview

Currently, the deployment has:
- `oauth2-proxy`: Protects ide.kushnir.cloud
- `oauth2-proxy-portal`: Protects kushnir.cloud

**Consolidation Goal**: Single oauth2-proxy service protecting both subdomains with unified session persistence.

---

## Implementation Steps

### Step 1: oauth2-proxy.cfg Consolidation

**Current State**: Two separate proxy configurations  
**Target State**: Single unified configuration

```bash
# Key configuration settings to consolidate:

# Cookie Configuration (enables subdomain session sharing)
cookie-domain = .kushnir.cloud
cookie-name = oauth2-proxy-session
cookie-secure = true
cookie-httponly = true
cookie-samesite = Lax

# Subdomain Whitelist
whitelist-domains = .kushnir.cloud
cookie-refresh = 1h
cookie-expire = 24h

# Redis Session Store (cluster-wide persistence)
session-store-type = redis
redis-connection-url = redis://redis-session:6379/0

# OAuth Provider Configuration
provider = oidc
provider-display-name = OIDC
oidc-issuer-url = ${OIDC_ISSUER_URL}
client-id = ${OAUTH_CLIENT_ID}
client-secret = ${OAUTH_CLIENT_SECRET}

# Redirect URIs (both subdomains)
redirect-url = https://kushnir.cloud/oauth2/callback
redirect-url = https://ide.kushnir.cloud/oauth2/callback

# Token Settings
scope = openid email profile groups
token-validation = jwt
```

### Step 2: docker-compose.yml Updates

**Remove**: `oauth2-proxy-portal` service (consolidate into `oauth2-proxy`)

**Update**: `oauth2-proxy` service configuration

```yaml
services:
  oauth2-proxy:
    image: oauth2-proxy/oauth2-proxy:v7.5.1
    container_name: oauth2-proxy
    restart: unless-stopped
    networks:
      - net-app
    ports:
      - "4180:4180"
    environment:
      OAUTH2_PROXY_CONFIG_FILE: /etc/oauth2-proxy/oauth2-proxy.cfg
      # Session store
      OAUTH2_PROXY_SESSION_STORE_TYPE: redis
      OAUTH2_PROXY_REDIS_CONNECTION_URL: redis://redis-session:6379/0
      # Cookie settings for subdomain sharing
      OAUTH2_PROXY_COOKIE_DOMAIN: .kushnir.cloud
      OAUTH2_PROXY_COOKIE_SECURE: "true"
      OAUTH2_PROXY_COOKIE_HTTPONLY: "true"
      OAUTH2_PROXY_COOKIE_SAMESITE: Lax
      # OAuth provider
      OAUTH2_PROXY_PROVIDER: oidc
      OAUTH2_PROXY_OIDC_ISSUER_URL: ${OIDC_ISSUER_URL}
      OAUTH2_PROXY_CLIENT_ID: ${OAUTH_CLIENT_ID}
      OAUTH2_PROXY_CLIENT_SECRET: ${OAUTH_CLIENT_SECRET}
      # Whitelist subdomains
      OAUTH2_PROXY_WHITELIST_DOMAINS: .kushnir.cloud
    volumes:
      - ./oauth2-proxy.cfg:/etc/oauth2-proxy/oauth2-proxy.cfg:ro
    health_check:
      test: ["CMD", "curl", "-f", "http://127.0.0.1:4180/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    depends_on:
      - redis-session
```

### Step 3: Caddyfile Updates

**Current**: Two separate upstream targets (oauth2-proxy-portal, oauth2-proxy)  
**Target**: Single oauth2-proxy upstream for both subdomains

```caddyfile
# Unified OAuth proxy (protects both subdomains)
oauth2-proxy-unified {
  upstream http://oauth2-proxy:4180
}

# kushnir.cloud (portal)
kushnir.cloud, www.kushnir.cloud {
  handle /oauth2/* {
    # OAuth callbacks
    reverse_proxy oauth2-proxy-unified
  }
  
  handle {
    # Protected routes via oauth2-proxy
    forward_auth oauth2-proxy-unified {
      uri /oauth2/auth
      header_down X-Auth-Request-User {http.auth.user.id}
      header_down X-Auth-Request-Email {http.auth.user.email}
    }
    
    # Route to Appsmith
    reverse_proxy appsmith:80
  }
}

# ide.kushnir.cloud (VS Code IDE)
ide.kushnir.cloud {
  handle /oauth2/* {
    # OAuth callbacks
    reverse_proxy oauth2-proxy-unified
  }
  
  handle {
    # Protected routes via oauth2-proxy
    forward_auth oauth2-proxy-unified {
      uri /oauth2/auth
      header_down X-Auth-Request-User {http.auth.user.id}
      header_down X-Auth-Request-Email {http.auth.user.email}
    }
    
    # Route to code-server
    reverse_proxy code-server:80
  }
}
```

---

## Unified Session Behavior

### Session Persistence Across Subdomains

**Cookie Name**: `oauth2-proxy-session`  
**Domain**: `.kushnir.cloud` (shared across all subdomains)  
**Storage**: Redis (cluster-wide, replicated across 192.168.168.31 and 192.168.168.42)

**Flow**:
1. User authenticates at kushnir.cloud → oauth2-proxy sets session cookie
2. Cookie domain = `.kushnir.cloud` → cookie sent to all subdomains
3. User navigates to ide.kushnir.cloud → cookie validated via Redis
4. No re-authentication required ✅

### Token Refresh Behavior

**Automatic Refresh**: Background token refresh without user prompt

```bash
# Configuration
cookie-refresh = 1h          # Validate token every 1 hour
cookie-expire = 24h          # Session expires after 24 hours
token-validation = jwt       # Validate JWT signature
```

**Behavior**:
- Token approaches expiry → oauth2-proxy auto-refreshes via OIDC provider
- New token stored in Redis session
- User unaware of refresh ✅

### Logout Behavior

**Single Logout Point**: Any subdomain logout clears all sessions

```bash
# Logout configuration
logout-url = https://kushnir.cloud/oauth2/logout
```

**Implementation**:
1. User clicks logout anywhere
2. oauth2-proxy deletes session from Redis
3. Cookie cleared (all subdomains affected)
4. All subdomains immediately require re-authentication ✅

---

## Deployment Procedure

### Pre-Deployment

```bash
# 1. Verify configuration files
grep -n "cookie-domain" oauth2-proxy.cfg
grep -n "redis-connection-url" oauth2-proxy.cfg
grep -n "oauth2-proxy:4180" Caddyfile

# 2. Backup current configuration
cp oauth2-proxy.cfg oauth2-proxy.cfg.backup
cp docker-compose.yml docker-compose.yml.backup
cp Caddyfile Caddyfile.backup
```

### Deployment to Replicas

```bash
# Parallel deployment to both replicas
for replica in 192.168.168.31 192.168.168.42; do
  ssh akushnir@$replica "cd code-server-enterprise && \
    git fetch origin main && \
    git checkout origin/main -- oauth2-proxy.cfg Caddyfile docker-compose.yml && \
    docker compose pull oauth2-proxy && \
    docker compose up -d oauth2-proxy && \
    sleep 30" &
done
wait
```

### Post-Deployment Verification

```bash
# 1. Verify oauth2-proxy health
curl -I http://192.168.168.31:4180/ping  # Should return 200
curl -I http://192.168.168.42:4180/ping  # Should return 200

# 2. Verify cookie domain configuration
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker compose exec -T oauth2-proxy grep 'cookie-domain' oauth2-proxy.cfg"

# 3. Verify Redis connection
ssh akushnir@192.168.168.31 "cd code-server-enterprise && \
  docker compose exec redis-session redis-cli ping"

# 4. Test cross-subdomain session
curl -I https://kushnir.cloud/        # Should 200 or redirect to auth
curl -I https://ide.kushnir.cloud/    # Should 200 or redirect to auth
```

---

## Acceptance Criteria

- [ ] Single oauth2-proxy service configured
- [ ] Cookie domain set to .kushnir.cloud
- [ ] SameSite=Lax, Secure, HttpOnly flags set
- [ ] Session persists across kushnir.cloud ↔ ide.kushnir.cloud
- [ ] No redirect loops in OAuth callback flow
- [ ] Token refresh: automatic background refresh without user prompt
- [ ] Logout: single logout clears all subdomain sessions
- [ ] PR merged with conventional commit

---

## Troubleshooting

### Issue: Session not persisting across subdomains

**Cause**: Cookie domain not set to `.kushnir.cloud`

**Resolution**:
```bash
# Verify cookie domain
grep "cookie-domain" oauth2-proxy.cfg

# Should return:
# cookie-domain = .kushnir.cloud
```

### Issue: Redis connection failed

**Cause**: redis-session service not running or misconfigured

**Resolution**:
```bash
# Check redis-session status
docker compose ps redis-session

# Check Redis connection URL
docker compose exec oauth2-proxy env | grep REDIS
```

### Issue: Redirect loop between kushnir.cloud and id.kushnir.cloud

**Cause**: Caddyfile routing misconfigured

**Resolution**:
```bash
# Verify Caddyfile has both subdomains pointing to same oauth2-proxy
grep -A 5 "kushnir.cloud" Caddyfile | grep "forward_auth"
grep -A 5 "ide.kushnir.cloud" Caddyfile | grep "forward_auth"

# Both should reference same upstream
```

---

## Related Issues

- Parent Epic: #1545 (Endpoint & SSO)
- Previous Phase: #1677 (Portal Foundation)
- Next Phase: #1676 (SSO Validation Tests)

---

**Version**: 1.0  
**Status**: Implementation-Ready  
**Last Updated**: April 24, 2026
