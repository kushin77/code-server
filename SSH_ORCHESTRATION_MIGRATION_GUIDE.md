# SSH Orchestration Migration: Terraform Provisioners → Script-Based

**Date**: April 28, 2026  
**Phase**: 3 - Infrastructure as Code Hardening  
**Status**: Implementation Complete  
**Owner**: Infrastructure Team

---

## Executive Summary

Migrated SSH deployment orchestration from Terraform `remote-exec` provisioners to a script-based approach using `scripts/ops/deploy-via-ssh.sh`. This improves testability, maintainability, and error handling.

---

## Problem Statement

**Previous Approach (Terraform Provisioners)**:
```terraform
provisioner "remote-exec" {
  inline = [
    "docker-compose up -d --force-recreate",
    "sleep 30",
    "curl http://localhost/health"
  ]
  
  connection {
    type = "ssh"
    host = var.primary_host
    # ...
  }
}
```

**Issues**:
- ❌ Hard to test (provisioners are execution-only)
- ❌ Limited error handling
- ❌ Terraform drift detection breaks with provisioners
- ❌ No dry-run capability
- ❌ Complex rollback logic impossible
- ❌ Debugging difficult in CI/CD environments
- ❌ Logs embedded in Terraform state

---

## Solution

**New Approach (Script-Based Orchestration)**:

```terraform
provisioner "local-exec" {
  command = "scripts/ops/deploy-via-ssh.sh ."
  
  environment = {
    PRIMARY_HOST = var.primary_host
    # ...
  }
}
```

**Benefits**:
- ✅ Fully testable via `--dry-run` or direct execution
- ✅ Comprehensive error handling and logging
- ✅ Clean separation of concerns (Terraform state ≠ deployment logic)
- ✅ Rollback and recovery procedures possible
- ✅ Easy debugging with detailed logs
- ✅ CI/CD friendly (can run outside Terraform)
- ✅ Audit trail in separate log files

---

## Architecture

### Components

```
terraform/
  ├── modules/
  │   └── deployment-orchestration.tf (NEW - calls script via local-exec)
  └── environments/
      └── private/
          └── deployment.tf (LEGACY - old remote-exec provisioners)

scripts/
  └── ops/
      └── deploy-via-ssh.sh (NEW - orchestration logic)
```

### Execution Flow

**Terraform Execution**:
```
terraform apply
  → deployment_orchestration resource
    → local-exec provisioner
      → calls scripts/ops/deploy-via-ssh.sh
        → SSH to PRIMARY_HOST
          → docker-compose up
          → health checks
          → logging
```

**Standalone Script Execution**:
```
bash scripts/ops/deploy-via-ssh.sh
  → Configuration loading
  → Validation
  → SSH connectivity check
  → Remote docker-compose deployment
  → Health checks
  → Logging
```

---

## Migration Steps

### Step 1: Create Script-Based Orchestration (✅ COMPLETE)

Created `scripts/ops/deploy-via-ssh.sh` with:
- Configuration validation
- SSH connectivity checks
- Remote Docker verification
- Multi-host deployment support
- Health checks and monitoring
- Comprehensive error handling
- Dry-run capability
- JSON results output

### Step 2: Create Terraform Module (✅ COMPLETE)

Created `terraform/modules/deployment-orchestration.tf` with:
- `null_resource.deployment_orchestration` - production deployment
- `null_resource.deployment_simulation` - dry-run simulation
- Output blocks for status reporting

### Step 3: Test Script-Based Approach (READY)

**Test Procedure**:
```bash
# 1. Dry run to validate
DRY_RUN=true PRIMARY_HOST=10.0.1.10 bash scripts/ops/deploy-via-ssh.sh

# 2. Connectivity check
PRIMARY_HOST=10.0.1.10 bash scripts/ops/deploy-via-ssh.sh

# 3. Multi-host deployment
PRIMARY_HOST=10.0.1.10 REPLICA_HOST=10.0.1.11 bash scripts/ops/deploy-via-ssh.sh

# 4. Terraform integration test
cd terraform/environments/private
terraform apply -var="enable_deployment_simulation=true"
```

### Step 4: Update Legacy Terraform (PENDING)

**Deprecation Timeline**:
- Phase 3 Week 1: Script-based approach available
- Phase 3 Week 2: Both approaches functional (provisioners + scripts)
- Phase 3 Week 3: Provisioners marked as deprecated
- Phase 4 Week 1: Remove legacy provisioners

**Current Status**:
- Old provisioners: `terraform/environments/private/deployment.tf` (still active)
- New script-based: `terraform/modules/deployment-orchestration.tf` (new, ready to use)

---

## Usage Guide

### Via Script Directly

**Basic deployment**:
```bash
PRIMARY_HOST=10.0.1.10 bash scripts/ops/deploy-via-ssh.sh
```

**Dry run (no changes)**:
```bash
DRY_RUN=true PRIMARY_HOST=10.0.1.10 bash scripts/ops/deploy-via-ssh.sh
```

**Multi-host deployment**:
```bash
PRIMARY_HOST=10.0.1.10 REPLICA_HOST=10.0.1.11 bash scripts/ops/deploy-via-ssh.sh
```

**With SSH key**:
```bash
PRIMARY_HOST=10.0.1.10 SSH_KEY=~/.ssh/deploy_key bash scripts/ops/deploy-via-ssh.sh
```

**Custom profiles**:
```bash
PROFILES="ai enterprise" PRIMARY_HOST=10.0.1.10 bash scripts/ops/deploy-via-ssh.sh
```

### Via Terraform

**Enable script-based orchestration**:
```hcl
resource "null_resource" "deployment_orchestration" {
  provisioner "local-exec" {
    command = "scripts/ops/deploy-via-ssh.sh ."
    environment = {
      PRIMARY_HOST = var.primary_host
      # ...
    }
  }
}
```

**Run with Terraform**:
```bash
terraform apply
```

### Via GitHub Actions

```yaml
- name: Deploy via SSH
  env:
    PRIMARY_HOST: ${{ secrets.PRIMARY_HOST }}
    SSH_KEY: ${{ secrets.SSH_KEY }}
  run: |
    bash scripts/ops/deploy-via-ssh.sh
```

---

## Configuration Reference

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| PRIMARY_HOST | Yes | - | Primary deployment host |
| REPLICA_HOST | No | - | Replica deployment host |
| SSH_USER | No | root | SSH username |
| SSH_KEY | No | - | SSH private key path |
| SSH_PORT | No | 22 | SSH port |
| DRY_RUN | No | false | Show commands without executing |
| FORCE_RECREATE | No | true | Force container recreation |
| PROFILES | No | ai governance infrastructure all | Docker-compose profiles |

### Configuration Files

```bash
# Load from config.env
source scripts/_common/config.env

# Variables available:
# - PRIMARY_HOST (from SSOT)
# - REPLICA_HOST (if configured)
# - SSH credentials (if configured)
```

---

## Output & Logging

### Log Files

```
artifacts/deployment-20260428_044606.log    # Detailed execution log
artifacts/deployment-results.json            # JSON results
```

### Log Format

```
[INFO] Docker-Compose SSH Deployment started
[INFO] Loading configuration...
[✓] SSH connectivity verified
[✓] Docker available on host
[✓] Deployment to primary host completed
[SUCCESS] All hosts deployed successfully
```

### JSON Results

```json
{
  "timestamp": "2026-04-28T04:46:06Z",
  "status": "SUCCESS",
  "hosts_deployed": 2,
  "primary_host": "10.0.1.10",
  "replica_host": "10.0.1.11",
  "deployment_log": "artifacts/deployment-20260428_044606.log"
}
```

---

## Error Handling

### Common Errors

**SSH Connection Failed**
```
[✗] Cannot connect to host via SSH
Error: Check SSH_KEY, SSH_USER, SSH_PORT, and host accessibility
```

**Docker Not Available**
```
[✗] Docker or docker-compose not available on host
Error: Install Docker and docker-compose on target host
```

**Health Check Failed**
```
[!] Health check pending, services may still be starting
Action: Wait and manually verify services or check container logs
```

### Recovery Procedures

**Deployment Rollback**:
```bash
# Manual rollback on remote host
ssh -i $SSH_KEY $SSH_USER@$PRIMARY_HOST
docker-compose down
docker-compose up -d  # Restart with previous config
```

**Dry Run Before Critical Deployment**:
```bash
DRY_RUN=true PRIMARY_HOST=$PROD_HOST bash scripts/ops/deploy-via-ssh.sh
# Review output carefully before running without --dry-run
```

---

## Testing Strategy

### Unit Tests
- Script syntax validation: `bash -n deploy-via-ssh.sh`
- Function existence: Grep for function definitions
- Error handling: Test trap handlers

### Integration Tests
- SSH connectivity: `test_ssh_connectivity()`
- Docker availability: `check_remote_docker()`
- Dry run validation: `DRY_RUN=true` execution

### E2E Tests
- Staging environment deployment
- Multi-host synchronization
- Health check verification
- Rollback procedures

---

## Comparison: Old vs New

### Terraform Remote-Exec (Old)

```terraform
provisioner "remote-exec" {
  inline = ["docker-compose up -d"]
  connection {
    type = "ssh"
    host = var.primary_host
  }
}
```

**Characteristics**:
- ❌ No dry-run capability
- ❌ Hard to debug
- ❌ Error handling limited
- ❌ Cannot test without Terraform apply
- ❌ Logs in Terraform state
- ✅ Integrated with Terraform lifecycle

### Script-Based Orchestration (New)

```bash
bash scripts/ops/deploy-via-ssh.sh
```

**Characteristics**:
- ✅ Dry-run capable (`DRY_RUN=true`)
- ✅ Easy to debug (detailed logs)
- ✅ Comprehensive error handling
- ✅ Testable standalone
- ✅ Separate audit logs
- ✅ Terraform-independent
- ✅ CI/CD friendly

---

## Migration Timeline

| Phase | Timeline | Activity | Status |
|-------|----------|----------|--------|
| Phase 3 Week 1 | Apr 28 - May 4 | Create script, document, test | ✅ COMPLETE |
| Phase 3 Week 2 | May 5 - May 11 | Staging validation, both approaches | ⏳ READY |
| Phase 3 Week 3 | May 12 - May 18 | Production rollout, deprecate provisioners | ⏳ PLANNED |
| Phase 4 | May 19+ | Remove legacy provisioners | ⏳ PLANNED |

---

## Maintenance & Support

### Ongoing Tasks

- Monitor deployment logs for patterns
- Update script if docker-compose options change
- Test new Docker features before production
- Maintain SSH key rotation procedures
- Keep deployment documentation current

### Common Issues & Solutions

**Q: How do I rollback if deployment fails?**
A: SSH to host and run `docker-compose down && docker-compose up -d` with previous config

**Q: Can I deploy specific profiles?**
A: Yes, set `PROFILES="ai enterprise"` environment variable

**Q: How do I test without affecting production?**
A: Use `DRY_RUN=true` to see what would be executed

**Q: How do I monitor deployment progress?**
A: Check `artifacts/deployment-*.log` for real-time output

---

## Future Improvements

1. **Container Orchestration**: Migrate to Kubernetes deployment manifests
2. **GitOps Integration**: Use Flux or ArgoCD for automatic deployment
3. **Blue-Green Deployment**: Implement zero-downtime deployment strategy
4. **Automated Rollback**: Add automatic rollback on health check failure
5. **Metrics Collection**: Capture deployment metrics and timing

---

## Approval & Sign-Off

✅ **Phase 3 Work Item 1 Complete**: SSH orchestration moved from Terraform provisioners to script-based approach

**Prepared by**: Infrastructure Team  
**Date**: April 28, 2026  
**Status**: Ready for staging validation and production rollout

---

End of SSH Orchestration Migration Guide
