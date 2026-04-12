# GitHub Copilot Chat - Quick Reference

## ✅ Current Status
- **Extensions Installed**: ✅ Both github.copilot and github.copilot-chat
- **Configuration**: ✅ Product.json patched and ready
- **Authentication**: ⏳ Requires GitHub sign-in
- **Cloud Provider**: ✅ Works on any cloud with GitHub access

---

## 🚀 3-Minute Setup

```bash
# 1. Start code-server
make deploy

# 2. Open in browser
# → http://localhost

# 3. Click Copilot icon
# → Sign in with GitHub
# → Complete OAuth flow

# Done! Use Copilot Chat with Ctrl+L
```

---

## ⌨️ Keyboard Shortcuts

| Action | Windows | macOS |
|--------|---------|-------|
| Open Chat Panel | `Ctrl+L` | `Cmd+L` |
| Inline Chat | `Ctrl+I` | `Cmd+I` |
| Quick Fix | `Ctrl+K` | `Cmd+K` |
| Accept Suggestion | `Tab` | `Tab` |

---

## 💬 Chat Examples

```
@workspace What does this codebase do?
Explain this error message
Generate unit tests for this function
Refactor this for performance
Debug why this is failing
How do I implement...?
```

---

## 🔍 Verify Installation

```bash
# Check extensions are installed
docker exec code-server /usr/bin/code-server --list-extensions | grep copilot

# Check .vsix files cached
docker exec code-server ls -lh /opt/vsix/

# Run full validation
docker exec code-server bash /home/coder/workspace/scripts/validate-copilot.sh
```

---

## 🔐 Authentication

1. Click Copilot icon → "Sign in"
2. Get code from: https://github.com/settings/copilot
3. Paste code in code-server
4. Approve in browser
5. Done!

---

## ⚡ Pro Tips

- Use `@workspace` to reference your codebase
- Use `#selection` to reference selected code
- Use `/` commands for specialized tasks
- Create `.instructions.md` for project context
- Enable settings sync for multi-device

---

## 📚 Full Docs

- [COPILOT_CHAT_SETUP.md](COPILOT_CHAT_SETUP.md) - Complete guide
- [COPILOT_CHAT_DISCOVERY_REPORT.md](COPILOT_CHAT_DISCOVERY_REPORT.md) - Technical details

---

## 🆘 Troubleshooting

| Issue | Solution |
|-------|----------|
| Chat not showing | Check Copilot icon in sidebar |
| Auth fails | Verify internet connection to GitHub |
| Slow responses | Check rate limits or use Copilot Pro |
| Extensions not loading | Run: `docker compose build --no-cache` |

---

**Ready to go!** Open code-server and authenticate with GitHub. 🚀

