# GitHub Issue Sync with GCP GSM Integration

**Status**: ✅ Ready to Deploy  
**Approach**: Retrieve GitHub token from Google Secret Manager  
**Time**: ~10 minutes  
**Prerequisites**: GCP SDK installed, GCP authentication available  

---

## Overview

This setup uses your existing GitHub token stored in Google Secret Manager (GSM) on GCP project `purebliss-ghl` instead of manually creating a new token. This is more secure and aligns with your production infrastructure.

### What This Does

1. ✅ Verifies/installs GCP SDK (`gcloud` command)
2. ✅ Authenticates to GCP (uses application-default credentials)
3. ✅ Retrieves GitHub token from GSM secret `github-fine-grained-token`
4. ✅ Installs GitHub CLI (`gh` command)
5. ✅ Configures GitHub CLI with the retrieved token
6. ✅ Sets up environment variables for VS Code
7. ✅ Verifies everything works

---

## Quick Start

### Option 1: Full Setup (Recommended if Not Yet Authenticated to GCP)

This script handles authentication, installation, and configuration:

```bash
bash setup-github-gcp-integration.sh
```

**Will do**:
- Prompt for GCP authentication if needed
- Install GCP SDK if missing
- Install GitHub CLI
- Retrieve token from GSM
- Configure everything

### Option 2: Quick Setup (If Already GCP Authenticated)

If you're already authenticated to GCP:

```bash
bash setup-github-gcp-quick.sh
```

**Faster** because it skips authentication checks.

---

## Prerequisites

### Required

- [ ] GCP SDK (`gcloud` command) - installed on system
- [ ] GCP authentication available
  - Either: `gcloud auth application-default login`
  - Or: Service account credentials configured
- [ ] Access to GCP project `purebliss-ghl`
- [ ] Permission to read from GSM secrets

### GitHub Token Location

The script retrieves token from:
```
Project: purebliss-ghl
Secret: github-fine-grained-token
```

---

## Step-by-Step Execution

### Step 1: Check GCP Authentication

```bash
# Test if authenticated to GCP
gcloud auth application-default print-access-token

# Should output a long access token (starts with ya29...)
```

If this fails, authenticate first:

```bash
gcloud auth application-default login
# Opens browser window - complete login and return
```

### Step 2: Run Setup Script

```bash
# Option A: Full setup (handles auth)
bash setup-github-gcp-integration.sh

# Option B: Quick setup (assumes you're authenticated)
bash setup-github-gcp-quick.sh
```

### Step 3: When Prompted

- If asked for GCP authentication, complete browser login
- If asked to press Enter, just press Enter
- Scripts will handle the rest automatically

### Step 4: Verify Success

```bash
# Reload shell with new environment
source ~/.bashrc  # or ~/.zshrc

# Verify GitHub CLI
gh auth status

# Test repository access
gh issue list --repo kushin77/code-server --limit 5
```

### Step 5: Restart VS Code

```bash
# Close VS Code completely
# Reopen it - environment variables load on startup
```

---

## What Gets Configured

### GitHub CLI
```bash
# Token source: GCP GSM
# Repository: kushin77/code-server
# Authenticated as: Your GitHub account
```

### Environment Variables
```bash
export GITHUB_REPO="kushin77/code-server"
export GITHUB_OWNER="kushin77"
export GCP_PROJECT="purebliss-ghl"
```

### Shell Integration
- Added to `~/.bashrc` or `~/.zshrc`
- Loaded on shell startup
- Environment variables available to all commands and VS Code

---

## Verification

After setup, verify all components:

```bash
# Check GitHub CLI is installed and authenticated
gh auth status

# Should show:
# github.com
#   ✓ Logged in to github.com as YOUR_USERNAME
#   ✓ Git operations for github.com configured to use HTTPS

# Check environment variables
echo $GITHUB_REPO        # Should output: kushin77/code-server
echo $GITHUB_OWNER       # Should output: kushin77
echo $GCP_PROJECT        # Should output: purebliss-ghl

# Test GitHub access
gh repo view kushin77/code-server

# Test issue listing
gh issue list --repo kushin77/code-server --limit 5
```

---

## Troubleshooting

### Problem: "There was a problem refreshing your current auth tokens"

**Cause**: Not authenticated to GCP

**Solution**:
```bash
gcloud auth application-default login
# Complete browser authentication, then re-run setup script
```

### Problem: "ERROR (gcloud.secrets.versions.access) Permission denied"

**Cause**: Your account doesn't have access to the secret

**Solution**:
- Verify you have "Secret Accessor" role on the project
- Contact GCP admin to grant permissions
- Fallback to manual token (see manual setup guide)

### Problem: "gh: command not found"

**Cause**: GitHub CLI not installed properly

**Solution**:
```bash
# Try manual installation
bash setup-github-gcp-quick.sh
# or reinstall manually:
sudo apt-get install -y gh
```

### Problem: GitHub CLI shows "not authenticated"

**Cause**: Token wasn't set properly

**Solution**:
```bash
# Manually set token
GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-fine-grained-token")
echo "$GITHUB_TOKEN" | gh auth login --with-token
```

### Problem: VS Code Copilot still can't access GitHub

**Cause**: VS Code hasn't reloaded environment

**Solution**:
1. Close VS Code completely
2. Reload shell: `source ~/.bashrc`
3. Reopen VS Code
4. Verify: Command Palette → "Copilot: Show GitHub Status"

---

## Refreshing Token from GSM

If the token expires or you need to refresh it:

```bash
# Retrieve latest token from GSM
GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-fine-grained-token")

# Re-authenticate GitHub CLI
echo "$GITHUB_TOKEN" | gh auth login --with-token

# Verify
gh auth status
```

Or add this command to your shell profile to load automatically:

```bash
# In ~/.bashrc or ~/.zshrc
export GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-fine-grained-token" 2>/dev/null || echo "")
```

---

## Why GSM Integration?

### Advantages

✅ **Secure**: Token stored in Google Secret Manager, not in shell profile  
✅ **Centralized**: Single source of truth for token (easier management)  
✅ **Production-aligned**: Matches your deployment infrastructure  
✅ **Rotatable**: Token can be rotated in GSM without code changes  
✅ **Auditable**: All secret access logged in GCP audit logs  

### How It Works

1. Script authenticates to GCP using application-default credentials
2. Retrieves token from GSM secret `github-fine-grained-token`
3. Configures GitHub CLI with that token
4. Token lives in gh CLI's secure storage (not in plain text)

---

## Reference Files

| File | Purpose |
|------|---------|
| `setup-github-gcp-integration.sh` | Full setup (handles auth, install, config) |
| `setup-github-gcp-quick.sh` | Quick setup (assumes GCP auth exists) |
| `GITHUB_GCP_INTEGRATION.md` | This guide |

---

## Next Steps

1. **Verify GCP authentication**: `gcloud auth application-default print-access-token`
2. **Run setup**: `bash setup-github-gcp-integration.sh`
3. **Reload shell**: `source ~/.bashrc`
4. **Restart VS Code**
5. **Verify**: `gh auth status`

---

## Support

For issues:
1. Check troubleshooting section above
2. Verify GCP access: `gcloud secrets list`
3. Check token in GSM: `gcloud secrets versions list --secret="github-fine-grained-token"`
4. Test gh CLI directly: `gh --version` and `gh auth status`

---

**Status**: Ready for execution  
**Date**: April 28, 2026  
**Integration**: GCP Secret Manager (purebliss-ghl)
