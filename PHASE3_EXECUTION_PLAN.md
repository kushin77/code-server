# Phase 3: Infrastructure as Code Hardening - Execution Plan

**Phase**: 3 (IaC Hardening)  
**Start Date**: April 28, 2026  
**Estimated Duration**: 3-4 weeks  
**Status**: PLANNING  
**Owner**: Infrastructure Team

---

## Overview

Phase 3 focuses on hardening infrastructure through Infrastructure as Code, removing procedural logic from Terraform provisioners, and establishing clear resource classification. This phase builds on the consolidations from Phases 1-2C.

---

## Objectives

1. ✅ Move SSH orchestration from Terraform to scripts
2. ⏳ Migrate database initialization to Terraform IaC
3. ⏳ Migrate SSL/TLS setup to Terraform ACME provider
4. ⏳ Document ephemeral vs persistent resource classification
5. ⏳ Complete Tier 2 application migrations (7 apps)

---

## Work Items

### Work Item 1: Move SSH Orchestration from Terraform to Scripts

**Status**: IN PROGRESS  
**Scope**: Extract SSH deployment logic from Terraform provisioners  
**Target**: scripts/ops/deploy-via-ssh.sh

**Current State** (Terraform provisioners):
- terraform/environments/private/deployment.tf contains remote-exec provisioners
- Provisioners execute docker-compose deployment on primary and replica hosts
- Triggers on docker-compose.yml, override, and Caddy config changes

**Migration Steps**:

**Step 1: Create SSH deployment script** (1 hour)
```bash
# scripts/ops/deploy-via-ssh.sh
# New script to handle SSH orchestration
```

**Step 2: Implement host detection and validation** (30 minutes)
```bash
# Detect primary host, replica host from config.env
# Validate SSH connectivity
# Verify Docker and docker-compose available on remote hosts
```

**Step 3: Implement docker-compose deployment** (1 hour)
```bash
# Pull latest docker-compose files via SCP or git clone
# Start docker-compose with all profiles
# Perform health checks
# Log results
```

**Step 4: Add error handling and rollback** (1 hour)
```bash
# Trap errors during deployment
# Implement rollback on failure
# Generate deployment report
```

**Step 5: Update Terraform to call script** (30 minutes)
```terraform
# Replace provisioners with local-exec calling new script
# Pass variables via environment or CLI arguments
# Keep Terraform state management
```

**Step 6: Test and validate** (1 hour)
```bash
# Test with --dry-run flag
# Validate against staging environment
# Verify state consistency
```

**Benefits**:
- Easier to test (scripts are testable, provisioners are not)
- Better error handling and logging
- More maintainable (scripts vs HCL)
- Supports both SSH and local execution
- Enables dry-run and rollback

**Deliverables**:
- scripts/ops/deploy-via-ssh.sh (deployable)
- Updated terraform/environments/private/deployment.tf
- Documentation on SSH deployment workflow
- Test report

---

### Work Item 2: Migrate Database Initialization to Terraform IaC

**Status**: PLANNING  
**Scope**: Move database schema and initialization to Terraform provisioners (proper way)

**Current Gaps**:
- Database initialization may be done via docker-entrypoint.sh
- Schema migrations may be manual
- User creation and permissions may be ad-hoc

**Plan**:
1. Identify current database initialization procedures
2. Create Terraform null_resource with proper scripts
3. Use docker-compose exec for database operations
4. Version control all schemas and migrations
5. Validate idempotency

**Timeline**: Week 2 of Phase 3

---

### Work Item 3: Migrate SSL/TLS Setup to Terraform ACME Provider

**Status**: PLANNING  
**Scope**: Replace manual cert management with Terraform acme_certificate resource

**Current State**:
- Caddy config may have hardcoded certs or manual renewal
- No automated cert provisioning in Terraform
- Manual renewal procedures

**Plan**:
1. Add acme_certificate resource to Terraform
2. Configure Let's Encrypt provider
3. Manage certificate renewal automatically
4. Update Caddy configuration to use Terraform-managed certs
5. Validate certificate validation

**Timeline**: Week 2-3 of Phase 3

---

### Work Item 4: Document Ephemeral vs Persistent Resources

**Status**: PLANNING  
**Scope**: Classify infrastructure resources by lifecycle

**Classification**:
```
EPHEMERAL (can be recreated from IaC):
- Docker containers
- Docker volumes (some)
- Temporary configuration files
- Application state (if stored externally)

PERSISTENT (must be preserved):
- PostgreSQL data volumes
- Redis data volumes
- NAS/NFS storage
- SSL certificates (if not auto-renewed)
- SSH keys
- Secrets
```

**Deliverable**: EPHEMERAL_VS_PERSISTENT_RESOURCES.md

**Timeline**: Week 1-2 of Phase 3

---

### Work Item 5: Complete Tier 2 Application Migrations

**Status**: READY  
**Scope**: Migrate 7 Tier 2 apps to config.py

**Tier 2 Apps**:
1. activity_feed
2. agent-runtime
3. edge_agent
4. api_gateway
5. orchestrator
6. dashboard
7. event_processor

**Approach**: Follow same pattern as Tier 1
- grep for os.getenv() calls
- Replace with config.get() / config.get_int() / config.get_bool()
- Validate syntax
- Commit with reference to guide

**Timeline**: Week 3-4 of Phase 3 (can run in parallel with other work)

---

## Success Criteria

✅ Phase 3 Work Item 1: SSH orchestration moved to scripts, Terraform updated  
✅ Phase 3 Work Item 2: Database initialization managed by Terraform  
✅ Phase 3 Work Item 3: SSL/TLS automated via Terraform ACME  
✅ Phase 3 Work Item 4: Resource classification documented  
✅ Phase 3 Work Item 5: All Tier 2 apps migrated (7/7)

---

## Timeline

| Week | Activity | Duration |
|------|----------|----------|
| 1 | SSH orchestration migration (1) | 5 hours |
| 1 | Resource classification docs (4) | 3 hours |
| 2 | Database initialization migration (2) | 6 hours |
| 2 | SSL/TLS ACME setup (3) | 6 hours |
| 3-4 | Tier 2 app migrations (5) | 20 hours |
| 4 | Integration testing and validation | 8 hours |

**Total**: ~48 hours (6 business days)

---

## Risk Mitigation

**Risk**: SSH deployment fails, infrastructure down  
**Mitigation**: 
- Test script extensively in staging
- Keep Terraform provisioners as fallback initially
- Implement comprehensive error handling and rollback

**Risk**: Database migration breaks existing data  
**Mitigation**:
- Test on copy of production database first
- Keep backup procedures in place
- Implement data validation checks

**Risk**: Certificate renewal fails  
**Mitigation**:
- Monitor certificate expiration
- Keep manual renewal procedure as fallback
- Set up alerts for cert expiration

---

## Dependencies

- Phases 1-2C must be complete ✅
- Terraform state must be clean
- SSH access to deployment hosts must be working
- Docker and docker-compose must be installed on remote hosts

---

## Deliverables

1. **scripts/ops/deploy-via-ssh.sh** (executable script)
2. **Updated terraform/environments/private/deployment.tf** (Terraform changes)
3. **terraform/database-initialization.tf** (new - database IaC)
4. **terraform/ssl-certificates.tf** (new - ACME provider)
5. **EPHEMERAL_VS_PERSISTENT_RESOURCES.md** (documentation)
6. **Tier 2 App Migration Results** (7 apps, ~100 os.getenv() calls eliminated)
7. **Phase 3 Completion Report** (final status and recommendations)

---

## Owner & Approval

**Phase Owner**: Infrastructure Team  
**Prepared by**: Phase 2C Team  
**Date**: April 28, 2026

---

End of Phase 3 Execution Plan
