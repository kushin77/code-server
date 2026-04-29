# Phase 2.3 - Staged Rollout Procedures
**Gated Deployment Pipeline: Canary → Replica → Primary**

---

## Overview

The Staged Rollout Controller enforces safe, sequential deployment across three environments with health gates between each stage. This prevents catastrophic failures by catching issues early in low-risk environments before they reach production.

**Key Benefits:**
- **Progressive Risk:** Test in canary (low impact) → replica (medium impact) → primary (production)
- **Health Gates:** Services must converge to healthy state before advancing to next stage
- **Rollback Safety:** Automatic rollback capability if health checks fail
- **Audit Trail:** Full deployment history with timestamps and health states
- **Manual Approval:** Production deployments require explicit approval (safety gate)

---

## Architecture

### Deployment Pipeline

```
┌─────────────────────────────────────────────────────┐
│           Deployment Request                         │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
       ┌─────────────────────────┐
       │ CANARY ENVIRONMENT      │ (primary host, dev config)
       │ ✓ Quick feedback (5m)   │
       │ ✓ Low blast radius      │
       └──────────┬──────────────┘
                  │ health ✓
                  ▼
       ┌─────────────────────────┐
       │ REPLICA ENVIRONMENT     │ (secondary host, prod config)
       │ ✓ Validate at scale     │
       │ ✓ Test high availability│
       └──────────┬──────────────┘
                  │ health ✓
                  ▼
       ┌─────────────────────────┐
       │ MANUAL APPROVAL GATE    │
       │ (operator reviews logs) │
       └──────────┬──────────────┘
                  │ approved
                  ▼
       ┌─────────────────────────┐
       │ PRIMARY (PRODUCTION)    │
       │ ✓ Production ready      │
       │ ✓ Full capacity deployed│
       └─────────────────────────┘
```

### State Machine

```
┌─────────────────┐
│  not_started    │
└────────┬────────┘
         │ execute_stage
         ▼
┌─────────────────┐
│  in_progress    │
└────┬────────┬───┘
     │        │
  success   failed
     │        │
     ▼        ▼
┌─────────┐  ┌──────────────┐
│ success │  │ failed       │
└────┬────┘  └──────────────┘
     │
     └─→ [can proceed to next stage]
```

---

## Usage

### Quick Start

**Deploy to canary (test environment):**
```bash
./scripts/staged-rollout.sh --stage canary
```

**Deploy to replica (with health checks):**
```bash
./scripts/staged-rollout.sh --stage replica --health-wait 300 --rollback-on-fail
```

**Deploy to primary (production, with approval):**
```bash
./scripts/staged-rollout.sh --stage primary --approval-timeout 600 --rollback-on-fail
```

### Full CI/CD Pipeline

```bash
#!/bin/bash
# Fully automated deployment pipeline (no approval gates)

set -e

echo "Starting staged deployment pipeline..."

./scripts/staged-rollout.sh --stage canary --auto-approve
echo "✓ Canary passed"

./scripts/staged-rollout.sh --stage replica --auto-approve --health-wait 300
echo "✓ Replica passed"

./scripts/staged-rollout.sh --stage primary --auto-approve --health-wait 300 --rollback-on-fail
echo "✓ Primary deployed (production ready)"

echo "Pipeline complete!"
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `--stage` | required | Target stage: canary, replica, primary, both |
| `--health-wait` | 300s | Max seconds to wait for health convergence |
| `--health-retries` | 5 | Max health check attempts before failure |
| `--approval-timeout` | 300s | Seconds to wait for manual approval |
| `--auto-approve` | false | Skip manual approval (for CI/CD) |
| `--skip-health-gate` | false | Skip health checks (risky, not recommended) |
| `--rollback-on-fail` | false | Automatically rollback if health fails |
| `--dry-run` | false | Show what would happen without executing |
| `--help` | - | Show help message |

---

## Deployment Scenarios

### Scenario 1: Developer Testing (Canary)

**Goal:** Quickly validate changes in low-risk environment

```bash
# Fast feedback loop
./scripts/staged-rollout.sh --stage canary --health-wait 120 --auto-approve

# Result: Changes deployed to canary (primary host)
# - Services restarted
# - Health checked for 2 minutes
# - Logs in: /tmp/staged-rollout-TIMESTAMP.log
```

**Success Criteria:**
- ✓ All 37 services deployed
- ✓ 35+ services healthy after 2 minutes
- ✓ No critical errors in logs

### Scenario 2: Staging Validation (Replica)

**Goal:** Validate at production scale before primary deployment

```bash
# Production config, with safety gates
./scripts/staged-rollout.sh \
  --stage replica \
  --health-wait 300 \
  --rollback-on-fail \
  --auto-approve

# Deployment to replica (192.168.168.42)
# - Replica must match current production config
# - Services validated for 5 minutes
# - Auto-rollback if health fails
```

**Success Criteria:**
- ✓ Cross-host consistency check passes
- ✓ All services in healthy state
- ✓ No restart loops
- ✓ Performance metrics nominal

### Scenario 3: Production Deployment (Primary)

**Goal:** Deploy to production with human oversight

```bash
# Manual approval required
./scripts/staged-rollout.sh \
  --stage primary \
  --approval-timeout 600 \
  --health-wait 300 \
  --rollback-on-fail

# Output:
# ═══════════════════════════════════════
# MANUAL APPROVAL REQUIRED FOR: primary
# ═══════════════════════════════════════
# 
# About to deploy to: primary
# Timeout: 600s
# 
# Approve deployment to primary? (yes/no):
```

**Approval Decision Criteria:**
- ✓ Canary deployment succeeded
- ✓ Replica validation passed
- ✓ No blocking issues in logs
- ✓ Maintenance window confirmed (if applicable)

---

## Health Gates

### Health Convergence Logic

Before advancing to next stage, the controller:

1. **Waits 10 seconds** (service stabilization)
2. **Runs consistency check** (37 services, image tags, health states)
3. **If all match:** Pass health gate → proceed to next stage
4. **If mismatch:** Retry (max 5 times)
5. **If all retries fail:** Mark as "health_failed"

### Customizing Health Thresholds

**Default behavior:** 5-minute health window, 5 retries

**For faster validation:**
```bash
./scripts/staged-rollout.sh --stage replica \
  --health-wait 120 \        # 2 minutes instead of 5
  --health-retries 3         # 3 attempts instead of 5
```

**For stricter validation:**
```bash
./scripts/staged-rollout.sh --stage primary \
  --health-wait 600 \        # 10 minutes instead of 5
  --health-retries 10        # 10 attempts instead of 5
  --rollback-on-fail         # Auto-rollback on any failure
```

---

## Rollback Procedures

### Automatic Rollback

When `--rollback-on-fail` is enabled:

```bash
./scripts/staged-rollout.sh --stage primary --rollback-on-fail

# If health checks fail after 5 retries:
# 1. Logs error: "Health convergence failed"
# 2. Initiates rollback
# 3. Restores previous service version
# 4. Verifies rollback succeeded
# 5. Alerts operator
```

**Rollback Actions:**
- Redeploy previous docker-compose version (from git history)
- Run health checks (wait for convergence)
- Verify rollback succeeded
- Send alert with rollback reason

### Manual Rollback

If automatic rollback is disabled, manually rollback:

```bash
# Option 1: Using deployment script
./scripts/deploy-enterprise-idempotent.sh --target=primary --mode=apply

# Option 2: Using git to restore previous state
cd ~/code-server-enterprise
git checkout HEAD~1 docker-compose.enterprise.yml
./scripts/deploy-enterprise-idempotent.sh --target=primary --mode=apply

# Option 3: Docker manual reset
ssh 192.168.168.31 "
  cd ~/code-server-enterprise
  docker-compose -f docker-compose.enterprise.yml down
  docker-compose -f docker-compose.enterprise.yml up -d
"
```

---

## Status Tracking

### View Current Rollout Status

```bash
# Check real-time status
cat /tmp/staged-rollout-state.json | jq '.'

# Output:
{
  "canary": {
    "status": "success",
    "timestamp": "2026-04-29T17:30:00Z",
    "health_checks": []
  },
  "replica": {
    "status": "success",
    "timestamp": "2026-04-29T17:35:00Z",
    "health_checks": []
  },
  "primary": {
    "status": "in_progress",
    "timestamp": "2026-04-29T17:40:00Z",
    "health_checks": []
  }
}
```

### Review Deployment Logs

```bash
# Latest rollout log
tail -100 /tmp/staged-rollout-*.log

# Full log for troubleshooting
less /tmp/staged-rollout-20260429_173000.log
```

### Query Loki for Rollout Events

```bash
# All events during rollout
{job="healthcheck-monitor"} | __timestamp__ > now - 30m

# Status transitions during rollout
{job="healthcheck-monitor"} | pattern `STATUS_TRANSITION` | __timestamp__ > now - 30m
```

---

## Integration with CI/CD

### GitHub Actions Workflow

```yaml
# .github/workflows/staged-deployment.yml
name: Staged Deployment Pipeline

on:
  workflow_dispatch:  # Manual trigger

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Canary Deployment
        run: |
          chmod +x scripts/staged-rollout.sh
          ./scripts/staged-rollout.sh --stage canary --auto-approve
          
      - name: Replica Deployment
        if: success()
        run: |
          ./scripts/staged-rollout.sh --stage replica --auto-approve --health-wait 300
          
      - name: Production Approval
        if: success()
        run: |
          echo "Awaiting manual approval for production deployment..."
          # Could send Slack notification, open approval in UI, etc.
          
      - name: Primary Deployment
        if: success()
        run: |
          ./scripts/staged-rollout.sh --stage primary --auto-approve --health-wait 300 --rollback-on-fail
          
      - name: Deployment Summary
        if: always()
        run: |
          cat /tmp/staged-rollout-*.log | tail -50
```

### GitLab CI Example

```yaml
# .gitlab-ci.yml
stages:
  - canary
  - replica
  - approval
  - primary

canary_deploy:
  stage: canary
  script:
    - ./scripts/staged-rollout.sh --stage canary --auto-approve
  only:
    - main

replica_deploy:
  stage: replica
  script:
    - ./scripts/staged-rollout.sh --stage replica --auto-approve --health-wait 300
  only:
    - main

manual_approval:
  stage: approval
  script:
    - echo "Awaiting manual approval"
  when: manual
  only:
    - main

primary_deploy:
  stage: primary
  script:
    - ./scripts/staged-rollout.sh --stage primary --auto-approve --health-wait 300 --rollback-on-fail
  only:
    - main
```

---

## Prerequisites & Dependencies

### Phase 2.3 Depends On:
- ✅ Phase 2.1: Cross-host consistency verification script
- ✅ Phase 2.2: Healthcheck event streaming to Loki
- ✅ Phase 1.3: Idempotent deployment script

### Required Files:
- `scripts/deploy-enterprise-idempotent.sh` (Phase 1.3)
- `scripts/verify-cross-host-consistency.sh` (Phase 2.1)
- `docker-compose.enterprise.yml` (deployed configuration)

### Infrastructure Requirements:
- SSH access to both hosts (192.168.168.31, 192.168.168.42)
- Docker running on both hosts
- Loki running (for health event streaming)

---

## Troubleshooting

### Issue 1: Canary Deployment Fails

```
Error: Deployment failed for stage: canary
```

**Diagnosis:**
```bash
tail /tmp/staged-rollout-*.log
# Check if SSH connectivity issue or deployment script error
```

**Solution:**
```bash
# Test SSH connectivity
ssh 192.168.168.31 "echo test"

# Test deployment script directly
./scripts/deploy-enterprise-idempotent.sh --target=primary --mode=dry-run
```

### Issue 2: Health Check Gate Fails

```
Error: Health convergence failed after 5 retries
```

**Diagnosis:**
```bash
# Check actual consistency
./scripts/verify-cross-host-consistency.sh --verbose

# Check service health on primary
ssh 192.168.168.31 "docker ps --format '{{.Names}}\t{{.Status}}' | grep code-server"
```

**Solution:**
```bash
# Increase health wait time
./scripts/staged-rollout.sh --stage replica --health-wait 600

# Or skip health gate (not recommended)
./scripts/staged-rollout.sh --stage replica --skip-health-gate
```

### Issue 3: Manual Approval Timeout

```
Error: Approval timeout expired for stage: primary
```

**Diagnosis:**
- Operator didn't respond within approval timeout

**Solution:**
```bash
# Retry with longer timeout
./scripts/staged-rollout.sh --stage primary --approval-timeout 1800  # 30 minutes

# Or use auto-approval for CI/CD
./scripts/staged-rollout.sh --stage primary --auto-approve
```

---

## Performance Expectations

### Deployment Timeline (Per Stage)

| Phase | Duration | Activity |
|-------|----------|----------|
| Prerequisite check | <10s | Verify previous stage succeeded |
| Manual approval | 0-600s | Wait for operator approval |
| Deployment | 2-5min | Pull images, start containers |
| Health stabilization | 10-30s | Services become responsive |
| Health convergence | 2-5min | All services reach healthy state |
| **Total per stage** | **5-15min** | Typical production deployment |

### Full Pipeline Timeline

```
Canary     → 5-10 min
Replica    → 5-10 min (+ approval if manual)
Primary    → 5-15 min (+ 10 min approval)
────────────────────
Total:     → 15-35 min (for full pipeline)
```

---

## Success Criteria

Phase 2.3 is successful when:

- [x] Staged rollout script created (300+ lines)
- [x] Canary → Replica → Primary deployment logic implemented
- [x] Health gates between stages working
- [x] Manual approval mechanism implemented
- [x] Automatic rollback capability present
- [x] Comprehensive documentation provided
- [x] CI/CD integration examples included
- [x] Tested on live deployment environment
- [x] State tracking and audit trail enabled
- [x] Troubleshooting guide created

---

## Integration with Phase 3 & 4

### Phase 3 (Service Dependency Mapping)
- Phase 2.3 can pause between stages for dependency validation
- Staged rollout gates ensure dependencies are satisfied before proceeding

### Phase 4 (Comprehensive Runbook)
- Phase 2.3 is part of "Operational Procedures"
- Full deployment walkthrough uses staged rollout as central mechanism

---

## References

- [Phase 2.1: Cross-Host Consistency](./PHASE2.1_COMPLETION_REPORT.md)
- [Phase 2.2: Healthcheck Event Streaming](./PHASE2.2_COMPLETION_REPORT.md)
- [Phase 1.3: Idempotent Deployment](./PHASE1_COMPLETION_REPORT.md)
- [Deployment Script](../scripts/deploy-enterprise-idempotent.sh)
- [Consistency Verification](../scripts/verify-cross-host-consistency.sh)

---
