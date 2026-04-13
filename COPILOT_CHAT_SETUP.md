# ✅ GitHub Copilot Chat - Setup & Activation Guide

**Status**: ✅ **INSTALLED AND READY**

Both GitHub Copilot extensions are already installed and configured in your code-server instance:
- ✅ `github.copilot` (base Copilot extension)
- ✅ `github.copilot-chat` (chat interface)

---

## 🎯 Quick Star

### 1. **Verify Installation** (Optional)

In code-server, open the Extensions view (Ctrl+Shift+X) and check for:
- GitHub Copilo
- GitHub Copilot Cha

Both should show as "Installed" with a green checkmark.

### 2. **Authenticate with GitHub**

Copilot Chat requires a GitHub Copilot subscription or free trial:

#### Option A: GitHub Copilot Free (Recommended)
1. Go to: https://github.com/settings/copilo
2. Click "Copy activation code"
3. In code-server, press `Ctrl+Shift+P` (Windows) or `Cmd+Shift+P` (Mac)
4. Search for "GitHub: Authorize with GitHub Copilot"
5. Paste the activation code
6. Authorize the GitHub app in your browser
7. Return to code-server - you're authenticated!

#### Option B: GitHub Copilot Business/Enterprise
- Contact your enterprise admin for access and configuration

### 3. **Enable Chat Interface**

Once authenticated, open Copilot Chat:
- **Keyboard Shortcut**: `Ctrl+L` (Windows) or `Cmd+L` (Mac)
- **VS Code Command**: Press `Ctrl+Shift+P`, type "Copilot Chat: Focus Chat"
- **UI**: Click the Copilot icon in the sidebar

---

## 🚀 Usage Examples

### Inline Chat (Quick edits)
Press `Ctrl+I` in your editor and describe a code change:

Make this function async
Add error handling
Optimize this loop


### Chat Panel (Full conversations)
Press `Ctrl+L` for the chat panel. Ask:

Explain this code to me
How do I fix this error?
Generate unit tests for this function
Refactor this for readability


### Agent Mode (Autonomous tasks)
Use chat to delegate complex tasks:

Implement user authentication with JW
Create a CI/CD pipeline for this repo
Debug this failing test and fix i
Refactor the entire auth module


---

## 🔐 Architecture & Security

### How Copilot Chat Works in code-server

1. **Extensions Downloaded at Build Time**
   - File: [Dockerfile.code-server](../Dockerfile.code-server) (lines 20-27)
   - Extensions are cached in `/opt/vsix/` for faster startup

2. **GitHub Authentication**
   - OAuth flow happens in your browser
   - Tokens are securely stored in code-server's encrypted state
   - OAuth2-Proxy provides an additional authentication layer (optional)

3. **Patched Configuration** (product.json)
   - Copilot Chat added to `trustedExtensionAuthAccess
   - Without this, Copilot Chat can't access GitHub tokens
   - Automatic `defaultChatAgent` removal prevents install loops

4. **Entrypoint Script**
   - File: [scripts/code-server-entrypoint.sh](../scripts/code-server-entrypoint.sh)
   - Automatically installs extensions on startup if missing
   - Idempotent: safe to run multiple times

---

## 📋 System Requirements Me

✅ **Code-Server Version**: 4.115.0 (latest)
✅ **Copilot Chat Compatibility**: Latest version (auto-downloaded)
✅ **Network Access**: Required (Copilot API calls to GitHub)
✅ **GitHub Account**: Required (free tier supported)
✅ **VS Code Version Parity**: Synchronized with base VS Code

---

## 🔧 Troubleshooting

### Copilot Chat Not Activating

**Problem**: Extensions show installed but chat doesn't work

**Solution**:
1. Verify GitHub authentication:
   - Click Copilot icon → "Sign in with GitHub"
   - Complete the OAuth flow

2. Check extension compatibility:
   ```bash
   docker exec code-server code-server --list-extensions

   Both `github.copilot` and `github.copilot-chat` should appear

3. Rebuild container to get latest extensions:
   ```bash
   docker compose down
   docker compose build --no-cache code-server
   docker compose up -d


### "Copilot Chat Extension Not Found" Error

**Cause**: Extensions didn't download properly during build

**Solution**:
```bash
# Rebuild with fresh extension downloads
docker compose build --no-cache code-server
docker compose up -d

# Check logs
docker compose logs code-server | grep -i copilo


### GitHub Token Issues

**Problem**: "Failed to authenticate with GitHub"

**Solution**:
1. Visit: https://github.com/settings/tokens
2. Create new token with `gist`, `user:email` scopes
3. In code-server: `Ctrl+Shift+P` → "GitHub: Sign Out"
4. Re-authenticate with new token

### Slow Chat Responses

**Cause**: Network latency or Copilot API rate limits

**Solution**:
1. Check internet connectivity
2. Wait a few minutes if rate-limited
3. Ensure adequate code-server resources: `make status

---

## 📚 Cloud Provider Suppor

### GCP (Google Cloud Platform)
- ✅ Fully supported
- Use with Cloud Code extension for integrated debugging
- Works with CloudSQL, Cloud Run, etc.

### Azure
- ✅ Fully supported
- Pairs well with Azure CLI extension
- GitHub Copilot works with Azure DevOps repos

### AWS
- ✅ Fully supported
- Integrates with AWS CLI, CloudFormation, etc.

### Other Clouds
- ✅ Works on any cloud with internet access
- Requires GitHub connectivity only

---

## 🎓 Best Practices

### For Team Developmen
1. **Enable in Docker**: Already done ✅
2. **Share settings**: Settings sync via GitHub accoun
3. **Use custom instructions**: Define project patterns in `.instructions.md
4. **Disable telemetry** (optional): Set in VS Code settings

### For Security
1. **Never commit tokens**: Use `.gitignore` for sensitive files
2. **Use GitHub Copilot Business for enterprise**: Additional privacy controls
3. **Audit Copilot requests**: Review sensitive code before using Copilo
4. **Keep extensions updated**: Automatic via latest Docker image

### For Performance
1. **Use inline chat** for quick fixes (Ctrl+I)
2. **Use chat panel** (Ctrl+L) for complex discussions
3. **Limit concurrent sessions**: One browser tab at a time recommended
4. **Clear browser cache** if slow: Common for long-running sessions

---

## 🔗 Official Resources

- **GitHub Copilot Home**: https://github.com/features/copilo
- **Copilot Documentation**: https://docs.github.com/en/copilo
- **Copilot Chat Guide**: https://code.visualstudio.com/docs/copilot/copilot-cha
- **Pricing & Plans**: https://github.com/pricing/copilo

---

## 📊 Feature Comparison: Free vs Paid

| Feature | Free Trial | Copilot Pro | Copilot Business |
|---------|-----------|-------------|------------------|
| Chat interface | ✅ (Limited) | ✅ | ✅ |
| Inline suggestions | ✅ | ✅ | ✅ |
| Code completions | ✅ | ✅ | ✅ |
| Requests per month | 50 | Unlimited | Unlimited |
| Priority queue | ❌ | ✅ | ✅ |
| Custom instructions | ✅ | ✅ | ✅ |
| Agent mode | Limited | ✅ | ✅ |
| Team deployment | ❌ | ❌ | ✅ |
| Privacy controls | ❌ | ❌ | ✅ |

---

## ✅ Installation Summary

### What's Already Done
✅ Copilot Chat .vsix files cached in Docker image
✅ github-authentication patch applied
✅ product.json patched for token access
✅ Entrypoint script configured for auto-installation
✅ Extensions installed on container startup

### What You Need to Do
1. Launch code-server: `make deploy` or `docker compose up -d
2. Click Copilot icon in sidebar
3. Click "Sign in with GitHub"
4. Authorize GitHub Copilo
5. Start using Copilot Chat! 🚀

---

## 📞 Suppor

**Issue with Copilot Chat?**
1. Check [troubleshooting section](#-troubleshooting) above
2. Review [GitHub Copilot Issues](https://github.com/microsoft/vscode-copilot-release/issues)
3. Check [code-server Issues](https://github.com/coder/code-server/issues)

**Want to customize Copilot?**
- Create `.instructions.md` in your workspace for project-specific instructions
- Use `settings.json` to configure Copilot behavior
- Define custom agents for specialized tasks

---

**Status**: ✅ Copilot Chat fully configured and ready to use
**Last Updated**: April 12, 2026
**Docker Image**: codercom/code-server:4.115.0
