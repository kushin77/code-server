# Docker-Compose Consolidation Strategy - Phase 1

**Status**: Strategic planning  
**Current State**: 8 docker-compose files managing different concerns  
**Target**: Single parameterized docker-compose.yml with environment control  
**Effort**: 6-8 hours

## Current File Inventory

| File | Size | Services | Purpose | Status |
|------|------|----------|---------|--------|
| `docker-compose.yml` | 35.8 KB | 18 | **MAIN** - Production all-in-one | ✅ Active (14/18 healthy) |
| `docker-compose.ha.yml` | 22 KB | 12 | High-availability variant | ⏳ Partial |
| `docker-compose.hardened.yml` | 28 KB | 15 | Security-hardened variant | ⏳ Partial |
| `docker-compose.git-proxy.yml` | 2 KB | 2 | Git proxy sidecar | ⏳ Supplementary |
| `docker-compose.telemetry.yml` | 5 KB | 3 | Observability extensions | ⏳ Supplementary |
| `docker-compose.jaeger.yml` | 8 KB | 2 | Jaeger tracing detailed | ⏳ Supplementary |
| `docker-compose-phase-6.yml` | 18 KB | 10 | Legacy phase 6 | ❌ Deprecated |
| `docker-compose.cloudflared.yml` | 3 KB | 1 | Cloudflare tunnel | ⏳ Optional |

**Total Size**: ~121 KB (before consolidation)  
**Duplication**: ~60% (same services defined 2-4x)  

---

## Duplication Analysis

### Duplicated Services

| Service | Files | Variations |
|---------|-------|-----------|
| redis | 4 | .yml, .ha, .hardened, .telemetry |
| postgres | 4 | .yml, .ha, .hardened, .jaeger |
| prometheus | 4 | .yml, .ha, .hardened, .jaeger |
| grafana | 3 | .yml, .ha, .hardened |
| jaeger | 4 | .yml, .ha, .hardened, .jaeger (separate) |
| alertmanager | 3 | .yml, .ha, .hardened |
| code-server | 3 | .yml, .ha, .hardened |
| loki | 3 | .yml, .ha, .hardened |
| **Total Duplication**: 15 duplicated service entries |

### Configuration Variance

Each variant adds:
- `docker-compose.yml` - Baseline
- `docker-compose.ha.yml` - HA tweaks (replica_factor, replication_lag)
- `docker-compose.hardened.yml` - Security options (cap_drop, security_opt, read_only_root_fs)
- `.telemetry.yml`, `.jaeger.yml` - Minor extensions

**Issue**: This variation isn't in source control; it's achieved by file copying/merging, not environment-driven.

---

## Consolidation Approach

### Phase 1: Parametrize Existing Main File

Add environment variables to docker-compose.yml to control all variants:

```yaml
# Main docker-compose.yml with environment control

version: '3.9'

services:
  postgres:
    image: postgres:${POSTGRES_VERSION:-15.6}
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    security_opt:
      ${POSTGRES_SECURITY_OPT:-[]' }  # Empty by default
    read_only_root_fs: ${POSTGRES_READ_ONLY_ROOT:-false}
    # HA replica config (if POSTGRES_REPLICATION_ENABLED)
    {{if env "POSTGRES_REPLICATION_ENABLED"}}
    environment:
      POSTGRES_INITDB_ARGS: "-c wal_level=replica"
    {{end}}

  redis:
    image: redis:${REDIS_VERSION:-7.2-bookworm}
    # HA clustering (if REDIS_CLUSTER_ENABLED)
    {{if env "REDIS_CLUSTER_ENABLED"}}
    command: redis-server --cluster-enabled yes
    {{end}}

  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION:-v2.49.1}
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    {{if env "PROMETHEUS_HA_ENABLED"}}
      - ./config/prometheus-ha-replication.yml:...
    {{end}}
```

### Environment Variable Control

Create .env file with feature toggles:

```bash
# Basic deployment
DEPLOYMENT_MODE=production  # {development, staging, production}

# HA Features
POSTGRES_REPLICATION_ENABLED=false
REDIS_CLUSTER_ENABLED=false
PROMETHEUS_HA_ENABLED=false

# Security (hardening profile)
HARDENING_ENABLED=false
POSTGRES_SECURITY_OPT="--cap-drop ALL --security-opt no-new-privileges:true"
POSTGRES_READ_ONLY_ROOT=false

# Observability Extensions
TELEMETRY_ENABLED=true
JAEGER_DETAIL=standard  # {off, standard, detailed}

# Optional Services
CLOUDFLARE_ENABLED=false
GIT_PROXY_ENABLED=false
```

### Phase 2: Migrate Variant Content

1. **docker-compose.ha.yml** → Merge high-availability configs into main + HA env vars
2. **docker-compose.hardened.yml** → Merge security hardening into main + HARDENING_ENABLED=true
3. **docker-compose.telemetry.yml** → Extend main with conditional telemetry section
4. **docker-compose.jaeger.yml** → Jaeger details merge, JAEGER_DETAIL env control
5. **docker-compose.cloudflared.yml** → Move to profiles: ["cloudflare"] in main
6. **docker-compose.git-proxy.yml** → Move to profiles: ["git-proxy"] in main
7. **docker-compose-phase-6.yml** → Archive (no longer needed, main is comprehensive)

### Phase 3: Test & Deploy

```bash
# Development mode (all features)
DEPLOYMENT_MODE=development \
HARDENING_ENABLED=true \
PROMETHEUS_HA_ENABLED=true \
docker-compose up -d

# Production mode (hardened, no HA for on-prem)
DEPLOYMENT_MODE=production \
HARDENING_ENABLED=true \
PROMETHEUS_HA_ENABLED=false \
docker-compose up -d

# High-availability mode (replicated)
DEPLOYMENT_MODE=production \
HARDENING_ENABLED=true \
POSTGRES_REPLICATION_ENABLED=true \
REDIS_CLUSTER_ENABLED=true \
docker-compose up -d
```

---

## Implementation Plan

### Effort Breakdown

| Phase | Task | Duration | Complexity |
|-------|------|----------|-----------|
| 1 | Create parameterized docker-compose template | 1.5 hr | Low |
| 1 | Extract variant-specific configs to env vars | 2 hr | Medium |
| 1 | Test baseline mode (current functionality) | 1 hr | Low |
| 2 | Merge HA configs + test HA mode | 1.5 hr | Medium |
| 2 | Merge hardening configs + test hardening | 1 hr | Medium |
| 2 | Migrate optional service profiles | 1 hr | Low |
| 3 | Validation across all modes | 1 hr | Low |
| 3 | Archive old files + git cleanup | 0.5 hr | Low |
| **TOTAL** | | **8.5 hr** | |

### Success Criteria

- ✅ Single docker-compose.yml supports all current modes
- ✅ No feature loss (all services available in appropriate modes)
- ✅ All 14 healthy services continue working
- ✅ HA mode can be enabled with env vars
- ✅ Hardening can be toggled on/off
- ✅ Old files archived but referenced for historical context
- ✅ Documentation updated with deployment modes
- ✅ CI/CD tests all 3 modes (basic, hardened, HA)

### Risks & Mitigation

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Break existing deployment | High | Keep main .yml as backup, test each mode separately |
| Version conflicts in variants | Medium | Pin all image versions in .env, test combinations |
| Missing env vars in CI/CD | Medium | Create template .env.template, validate in CI |
| Users confused by modes | Low | Clear documentation + convenience scripts |

---

## Post-Consolidation File Structure

```
code-server-enterprise/
├── docker-compose.yml          # ← Single consolidated file (all modes)
├── .env.example                # Template with all control variables
├── .env                         # Actual deployment config
├── .env.production              # Production mode preset
├── .env.staging                 # Staging mode preset
├── .env.development             # Development mode preset
├── docker-compose.examples/     # Documentation examples
│   ├── DEPLOYMENT_MODES.md
│   ├── HA-SETUP.md
│   └── SECURITY-HARDENING.md
├── _archive/
│   ├── docker-compose.ha.yml
│   ├── docker-compose.hardened.yml
│   ├── docker-compose.telemetry.yml
│   └── ... (other variants)
└── scripts/
    ├── deploy-mode.sh          # Helper to switch modes
    └── validate-compose.sh     # Validate all modes
```

---

## Benefits of Consolidation

| Benefit | Impact | Effort Saved |
|---------|--------|--------------|
| Single source of truth | Reduces variant drift bugs | 5 hrs/quarter |
| Faster onboarding | Developers understand 1 file vs 8 | 2 hrs/new dev |
| CI validation | Catch config errors before deploy | 1 hr/deploy |
| Version sync | Easier to update all variants at once | 2 hrs/release |
| Documentation | One deployment guide vs 8 variant guides | 4 hrs initial |

**Total 1st year savings**: ~100 hours

---

## Timeline

**Week 1 (This Week)**: Phase 1 parameterization  
**Week 2**: Phase 2 variant migration  
**Week 3**: Phase 3 testing & deployment  
**Week 4**: Documentation & training  

---

## Decision Gate

**Recommended**: Proceed with consolidation after infrastructure stabilization (now ✅)

**Blockers**: 
- [ ] oauth2-proxy running (needed for testing HA/hardened variants)
- [ ] All 18 services healthy (currently 14/18)

**Go/No-go**: Execute consolidation after Phase 1 critical fixes complete

---

## Related Documentation

- [docker-compose.yml specification](../docker-compose.yml)
- [Configuration management](../DEVELOPMENT-GUIDE.md#configuration)
- [Deployment modes](../DEPLOYMENT-GUIDE.md)
- [Environment variables](../.env.example)

---

**Next Step**: Create .env.template with all control variables and parameterize docker-compose.yml for Phase 1 execution
