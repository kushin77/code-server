# GitHub Issue Sync - Ubuntu Setup Complete ✓

Your GitHub issue sync infrastructure has been diagnosed and fixed. Everything is ready to implement now.

## 🚀 START HERE

You have **2 options** to restore GitHub issue sync on Ubuntu:

### Option A: Automated Setup (Recommended)
```bash
cd /home/akushnir/code-server
bash setup-github-issue-sync-ubuntu.sh
```
This runs all steps automatically. It will:
1. Install GitHub CLI
2. Prompt you to authenticate (paste your token)
3. Configure environment variables
4. Verify everything works

**Note**: It will ask for your sudo password during installation.

---

### Option B: Manual Step-by-Step
If you prefer to run commands individually:

**Step 1: Install GitHub CLI**
```bash
bash install-gh-cli.sh
```

**Step 2: Authenticate with GitHub**
```bash
gh auth login
```
When prompted:
- Choose: **HTTPS**
- Paste your fine-grained token from: https://github.com/settings/tokens?type=beta

**Step 3: Configure Environment**
```bash
bash configure-github-ubuntu.sh
```

**Step 4: Reload Shell**
```bash
source ~/.bashrc  # or ~/.zshrc
```

**Step 5: Restart VS Code**
```bash
# Close and reopen VS Code completely
```

---

## 📋 What You Need Before Starting

1. **GitHub Account Access** - Must be able to log into github.com
2. **Sudo Password** - Required to install gh CLI (just Ubuntu user password)
3. **GitHub Fine-Grained Token** - Will be created during setup

---

## 🔑 Create Your GitHub Token (Do This First)

1. Go to: https://github.com/settings/tokens?type=beta
2. Click **"Generate new token"** → **"Generate new fine-grained personal access token"**
3. Set:
   - **Name**: Ubuntu Workstation
   - **Expiration**: 90 days
   - **Repository access**: kushin77/code-server
   - **Scopes**: 
     - ✓ repo:read, repo:write
     - ✓ issues:read, issues:write  
     - ✓ pull_requests:read, pull_requests:write
     - ✓ projects:read
4. Click **"Generate token"** and **COPY IT IMMEDIATELY**
5. It looks like: `github_pat_XXXXXXXXXXXXXXXXXXXXXXXXXXXX`

Keep this token handy - you'll need it when the setup asks "Paste your authentication token"

---

## ✅ Verify It Works

After setup completes, run:

```bash
# Check GitHub CLI
gh auth status

# List issues from your repo
gh issue list --repo kushin77/code-server --limit 5

# Create a test issue
gh issue create --repo kushin77/code-server --title "Ubuntu Setup Test" --body "Testing"
```

All three should work without errors.

---

## 📁 Setup Files Created

| File | Purpose |
|------|---------|
| `setup-github-issue-sync-ubuntu.sh` | Full automated setup (recommended) |
| `install-gh-cli.sh` | Just install GitHub CLI |
| `configure-github-ubuntu.sh` | Just configure auth & environment |
| `IMPLEMENTATION_GUIDE_UBUNTU.md` | Detailed step-by-step guide |
| `UBUNTU_GITHUB_ISSUE_SYNC_SETUP.md` | Complete reference manual |
| `GITHUB_ISSUE_SYNC_QUICK_START.md` | Quick troubleshooting reference |

---

## 🆘 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| "sudo: authenticate" prompt | Enter your Ubuntu user password |
| "gh: command not found" | Terminal needs reload - close and reopen it |
| "Token not found" | Verify token generated at https://github.com/settings/tokens?type=beta |
| Copilot still can't sync | Restart VS Code completely (File → Close Window) |
| Rate limit errors | Check: `gh api rate_limit` (recovers in ~1 hour) |

---

## 🎯 What Gets Fixed

After completing setup:

✅ GitHub CLI installed and working  
✅ GitHub authentication configured  
✅ Environment variables set (GITHUB_REPO, GITHUB_OWNER)  
✅ Copilot can sync GitHub issues  
✅ `gh issue` commands work in terminal  
✅ GitHub Projects board sync active  
✅ All sync infrastructure ready  

---

## 📞 Need Help?

See detailed guides:
- **Quick Start**: GITHUB_ISSUE_SYNC_QUICK_START.md
- **Full Guide**: UBUNTU_GITHUB_ISSUE_SYNC_SETUP.md
- **Step-by-Step**: IMPLEMENTATION_GUIDE_UBUNTU.md

---

## ⏱️ Time Required

- **Automated setup**: ~5 minutes
- **Manual setup**: ~15 minutes

---

## 🎬 Ready? Start Here:

```bash
bash setup-github-issue-sync-ubuntu.sh
```

Or if that fails, read IMPLEMENTATION_GUIDE_UBUNTU.md for manual steps.

---

**Status**: Windows → Ubuntu Migration Fix - Ready to Deploy  
**Date**: April 28, 2026  
**Next Step**: Run the setup script above ⬆️
