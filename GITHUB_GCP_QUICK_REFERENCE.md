# GitHub Issue Sync with GCP GSM - Quick Reference

**Status**: ✅ READY TO DEPLOY  
**Method**: Retrieve token from Google Secret Manager  
**Time**: ~10 minutes  
**Entry Point**: `setup-github-gcp-integration.sh`  

---

## 🚀 START HERE - Fastest Path

```bash
cd /home/akushnir/code-server
bash setup-github-gcp-integration.sh
```

This will:
1. Check GCP authentication (prompts if needed)
2. Install GitHub CLI
3. Retrieve your token from GSM
4. Configure everything
5. Verify it works

---

## ⏱️ If Already GCP Authenticated

```bash
bash setup-github-gcp-quick.sh
```

Much faster - skips authentication checks.

---

## 🔐 GCP Authentication Required

First time only - authenticate to GCP:

```bash
gcloud auth application-default login
```

This opens a browser window. Complete login, return to terminal. Then run the setup script.

---

## ✅ Verify Success

After setup completes:

```bash
# Reload shell
source ~/.bashrc

# Check authentication
gh auth status

# List issues
gh issue list --repo kushin77/code-server --limit 5

# Restart VS Code - Cmd+Q and reopen
```

---

## 🎯 What's Different from Manual Setup

| Aspect | Manual | GCP GSM |
|--------|--------|---------|
| Token entry | Copy-paste token | Retrieved automatically |
| Security | Token in shell config | Stored in GSM |
| Rotation | Manual regeneration | Update in GSM |
| Production-ready | No | Yes |

---

## 📂 New Files Created

```
setup-github-gcp-integration.sh    8.4 KB   Full setup
setup-github-gcp-quick.sh          2.8 KB   Quick setup  
GITHUB_GCP_INTEGRATION.md          8.2 KB   Full docs
GITHUB_GCP_QUICK_REFERENCE.md             This file
```

---

## 🔧 Technical Details

**What Script Does**:
- Verifies GCP SDK installed (gcloud command)
- Authenticates to GCP if needed
- Retrieves token from GSM secret: `github-fine-grained-token`
- Installs GitHub CLI (gh command)
- Configures gh with the retrieved token
- Sets environment variables: GITHUB_REPO, GITHUB_OWNER, GCP_PROJECT
- Tests everything works

**Token Location**:
```
GCP Project: purebliss-ghl
GSM Secret: github-fine-grained-token
```

**Environment Configured**:
```bash
export GITHUB_REPO="kushin77/code-server"
export GITHUB_OWNER="kushin77"
export GCP_PROJECT="purebliss-ghl"
```

---

## ⚠️ Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| "cannot prompt during non-interactive execution" | Run: `gcloud auth application-default login` first |
| "Permission denied" on secret | Admin needs to grant Secret Accessor role in GCP |
| "gh: command not found" | Try manual install: `sudo apt-get install gh` |
| Copilot still can't access | Restart VS Code (File → Close Window, reopen) |

---

## 📖 Full Documentation

See `GITHUB_GCP_INTEGRATION.md` for:
- Detailed troubleshooting
- Token refresh procedures
- Production usage
- Architecture explanation

---

## ✨ What Gets Fixed

✅ GitHub CLI installed  
✅ GitHub authentication configured  
✅ Token retrieved from GSM securely  
✅ Environment variables set  
✅ VS Code Copilot issue sync enabled  
✅ Terminal `gh` commands working  

---

## 🎬 Execution

```bash
# One command to fix everything:
bash setup-github-gcp-integration.sh

# Then:
source ~/.bashrc
# Restart VS Code
```

That's it! GitHub issue sync will work.

---

**Ready to execute**: YES  
**Time required**: 10 minutes  
**Prerequisites**: GCP authentication  
**Next step**: Run `bash setup-github-gcp-integration.sh`
