# GitHub Actions Secrets Configuration Guide

**Status:** ✅ READY FOR SETUP  
**Date:** May 1, 2026

---

## Overview

Before deploying Phases 4-7 using the automated workflows, you must configure the following GitHub Actions secrets. These secrets are required for:

1. **Azure Kubernetes Service (AKS) provisioning**
2. **Docker host SSH access for data migration**
3. **VS Code Marketplace extension publishing**
4. **Security scanning and vulnerability detection**
5. **Slack notifications**

---

## Required Secrets

### 1. Azure Deployment Credentials

#### `AZURE_CREDENTIALS`
**Purpose**: Provision and manage Azure AKS clusters  
**Type**: JSON object (Azure Service Principal)

**How to Create:**
```bash
# Step 1: Create an Azure service principal
az ad sp create-for-rbac \
  --name "code-server-deployment-bot" \
  --role "Contributor" \
  --scopes "/subscriptions/<SUBSCRIPTION_ID>"

# Output will include: appId, displayName, password, tenant
# Store the output for next step
```

**Format**:
```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

**GitHub Steps**:
1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `AZURE_CREDENTIALS`
4. Paste the JSON output from `az ad sp create-for-rbac`
5. Click "Add secret"

---

#### `DOCKER_HOST_IP`
**Purpose**: IP address of Docker HA primary node  
**Type**: String  
**Value**: `192.168.168.31`

**GitHub Steps**:
1. Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `DOCKER_HOST_IP`
4. Value: `192.168.168.31`
5. Click "Add secret"

---

#### `DOCKER_HOST_SSH_KEY`
**Purpose**: SSH private key for accessing Docker host  
**Type**: Private key (PEM format)

**How to Create**:
```bash
# If you don't have an SSH key for the Docker host, create one:
ssh-keygen -t rsa -b 4096 -f ~/.ssh/docker-host-key -N ""

# Get the private key (for GitHub secret)
cat ~/.ssh/docker-host-key

# Get the public key (for Docker host authorization)
cat ~/.ssh/docker-host-key.pub
```

**Authorization on Docker Host**:
```bash
# SSH to Docker host as akushnir user
ssh akushnir@192.168.168.31

# Add public key to authorized_keys
mkdir -p ~/.ssh
cat >> ~/.ssh/authorized_keys << 'EOF'
ssh-rsa AAAA... (paste public key here)
EOF

chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

**GitHub Steps**:
1. Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `DOCKER_HOST_SSH_KEY`
4. Value: (paste entire private key, including `-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----`)
5. Click "Add secret"

---

### 2. Extension Publishing Credentials

#### `VSCODE_MARKETPLACE_TOKEN`
**Purpose**: Publish extension to VS Code Marketplace  
**Type**: Personal Access Token  
**Provider**: Visual Studio Marketplace

**How to Create**:
1. Go to: https://marketplace.visualstudio.com/manage/publishers
2. Sign in or create a publisher account
3. Click your profile → Personal access tokens
4. Click "New token"
5. Name: `code-server-deployment`
6. Scopes: `Publish`
7. Expiration: 90 days or longer
8. Create token
9. Copy token (you'll only see it once)

**GitHub Steps**:
1. Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `VSCODE_MARKETPLACE_TOKEN`
4. Value: (paste the token)
5. Click "Add secret"

---

#### `OPEN_VSX_TOKEN`
**Purpose**: Publish extension to Open VSX Registry  
**Type**: Personal Access Token  
**Provider**: OpenVSX.dev

**How to Create**:
1. Go to: https://open-vsx.org
2. Click "Login" → Create account (if needed)
3. Click your profile → "Access Tokens"
4. Click "Generate"
5. Name: `code-server-deployment`
6. Copy token

**GitHub Steps**:
1. Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `OPEN_VSX_TOKEN`
4. Value: (paste the token)
5. Click "Add secret"

---

### 3. Security Scanning

#### `SNYK_TOKEN`
**Purpose**: Scan dependencies for security vulnerabilities  
**Type**: API Token  
**Provider**: Snyk.io

**How to Create**:
1. Go to: https://app.snyk.io/account/settings (create account if needed)
2. Click "Auth Token"
3. Copy the token

**GitHub Steps**:
1. Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `SNYK_TOKEN`
4. Value: (paste the token)
5. Click "Add secret"

---

### 4. Notifications

#### `SLACK_WEBHOOK`
**Purpose**: Send deployment notifications to Slack  
**Type**: Webhook URL  
**Provider**: Slack Workspace

**How to Create**:
1. Go to your Slack workspace
2. Create a new channel: `#deployments` (or use existing)
3. Go to: https://api.slack.com/apps
4. Click "Create New App"
5. Select "From scratch"
6. Name: `code-server-deployment-bot`
7. Select your workspace
8. Click "Create App"
9. Go to "Incoming Webhooks" in left sidebar
10. Toggle "Activate Incoming Webhooks" ON
11. Click "Add New Webhook to Workspace"
12. Select channel: `#deployments`
13. Click "Allow"
14. Copy the "Webhook URL"

**GitHub Steps**:
1. Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `SLACK_WEBHOOK`
4. Value: (paste the webhook URL)
5. Click "Add secret"

---

### 5. Auto-Generated Secrets

#### `GITHUB_TOKEN`
**Purpose**: GitHub API access for workflow operations  
**Type**: Auto-generated  
**Provider**: GitHub Actions

**Status**: ✅ Already available - No setup required

This token is automatically available in all GitHub Actions workflows without manual configuration.

---

## Verification Steps

After adding all secrets, verify they're accessible:

```bash
# Via GitHub CLI (if installed)
gh secret list --repo kushin77/code-server

# Expected output:
# AZURE_CREDENTIALS     ***
# DOCKER_HOST_IP        ***
# DOCKER_HOST_SSH_KEY   ***
# VSCODE_MARKETPLACE_TOKEN ***
# OPEN_VSX_TOKEN        ***
# SNYK_TOKEN            ***
# SLACK_WEBHOOK         ***
```

---

## Security Best Practices

1. **Token Rotation**
   - Rotate tokens every 90 days
   - Use workspace-specific tokens (not personal)
   - Revoke old tokens after rotation

2. **Least Privilege**
   - Give tokens only necessary scopes
   - Azure: `Contributor` role (minimum needed for cluster provisioning)
   - VS Code: `Publish` scope only
   - Snyk: Default scopes (read-only)

3. **Access Control**
   - Restrict secret access to required workflows
   - Only store production credentials
   - Use branch protection rules

4. **Monitoring**
   - Review secret access logs regularly
   - Monitor workflow runs for failures
   - Set up Slack alerts for deployment status

---

## Troubleshooting

### "Secret not found" error in workflow
- Verify secret name matches exactly (case-sensitive)
- Check secret is added to repository (not organization)
- Ensure workflow has correct repository access

### Azure authentication fails
```
Error: Failed to authenticate with Azure
```
- Verify Azure service principal credentials are valid
- Check subscription ID is correct
- Ensure service principal has `Contributor` role
- Test locally: `az login --service-principal -u <client-id> -p <secret> --tenant <tenant>`

### Docker SSH fails
```
Error: Permission denied (publickey)
```
- Verify Docker host SSH key is correctly formatted
- Check public key is added to `~/.ssh/authorized_keys` on Docker host
- Test locally: `ssh -i ~/.ssh/docker-host-key akushnir@192.168.168.31`

### Marketplace token rejected
```
Error: 401 Unauthorized
```
- Verify token is from correct publisher account
- Check token expiration date
- Test with: `npm login` → `npm publish --dry-run`

---

## Environment-Specific Secrets

For different environments (staging vs production), create environment-specific secrets:

### Staging Environment

1. Go to Settings → Environments
2. Click "New environment"
3. Name: `staging`
4. Add staging-specific secrets:
   - `AZURE_CREDENTIALS` (staging service principal)
   - `DOCKER_HOST_IP` (staging Docker host: 192.168.168.41)

### Production Environment

1. Go to Settings → Environments
2. Click "New environment"
3. Name: `production`
4. Add required reviewers (code owners)
5. Add production-specific secrets:
   - `AZURE_CREDENTIALS` (production service principal)
   - `DOCKER_HOST_IP` (production Docker host: 192.168.168.31)

---

## Next Steps

1. ✅ Add all required secrets (from above)
2. ✅ Verify secrets are accessible
3. ✅ Test secret access via workflow run
4. ➡️ Trigger Phase 4-7 orchestration workflow
5. ➡️ Monitor deployment progress

---

## Quick Reference

| Secret Name | Required | Type | Expiration |
|---|---|---|---|
| AZURE_CREDENTIALS | ✅ | Service Principal | Never (app) |
| DOCKER_HOST_IP | ✅ | String | N/A |
| DOCKER_HOST_SSH_KEY | ✅ | Private Key | Never |
| VSCODE_MARKETPLACE_TOKEN | ✅ | Personal Token | 90+ days |
| OPEN_VSX_TOKEN | ✅ | Personal Token | N/A |
| SNYK_TOKEN | ✅ | API Token | 90+ days |
| SLACK_WEBHOOK | ❌ | Webhook URL | N/A |
| GITHUB_TOKEN | ✅ | Auto-generated | Per workflow |

---

## Support

For issues with secrets or authentication:

1. Check GitHub documentation: https://docs.github.com/en/actions/security-guides/encrypted-secrets
2. Review workflow logs: Settings → Actions → Recent workflow runs
3. Test credentials locally before adding to GitHub
4. Contact platform team if additional permissions needed

---

*Last Updated: May 1, 2026*
