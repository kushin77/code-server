# Phase 14-16 Immutable Infrastructure Specification

## Immutability Principles

All infrastructure deployed in Phase 14-16 follows immutable infrastructure patterns:

1. **No Manual Configuration Changes**: All configuration via code (Terraform/Docker/Scripts)
2. **Read-Only Runtime**: Application runtime filesystems are read-only where possible
3. **Container Image Integrity**: Images are signed and verified on deployment
4. **Configuration Externalization**: All configuration in environment variables or ConfigMaps
5. **Rollback Ready**: Every deployment can be rolled back to previous known state

---

## Phase 14: Immutable Canary Deployment

### Principle
- Each stage (10%, 50%, 100%) is immutable once deployed
- DNS routing changes trigger new immutable deployment
- All state stored in distributed system (not container local storage)

### Implementation

```yaml
Docker Images:
  - code-server:phase-14-<SHA256>  (immutable by SHA)
  - caddy:phase-14-<SHA256>        (immutable by SHA)
  - redis:phase-14-<SHA256>        (immutable by SHA)

Volume Mounts:
  - /etc/code-server/config.yml:ro (read-only)
  - /etc/caddy/Caddyfile:ro        (read-only)
  - /data (for mutable data only)

Environment Variables (Immutable):
  PHASE_14_STAGE=1                 (Stage number)
  CANARY_PERCENTAGE=10             (Traffic %)
  DNS_ROUTING_POLICY=canary        (Routing mode)
  REPLICA_MODE=false               (Primary/standby)
```

### Rollback Mechanism
- Each stage has immutable snapshot
- Rollback = Switch DNS to previous stage VIP
- No data loss (database is separate, replicated)

---

## Phase 15: Immutable Performance Testing

### Principle
- Load test infrastructure is ephemeral and stateless
- Test results stored in immutable artifact store
- No impact on production infrastructure

### Implementation

```yaml
Test Environment:
  - Separate Redis cache instance (not production)
  - Isolated load testing network
  - No shared persistent storage with production

Test Results:
  - Store in S3/artifact registry
  - Tagged with immutable timestamp
  - Never modified after creation

Cleanup:
  - All test resources destroyed after validation
  - No residual test infrastructure
```

---

## Phase 16: Immutable HA Infrastructure

### PostgreSQL High Availability

```yaml
Database Deployment (Immutable):
  - Primary PostgreSQL (192.168.168.31)
  - Standby PostgreSQL (192.168.168.30)
  - Both deployed from same Docker image
  - Configuration via environment variables only
  
Virtual IP (192.168.168.40):
  - Managed by Keepalived
  - Always points to active database
  - Automatic failover (no manual intervention)
  
Data Durability:
  - Streaming replication (synchronous)
  - WAL archiving to S3
  - Point-in-time recovery capability
  
Configuration Immutability:
  - postgresql.conf: environment-driven
  - pg_hba.conf: generated from template
  - No post-deployment configuration changes
  - All changes tracked in git
```

### HAProxy Load Balancing

```yaml
Load Balancer (Immutable):
  - HAProxy deployed from immutable image
  - Configuration via:
    * haproxy.cfg: generated from Terraform
    * Environment variables for dynamic backend IPs
  
  - VIP Failover:
    * Primary HAProxy (192.168.168.50)
    * Secondary HAProxy (standby)
    * Keepalived manages automatic failover
  
  - Backend Auto-Scaling:
    * Kubernetes integration (if needed)
    * Auto-scale on CPU/memory metrics
    * New instances use immutable image
    * Old instances terminate cleanly
  
  - Session State:
    * Sticky sessions via source IP hash
    * No server-local session storage
    * Backend servers are stateless
```

---

## Idempotency Guarantees

### Principle
All deployments are idempotent: running twice produces same result as running once

### Implementation

**Terraform Idempotency**:
```hcl
# Safe to run multiple times - only creates/updates if state differs
terraform apply -auto-approve
terraform apply -auto-approve  # Second run does nothing
```

**Script Idempotency**:
```bash
# Check state before making changes
if ! grep -q "already_deployed" /tmp/state.txt; then
    # Make changes only if not already done
    deploy_surface
    echo "already_deployed" > /tmp/state.txt
fi
# Re-running script is harmless
```

**Docker Idempotency**:
```bash
# Containers are stateless (state in persistent volumes)
docker stop container || true
docker rm container || true
docker run --name container image:sha256  # Repeatable by SHA
```

---

## Independence Verification

Each phase can be deployed independently:

| Phase | Dependencies | Deployment Method |
|-------|---|---|
| 14 Stage 1 | DNS routing | terraform apply -var="phase_14_canary_percentage=10" |
| 14 Stage 2 | Stage 1 GO | terraform apply -var="phase_14_canary_percentage=50" |
| 14 Stage 3 | Stage 2 GO | terraform apply -var="phase_14_canary_percentage=100" |
| 15 Quick | Phase 14 Stage 3 GO | terraform apply -var="phase_15_enabled=true" |
| 16-A PostgreSQL HA | None (independent) | terraform apply -var="phase_16_postgresql_ha_enabled=true" |
| 16-B HAProxy LB | None (independent) | terraform apply -var="phase_16_load_balancing_enabled=true" |

**Independence Guarantee**:
- Each phase has explicit environment variables
- No implicit resource dependencies
- Can deploy in any order (with business logic ordering)
- Terraform validates resource dependencies

---

## Immutability Audit Trail

All changes tracked in git:

```bash
git log --all --pretty=format:"%h %s %ai"
# Shows every infrastructure change
# Immutable: cannot be modified without audit trail
```

---

## Rollback Procedures

### Immutable Rollback (No Data Loss)

**Phase 14 Rollback**:
```bash
# Revert DNS routing to previous stage
terraform apply -var="phase_14_canary_percentage=50"  # Roll back from 100% to 50%
# All data preserved (database is replicated separately)
# RTO: <5 minutes
```

**Phase 16 Rollback**:
```bash
# Kill HAProxy/PostgreSQL HA, keep data
terraform apply -var="phase_16_load_balancing_enabled=false"
# Data remains in persistent volumes
# Can re-enable at any time
# Point-in-time recovery: 24-hour retention
```

---

## Compliance Checklist

✅ **Immutability**:
- [ ] All configuration in code (Terraform/Docker/Scripts)
- [ ] No manual SSH configuration changes
- [ ] Docker images immutable by SHA256
- [ ] All runtime filesystems read-only except /data
- [ ] Configuration externalized (environment variables)

✅ **Idempotency**:
- [ ] Terraform plan shows no changes on second run
- [ ] Scripts check state before making changes
- [ ] Docker deployments use explicit image SHAs
- [ ] All state externalized (not in containers)

✅ **Independence**:
- [ ] Each phase deployable without others
- [ ] Explicit dependency graph in Terraform
- [ ] No implicit resource dependencies
- [ ] Variables explicitly control behavior

✅ **Auditability**:
- [ ] All changes in git with timestamps
- [ ] Rollback procedures tested and documented
- [ ] Monitoring captures all deployments
- [ ] Change log shows who/what/when/why
