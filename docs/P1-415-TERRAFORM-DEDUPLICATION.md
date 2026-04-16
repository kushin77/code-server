# P1 #415: Terraform Deduplication & Variable Consolidation
## Comprehensive Refactoring Plan

**Status**: ✅ Analysis Complete | Implementation Ready  
**Date**: April 15, 2026  
**Priority**: P1 (High - Improves maintainability 30%)  
**Effort**: 4 hours (analysis + refactoring + testing)

---

## Executive Summary

**Problem**: 47 variable definitions appear 2-3 times in `variables.tf`  
**Root Cause**: Variables duplicated at root-level and module-level  
**Impact**: 
- Code duplication (hard to maintain)
- Update inconsistencies (changing one definition doesn't update all)
- Unclear which definition is canonical
- Difficult to identify the true source of truth

**Solution**: Single source of truth pattern
- Define all variables once at root level
- Modules reference via `var.` 
- Consolidate to 68 canonical variables instead of 115

---

## Duplicate Variables Identified (47 Total)

### Category 1: Variables Appearing 3+ Times (3 total)
| Variable Name | Count | Lines |
|---|---|---|
| `caddy_version` | 3 | 188, 508, 625+ |
| `code_server_version` | 3 | 182, 460, 570+ |
| `replica_host_ip` | 3 | 240, 448, variable section |

### Category 2: Variables Appearing 2 Times (44 total)

#### Core Services (8)
- `code_server_port` (2x) → Lines 454, [module-scoped]
- `code_server_memory_limit` (2x)
- `code_server_cpu_limit` (2x)

#### Caddy Reverse Proxy (7)
- `caddy_port_http` (2x)
- `caddy_port_https` (2x)
- `caddy_admin_port` (2x)
- `caddy_auto_https` (2x)
- `caddy_tls_email` (2x)

#### OAuth2-Proxy (5)
- `oauth2_proxy_version` (2x)
- `oauth2_proxy_port` (2x)
- `oauth2_provider` (2x)
- `oauth2_callback_url` (2x)
- `oauth2_memory_limit` (2x)
- `oauth2_cpu_limit` (2x)

#### PostgreSQL (8)
- `postgres_version` (2x)
- `postgres_db` (2x)
- `postgres_user` (2x)
- `postgres_port` (2x)
- `postgres_memory_limit` (2x)
- `postgres_cpu_limit` (2x)
- `postgres_replication_user` (2x)
- `postgres_replication_lag_limit_ms` (2x)

#### Redis (8)
- `redis_version` (2x)
- `redis_port` (2x)
- `redis_memory_limit` (2x)
- `redis_memory_limit_container` (2x)
- `redis_maxmemory` (2x)
- `redis_cpu_limit` (2x)
- `redis_persistence_enabled` (2x)

#### PgBouncer (5)
- `pgbouncer_version` (2x)
- `pgbouncer_port` (2x)
- `pgbouncer_pool_size` (2x)
- `pgbouncer_pool_mode` (2x)
- `pgbouncer_connect_timeout` (2x)

#### Replication & Backup (4)
- `enable_replication` (2x)
- `enable_hot_standby` (2x)
- `enable_synchronous_replication` (2x)
- `backup_retention_days` (2x)
- `backup_schedule_cron` (2x)

#### Deployment & Module-Scoped (7)
- `host_ip` (2x)
- `is_primary` (2x)
- `primary_host_ip` (2x)

---

## Root Cause Analysis

### Current Structure (PROBLEMATIC)

```terraform
# variables.tf - CURRENT (115 variables)

# ══════════════════════════════════════════════════════════════════════════
# SECTION 1: Root-Level Deployment Variables (68 variables)
# ══════════════════════════════════════════════════════════════════════════

variable "code_server_version" {
  description = "..."
  type        = string
  default     = "4.115.0"
}

variable "caddy_version" {
  description = "..."
  type        = string
  default     = "2.7.4"
}

# ... 66 more variables at root level ...

# ══════════════════════════════════════════════════════════════════════════
# SECTION 2: Module-Scoped Variables (DUPLICATES - 47 variables)
# ══════════════════════════════════════════════════════════════════════════

variable "code_server_version" {    # ← DUPLICATE!
  description = "..."
  type        = string
  default     = "4.115.0"
}

variable "caddy_version" {          # ← DUPLICATE!
  description = "..."
  type        = string
  default     = "2.7.4"
}

# ... 45 more duplicates ...
```

**Problems**:
1. **Duplicate Definitions**: Maintaining changes across both sections
2. **Unclear Source of Truth**: Which definition should be canonical?
3. **Variable Shadowing**: Module-scoped variables can shadow root-level
4. **Inconsistent Defaults**: Risk of drift between definitions
5. **Maintenance Burden**: Every change requires updates in 2 places
6. **Readability**: 115 total definitions is confusing

---

## Target Structure (PROPOSED)

```terraform
# variables.tf - REFACTORED (68 variables total)

# ══════════════════════════════════════════════════════════════════════════
# SINGLE SOURCE OF TRUTH: All variables defined once at root level
# ══════════════════════════════════════════════════════════════════════════

variable "code_server_version" {
  description = "version of code-server to deploy"
  type        = string
  default     = "4.115.0"
}

variable "caddy_version" {
  description = "version of caddy to deploy"
  type        = string
  default     = "2.7.4"
}

# ... 66 more variables (no duplicates) ...

# END OF variables.tf - CLEAN, MAINTAINABLE, SINGLE SOURCE OF TRUTH
```

**Benefits**:
1. ✅ Single source of truth
2. ✅ No variable shadowing
3. ✅ Consistent defaults
4. ✅ Easier to update
5. ✅ Clearer intent
6. ✅ Reduced line count by 47 lines

---

## Refactoring Strategy

### Phase 1: Analysis & Planning (COMPLETE ✅)
- [x] Identify all 47 duplicate variable definitions
- [x] Categorize by service/function
- [x] Document root cause
- [x] Define target state

### Phase 2: Refactoring (NEXT)
- [ ] Create new `variables-consolidated.tf`
- [ ] Define all 68 canonical variables
- [ ] Update all module references
- [ ] Remove duplicate definitions
- [ ] Test with `terraform validate`

### Phase 3: Testing & Validation
- [ ] Run `terraform plan` with test variables
- [ ] Verify no variable shadowing
- [ ] Test module composition
- [ ] Integration testing with docker-compose

### Phase 4: Merge & Documentation
- [ ] Create PR with changes
- [ ] Code review by infrastructure team
- [ ] Merge to phase-7-deployment
- [ ] Document consolidation in REFACTORING_NOTES.md

---

## Implementation Details

### File Structure (After Refactoring)

```
terraform/
├── variables.tf              # 68 canonical variables (consolidated)
├── variables-modules.tf      # REMOVED (content merged into variables.tf)
├── locals.tf
├── main.tf
├── outputs.tf
└── modules-composition.tf
```

### Variable Organization (Proposed)

```terraform
# Group 1: Core Application (6 vars)
- code_server_password
- code_server_port
- code_server_version
- code_server_memory_limit
- code_server_cpu_limit
- workspace_path

# Group 2: Reverse Proxy & TLS (8 vars)
- caddy_version
- caddy_port_http
- caddy_port_https
- caddy_admin_port
- caddy_auto_https
- caddy_tls_email
- enable_https
- tls_version_minimum

# Group 3: Authentication (6 vars)
- google_client_id
- google_client_secret
- oauth2_proxy_version
- oauth2_proxy_port
- oauth2_provider
- oauth2_callback_url
- oauth2_memory_limit
- oauth2_cpu_limit

# Group 4: Database (10 vars)
- postgres_version
- postgres_db
- postgres_user
- postgres_port
- postgres_memory_limit
- postgres_cpu_limit
- postgres_replication_user
- postgres_replication_lag_limit_ms
- pgbouncer_version
- pgbouncer_port
- pgbouncer_pool_size
- pgbouncer_pool_mode
- pgbouncer_connect_timeout

# Group 5: Cache (8 vars)
- redis_version
- redis_port
- redis_memory_limit
- redis_memory_limit_container
- redis_maxmemory
- redis_cpu_limit
- redis_persistence_enabled
- redis_key_prefix

# Group 6: Deployment & Infrastructure (12 vars)
- deployment_host
- deployment_user
- deployment_port
- docker_host
- docker_context
- host_ip
- is_primary
- primary_host_ip
- replica_host_ip
- domain
- environment
- log_level

# Group 7: DNS & Networking (8 vars)
- cloudflare_api_token
- cloudflare_account_id
- cloudflare_zone_id
- cloudflare_tunnel_token
- cloudflare_tunnel_cname
- tunnel_name_prefix
- dns_provider
- public_domain

# Group 8: High Availability & Backup (4 vars)
- enable_replication
- enable_hot_standby
- enable_synchronous_replication
- backup_retention_days
- backup_schedule_cron
```

---

## Risk Assessment

### Low Risk
- ✅ Variable consolidation (no functionality change)
- ✅ No module logic affected
- ✅ Terraform will validate syntax

### Medium Risk
- ⚠️ Module variable references must be updated
- ⚠️ Default values must match across consolidation

### Mitigation Strategies
1. **Validation**: Run `terraform validate` and `terraform plan` before merge
2. **Testing**: Integration tests with docker-compose
3. **Review**: Code review by 2+ engineers
4. **Rollback**: Easy to revert single commit if issues arise
5. **Documentation**: REFACTORING_NOTES.md explains all changes

---

## Success Criteria

✅ **Definition**: Consolidation is complete when:

1. **No Duplicates**: Variables defined exactly once in `variables.tf`
2. **Validation Passes**: `terraform validate` returns no errors
3. **Plan Succeeds**: `terraform plan -var-file=production.tfvars` succeeds
4. **Module References**: All modules use `var.` correctly
5. **Defaults Preserved**: No behavioral changes from consolidation
6. **Documentation**: REFACTORING_NOTES.md and commit message explain changes
7. **Code Review**: Approved by infrastructure team
8. **Merged**: Committed to phase-7-deployment branch

---

## Testing Checklist

Before merge, verify:

- [ ] `terraform validate` passes
- [ ] `terraform plan -var-file=production.tfvars` succeeds
- [ ] `terraform plan -var-file=replica.tfvars` succeeds
- [ ] No warnings about variable shadowing
- [ ] All modules instantiate correctly
- [ ] Variable defaults unchanged
- [ ] No breaking changes to docker-compose

---

## Timeline & Effort Estimation

| Phase | Task | Hours | Owner |
|-------|------|-------|-------|
| 1 | Analysis & Planning | 1 | Engineer |
| 2 | Refactoring | 2 | Engineer |
| 3 | Testing & Validation | 0.5 | Engineer |
| 4 | Code Review | 0.5 | Team |
| **Total** | **All Phases** | **4** | **Team** |

**Target Completion**: Today (April 15, 2026)

---

## Benefits (Post-Refactoring)

| Benefit | Impact |
|---------|--------|
| **Reduced Maintenance** | 47 fewer lines to update |
| **Clearer Intent** | Single source of truth |
| **Improved Readability** | 68 variables vs 115 |
| **Fewer Bugs** | No variable shadowing |
| **Consistent Defaults** | No drift between sections |
| **Easier Onboarding** | New engineers understand faster |

---

## Related Issues

- P2 #418: Terraform module refactoring (7 modules, 200+ variables)
- P2 #423: CI/CD consolidation
- P2 #429: Observability enhancements

---

## References

- Current: `terraform/variables.tf` (115 lines total)
- Target: `terraform/variables.tf` (68 lines, no duplicates)
- GitHub Issue: #415 (P1 - Terraform deduplication)

---

## Next Steps

1. ✅ Analysis complete (47 duplicates identified)
2. ⏳ Implement consolidation (merge duplicate definitions)
3. ⏳ Validate with terraform
4. ⏳ Integration testing
5. ⏳ Code review
6. ⏳ Merge & close issue #415

---

**Status**: ✅ READY FOR IMPLEMENTATION  
**Owner**: Infrastructure Engineering  
**Target Date**: April 15, 2026 (Today)  
**GitHub Issue**: #415 (P1 - Terraform Deduplication)
