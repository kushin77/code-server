# VS Code To code-server Preservation Runbook

## Goal
Preserve existing VS Code user state, repo instruction rules, secrets, and editor enhancements during migration to code-server.

## What Gets Preserved
- User settings, keybindings, snippets, extension state, and workspace state from VS Code User profile.
- Extension payloads from VS Code extension directory.
- Repository instruction rules from .github/copilot-instructions.md (already repo-native).
- Existing code-server enterprise defaults from config/code-server/settings.json.
- Secrets strategy and credentials flow already implemented in this repository.

## Scope Boundaries
- This runbook does not rotate or rewrite secrets.
- This runbook does not edit branch protection, workflows, or issue state.
- This runbook does not modify production compose topology.

## Pre-Checks
Run these from repository root.

```bash
# 1) Ensure instruction rules are present
ls -la .github/copilot-instructions.md

# 2) Ensure canonical code-server settings baseline exists
ls -la config/code-server/settings.json

# 3) Ensure profile persistence services are configured
grep -n "code-server-data\|code-server-profile-backup" docker-compose.yml
```

## Step 1: Export VS Code Profile On Source Machine

Preferred path (single command from this repo):

```bash
bash scripts/dev/export-vscode-profile-archive.sh
```

This generates an archive like `vscode-profile-export-YYYYMMDD-HHMMSS.tgz` in the current directory.

If auto-detection cannot find your VS Code folders, set overrides:

```bash
VSCODE_USER_DIR="/path/to/Code/User" \
VSCODE_EXTENSIONS_DIR="/path/to/.vscode/extensions" \
bash scripts/dev/export-vscode-profile-archive.sh /tmp/vscode-profile-export.tgz
```

Manual export examples remain below for environments where repository scripts are not available.

### Linux/macOS source

```bash
mkdir -p /tmp/vscode-export
cp -R "$HOME/.config/Code/User" /tmp/vscode-export/User
cp -R "$HOME/.vscode/extensions" /tmp/vscode-export/extensions

tar -czf /tmp/vscode-profile-export.tgz -C /tmp/vscode-export .
```

### Windows source (PowerShell)

```powershell
$srcUser = "$env:APPDATA\Code\User"
$srcExt  = "$env:USERPROFILE\.vscode\extensions"
$stage   = "$env:TEMP\vscode-export"
$tarOut  = "$env:TEMP\vscode-profile-export.tgz"

Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item $srcUser "$stage\User" -Recurse -Force
if (Test-Path $srcExt) { Copy-Item $srcExt "$stage\extensions" -Recurse -Force }

tar -czf $tarOut -C $stage .
Write-Output "Archive: $tarOut"
```

Copy the archive to primary host 192.168.168.31:

```bash
scp /path/to/vscode-profile-export.tgz akushnir@192.168.168.31:/home/akushnir/
```

Or if you used the script default output from repo root:

```bash
scp ./vscode-profile-export-*.tgz akushnir@192.168.168.31:/home/akushnir/
```

## Step 2: Import Archive Into code-server (Primary Host)

```bash
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server-enterprise
bash scripts/dev/import-vscode-profile-archive.sh /home/akushnir/vscode-profile-export.tgz --restart
```

What this does:
- Creates pre-import rollback backup inside code-server container.
- Imports User profile and extensions into /home/coder/.local/share/code-server.
- Preserves ownership for runtime compatibility.
- Leaves .env and secret manager flows unchanged.

## Step 3: Verify Preservation

```bash
# Run on primary host
cd /home/akushnir/code-server-enterprise
docker compose ps --format 'table {{.Names}}\t{{.Status}}' | egrep '^(code-server|code-server-profile-backup)\s'
docker exec code-server ls -la /home/coder/.local/share/code-server/User | head -30
docker exec code-server ls -la /home/coder/.local/share/code-server/extensions | head -30
docker exec code-server ls -la /home/coder/.local/share/code-server | egrep 'User|extensions|workspaceStorage|History|Backups'
```

## Step 4: Verify Instruction Rules And Enhancements

```bash
# Rule file should remain tracked in repo
ls -la .github/copilot-instructions.md

# Enterprise defaults should still be the baseline for first-launch users
cat config/code-server/settings.json
```

Enterprise defaults are merged additively at container start. User-defined
values remain authoritative for keys they already set, while new shared
defaults are appended for all users automatically.

## Step 5: Secrets And Credentials Validation
This repository already uses canonical secrets and credential handling. Keep these unchanged after migration.

```bash
# Existing secure git credential setup (GSM-backed helper)
bash scripts/setup-git-credentials.sh

# Optional: verify no plaintext helper remains
git config --global --get credential.helper
git config --global --get credential.https://github.com.helper
```

## Rollback
If import quality is not acceptable, restore from the pre-import backup created by the import script.

```bash
# Run on primary host
ssh akushnir@192.168.168.31

docker exec code-server sh -lc 'ls -la /home/coder/.migration-backups | tail -5'

# Replace <backup-file> with latest pre-vscode-import-*.tgz
docker exec code-server sh -lc 'tar -xzf /home/coder/.migration-backups/<backup-file> -C /home/coder/.local/share/code-server'
docker restart code-server
```

## Operational Notes
- Deploy and runtime verification must be done on 192.168.168.31.
- Do not run Terraform locally on Windows for this stack.
- Keep environments/production/hosts.yml as canonical IP SSOT.
