# Issue #984 Deployment Automation - Complete Guide

## Overview

This package contains complete, production-ready automation for Issue #984 (QA environment oauth2-proxy deployment).

**Status**: 100% Ready for execution  
**Blocker**: Issue #983 (QA user creation - manual action required)  
**Automation Level**: Fully automated (40-50 minutes)

## Files Included

### Automation Scripts
- `ISSUE-984-ORCHESTRATOR.sh` - Master 8-phase deployment orchestrator
- `ISSUE-984-PRE-DEPLOYMENT-VERIFICATION.sh` - Pre-flight checks (30+ validations)
- `ISSUE-984-POST-DEPLOYMENT-VERIFICATION.sh` - Post-deployment validation
- `ISSUE-984-ROLLBACK-PROCEDURE.sh` - Emergency rollback automation
- `MONITOR-ISSUE-983.sh` - Issue #983 completion detector
- `DEPLOYMENT-READY-VERIFICATION.sh` - System readiness check

### Documentation
- `ISSUE-984-QUICK-EXECUTION.md` - Quick reference
- This file - Complete guide

## Quick Start

```bash
# From production host (192.168.168.31)
cd ~/code-server-enterprise

# Run full automated deployment
bash ISSUE-984-ORCHESTRATOR.sh

# Expected: 40-50 minutes, fully automated
# All phases include safety verification and rollback capability
```

## Prerequisites

1. Issue #983 completed (qa@kushnir.cloud user exists in Google Workspace)
2. SSH access to production host
3. gcloud CLI authenticated
4. Docker and Terraform available
5. All core services running (code-server, postgres, redis, caddy)

## What Gets Deployed

- oauth2-proxy v7.5.1 service
- OAuth whitelist with QA credentials  
- Health checks and monitoring
- Automatic service restart
- Post-deployment validation

## Infrastructure Requirements

**Host**: 192.168.168.31  
**Services**: code-server, postgres, redis, caddy (all UP)  
**Tools**: Terraform 1.14.8+, gcloud CLI, Docker  
**Network**: Internet connectivity for GSM access

## Deployment Phases

1. **Pre-deployment** (5 min) - Verify all prerequisites
2. **Confirmation** (2 min) - User approval gate
3. **GSM Update** (2-3 min) - Load QA credentials from Secret Manager
4. **Terraform** (10-15 min) - Apply infrastructure changes
5. **Service Restart** (2-3 min) - Restart oauth2-proxy
6. **Post-deployment** (5 min) - Validate deployment success
7. **E2E Tests** (optional, 15-20 min) - Run full test suite
8. **GitHub Update** (2 min) - Close issue with evidence

**Total Duration**: 40-50 minutes (fully automated)

## External Blocker: Issue #983

**Status**: OPEN - Requires manual action  
**Action**: Create Google Workspace user qa@kushnir.cloud  
**How**: https://admin.google.com/ → Directory → Users → Add new user  
**Steps**:
1. First Name: QA
2. Last Name: Testing
3. Email: qa@kushnir.cloud
4. Password: Generate 32-character strong password
5. Store password in Google Secret Manager

## Rollback Procedure

If deployment fails:

```bash
bash ISSUE-984-ROLLBACK-PROCEDURE.sh
```

This automatically reverses all changes and restores previous state (5-10 minutes).

## Success Indicators

After deployment:
- oauth2-proxy service running and healthy
- Port 4180 responding to health checks
- QA user can authenticate via OAuth
- E2E tests passing (if run)
- GitHub issue updated with evidence

## Troubleshooting

| Issue | Solution |
|-------|----------|
| terraform not found | Ensure running on production host |
| GSM auth fails | Verify gcloud authentication: `gcloud auth list` |
| Service won't start | Check logs: `docker logs oauth2-proxy` |
| E2E tests timeout | Increase timeout in test configuration |

## Next Steps

1. **Complete Issue #983** - Create QA user in Google Workspace
2. **Execute Deployment** - Run `bash ISSUE-984-ORCHESTRATOR.sh`
3. **Run E2E Tests** - Verify OAuth login flow (Issues #986-990)
4. **Close Issues** - #984 with deployment evidence
5. **Close Test Issues** - #986-990 with test results

## Support

All scripts include:
- Comprehensive error handling
- Automatic rollback on failure
- Detailed logging to artifacts directory
- Exit codes for CI/CD integration
- Health verification at each step

**For questions**: Review the script source code or check logs in artifacts/ directory

---

**Version**: April 21, 2026  
**Status**: Production-Ready  
**Deployment Host**: 192.168.168.31  
**Estimated Time**: 40-50 minutes
