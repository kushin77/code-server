# VS Code Crash Troubleshooting Guide

## Quick Diagnosis

Your VS Code is crashing due to one of these causes:

1. **Extension conflict** (most common) — Copilot Chat or YAML parser
2. **Language server memory leak** — LSP process consuming excessive memory
3. **File watcher limit exceeded** — Too many files causing nodemon/inotify overflow
4. **Workspace metadata corruption** — Stale cached state

## Immediate Actions (Try in Order)

### Step 1: Launch with Extensions Disabled
```powershell
code --disable-extensions
```

✅ **If this works:** An extension is crashing. Proceed to Step 2.
❌ **If it still crashes:** Skip to Step 3.

### Step 2: Find the Culprit Extension
1. Re-enable extensions one at a time via VS Code UI
2. Restart VS Code after each enable
3. First one to crash is the culprit
4. **Most likely:** `github.copilot-chat` or `redhat.vscode-yaml`

### Step 3: Clear Workspace Cache
```powershell
# Close VS Code completely, then:
$appdata = "$env:APPDATA\Code"
Remove-Item "$appdata\User\workspaceStorage" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$appdata\Cache" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$appdata\CrashDumps" -Recurse -Force -ErrorAction SilentlyContinue

# Reopen VS Code
code
```

### Step 4: Check VS Code Logs
```powershell
$logPath = "$env:APPDATA\Code\logs"
Get-ChildItem $logPath -Recurse | Where-Object {$_.LastWriteTime -gt (Get-Date).AddHours(-1)} |
  ForEach-Object {Select-String -Path $_.FullName -Pattern "ERROR|FATAL|crash" -Context 2}
```

### Step 5: Increase File Watcher Limit (Windows)
```powershell
# Add to settings.json (already done in .vscode/settings.json):
# "files.watcherExclude": {...}
```

## Prevention: Workspace Optimization ✅

I've created `.vscode/settings.json` which:
- ✅ Excludes `node_modules`, `.terraform`, `*.tfstate` from watchers
- ✅ Disables schema validation on large files
- ✅ Turns off formatters that can hang
- ✅ Reduces telemetry overhead

**The optimization is already applied.** Next time you open VS Code, it should use these settings.

## Emergency Reset (Last Resort)

```powershell
# Completely reset VS Code to factory state
code --user-data-dir $env:TEMP\vscode-new
```

This launches with a blank VS Code instance. If it works, your settings are corrupted.

## Verify the Fix

1. Close VS Code completely
2. Open it from the workspace: `code .` from `c:\code-server-enterprise\`
3. **Should now be stable** with the new `.vscode/settings.json` applied
4. If it crashes, run diagnostic: `bash scripts/vscode-crash-diagnostics.sh`

## When to Escalate

If crashes persist after these steps:
- Update VS Code: `code --version` then download latest
- Disable antivirus scanning on `%APPDATA%\Code`
- Check system RAM (requires >2GB for large workspaces)
- Check Event Viewer for system errors
