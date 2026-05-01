# Docker Compose Profile Consolidation Strategy

## Overview

This document outlines the strategy for consolidating multiple docker-compose files into a single canonical file using Docker Compose profiles. This resolves issue #3121.

### Current State (Before)

Multiple overlay files create drift risk:

```
docker-compose.yml (base - 1699 lines)
├── docker-compose.enterprise.yml (overlays code-server-ide)
├── docker-compose.prod.yml (adds OPA, policy engine)
├── docker-compose.override.yml (local dev overrides)
├── docker-compose.vault.yml (Vault integration)
└── docker-compose.minio.yml (MinIO S3 compatibility)

Orchestration Required:
  docker compose -f docker-compose.yml \
    -f docker-compose.enterprise.yml \
    -f docker-compose.prod.yml \
    up -d
    
Problems:
  ❌ File ordering matters for override behavior
  ❌ Easy to forget required files
  ❌ New developers confused about which files to use
  ❌ CI/CD must know about all file combinations
  ❌ Hard to maintain consistency
```

### Target State (After)

Single canonical file with conditional profiles:

```
docker-compose.yml (unified - ~2200 lines with profiles)

Services with profiles:
  - base: All core services (always included)
  - enterprise: Code Server IDE and related tools
  - prod: Production policy engine (OPA)
  - vault: HashiCorp Vault integration
  - minio: MinIO S3-compatible storage
  - override: Local development overrides

Orchestration Simplified:
  # Default (base only)
  docker compose up -d
  
  # Enterprise + Production
  docker compose --profile enterprise --profile prod up -d
  
  # All profiles
  docker compose --profile "*" up -d

Benefits:
  ✅ Single authoritative source
  ✅ `docker compose up -d` is the default command
  ✅ Explicit profiles prevent confusion
  ✅ Easier maintenance and versioning
  ✅ Better IDE support and validation
```

## Docker Compose Profiles Explained

### What are Profiles?

Profiles are a Docker Compose v1.28+ feature that allows conditional service activation:

```yaml
version: '3.9'

services:
  # Always included (no profile specified)
  postgres:
    image: postgres:15
    
  # Only included when --profile enterprise is used
  code-server-ide:
    image: codercom/code-server:4.19.0
    profiles:
      - enterprise
      
  # Included in multiple profiles
  opa:
    image: openpolicyagent/opa:0.58.0
    profiles:
      - prod
      - enterprise
```

### Profile Usage Examples

```bash
# Start only base services (no profiles)
docker compose up -d

# Start base + enterprise services
docker compose --profile enterprise up -d

# Start base + enterprise + prod services
docker compose --profile enterprise --profile prod up -d

# Start ALL services (all profiles)
docker compose --profile "*" up -d

# List services in active profiles
docker compose --profile enterprise config --services

# Stop specific profile
docker compose --profile enterprise down
```

## Implementation Plan

### Phase 1: Analysis (CURRENT)

1. **Map services to profiles**:
   - Identify which services go in each profile
   - Document dependencies between services
   - Identify shared volumes and networks

2. **Profile organization**:
   ```
   base       → Core services always needed
   enterprise → Code Server IDE and related tools
   prod       → Production-specific (OPA, Vault, etc.)
   vault      → Optional HashiCorp Vault integration
   minio      → Optional S3-compatible storage
   override   → Local development overrides
   ```

### Phase 2: Implementation (IN PROGRESS)

1. **Merge overlays into base docker-compose.yml**
   - Copy services from enterprise, prod, vault, minio files
   - Add `profiles: [enterprise]`, `profiles: [prod]`, etc.
   - Resolve naming conflicts (add prefixes if needed)

2. **Add profile documentation**
   - Each service has comments explaining which profile it's in
   - Document dependencies between profiles
   - Explain when each profile should be used

3. **Update references**:
   - Update deployment scripts to use new profile syntax
   - Update CI/CD workflows
   - Update documentation

### Phase 3: Validation & Migration

1. **Test all profile combinations**:
   ```bash
   docker compose config --quiet                    # base only
   docker compose --profile enterprise config --quiet
   docker compose --profile prod config --quiet
   docker compose --profile "*" config --quiet      # all
   ```

2. **Verify service dependencies**
   ```bash
   docker compose --profile enterprise up --no-start
   docker compose --profile enterprise logs postgres # verify dependencies
   ```

3. **Update documentation**
   - Update README with new usage patterns
   - Update deployment guides
   - Update CI/CD documentation

## Service to Profile Mapping

### Base (No Profile) - Always Started

```
Core Infrastructure:
  ✓ code-server-postgres (database)
  ✓ code-server-redis (caching)
  ✓ code-server-redpanda (message broker)
  ✓ code-server-qdrant (vector DB)
  ✓ code-server-ollama (LLM inference)

Observability:
  ✓ code-server-prometheus (metrics)
  ✓ code-server-grafana (dashboards)
  ✓ code-server-loki (logs)
  ✓ code-server-alertmanager (alerts)
  ✓ code-server-tempo (tracing)
  ✓ code-server-otel-collector (OTEL)

Application Services:
  ✓ code-server-execution-scheduler
  ✓ code-server-memory-engine
  ✓ code-server-reputation-engine
  ✓ code-server-paperclip
  ✓ code-server-control-plane
```

### Enterprise Profile - `--profile enterprise`

```
Developer Tools:
  → code-server-ide (Coder code-server IDE)
  → code-server-appsmith (AppSmith low-code IDE)
  → code-server-mongodb (Appsmith backend)
  
Autonomous Agents:
  → code-server-agent-runtime
  → code-server-code-reviewer
  → code-server-incident-responder
  
Cache:
  → redis-appsmith (Appsmith cache)
```

### Production Profile - `--profile prod`

```
Policy Engine:
  → code-server-opa (Open Policy Agent)

Authentication:
  → code-server-oauth2-proxy (OAuth2 gateway)
  
Integration:
  → code-server-caddy (API gateway)
```

### Vault Profile - `--profile vault`

```
Secrets Management:
  → vault (HashiCorp Vault server)
```

### MinIO Profile - `--profile minio`

```
Object Storage:
  → minio (S3-compatible storage)
  → minio-init (bucket initialization)
```

### Override Profile - `--profile override`

```
Development Overrides:
  (Used only for local development)
  → service resource limit overrides
  → local port mappings
```

## Example Consolidated docker-compose.yml Structure

```yaml
version: '3.9'

# Unified services with profiles
services:
  # ========================================================================
  # BASE SERVICES (No Profile - Always Started)
  # ========================================================================
  
  code-server-postgres:
    image: postgres:15
    container_name: code-server-postgres
    # ... rest of config
    
  code-server-redis:
    image: redis:7-alpine
    container_name: code-server-redis
    # ... rest of config
    
  # ========================================================================
  # ENTERPRISE SERVICES (Profile: enterprise)
  # ========================================================================
  
  code-server-ide:
    image: codercom/code-server:4.19.0
    container_name: code-server-ide
    profiles:
      - enterprise
    ports:
      - 8090:8080
    environment:
      - PASSWORD=${CODE_SERVER_PASSWORD}
    # ... rest of config
    
  code-server-appsmith:
    image: appsmith/appsmith:latest
    container_name: code-server-appsmith
    profiles:
      - enterprise
    # ... rest of config
    
  # ========================================================================
  # PRODUCTION SERVICES (Profile: prod)
  # ========================================================================
  
  code-server-opa:
    image: openpolicyagent/opa:0.58.0
    container_name: code-server-opa
    profiles:
      - prod
    ports:
      - 8181:8181
    # ... rest of config
    
  # ========================================================================
  # VAULT SERVICES (Profile: vault)
  # ========================================================================
  
  vault:
    image: vault:latest
    container_name: code-server-vault
    profiles:
      - vault
    # ... rest of config
    
  # ========================================================================
  # MINIO SERVICES (Profile: minio)
  # ========================================================================
  
  minio:
    image: minio/minio:latest
    container_name: code-server-minio
    profiles:
      - minio
    # ... rest of config

networks:
  services:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
  # ... rest of volumes
```

## Migration Path for Existing Deployments

### For Running Instances

1. **Backup current docker-compose setup**
   ```bash
   docker compose config > docker-compose.backup.yml
   docker compose down
   ```

2. **Update to profiles-based compose file**
   ```bash
   git pull  # Get new docker-compose.yml with profiles
   ```

3. **Start with appropriate profiles**
   ```bash
   # If was running: docker compose -f docker-compose.yml -f docker-compose.enterprise.yml ...
   # Now run:
   docker compose --profile enterprise up -d
   ```

4. **Verify all services started**
   ```bash
   docker compose --profile enterprise ps
   docker compose --profile enterprise logs --tail=100
   ```

### For CI/CD Pipelines

**Before**:
```yaml
- name: Start services
  run: |
    docker compose -f docker-compose.yml \
      -f docker-compose.enterprise.yml \
      -f docker-compose.prod.yml \
      up -d
```

**After**:
```yaml
- name: Start services
  run: |
    docker compose \
      --profile enterprise \
      --profile prod \
      up -d
```

### For Documentation

Update all references:
- Change `docker compose -f docker-compose.yml -f docker-compose.prod.yml` to `docker compose --profile prod`
- Document which profiles to use for different scenarios
- Add profile reference to README

## Benefits of Profile-Based Approach

| Aspect | Before (Overlays) | After (Profiles) |
|--------|-------------------|------------------|
| **Simplicity** | Complex file ordering | Single authoritative file |
| **Default Behavior** | Multiple commands needed | `docker compose up -d` works |
| **Discoverability** | Hard to find all files | All services in one file |
| **Validation** | Must remember all files | IDE validates automatically |
| **Versioning** | Overlays must match base | Single version number |
| **Documentation** | Scattered across files | Unified with comments |
| **CI/CD** | Hardcoded file lists | Profile flags in config |
| **New Users** | Confusing for developers | Clear and intuitive |

## Risk Mitigation

### Backward Compatibility

Keep old overlay files for one release cycle:
- `.github/workflows/compat.yml` tests both old and new approaches
- Documentation explains transition
- Old files marked as "deprecated - use profiles instead"

### Validation Checklist

Before merging to main:
- [ ] All services present in new file
- [ ] `docker compose config` validates without errors
- [ ] Each profile combination tested:
  - [ ] `docker compose up -d` (base)
  - [ ] `--profile enterprise` (+ enterprise)
  - [ ] `--profile prod` (+ prod)
  - [ ] `--profile "*"` (all)
- [ ] Volumes and networks correct in all profiles
- [ ] Service dependencies preserved
- [ ] Health checks intact
- [ ] Image digests preserved (@sha256:)
- [ ] No :latest tags
- [ ] Environment variables consistent
- [ ] All ports correctly mapped
- [ ] Logging configuration preserved

## Related Issues

- **Issue #3121**: Merge docker-compose overlays into profiles (THIS ISSUE)
- **Issue #3118**: GitHub Actions CI for compose validation
- **Issue #3117**: Environment consolidation (COMPLETED)

## Implementation Timeline

| Phase | Dates | Tasks |
|-------|-------|-------|
| **Analysis** | Apr 30 - May 1 | Map services, document profiles, identify dependencies |
| **Implementation** | May 1 - May 3 | Merge files, add profiles, update references |
| **Validation** | May 3 - May 5 | Test combinations, verify dependencies, validate YAML |
| **Documentation** | May 5 - May 6 | Update README, CI/CD, deployment guides |
| **Migration** | May 6 - May 8 | Roll out to staging, then production |
| **Cleanup** | May 8 | Remove deprecated overlay files |

## Next Steps

1. Create consolidated `docker-compose.yml` with profiles
2. Add services from all overlay files with appropriate profile tags
3. Test all profile combinations
4. Update deployment scripts and CI/CD
5. Update documentation with new usage patterns
6. Deploy to staging for verification
7. Roll out to production

---

*Document: Docker Compose Profile Consolidation Strategy*
*Issue: #3121*
*Status: PLANNING/ANALYSIS*
*Last Updated: April 30, 2026*
