# GitHub Issue Sync Fix for Ubuntu - Implementation Guide

**Status**: Ready to execute  
**Time Required**: 10-15 minutes  
**Prerequisites**: Linux terminal access with sudo permissions

---

## Quick Start (Copy-Paste Commands)

### Phase 1: Install GitHub CLI (requires sudo password)

```bash
# Run this command - it will ask for your sudo password
bash /home/akushnir/code-server/install-gh-cli.sh
```

**What it does**:
- Adds GitHub CLI repository
- Updates package lists
- Installs `gh` command-line tool
- Verifies installation

**Expected output**:
```
✓ Installation complete!
gh version X.Y.Z (YYYY-MM-DD)
```

---

### Phase 2: Create GitHub Fine-Grained Token

**Do this in a web browser** (can be done while Phase 1 installs):

1. Open: https://github.com/settings/tokens?type=beta
2. Click **"Generate new token"** → **"Generate new fine-grained personal access token"**
3. Fill in:
   - **Token name**: `Ubuntu Workstation`
   - **Expiration**: 90 days
   - **Repository access**: Select `kushin77/code-server`
   - **Permissions** (check these boxes):
     - `repo:read`, `repo:write`
     - `issues:read`, `issues:write`
     - `pull_requests:read`, `pull_requests:write`
     - `projects:read`

4. Click **"Generate token"** at bottom
5. **COPY the token immediately** (looks like: `github_pat_XXXXXXXXXXXXXXXXXXXXXXXXXXXXX`)
   - ⚠️ This is your only chance to copy it - save it somewhere safe

---

### Phase 3: Authenticate GitHub CLI

```bash
# Run this command
gh auth login

# When prompted, answer:
# What is your preferred protocol for Git operations? → HTTPS
# Authenticate Git with your GitHub credentials? → Y
# How would you like to authenticate GitHub CLI? → Paste an authentication token
# Paste your authentication token → [PASTE YOUR TOKEN FROM PHASE 2]
# Protocol: HTTPS
```

**Verify it worked**:
```bash
gh auth status
```

Should show:
```
github.com
  ✓ Logged in to github.com as YOUR_USERNAME
  ✓ Git operations for github.com configured to use HTTPS
```

---

### Phase 4: Configure Shell Environment

```bash
# Run this command
bash /home/akushnir/code-server/configure-github-ubuntu.sh
```

**What it does**:
- Verifies GitHub authentication
- Adds `GITHUB_REPO` and `GITHUB_OWNER` to your shell
- Tests repository access
- Provides verification commands

**After it completes**:
```bash
# Reload your shell with new variables
source ~/.bashrc
# or if using zsh:
source ~/.zshrc
```

---

### Phase 5: Restart VS Code & Test

```bash
# Close and restart VS Code completely:
# File → Close Window (or Cmd+Q / Ctrl+Q)
# Then reopen VS Code

# In terminal, verify:
gh issue list --repo kushin77/code-server --limit 5

# Should list your GitHub issues
```

---

## Troubleshooting During Setup

### Problem: "sudo: command not found" or permission denied

**Solution**: You need to provide your Ubuntu user password when installing gh CLI

```bash
bash /home/akushnir/code-server/install-gh-cli.sh
# When it says "[sudo: authenticate] Password:" → type your password
```

### Problem: "gh: command not found" after Phase 1

**Solution**: Terminal didn't reload. Restart your terminal:

```bash
# Close terminal completely, open new one
which gh
gh --version
```

### Problem: GitHub token generation failed

**Solution**: Make sure you're logged into GitHub.com:

1. Go to: https://github.com/login
2. Log in with your GitHub account
3. Then try token generation again at: https://github.com/settings/tokens?type=beta

### Problem: "Authentication failed" on `gh auth login`

**Check**:
- Token starts with `github_pat_` (not `ghp_`)
- Token hasn't expired
- You selected required scopes: repo, issues, pull_requests, projects
- You pasted the full token without extra spaces

**Recovery**:
```bash
gh auth logout
gh auth login
# Try again with correct token
```

### Problem: "Cannot access repository" error

**Check**:
```bash
# Verify your token has correct permissions
gh auth status --show-token

# Verify you can see the repo
gh repo view kushin77/code-server
```

If repo access fails, regenerate token with correct scopes (see Phase 2 above)

---

## Verification Checklist

After each phase, verify:

✅ **Phase 1**: `gh --version` shows version number  
✅ **Phase 2**: Token saved and starts with `github_pat_`  
✅ **Phase 3**: `gh auth status` shows "Logged in"  
✅ **Phase 4**: `echo $GITHUB_REPO` outputs `kushin77/code-server`  
✅ **Phase 5**: `gh issue list --repo kushin77/code-server --limit 1` shows an issue  

---

## What Gets Fixed

After completing this setup:

| Feature | Status |
|---------|--------|
| GitHub CLI (`gh` command) | ✅ Installed |
| GitHub authentication | ✅ Configured |
| Copilot issue sync | ✅ Enabled |
| Issue management in prompts | ✅ Working |
| GitHub Projects board sync | ✅ Active |
| Shell environment variables | ✅ Set |
| VS Code Copilot integration | ✅ Ready |

---

## Scripts Created

| Script | Purpose | Run When |
|--------|---------|----------|
| `install-gh-cli.sh` | Install GitHub CLI | Phase 1 |
| `configure-github-ubuntu.sh` | Configure auth & environment | Phase 4 |
| `setup-github-issue-sync-ubuntu.sh` | Complete automated setup | As backup |

---

## Reference Files

| File | Purpose |
|------|---------|
| `GITHUB_ISSUE_SYNC_QUICK_START.md` | Quick reference |
| `UBUNTU_GITHUB_ISSUE_SYNC_SETUP.md` | Detailed manual |
| `IMPLEMENTATION_GUIDE_UBUNTU.md` | This file - step-by-step |

---

## Questions or Issues?

**VS Code Copilot Issues**:
- Command Palette → `Copilot: Show GitHub Status`
- Restart VS Code if token not recognized

**GitHub CLI Issues**:
- Run: `gh auth troubleshoot`
- Check: https://cli.github.com/manual

**SSH/Connectivity Issues**:
- Ubuntu may have different network setup than Windows
- Verify: `gh api -H "Accept: application/vnd.github+json" /user`

---

## Timeline

- **Phase 1** (Install): 5 min
- **Phase 2** (Token): 2 min  
- **Phase 3** (Authenticate): 2 min
- **Phase 4** (Configure): 2 min
- **Phase 5** (Test & Restart): 3 min

**Total**: ~15 minutes

---

**Last Updated**: April 28, 2026  
**Status**: Ready for execution  
**Next Step**: Run Phase 1 - `bash /home/akushnir/code-server/install-gh-cli.sh`
