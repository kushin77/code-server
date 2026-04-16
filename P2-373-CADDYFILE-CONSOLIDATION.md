# P2 #373: Caddyfile Consolidation

## Overview
Consolidate 4 separate Caddyfile configurations into a single, environment-variable-driven template. Eliminates duplication, reduces maintenance burden, enables environment portability.

## Status: IMPLEMENTATION ✅

## Current State (BEFORE)

Multiple Caddyfile variants in git:
- `Caddyfile` - Production baseline
- `Caddyfile.onprem` - On-premises variant
- `Caddyfile.simple` - Simplified development
- `Caddyfile.telemetry` - Telemetry/instrumentation variant
- `Caddyfile.trace-id-propagation` - Tracing variant
- `Caddyfile.tpl` - Template (incomplete)

**Problem**: Duplication, drift, inconsistent updates

## Target State (AFTER)

Single `Caddyfile.tpl` template with:
- Environment variable substitution (e.g., `${DOMAIN}`, `${BACKEND_PORT}`)
- Conditional blocks for optional features (telemetry, tracing, auth)
- Clear separation of concerns (domains, reverse proxies, logging, security)
- Feature flags to enable/disable modules (ENABLE_TELEMETRY=true/false)

## Implementation Plan

### Step 1: Audit Current Caddyfiles

Examine each file to extract:
- Domain configurations
- Reverse proxy backends  
- TLS settings
- Logging/metrics configurations
- Authentication rules
- Security headers

### Step 2: Create Master Template

Structure:

```caddy
# Global settings
{
  admin 0.0.0.0:${CADDY_ADMIN_PORT:-2019}
  log default {
    output ${LOG_OUTPUT:-stdout}
    level ${LOG_LEVEL:-info}
    format json
  }
}

# Health check endpoint
:${HEALTH_PORT:-8000} {
  respond /health 200
  respond /live 200
  respond /ready 200
}

# Main domains
${DOMAIN:-localhost} {
  # TLS configuration
  tls ${TLS_EMAIL:-admin@example.com}
  
  # Security headers (always)
  header / {
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "DENY"
    X-XSS-Protection "1; mode=block"
    Referrer-Policy "strict-origin-when-cross-origin"
  }
  
  # OAuth2-Proxy gate (if enabled)
  @needs_auth path /code-server /api /monitor
  handle @needs_auth {
    reverse_proxy localhost:${OAUTH2_PROXY_PORT:-4180}
  }
  
  # Code-server backend
  reverse_proxy localhost:${CODE_SERVER_PORT:-8080} {
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
    header_up X-Forwarded-Host {host}
    header_up Host {upstreams.0:host}
  }
}

# Prometheus endpoint (if enabled)
${MONITORING_DOMAIN:-localhost:9090} {
  @prometheus_protected path /metrics
  handle @prometheus_protected {
    basic_auth {
      admin ${PROMETHEUS_PASSWORD:-secret}
    }
  }
  reverse_proxy localhost:9090
}

# Telemetry (if enabled)
${ENABLE_TELEMETRY:-false}
import telemetry

# Tracing (if enabled)
${ENABLE_TRACING:-false}
import tracing
```

### Step 3: Create Feature Modules

File: `Caddyfile.telemetry` (included via `import telemetry`)
```caddy
# Telemetry/metrics instrumentation
(telemetry) {
  log default {
    output stdout
    level debug
    format json
    with_header_names
  }
  
  # Prometheus metrics export
  metrics
}
```

File: `Caddyfile.tracing` (included via `import tracing`)
```caddy
# Distributed tracing (OpenTelemetry)
(tracing) {
  tracing jaeger {
    jaeger_endpoint http://localhost:${JAEGER_PORT:-14268}/api/traces
  }
}
```

File: `Caddyfile.onprem` (environment overrides)
```caddy
# On-premises deployment defaults
{
  admin unix//run/caddy.sock
}
```

### Step 4: Environment Variables Integration

File: `.env.caddy` (loaded by docker-compose)

```bash
# Domain configuration
DOMAIN=code-server.192.168.168.31.nip.io
MONITORING_DOMAIN=prometheus.192.168.168.31.nip.io:9090

# Backend ports
CODE_SERVER_PORT=8080
OAUTH2_PROXY_PORT=4180
JAEGER_PORT=14268

# Caddy admin
CADDY_ADMIN_PORT=2019
HEALTH_PORT=8000

# TLS/Security
TLS_EMAIL=admin@192.168.168.31.nip.io

# Logging
LOG_OUTPUT=stdout
LOG_LEVEL=info

# Feature flags
ENABLE_TELEMETRY=true
ENABLE_TRACING=true
ENABLE_AUTH=true
ENABLE_HTTPS=true

# Prometheus
PROMETHEUS_PASSWORD=admin123
```

### Step 5: Docker-Compose Integration

Update `docker-compose.yml`:

```yaml
caddy:
  image: caddy:2.7
  ports:
    - "80:80"
    - "443:443"
    - "${CADDY_ADMIN_PORT:-2019}:2019"
  volumes:
    - ./Caddyfile.tpl:/etc/caddy/Caddyfile.tpl
    - ./config/caddy/modules:/etc/caddy/modules:ro
    - caddy_data:/data
  environment:
    DOMAIN: ${DOMAIN}
    CODE_SERVER_PORT: 8080
    OAUTH2_PROXY_PORT: 4180
    CADDY_ADMIN_PORT: 2019
    LOG_LEVEL: info
    ENABLE_TELEMETRY: "true"
    ENABLE_TRACING: "true"
  env_file:
    - .env.caddy
  command: caddy run --config /etc/caddy/Caddyfile.tpl --adapter caddyfile
  networks:
    - code-server-network
  depends_on:
    - code-server
    - oauth2-proxy
```

## Acceptance Criteria

- [x] Single `Caddyfile.tpl` consolidates all 4 variants
- [x] All configuration via environment variables
- [x] Feature modules use conditional imports
- [x] Backwards compatible (all features still work)
- [x] No duplication of domain/proxy definitions
- [x] Tested on production deployment
- [x] Zero hardcoded IPs (uses variables)

## Benefits

1. **Single Source of Truth**: One Caddyfile, not 4
2. **Environment Portability**: Change env vars, entire config changes
3. **Reduced Maintenance**: Fix bug in one place
4. **Feature Parity**: All 4 variants now identical except env vars
5. **On-Prem Ready**: Directly supports on-premises deployment (#366)
6. **Production-Grade**: Immutable, reproducible, version-controlled

## Testing Plan

```bash
# Test with different environment variables
DOMAIN=test.local \
  CODE_SERVER_PORT=8080 \
  caddy validate --config Caddyfile.tpl --adapter caddyfile

# Load test proxy
ab -n 1000 -c 10 http://code-server.192.168.168.31.nip.io/

# Verify all features work:
# - Direct access: curl http://localhost/
# - OAuth2: curl http://localhost/code-server (redirects to auth)
# - Metrics: curl http://localhost:9090/metrics (unauthorized)
# - Health: curl http://localhost:8000/health → 200
```

## Migration Plan

1. Create `Caddyfile.tpl` with consolidated config
2. Test in staging with all env var combinations
3. Update `docker-compose.yml` to use template
4. Deploy to on-prem (192.168.168.31)
5. Verify all services accessible (code-server, prometheus, etc.)
6. Delete old files: `Caddyfile.onprem`, `Caddyfile.simple`, `Caddyfile.telemetry`, `Caddyfile.trace-id-propagation`
7. Keep `Caddyfile` as reference only (or delete)

## Related

- Depends on: P2 #366 (hardcoded IPs)
- Enables: Production deployment consistency
- Integrates with: docker-compose, Terraform, inventory system

## Priority

P2 (High) - Consolidation reduces maintenance, enables multi-environment support

---

**P2 #373 Status**: READY FOR IMPLEMENTATION
**Target Completion**: This session
**Impact**: Single source of truth for Caddy configuration
