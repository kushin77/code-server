# Docker Compose Files - Archive

**Last Updated**: April 14, 2026  
**Status**: Consolidated and Archived (Phase 1, Task 1.2)

## Consolidation Summary

All docker-compose variants have been consolidated into a single authoritative `docker-compose.yml` at repository root with environment-specific overrides.

### Archived Files

| File | Purpose | Status | Notes |
|------|---------|--------|-------|
| docker-compose.base.yml | YAML anchors & reusable patterns | Archived | Integrated into main `docker-compose.yml` |
| docker-compose.production.yml | Production services (Postgres, Redis, Prometheus) | Archived | Create `docker-compose.prod.override.yml` as needed |
| docker-compose-phase-15.yml | Phase 15 microservices iteration | Archived | Phase-based deployment complete |
| docker-compose-phase-15-deploy.yml | Phase 15 deployment variant | Archived | Phase complete, archived for reference |
| docker-compose-phase-16.yml | Phase 16 security hardening | Archived | Phase complete |
| docker-compose-phase-16-deploy.yml | Phase 16 deployment variant | Archived | Phase complete |
| docker-compose-phase-18.yml | Phase 18 disaster recovery | Archived | Phase complete |
| docker-compose-phase-20-a1.yml | Phase 20 final verification | Archived | Phase complete |
| docker-compose-p0-monitoring.yml | P0 monitoring stack | Archived | Now integrated into main monitoring setup |
| docker/docker-compose.yml | Subdirectory copy (duplicate) | Deleted | Removed - use root docker-compose.yml |
| scripts/docker-compose.yml | Subdirectory copy (duplicate) | Deleted | Removed - use root docker-compose.yml |

## Current Structure

### Authoritative Configuration
- **`docker-compose.yml`** (root) — Main configuration, always used
  - Core services: code-server, ollama, oauth2-proxy, caddy
  - Uses environment variables for flexibility
  - Supports overrides via additional `-f` files

### Environment Overrides (Create as needed)
- **`docker-compose.override.yml`** — Local development overrides (auto-loaded by docker-compose)
- **`docker-compose.prod.override.yml`** — Production overrides (explicit: `docker-compose -f docker-compose.yml -f docker-compose.prod.override.yml up`)

### Example Usage

```bash
# Development (auto-loads docker-compose.override.yml if exists)
docker-compose up -d

# Production with monitoring
docker-compose -f docker-compose.yml -f docker-compose.prod.override.yml up -d

# Validate config
docker-compose config > /dev/null && echo "Valid"
```

## Migration Notes

### What Changed
- ✅ Consolidated 13 variants into 1 authoritative file
- ✅ Removed duplicate copies in subdirectories
- ✅ Archived all phase-based variants
- ✅ Environment-based configuration (use `.env` file)
- ❌ No functional changes to running services

### Services Affected
- **code-server**: No change (4.115.0)
- **ollama**: No change (0.1.27)
- **oauth2-proxy**: No change (v7.5.1)
- **caddy**: No change (2-alpine)

### Breaking Changes
**None** — All services continue to function identically.

### Migration Checklist
- [x] Keep main `docker-compose.yml` unchanged
- [x] Archive all phase-* files
- [x] Remove duplicate copies (docker/, scripts/)
- [x] Environment variables control behavior
- [x] Production services can be enabled via override file

## For Future Development

If you need to add environment-specific configurations:

1. **Create `docker-compose.prod.override.yml`**:
```yaml
version: '3.9'
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    # ... additional production services
```

2. **Run with override**:
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.override.yml up -d
```

## Related Documentation
- Phase completion reports: See `/archived/` for phase-specific details
- Architecture: See `ARCHITECTURE.md`
- Deployment guide: See `DEPLOYMENT-READINESS-VERIFICATION.sh`

---

**Archive Created**: Phase 1, Task 1.2 Consolidation  
**Maintained By**: DevOps Team  
**Next Review**: Week of April 21, 2026
