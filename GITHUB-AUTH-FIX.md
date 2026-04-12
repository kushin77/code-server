# Code-Server GitHub Auth & Extension Fix

## Problem
Code-server was showing GitHub authentication and Copilot Chat errors even with auth disabled:
- "GitHub.copilot-chat" cannot be installed (extension not found)
- "Failed to sign in to GitHub" dialogs
- "Continue to GitHub to create a Personal Access Token" prompts

## Root Cause
- Extensions were attempting to load even if disabled
- GitHub features were not fully disabled in VS Code settings
- Telemetry and recommendation systems were still active

## Solution Applied

This fix **completely disables**:
✅ All extensions (including GitHub/Copilot)  
✅ GitHub authentication  
✅ Telemetry & crash reporting  
✅ Extension recommendations  
✅ Workspace trust prompts  
✅ Auto-update mechanisms  

## How to Apply

### Option 1: Auto-Fix Script (Recommended)
```bash
cd ~/code-server-enterprise
chmod +x fix-github-auth.sh
./fix-github-auth.sh
```

### Option 2: Manual Fix
```bash
# Stop code-server
pkill -f 'code-server --bind'

# Clean extensions
rm -rf ~/.local/share/code-server/extensions

# Update settings
# (See fix-github-auth.sh for exact settings)

# Restart
~/code-server/bin/code-server --bind-addr 0.0.0.0:8080
```

### Option 3: From Repo
```bash
git clone https://github.com/kushin77/code-server.git
cd code-server
./fix-github-auth.sh
```

## Configuration Files Updated

### ~/.config/code-server/config.yaml
```yaml
bind-addr: 0.0.0.0:8080
auth: password
password: 9c3f04d4307e07167125fdc5
cert: false
```

### ~/.local/share/code-server/User/settings.json
See `fix-github-auth.sh` for complete settings object with:
- `extensions.enabled: false`
- `github.gitAuthentication: false`
- `telemetry.telemetryLevel: off`
- And 10+ other disable flags

## Verification

After applying the fix:

```bash
# Restart browser at http://172.26.236.99:8080
# You should see:
✅ Clean Welcome screen
✅ No GitHub login dialogs
✅ No extension errors
✅ No telemetry prompts
```

## What's Disabled and Why

| Feature | Disabled | Reason |
|---------|----------|--------|
| All Extensions | ✅ | Prevents GitHub/Copilot auth attempts |
| GitHub Auth | ✅ | No dependency on GitHub services |
| Copilot | ✅ | Not available in Open VSX marketplace |
| Telemetry | ✅ | Privacy & no cloud dependencies |
| Auto-updates | ✅ | Deterministic, versioned deployment |
| Workspace Trust | ✅ | Not needed for local development |
| Recommendations | ✅ | Reduces noise & prompts |

## Post-Fix IDE Features Still Available

✅ File editing and navigation  
✅ Built-in terminal  
✅ Git integration (basic)  
✅ VS Code UI (theming, layout, keybinds)  
✅ Settings & preferences  
✅ Command palette  
✅ Search & replace  

## For Enterprise Deployment

Use the **Terraform IaC** setup in this repo for production:
```bash
terraform init
terraform apply
```

This ensures:
- Reproducible deployments
- Clean configuration from start
- Version-controlled infrastructure
- No manual fixes needed

## Source Repository

All code and configurations maintained at:
**https://github.com/kushin77/code-server**

## Additional Notes

- The "insecure context" warning for HTTP (non-HTTPS) is normal and doesn't affect functionality
- Use `fix-github-auth.sh` whenever you deploy a new instance
- All settings are idempotent (safe to run multiple times)

---

**Status**: ✅ All GitHub authentication and extension errors eliminated  
**Last Updated**: 2026-04-12  
**Maintained by**: kushin77
