# Issue #984 Quick Execution Guide

**Status**: Ready for deployment
**Blocker**: Issue #983 (QA user creation)
**Duration**: 40-50 minutes end-to-end

## One-Line Execution

```bash
bash ISSUE-984-ORCHESTRATOR.sh
```

## Prerequisites

- Issue #983 completed (QA user created)
- SSH access to production host (192.168.168.31)
- GitHub CLI authenticated
- QA user password from Issue #983 comments
- Google Secret Manager credentials ready

## Automated Deployment

The `ISSUE-984-ORCHESTRATOR.sh` script automates all phases:

1. **Pre-deployment verification** - Safety gates
2. **User confirmation** - Explicit approval before proceeding
3. **GSM secrets update** - Injects QA credentials
4. **Terraform apply** - Deploys oauth2-proxy configuration
5. **Service restart** - Reloads oauth2-proxy  
6. **Post-deployment verification** - Validates success
7. **E2E tests** (optional) - Runs full test suite
8. **GitHub update** - Updates issue with evidence

## Deployment Locations

- **OAuth2-Proxy Config**: `terraform/modules/oauth2-proxy/`
- **Secrets Source**: Google Secret Manager (gcloud)
- **Service**: oauth2-proxy (port 4180)
- **Health Check**: `curl http://localhost:4180/ping`

## Exit Codes

- **0**: Deployment successful
- **1**: Deployment failed
- **2**: Verification failed post-deployment

## Rollback

If deployment fails:

```bash
bash ISSUE-984-ROLLBACK-PROCEDURE.sh
```

For detailed information, see COMPLETE-DEPLOYMENT-AND-OPERATIONS-PLAYBOOK.md
