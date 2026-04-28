# Docker Compose Consolidation Strategy

**Status**: Phase 2 (In Progress)  
**Current State**: 14 docker-compose variants  
**Target State**: 3 files (main + overlays)  
**Risk Level**: MEDIUM (requires validation)

---

## Current Inventory

### Primary File
- **docker-compose.yml** (40K) - Main reference with 54 services (KEEP)

### Production/Environment Variants  
- docker-compose-production.yml (14K, 32 services) - Can become overlay
- docker-compose-cluster.yml (29K, 43 services) - Needs analysis
- docker-compose-fixed.yml (30K, ?) - Needs analysis
- docker-compose-clean.yml (30K, 43 services) - Candidate for archive

### Addon/Feature Overlays
- docker-compose.ai.yml (3.4K) - AI services addon
- docker-compose.enterprise.yml (8.5K) - Enterprise features
- docker-compose.enterprise-replica.yml (4.5K) - Replica config
- docker-compose.edge-agent.yml (5.8K) - Edge agent addon
- docker-compose.observability.yml (2.3K) - Observability addon
- docker-compose.redpanda.yml (1.4K) - Message broker addon

### Override File
- docker-compose.override.yml (597B) - Local dev overrides (KEEP)

### Backup/Historical
- docker-compose.yml.backup - Candidate for archive
- docker-compose-full-deployment.yml (36K) - Historical, candidate for archive
- docker-compose-noinit.yml (30K) - Candidate for archive

---

## Consolidation Plan

### Phase 2A: Analysis & Validation (2 days)

**Step 1: Analyze Each Variant**
```bash
# For each docker-compose-*.yml file:
for f in docker-compose-*.yml; do
  echo "=== $f ==="
  echo "Services: $(grep '^  [a-z].*:' "$f" | wc -l)"
  echo "Unique aspects: $(diff "$f" docker-compose.yml | head -10)"
done
```

**Step 2: Categorize**
- **Must Keep**: Main + overlays
- **Can Archive**: Redundant variants
- **Needs Testing**: Uncertain variants

**Step 3: Test Each Variant**
```bash
# For critical variants, test deployment
docker-compose -f docker-compose-production.yml config > /dev/null
docker-compose -f docker-compose-cluster.yml config > /dev/null
```

### Phase 2B: Consolidation (3 days)

**Recommended Target Structure**:
```
docker-compose.yml              (PRIMARY - all services, all profiles)
docker-compose.override.yml     (KEEP - local dev overrides)
docker-compose.prod.yml         (NEW - production env vars)
docker-compose.yml.backup       (ARCHIVE)
docker-compose-*.yml            (ARCHIVE 11 others)
```

**Consolidation Steps**:
1. Verify docker-compose.yml includes all services from variants
2. Extract environment-specific values from production.yml → .env
3. Test both configs run identically with proper env vars
4. Move variants to docs/archive/docker-compose-variants/
5. Update deployment docs

### Phase 2C: Production Validation (2-3 days)

**Validation Checklist**:
- [ ] All services start with `docker-compose up -d`
- [ ] All services reach health status
- [ ] No service conflicts or name collisions
- [ ] All profiles activate correctly (ai, governance, infrastructure, all)
- [ ] Environment variables properly substituted
- [ ] Persistent volumes mount correctly
- [ ] Network isolation works
- [ ] Deployment is idempotent (run twice, no errors)

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Unknown variant dependencies | Test each variant before archiving |
| Deployment script assumptions | Search for all references to variants in scripts |
| Git history loss | Use `git mv` to archive, preserving history |
| Production breakage | Comprehensive testing in staging first |
| Missing service configs | Compare all services across variants before consolidation |

---

## Analysis Findings

### Service Count Variance
```
docker-compose.yml (PRIMARY):           54 services
docker-compose-clean.yml:               43 services (-11)
docker-compose-cluster.yml:             43 services (-11)
docker-compose-fixed.yml:               ?? services
docker-compose-production.yml:          32 services (-22)
```

**Observation**: The "clean" and "cluster" variants are missing 11 services from the main. Need to identify which ones and verify they're intentional.

### Configuration Patterns

All variants use same pattern:
```yaml
services:
  service-name:
    image: ...
    container_name: code-server-*
    environment:
      - VAR_NAME=${VAR_NAME}
```

**Observation**: Good - configuration is uniform, just service selection differs.

---

## Immediate Action Items

### Week 1 (Analysis)
- [ ] Enumerate services in each variant
- [ ] Document which services are excluded from variants and why
- [ ] Grep codebase for references to each variant file
- [ ] Test production.yml deployment in staging

### Week 2 (Consolidation)  
- [ ] Archive variants that are redundant
- [ ] Create docker-compose.prod.yml from production.yml
- [ ] Validate consolidated setup works
- [ ] Update deployment documentation

### Week 3 (Validation)
- [ ] Full staging deployment with consolidated config
- [ ] Verify all services healthy
- [ ] Smoke tests pass
- [ ] Performance metrics unchanged

---

## Command Reference

```bash
# Analyze variant
docker-compose -f docker-compose-production.yml config | yq '.services | keys[]' | wc -l

# Test consolidation
docker-compose -f docker-compose.yml config > /dev/null && echo "Valid"

# Compare services
comm -23 <(grep '^  [a-z].*:' docker-compose.yml | sort) \
         <(grep '^  [a-z].*:' docker-compose-production.yml | sort)

# Find references in code
grep -r "docker-compose-production\|docker-compose-clean" scripts/ \
  apps/ .github/ --include="*.sh" --include="*.yml" --include="*.md"
```

---

## Decision Points

### Q: Should we keep docker-compose-production.yml?
**A**: Keep as reference but consolidate into docker-compose.prod.yml overlay or environment variables

### Q: Should we restore from docker-compose-*.backup?
**A**: No - use git history if restore needed

### Q: What about docker-compose.{ai,enterprise,edge-agent,observability,redpanda}.yml?
**A**: These are useful as modular overlays. Keep but ensure they compose cleanly with main

### Q: Should overlays be composed via `-f` or included in main?
**A**: Via `-f` for modularity (current approach is good)

---

## Related Documents

- Deployment procedures: DEPLOYMENT_MANIFEST.md
- Service definitions: docker-compose.yml
- Environment config: scripts/_common/config.env
- Terraform deployment: terraform/environments/private/deployment.tf

---

**Status**: READY FOR IMPLEMENTATION  
**Owner**: Infrastructure Audit Phase 2  
**Next Review**: After consolidation complete
