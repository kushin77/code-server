# GitHub Issue Sync on Ubuntu - Quick Reference

## TL;DR: What Broke

After moving from Windows to Ubuntu, GitHub issue sync stopped because:
- ❌ GitHub CLI (`gh`) not installed  
- ❌ GitHub authentication token not configured
- ❌ Environment variables not set (`GITHUB_TOKEN`, `GITHUB_REPO`)

## TL;DR: The Fix

```bash
# 1. Run the automated setup script (prompts for sudo password)
bash setup-github-issue-sync-ubuntu.sh

# 2. When prompted, create a token at: https://github.com/settings/tokens?type=beta
#    Required scopes:
#    ✓ repo:read, repo:write
#    ✓ issues:read, issues:write
#    ✓ pull_requests:read, pull_requests:write
#    ✓ projects:read

# 3. Paste token when gh auth login asks

# 4. Reload your shell
source ~/.bashrc  # or ~/.zshrc

# 5. Restart VS Code (Cmd+Q, then reopen)

# 6. Test it worked
gh issue list --repo kushin77/code-server --limit 5
```

## What You'll Get Back

✅ GitHub CLI integration with Copilot  
✅ Issue sync to GitHub Projects board  
✅ `gh` command available in terminal  
✅ GitHub issue creation/management in prompts  
✅ Sync scripts working properly  

## Key Files

| File | Purpose |
|------|---------|
| `setup-github-issue-sync-ubuntu.sh` | **Automated setup** (run this first) |
| `UBUNTU_GITHUB_ISSUE_SYNC_SETUP.md` | Detailed manual setup guide |
| `scripts/_common/github-api-client.sh` | Core API client (auto-loaded by scripts) |
| `scripts/automation/sync-projects-board-status.sh` | Issue sync automation |

## Troubleshooting

### "gh: command not found"
```bash
# GitHub CLI not installed or PATH issue
which gh
# If empty, run setup script again and restart terminal
```

### "Error: must authenticate"
```bash
# Token not recognized
gh auth logout
gh auth login
# Paste token when prompted
```

### "Copilot still can't see issues"
```bash
# Verify all components
gh auth status          # Should show authenticated
gh repo view kushin77/code-server  # Should show repo info
echo $GITHUB_TOKEN      # Should show token (if using env var)

# Then restart VS Code completely
```

### Rate limit errors
```bash
# GitHub API temporarily limited (recovers in ~1 hour)
gh api rate_limit       # Check current limits
# Use a new token with more quota if needed
```

## Automation Scripts Reference

These scripts handle the actual GitHub syncing (no action needed after setup):

| Script | Purpose |
|--------|---------|
| `sync-projects-board-status.sh` | Syncs issue state to GitHub Projects board |
| `github-api-client.sh` | Handles all GitHub API calls with retry/rate-limit logic |
| `github-token-rotation.sh` | Manages token lifecycle (90-day rotation) |
| `gh-wrapper.sh` | Enforces governance on GitHub CLI usage |

## Environment After Setup

```bash
# Shell will have these configured:
export GITHUB_REPO="kushin77/code-server"      # Your repository
export GITHUB_OWNER="kushin77"                  # Repository owner
# GITHUB_TOKEN managed automatically by gh CLI

# VS Code will recognize these and enable Copilot integrations
```

## Need More Help?

See [UBUNTU_GITHUB_ISSUE_SYNC_SETUP.md](UBUNTU_GITHUB_ISSUE_SYNC_SETUP.md) for:
- Detailed step-by-step guide
- Google Secret Manager (GSM) setup for production
- Advanced troubleshooting
- GitHub token creation walkthrough

## One-Liner Test

```bash
# If this works, you're all set:
gh issue create --repo kushin77/code-server --title "Ubuntu Setup Test" --body "Testing GitHub issue sync on Ubuntu" && \
gh issue list --repo kushin77/code-server --limit 1
```

---

**Status**: Windows → Ubuntu Migration Support  
**Created**: April 28, 2026  
**Setup Time**: ~5 minutes (mostly automated)  
**All Components**: GitHub CLI, authentication, shell config, VS Code integration  
