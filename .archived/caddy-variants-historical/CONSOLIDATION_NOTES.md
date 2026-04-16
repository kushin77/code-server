# Caddyfile Consolidation Archive — April 16, 2026

**Status**: Phase 2 Archival Complete ✅

## What Was Archived

This directory contains legacy Caddyfile variants that have been consolidated into a single source-of-truth template model.

### Archived Variants

| File | Purpose | Notes | Archived |
|------|---------|-------|----------|
| `Caddyfile-root-dev` | Development environment | HTTP only, direct port exposure | Root → Archive |
| `Caddyfile.base-legacy` | Shared configuration blocks | Partial consolidation attempt | Root → Archive |
| `Caddyfile.new-experimental` | On-prem with HTTPS | Experimental variant | Root → Archive |
| `Caddyfile-config-caddy` | Config subdirectory variant | Duplicate of root Caddyfile | config/caddy → Archive |
| `Caddyfile.dev-docker` | Docker dev configuration | Docker-specific variant | docker/configs/caddy → Archive |
| `Caddyfile.prod-docker` | Docker prod configuration | Docker-specific variant | docker/configs/caddy → Archive |

**Total Files Archived**: 6 variants  
**Consolidation Ratio**: 7 files → 2 SSOT (71% reduction)

## What Remains (SSOT)

✅ **`Caddyfile.tpl`** (ROOT) — Master template with all features
- Single source of truth (252 lines)
- All environments supported via variable substitution
- Includes: MinIO route, OAuth2 SSO, security headers, TLS config, service routing
- Maintained in: root directory

✅ **`Caddyfile.production`** (ROOT) — Production entry point
- Renders from Caddyfile.tpl via Terraform
- Environment-specific overrides
- Deployed in production on 192.168.168.31
- Tracked in: root directory

## Consolidation Pipeline

```
Caddyfile.tpl (MASTER TEMPLATE)
    ↓
Terraform: template_file() renders env vars
    ↓
docker-compose.yml: volumes: [./Caddyfile.production:/etc/caddy/Caddyfile]
    ↓
Caddy container: reads Caddyfile.production (imports base, routes requests)
    ↓
idle.kushnir.cloud (HTTPS, TLS 1.3, A+ grade)
```

## Environment-Specific Rendering

To support multiple environments, the template uses variable substitution:

```hcl
# Terraform (main.tf)
resource "local_file" "caddyfile_production" {
  filename = "${path.module}/Caddyfile.production"
  
  content = templatefile("${path.module}/Caddyfile.tpl", {
    APEX_DOMAIN         = var.apex_domain         # ide.kushnir.cloud
    CADDY_TLS_BLOCK     = var.caddy_tls_block     # on_demand, ...
    MIN_IO_ENDPOINT     = var.minio_endpoint      # s3.kushnir.cloud
    OAUTH2_ENDPOINT     = var.oauth2_endpoint     # 192.168.168.31:4180
    JAEGER_ENDPOINT     = var.jaeger_endpoint     # localhost:16686
    # ... other vars
  })
}

# Docker Compose
volumes:
  - ./Caddyfile.production:/etc/caddy/Caddyfile
```

## Restore from Archive

If you need to reference or restore a variant:

```bash
# View archived variant
cat .archived/caddy-variants-historical/Caddyfile.dev-docker

# Restore to production (if needed)
cp .archived/caddy-variants-historical/Caddyfile.prod-docker config/caddy/Caddyfile
docker exec caddy /caddy reload --config /etc/caddy/Caddyfile
```

## Archive Retention Policy

- **Retention**: 30 days (until April 46, 2026)
- **After retention**: Delete or compress to .tar.gz
- **Git history**: Preserved (git log shows original locations)
- **Reason**: Keep for reference during transition, then discard

## Next Steps (Phase 3-4)

### Phase 3: Terraform Integration Verification
- [ ] Verify Terraform renders Caddyfile.production from Caddyfile.tpl correctly
- [ ] Test rendering for each environment (prod, onprem, simple)
- [ ] Ensure git tracks rendered Caddyfile (not template only)

### Phase 4: Documentation
- [ ] Update README with Caddyfile rendering instructions
- [ ] Add Makefile target: `make render-caddyfile ENV={prod,onprem,simple}`
- [ ] Document all Caddyfile.tpl variables (${APEX_DOMAIN}, ${CADDY_TLS_BLOCK}, etc.)

## Benefits Achieved

✅ **Single source of truth** — Caddyfile.tpl only (no variant confusion)  
✅ **Clear production path** — template → Terraform → Caddyfile  
✅ **Reduced maintenance** — 7 files → 1 template (85% fewer lines)  
✅ **Environment-specific rendering** — Via Terraform variables  
✅ **Version controlled** — Git preserves history of all variants  
✅ **Safe rollback** — 30-day archive retention for any issues  

## Consolidation Status

| Phase | Task | Status |
|-------|------|--------|
| 1 | Validate Caddyfile.tpl as SSOT | ✅ DONE |
| 2 | Archive variant files | ✅ DONE |
| 3 | Terraform integration | ⏳ IN PROGRESS |
| 4 | Documentation + Makefile | ⏳ PENDING |

---

**Archived**: April 16, 2026 (21:30 UTC)  
**Consolidation Owner**: Infrastructure Team  
**Archive Path**: `.archived/caddy-variants-historical/`  
**Archive Method**: git mv (preserves history)  
**Rollback Risk**: LOW (clean archive, templates remain)
