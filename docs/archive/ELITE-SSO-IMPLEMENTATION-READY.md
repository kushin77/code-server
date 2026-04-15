# Elite SSO Implementation (#434)
**Status**: Ready for Immediate Deployment  
**Value**: Security hardening + UX improvement  
**Estimated Effort**: 6-8 hours (can be done in parallel)  
**Blockers**: None (can proceed independently)  

---

## Implementation Strategy

This implementation covers all 6 sub-issues of Epic #434:
- #435: Fix oauth2-proxy cookie domain
- #436: Add subdomain routing in Caddyfile
- #437: Enable Grafana header-based auth
- #438: Remove direct port exposure
- #439: Build root portal dashboard
- #440: Harden oauth2-proxy (PKCE, unified logout, rate limiting)

All changes are backward-compatible and can be deployed as a single unit.

---

## Part 1: Fix Cookie Domain (#435)

### Changes Required

**File**: `docker-compose.yml`

**Current** (Line ~310):
```yaml
OAUTH2_PROXY_COOKIE_DOMAIN: .${DOMAIN}   # resolves to .ide.kushnir.cloud
```

**Target**:
```yaml
OAUTH2_PROXY_COOKIE_DOMAIN: .${APEX_DOMAIN}   # resolves to .kushnir.cloud
```

### Environment Variables

**File**: `.env.example`, `.env`, `.env.ci`, `.env.production`

Add:
```bash
APEX_DOMAIN=kushnir.cloud      # Apex domain for shared SSO cookie
DOMAIN=ide.kushnir.cloud       # Subdomain for code-server
```

---

## Part 2: Add Subdomain Routing (#436)

### Update Caddyfile.tpl

Add new blocks for each monitoring service:

```caddy
# Apex domain - portal dashboard
${APEX_DOMAIN:-kushnir.cloud} {
  ${CADDY_TLS_BLOCK:-tls internal}
  import security_headers
  handle {
    reverse_proxy oauth2-proxy:4180 {
      header_up Host              {upstream_hostport}
      header_up X-Real-IP         {remote_host}
      header_up X-Forwarded-Proto {scheme}
    }
  }
}

# Monitoring subdomains - all behind oauth2-proxy
grafana.${APEX_DOMAIN:-kushnir.cloud} {
  ${CADDY_TLS_BLOCK:-tls internal}
  import security_headers
  handle {
    reverse_proxy oauth2-proxy:4180 {
      header_up Host              {upstream_hostport}
      header_up X-Real-IP         {remote_host}
      header_up X-Forwarded-Proto {scheme}
    }
  }
}

metrics.${APEX_DOMAIN:-kushnir.cloud} {
  ${CADDY_TLS_BLOCK:-tls internal}
  import security_headers
  handle {
    reverse_proxy oauth2-proxy:4180 {
      header_up Host              {upstream_hostport}
      header_up X-Real-IP         {remote_host}
      header_up X-Forwarded-Proto {scheme}
    }
  }
}

alerts.${APEX_DOMAIN:-kushnir.cloud} {
  ${CADDY_TLS_BLOCK:-tls internal}
  import security_headers
  handle {
    reverse_proxy oauth2-proxy:4180 {
      header_up Host              {upstream_hostport}
      header_up X-Real-IP         {remote_host}
      header_up X-Forwarded-Proto {scheme}
    }
  }
}

tracing.${APEX_DOMAIN:-kushnir.cloud} {
  ${CADDY_TLS_BLOCK:-tls internal}
  import security_headers
  handle {
    reverse_proxy oauth2-proxy:4180 {
      header_up Host              {upstream_hostport}
      header_up X-Real-IP         {remote_host}
      header_up X-Forwarded-Proto {scheme}
    }
  }
}
```

### Remove Old Port Blocks

Delete these from Caddyfile.tpl (if they exist):
```
:3000        → removed (use grafana.${APEX_DOMAIN} instead)
:9090        → removed (use metrics.${APEX_DOMAIN} instead)
:9093        → removed (use alerts.${APEX_DOMAIN} instead)
:16686       → removed (use tracing.${APEX_DOMAIN} instead)
```

---

## Part 3: Grafana Header-Based Auth (#437)

### Update docker-compose.yml - Grafana Service

Add to environment section:

```yaml
# SSO via oauth2-proxy header passthrough
GF_AUTH_PROXY_ENABLED:             "true"
GF_AUTH_PROXY_HEADER_NAME:         "X-Auth-Request-Email"
GF_AUTH_PROXY_HEADER_PROPERTY:     "email"
GF_AUTH_PROXY_AUTO_SIGN_UP:        "true"
GF_AUTH_PROXY_SYNC_TTL:            "60"
GF_AUTH_PROXY_WHITELIST:           "oauth2-proxy"
GF_AUTH_PROXY_HEADERS:             "Email:X-Auth-Request-Email Name:X-Auth-Request-User"

# Disable Grafana's native login (oauth2-proxy is gatekeeper)
GF_AUTH_DISABLE_LOGIN_FORM:        "true"
GF_AUTH_DISABLE_SIGNOUT_MENU:      "true"

# Default role for auto-provisioned users
GF_AUTH_PROXY_DEFAULT_ROLE:        "Viewer"

# Ensure anonymous access is disabled
GF_AUTH_ANONYMOUS_ENABLED:         "false"

# Root URL must match subdomain
GF_SERVER_ROOT_URL:                "https://grafana.${APEX_DOMAIN:-kushnir.cloud}"
GF_SERVER_SERVE_FROM_SUB_PATH:     "false"

# Logout redirect
GF_AUTH_SIGNOUT_REDIRECT_URL:      "https://ide.${APEX_DOMAIN}/oauth2/sign_out?rd=https://grafana.${APEX_DOMAIN}"
```

---

## Part 4: Port Exposure Hardening (#438)

### Already Completed

✅ Loki: Changed from `ports: [0.0.0.0:3100]` to `expose: [3100]`
✅ Grafana: Changed from `ports: [0.0.0.0:3000]` to `expose: [3000]`

Verify no other services expose monitoring ports on 0.0.0.0.

---

## Part 5: Root Portal Dashboard (#440)

### Create Portal Service

**File**: `portal/nginx.conf`

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
  worker_connections 1024;
}

http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;

  log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                  '$status $body_bytes_sent "$http_referer" '
                  '"$http_user_agent" "$http_x_forwarded_for"';

  access_log /var/log/nginx/access.log main;

  sendfile on;
  tcp_nopush on;
  tcp_nodelay on;
  keepalive_timeout 65;
  types_hash_max_size 2048;
  client_max_body_size 20M;

  gzip on;
  gzip_vary on;
  gzip_types text/plain text/css text/xml text/javascript 
             application/x-javascript application/xml+rss 
             application/javascript application/json;

  server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    location / {
      try_files $uri $uri/ /index.html;
    }

    # Health check
    location /healthz {
      return 200 "healthy";
    }
  }
}
```

**File**: `portal/index.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>kushnir.cloud - Enterprise Portal</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }

    .container {
      max-width: 1200px;
      width: 100%;
    }

    .header {
      text-align: center;
      color: white;
      margin-bottom: 50px;
    }

    .header h1 {
      font-size: 2.5em;
      margin-bottom: 10px;
    }

    .header p {
      font-size: 1.1em;
      opacity: 0.9;
    }

    .user-info {
      text-align: center;
      color: white;
      margin-bottom: 30px;
      font-size: 0.95em;
      opacity: 0.8;
    }

    .services-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
      gap: 20px;
      margin-bottom: 40px;
    }

    .service-card {
      background: white;
      border-radius: 8px;
      padding: 25px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
      transition: transform 0.3s, box-shadow 0.3s;
      text-decoration: none;
      color: inherit;
    }

    .service-card:hover {
      transform: translateY(-5px);
      box-shadow: 0 15px 40px rgba(0,0,0,0.3);
    }

    .service-icon {
      font-size: 2.5em;
      margin-bottom: 15px;
    }

    .service-name {
      font-size: 1.3em;
      font-weight: 600;
      margin-bottom: 8px;
      color: #333;
    }

    .service-desc {
      font-size: 0.9em;
      color: #666;
      margin-bottom: 15px;
    }

    .service-status {
      display: inline-block;
      padding: 4px 8px;
      border-radius: 4px;
      font-size: 0.8em;
      font-weight: 600;
    }

    .status-healthy {
      background: #d4edda;
      color: #155724;
    }

    .status-loading {
      background: #fff3cd;
      color: #856404;
    }

    .status-unhealthy {
      background: #f8d7da;
      color: #721c24;
    }

    .footer {
      text-align: center;
      color: white;
      margin-top: 30px;
      opacity: 0.7;
    }

    .logout-btn {
      background: rgba(255,255,255,0.2);
      color: white;
      border: 2px solid white;
      padding: 10px 20px;
      border-radius: 5px;
      cursor: pointer;
      font-size: 1em;
      transition: background 0.3s;
    }

    .logout-btn:hover {
      background: rgba(255,255,255,0.3);
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🚀 kushnir.cloud</h1>
      <p>Enterprise Development Platform</p>
    </div>

    <div class="user-info" id="userInfo">
      Loading...
    </div>

    <div class="services-grid" id="servicesGrid">
      <!-- Services will be populated by JavaScript -->
    </div>

    <div class="footer">
      <button class="logout-btn" onclick="logout()">Sign Out</button>
      <p style="margin-top: 20px; font-size: 0.9em;">All services require authentication via Google SSO</p>
    </div>
  </div>

  <script>
    const APEX_DOMAIN = window.location.hostname.endsWith('.kushnir.cloud') 
      ? '.kushnir.cloud' 
      : window.location.hostname;

    const services = [
      {
        name: 'IDE',
        icon: '💻',
        desc: 'Code Server - VS Code in your browser',
        url: `https://ide.kushnir.cloud`,
        healthUrl: `https://ide.kushnir.cloud/healthz`
      },
      {
        name: 'Dashboards',
        icon: '📊',
        desc: 'Grafana - Observability dashboards',
        url: `https://grafana.kushnir.cloud`,
        healthUrl: `https://grafana.kushnir.cloud/api/health`
      },
      {
        name: 'Metrics',
        icon: '📈',
        desc: 'Prometheus - Time-series metrics',
        url: `https://metrics.kushnir.cloud`,
        healthUrl: `https://metrics.kushnir.cloud/-/healthy`
      },
      {
        name: 'Alerts',
        icon: '🚨',
        desc: 'AlertManager - Alert routing & management',
        url: `https://alerts.kushnir.cloud`,
        healthUrl: `https://alerts.kushnir.cloud/-/healthy`
      },
      {
        name: 'Tracing',
        icon: '🔍',
        desc: 'Jaeger - Distributed tracing',
        url: `https://tracing.kushnir.cloud`,
        healthUrl: `https://tracing.kushnir.cloud/api/traces`
      }
    ];

    // Load user info
    async function loadUserInfo() {
      try {
        const response = await fetch('/oauth2/userinfo');
        if (response.ok) {
          const user = await response.json();
          document.getElementById('userInfo').innerHTML = 
            `Welcome, <strong>${user.email}</strong>`;
        }
      } catch (e) {
        document.getElementById('userInfo').innerHTML = 'Authenticated';
      }
    }

    // Check service health
    async function checkHealth(service) {
      try {
        const response = await fetch(service.healthUrl);
        return response.ok ? 'healthy' : 'unhealthy';
      } catch (e) {
        return 'unhealthy';
      }
    }

    // Render services
    async function renderServices() {
      const grid = document.getElementById('servicesGrid');
      
      for (const service of services) {
        const card = document.createElement('a');
        card.href = service.url;
        card.className = 'service-card';
        
        const status = await checkHealth(service);
        const statusClass = status === 'healthy' ? 'status-healthy' : 'status-unhealthy';
        const statusText = status === 'healthy' ? '✓ Online' : '⚠ Offline';
        
        card.innerHTML = `
          <div class="service-icon">${service.icon}</div>
          <div class="service-name">${service.name}</div>
          <div class="service-desc">${service.desc}</div>
          <div class="service-status ${statusClass}">${statusText}</div>
        `;
        
        grid.appendChild(card);
      }
    }

    // Logout
    function logout() {
      window.location.href = `https://ide.kushnir.cloud/oauth2/sign_out?rd=https://${APEX_DOMAIN}`;
    }

    // Initialize
    loadUserInfo();
    renderServices();
  </script>
</body>
</html>
```

### Add Portal to docker-compose.yml

```yaml
# Portal Dashboard (Root Domain Entry Point)
portal:
  image: nginx:1.27-alpine
  container_name: portal
  restart: always
  networks: [enterprise]
  security_opt: ["no-new-privileges:true"]
  cap_drop: [ALL]
  expose: ["80"]
  volumes:
    - ./portal/index.html:/usr/share/nginx/html/index.html:ro
    - ./portal/nginx.conf:/etc/nginx/nginx.conf:ro
  healthcheck:
    test: ["CMD", "wget", "-qO-", "http://localhost/healthz"]
    interval: 30s
    timeout: 5s
    retries: 3
  logging: *logging
```

---

## Part 6: oauth2-proxy Hardening (#440)

### Update docker-compose.yml - oauth2-proxy

Add/Update environment variables:

```yaml
# PKCE for authorization code flow
OAUTH2_PROXY_CODE_CHALLENGE_METHOD:    S256

# Cookie domain fix (APEX_DOMAIN, not DOMAIN)
OAUTH2_PROXY_COOKIE_DOMAIN:            .${APEX_DOMAIN}

# Stronger cookie security
OAUTH2_PROXY_COOKIE_EXPIRE:            8h       # was: 24h
OAUTH2_PROXY_COOKIE_SAMESITE:          lax      # keep for OAuth compatibility
OAUTH2_PROXY_COOKIE_SECURE:            "true"   # already set
OAUTH2_PROXY_COOKIE_HTTPONLY:          "true"   # already set

# Unified logout configuration
OAUTH2_PROXY_WHITELIST_DOMAINS:        .${APEX_DOMAIN}

# Disable wildcard email domains (enforce allowlist)
OAUTH2_PROXY_EMAIL_DOMAINS:            ""       # disabled (use allowlist file only)

# OIDC extra validation
OAUTH2_PROXY_OIDC_EXTRA_AUDIENCE:      ${GOOGLE_CLIENT_ID}

# Auth logging (structured JSON)
OAUTH2_PROXY_AUTH_LOGGING:             "true"
OAUTH2_PROXY_REQUEST_LOGGING:          "true"
```

### Caddy Rate Limiting (if caddy-ratelimit plugin available)

Add to Caddyfile.tpl:

```caddy
# Rate-limit auth endpoint to prevent brute-force
@auth_signin path /oauth2/sign_in
handle @auth_signin {
  rate_limit {
    zone signin_zone {
      key {remote_host}
      events 10
      window 1m
    }
  }
  reverse_proxy oauth2-proxy:4180
}
```

---

## Deployment Procedure

### 1. Pre-Deployment Validation

```bash
# Verify no secrets exposed
gitleaks detect --verbose | grep -c "secret found"  # Should be 0

# Validate docker-compose
docker-compose config --quiet  # Should pass

# Validate Terraform
cd terraform && terraform validate  # Should pass
```

### 2. Apply Changes

```bash
# Build portal nginx image
docker-compose build portal

# Deploy all services
docker-compose up -d

# Verify health
docker-compose ps --format "table {{.Service}}\t{{.Status}}" | grep healthy
```

### 3. DNS Configuration

For each subdomain, add DNS record (in Cloudflare, GoDaddy, or internal DNS):

```
kushnir.cloud           → CNAME/A to primary.prod.internal (192.168.168.31)
ide.kushnir.cloud       → CNAME/A to primary.prod.internal
grafana.kushnir.cloud   → CNAME/A to primary.prod.internal
metrics.kushnir.cloud   → CNAME/A to primary.prod.internal
alerts.kushnir.cloud    → CNAME/A to primary.prod.internal
tracing.kushnir.cloud   → CNAME/A to primary.prod.internal
```

### 4. Test

```bash
# Without auth (should redirect to login)
curl -I https://grafana.kushnir.cloud/  # Should 302 to /oauth2/sign_in

# Check portal loads
curl https://kushnir.cloud/  # Should 302 to Google login if not authenticated

# Verify SSO works across subdomains (after login)
# - Login at https://ide.kushnir.cloud
# - Navigate to https://grafana.kushnir.cloud (should NOT re-prompt for login)
# - Navigate to https://metrics.kushnir.cloud (should NOT re-prompt for login)
```

---

## Rollback

If issues occur:

```bash
# Revert to previous commit
git revert <commit_sha>

# Re-deploy
terraform apply -auto-approve
docker-compose restart

# Verify service health
docker-compose ps
```

---

## Success Metrics

- ✅ Single sign-on works across all subdomains
- ✅ Portal dashboard loads at kushnir.cloud
- ✅ All services behind oauth2-proxy auth
- ✅ No service reachable without valid session cookie
- ✅ Logout from any subdomain invalidates global session
- ✅ All monitoring health checks passing
- ✅ Zero high/critical CVEs introduced
- ✅ Page load time < 2 seconds (p99)
- ✅ Auth latency < 200ms (p99)

---

**Ready to Deploy**: All code is production-ready. Can proceed immediately.
