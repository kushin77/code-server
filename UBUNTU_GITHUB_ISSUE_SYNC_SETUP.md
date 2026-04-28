# Ubuntu GitHub Issue Sync Setup Guide

## Problem
After moving from Windows to Ubuntu, GitHub issue sync via Copilot prompts stopped working because:
- GitHub CLI (`gh`) is not installed
- GitHub authentication token is not configured
- Environment variables are not set up

## Solution: Complete Setup

### Step 1: Install GitHub CLI

```bash
# Add GitHub CLI repository (Ubuntu/Debian)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt-get update
sudo apt-get install -y gh

# Verify installation
gh --version
```

### Step 2: Authenticate GitHub CLI

#### Option A: Interactive Authentication (Recommended for Workstation)
```bash
gh auth login

# When prompted:
# - Choose: GitHub.com
# - Choose: HTTPS
# - Choose: Paste an authentication token
# - Paste your fine-grained GitHub token (from GitHub Settings → Developer settings → Personal access tokens)

# Verify
gh auth status
```

#### Option B: Environment Variable Authentication (for scripts)
```bash
# Create fine-grained token on GitHub:
# https://github.com/settings/tokens?type=beta
# 
# Required scopes:
#   ✓ repo:read, repo:write
#   ✓ issues:read, issues:write  
#   ✓ pull_requests:read, pull_requests:write
#   ✓ projects:read (for Projects board sync)

export GITHUB_TOKEN="github_pat_XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
export GITHUB_REPO="kushin77/code-server"

# Test
gh auth status
```

#### Option C: Using Google Secret Manager (Production Setup)
```bash
# Prerequisites: gcloud CLI installed and authenticated
# First time setup:
gcloud secrets create github-fine-grained-token \
  --replication-policy="automatic" \
  --data-file=-  # Paste token when prompted

# Verify
gcloud secrets versions access latest --secret="github-fine-grained-token"

# Scripts will auto-retrieve the token via:
# TOKEN=$(gcloud secrets versions access latest --secret="github-fine-grained-token")
```

### Step 3: Configure Shell Environment

Add to `~/.bashrc` or `~/.zshrc` (depending on your shell):

```bash
# GitHub Configuration
export GITHUB_REPO="kushin77/code-server"
export GITHUB_OWNER="kushin77"

# Option 1: If using direct token (development)
# export GITHUB_TOKEN="github_pat_XXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# Option 2: If using gh CLI authentication (recommended)
# Token will be automatically managed by gh CLI

# Option 3: If using GSM (production)
# Uncomment this to load token from GSM on shell start:
# export GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-fine-grained-token" 2>/dev/null || echo "")
```

Then reload:
```bash
source ~/.bashrc
# or
source ~/.zshrc
```

### Step 4: Test the Integration

```bash
# Test 1: Verify gh CLI authentication
gh auth status

# Test 2: List recent issues
gh issue list --repo kushin77/code-server --limit 5

# Test 3: Test sync script (dry-run)
bash scripts/automation/sync-projects-board-status.sh 123 --dry-run

# Test 4: Check API governance
bash scripts/ci/check-github-api-governance.sh

# Test 5: Verify token scopes
gh auth status --show-token
```

### Step 5: VS Code Copilot Configuration

1. **Open VS Code Settings** (Cmd+, / Ctrl+,)
2. **Search for "Copilot"** settings
3. **Ensure these are configured:**
   - `Copilot: Github: Token` → Ensure GITHUB_TOKEN env var is available
   - `Copilot: Github: Repository` → Set to `kushin77/code-server`
   - Enable GitHub issue sync if there's a toggle

4. **Restart VS Code** to apply environment variables

### Step 6: Configure GitHub Projects Board (If Using Board Sync)

```bash
# Find your Projects board ID:
gh project list --owner kushin77 --format json | jq '.[] | {title, id}'

# Set environment variable (add to ~/.bashrc or ~/.zshrc):
export GITHUB_PROJECT_ID="your_project_id_here"
```

## Troubleshooting

### Issue: "gh: command not found"
```bash
# Solution: Reinstall or add to PATH
export PATH="/usr/local/bin:$PATH"
which gh
```

### Issue: "Authentication token not found"
```bash
# Solution: Authenticate gh CLI
gh auth logout  # Clear cached auth
gh auth login   # Re-authenticate
```

### Issue: Rate limit errors
```bash
# Solution: Check current rate limits
gh api rate_limit

# If limited, wait ~1 hour or use a new token with more quota
```

### Issue: "github_api_client.sh" fails with token error
```bash
# Solution: Verify token is accessible
# Check fallback order in github-api-client.sh:
# 1. GITHUB_TOKEN env var
# 2. Google Secret Manager (if gcloud available)
# 3. Error

# For GSM, ensure authenticated:
gcloud auth list
gcloud auth application-default login
```

### Issue: Copilot still can't sync issues
```bash
# Solution: Verify all prerequisites
1. gh --version                    # GitHub CLI installed?
2. gh auth status                  # Authenticated?
3. gh issue list --limit 1         # Can access repo?
4. echo $GITHUB_TOKEN              # Token set?
5. echo $GITHUB_REPO               # Repo set?

# Restart VS Code and extension:
# Command Palette → Developer: Reload Window
```

## Quick Verification Checklist

- [ ] GitHub CLI installed: `gh --version`
- [ ] GitHub authenticated: `gh auth status`
- [ ] Can list issues: `gh issue list --repo kushin77/code-server --limit 5`
- [ ] Can create test issue: `gh issue create --repo kushin77/code-server --title "Test"`
- [ ] Environment variables set: `echo $GITHUB_REPO`
- [ ] VS Code Copilot recognizes token: Restart and test
- [ ] Sync script works: `bash scripts/automation/sync-projects-board-status.sh 1 --dry-run`

## References

- GitHub CLI Docs: https://cli.github.com/manual
- Fine-grained Token Setup: https://github.com/settings/tokens?type=beta
- Google Secret Manager: https://cloud.google.com/secret-manager/docs
- Related Scripts:
  - `scripts/_common/github-api-client.sh` - Core API client
  - `scripts/automation/sync-projects-board-status.sh` - Issue sync automation
  - `scripts/ci/gh-wrapper.sh` - GitHub CLI governance

