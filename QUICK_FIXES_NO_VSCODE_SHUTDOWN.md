# Quick Fixes - System Performance Remediation Without Shutting Down VSCode

## Status Summary
- **VSCode**: Running (DO NOT SHUT DOWN)
- **Memory**: 78% used, critical pressure
- **Swap**: 60% used, swapping heavily
- **Docker**: 0 containers running (expected: 33+)
- **File Handles**: 198k open (37% of limit)

---

## QUICK FIX #1: VSCode Terminal Cleanup (2 minutes)

**Impact**: Each terminal = ~5MB memory + 1 bash process

### Instructions:
1. In VSCode, go to **Terminal** menu → **Terminal**
2. Look at the terminal panel - you have **50+ terminal tabs open**
3. **Close all but 1-2 terminals**:
   - Right-click terminal tabs → "Kill Terminal"
   - Close each tab (X button)
4. Keep only: **1 main terminal** for commands

### Expected Impact:
- Memory freed: ~250MB
- File handles reduced: ~100-150
- System responsiveness: Noticeable improvement

### Verify:
```bash
# In remaining terminal:
ps aux | grep bash | wc -l
free -h
```

---

## QUICK FIX #2: Disable Unused VSCode Extensions (3 minutes)

**Impact**: Each extension spawns language server, memory accumulates

### Instructions:
1. In VSCode, click **Extensions** icon (left sidebar)
2. Click **Installed** tab
3. Look for extensions you're NOT using (e.g., formatting tools, themes, unused language servers)
4. Click extension → **Disable** (or **Disable Workspace**)

### Candidates to Disable (if not actively using):
- Python extensions (if not developing Python)
- Remote extensions (if not using remote SSH/Dev Containers)
- Java, Go, Rust extensions (if not using those languages)
- Theme extensions (only need one)
- Unused linters/formatters

### Expected Impact:
- Memory freed: 50-200MB per disabled extension
- Language server processes reduced

### Verify:
```bash
ps aux | grep node | wc -l  # Should decrease
```

---

## QUICK FIX #3: Reduce File Watching Pressure (5 minutes)

**Impact**: VSCode watches 625MB workspace with 2960 git commits, opening 198k file handles

### Instructions:

1. **Open VSCode Settings** (Ctrl+, or Cmd+,)
2. **Search for**: `files.watcherExclude`
3. **Click "Edit in settings.json"** (if shown)
4. **Add this to your settings.json**:

```json
"files.watcherExclude": {
    "**/.git/objects/**": true,
    "**/.git/subtree-cache/**": true,
    "**/node_modules/**": true,
    "**/.terraform/**": true,
    "**/artifacts/**": true,
    "**/terraform/environments/private/**": true,
    "**/.vscode-server/**": true,
    "**/dist/**": true,
    "**/build/**": true,
    "**/.next/**": true,
    "**/coverage/**": true,
    "**/logs/**": true
}
```

5. **Save** (Ctrl+S)
6. VSCode will auto-reload

### Expected Impact:
- File handles reduced: 30-50k
- File watcher CPU reduced significantly
- System responsiveness: Major improvement

### Verify:
```bash
# Wait 10 seconds for VSCode to reload, then:
lsof | wc -l  # Should drop from 198k to 150k-170k
```

---

## QUICK FIX #4: Restart TypeScript Language Server (2 minutes)

**Impact**: TS Server can accumulate memory over hours of editing

### Instructions:
1. In VSCode, press **Ctrl+Shift+P** (or Cmd+Shift+P on Mac)
2. Type: `TypeScript: Restart TS Server`
3. Press Enter
4. Wait 5 seconds for it to restart

### Expected Impact:
- Memory freed: 100-300MB
- TS performance: Improved

### Verify:
```bash
# In terminal:
ps aux | grep tsserver | head -2
free -h
```

---

## QUICK FIX #5: Check & Fix Docker Infrastructure (5 minutes)

**Impact**: 33+ containers not running - critical service gap

### Step 1: Verify Docker is Running
```bash
docker ps -a
# Should show something, if empty = Docker issue
```

### Step 2: Check Docker Status
```bash
docker system info | head -20
docker stats --no-stream | head -5
```

### Step 3: If Docker is OK but containers not running:
```bash
cd /home/akushnir/code-server

# Check if containers are stopped
docker ps -a | wc -l
# If >0: docker restart code-server-postgres code-server-redis code-server-caddy
# (adjust to whatever major services you need)

# OR: Start from compose file
docker-compose -f docker-compose.enterprise.yml ps
docker-compose -f docker-compose.enterprise.yml up -d

# Verify they started
docker ps | wc -l  # Should be 30+
```

### Step 4: If Docker daemon is not running:
```bash
sudo systemctl status docker
sudo systemctl start docker
# Wait 10 seconds
docker ps
```

---

## QUICK FIX #6: Reduce Memory Footprint of Language Servers (3 minutes)

**Impact**: Node memory limits already set to 3GB, but may need adjustment

### Instructions:
1. Open VSCode Settings (Ctrl+,)
2. Search for: `typescript.tsserver.maxTsServerMemory`
3. Set to: `2048` (reduced from default)
4. Also search: `"[typescript]": { maxOldSpaceSize: 2048 }`
5. Apply same for JSON: search `json.maxItemsComputed` set to `5000`

### Expected Impact:
- Memory per language server: Reduced by 20-30%
- Performance: May be slightly slower but more stable

---

## QUICK FIX #7: Monitor Improvements (1 minute)

**After all fixes, run this to see impact:**

```bash
echo "=== BEFORE vs AFTER ===" && \
echo "Memory:" && free -h && \
echo -e "\n--- File Handles:" && lsof 2>/dev/null | wc -l && \
echo -e "\n--- Processes:" && ps aux | wc -l && \
echo -e "\n--- Load Average:" && uptime && \
echo -e "\n--- Docker Containers:" && docker ps | wc -l && \
echo -e "\n--- Git Status:" && cd /home/akushnir/code-server && git status --short
```

---

## Expected Results After All Fixes

| Metric | Before | After Target |
|--------|--------|--------------|
| Memory Used | 78% (23GB) | 60% (18.5GB) |
| Swap Used | 60% (5GB) | 20% (1.6GB) |
| File Descriptors | 198k | 130-150k |
| Load Average | 2.87 | 1.5-2.0 |
| Docker Containers | 0 | 33+ |
| Responsiveness | Slow | Good |

---

## If Problems Persist - Escalation Path

### Option A: VSCode Cache Clear (30 second reset)
```bash
# Only if fixes don't work:
# 1. Save all work in VSCode
# 2. In terminal:
pkill -f "code --type"  # Kill language servers only (NOT main process)
# 3. Wait 5 seconds
# 4. VSCode will auto-respawn servers
# 5. Monitor: free -h
```

### Option B: Full VSCode Restart (60 second reset - last resort)
```bash
# Only if Option A doesn't work:
# 1. Save all work
# 2. Close VSCode completely (or: pkill -9 code)
# 3. Clear cache:
rm -rf ~/.config/Code/cache
rm -rf ~/.vscode/extensions/.cache

# 4. Reopen VSCode
# 5. Let it re-index (monitor: watch -n 2 free -h)
# 6. Should be much faster after 2-3 minutes
```

---

## Git Cleanup (Optional - if safe)

If you want to clean up uncommitted/untracked files:

```bash
cd /home/akushnir/code-server

# 1. Check current state
git status

# 2. Option A: Restore deleted files (if you want them back)
git restore config/caddy/Caddyfile docker-compose.override.yml

# 3. Option B: Commit the deletions (if intentional)
git add -A && git commit -m "cleanup: remove unused override files"

# 4. Clean untracked files
git clean -fd

# 5. Verify clean
git status  # Should show "nothing to commit"
```

---

## Docker Health Check (If containers ARE running)

```bash
# Test major services:
docker ps | grep -E "postgres|redis|caddy" | wc -l  # Should be 3+

# Check specific service health:
docker ps --format "{{.Names}} {{.Status}}" | head -10

# View logs of a service:
docker logs code-server-postgres --tail 20
docker logs code-server-caddy --tail 20

# If any service is unhealthy:
docker restart code-server-SERVICE-NAME
```

---

## Monitoring Script (Run in separate terminal)

**Keep this running to watch improvements:**

```bash
#!/bin/bash
while true; do
    clear
    echo "=== SYSTEM MONITOR ==="
    echo "Time: $(date)"
    echo ""
    echo "Memory:"
    free -h | grep "^Mem:"
    echo ""
    echo "File Descriptors:"
    echo "Open: $(lsof 2>/dev/null | wc -l) / 524288"
    echo ""
    echo "Load Average:"
    uptime
    echo ""
    echo "Docker Containers:"
    docker ps | wc -l | xargs echo "Running:"
    echo ""
    echo "VSCode Processes:"
    ps aux | grep "[/]code" | wc -l | xargs echo "Count:"
    echo ""
    sleep 5
done
```

---

## Quick Reference - Do's and Don'ts

### ✅ DO:
- Close unused terminal tabs
- Disable extensions you're not using
- Add file watch exclusions
- Restart language servers
- Monitor memory while making changes
- Commit or restore Git changes

### ❌ DON'T:
- Don't shut down VSCode (you requested this)
- Don't delete entire directories blindly
- Don't restart Docker containers without planning (may break services)
- Don't modify system files without understanding them
- Don't ignore error messages

---

## Summary of Actions

**Estimated total time**: 10-15 minutes (all fixes)
**Expected memory improvement**: 4-5GB freed
**Expected file handle reduction**: 30-50k
**System responsiveness**: Significant improvement
**VSCode remains running**: YES ✓

**CRITICAL**: After fixes, check Docker status. 0 running containers is abnormal.

---

**Last Updated**: April 30, 2026 @ 15:05 UTC  
**Status**: Ready for immediate execution  
**Prerequisites**: VSCode must remain running (no shutdown)
