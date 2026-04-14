# Caddyfile Consolidation Archive

**Last Updated**: April 14, 2026
**Status**: Consolidated (Phase 1, Task 1.3)

## Consolidation Summary

All Caddyfile variants have been consolidated into a single authoritative `Caddyfile` at repository root, with environment-specific overrides available.

### Archived Files

| File | Purpose | Status |
|------|---------|--------|
| Caddyfile.new | Experimental/development version | Archived |
| Caddyfile.production | Production-specific configuration | Integrated |
| Caddyfile.tpl | Terraform template | Archived |
| Caddyfile.base | Shared blocks (imports) | Consolidated |

## Current Structure

### Authoritative Configuration
- **`Caddyfile`** (root) — Main production configuration
  - TLS configuration (Cloudflare Origin CA)
  - Security headers (X-Content-Type-Options, X-Frame-Options)
  - Compression (gzip)
  - HTTP->HTTPS redirect
  - Health check endpoints
  - Reverse proxy to code-server

## Key Features

- ✅ **TLS 1.2+**: Enforced for all HTTPS connections
- ✅ **Security Headers**: Enterprise-grade header set
- ✅ **Compression**: gzip enabled for all responses
- ✅ **Health Checks**: Accessible on /health, /healthz
- ✅ **Cloudflare Origin CA**: Support for Cloudflare Tunnel
- ✅ **Let's Encrypt ACME**: Support via environment configuration
- ✅ **Proxy Headers**: X-Real-IP, X-Forwarded-Proto, CF-Connecting-IP

## Environment Variables

Configure via `.env` or docker-compose environment setup:

```bash
ACME_EMAIL=security@example.com          # Let's Encrypt notifications
CLOUDFLARE_API_TOKEN=your-token          # Cloudflare DNS challenge
```

## Validation

Validate Caddyfile syntax before deployment:

```bash
# Inside Caddy container
docker exec caddy caddy validate --config /etc/caddy/Caddyfile

# Or build locally (requires Caddy installed)
caddy validate --config ./Caddyfile
```

## Usage Examples

### Standard HTTP Redirect (Current)
```
:80 → redirect to HTTPS
:443 → code-server:8080 (with Origin CA certificate)
```

### Local Development Override
To allow HTTP in development, add to docker-compose.override.yml:
```yaml
services:
  caddy:
    volumes:
      - ./Caddyfile.dev:/etc/caddy/Caddyfile:ro
```

## Related Documentation
- Architecture: See `ARCHITECTURE.md`
- Security: See `INCIDENT-RUNBOOKS.md`
- TLS Setup: See `ADR-001-CLOUDFLARE-TUNNEL-ARCHITECTURE.md`

---

**Archive Created**: Phase 1, Task 1.3 Consolidation
**Maintained By**: DevOps Team
**Next Review**: Week of April 21, 2026
