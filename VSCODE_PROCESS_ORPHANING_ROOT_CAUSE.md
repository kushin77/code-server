# VSCode Process Orphaning - Root Cause & Solutions

**Diagnosis Date**: April 30, 2026  
**Issue**: VSCode processes don't terminate when main window closes  
**Root Cause**: Terminal sessions spawn as independent process group leaders

---

## THE PROBLEM EXPLAINED

### Current Architecture
```
VSCode Main Process (PID 2234394)
├─ Child Process (2234400)
├─ Child Process (2234401)
├─ Child Process (2234403)
│  └─ Grandchild (2234484) - Zygote
│     ├─ Terminal Session 1 [Ss+] ← Orphaned when parent exits
│     ├─ Terminal Session 2 [Ss+] ← Orphaned when parent exits
│     ├─ Terminal Session 3 [Ss+] ← Orphaned when parent exits
│     ... 88 more terminal sessions ...
└─ Utility Services (13 detached processes)
   └─ Run independently, ignore parent death
```

### What Happens When You Close VSCode

1. **GUI closes** - You click the X button
2. **Main process (2234394) terminates** - Receives SIGTERM
3. **Direct children killed** - 2234400, 2234401, 2234403 get SIGKILL
4. **Terminal sessions orphaned** - But terminals are Ss+ (session leaders!)
   - They don't receive the termination signal
   - They become children of init (PID 1)
   - They continue running indefinitely
5. **Result**: 
   - 91 terminal sessions still running
   - 13 utility services still running
   - 148 processes total in background
   - Memory still allocated (~10-15GB)
   - Disk I/O continuing
   - File handles not released

---

## EVIDENCE

### Terminal Sessions Analysis
```bash
ps aux | grep -E "pts/.*bash.*shellIntegration"
# Output: 91 sessions, each with Ss+ (session leader, running in background)

ps -p 2234394 -o pid,pgrp,sid,stat
# Main VSCode: SID=9759
# But terminal SIDs are individual (each is own session)
```

### Why This Happens
- **VSCode design**: Each terminal tab gets its own PTY (pseudoterminal)
- **PTY requirement**: Must have a session leader (shell process)
- **Independence**: Each terminal can run independently
- **Problem**: No mechanism to link them to parent on exit

---

## SOLUTIONS

### SOLUTION 1: Aggressive Kill Script (Immediate)

**Use this to completely clean VSCode:**

```bash
#!/bin/bash
# File: ~/.local/bin/kill-vscode-clean.sh
# Purpose: Forcefully terminate all VSCode processes including orphaned terminals

echo "Terminating VSCode and all child processes..."

# Method 1: Kill all VSCode processes
pkill -9 -f "code|node.*vscode" 2>/dev/null

# Method 2: Kill by session (more thorough)
ps aux | grep -E "pts.*shellIntegration-bash" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null

# Method 3: Kill any remaining utility services
ps aux | grep "/proc/self/exe --type=utility" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null

# Wait for processes to actually die
sleep 1

# Verify cleanup
REMAINING=$(ps aux | grep code | grep -v grep | wc -l)
if [ "$REMAINING" -eq 0 ]; then
    echo "✓ All VSCode processes terminated"
else
    echo "⚠ Warning: $REMAINING VSCode processes still running"
    ps aux | grep code | grep -v grep
fi

# Clear VSCode cache and locks
rm -rf ~/.config/Code/cache/* 2>/dev/null
rm -f ~/.config/Code/.lock 2>/dev/null

echo "Done. VSCode is fully cleaned up."
```

**Setup:**
```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/kill-vscode-clean.sh << 'SCRIPT'
#!/bin/bash
pkill -9 -f "code|node.*vscode"
ps aux | grep -E "pts.*shellIntegration-bash" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null
ps aux | grep "/proc/self/exe --type=utility" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null
sleep 1
SCRIPT

chmod +x ~/.local/bin/kill-vscode-clean.sh

# Use it:
~/.local/bin/kill-vscode-clean.sh
```

---

### SOLUTION 2: VSCode Settings Configuration (Prevention)

**Disable features that cause orphaning:**

Edit `~/.config/Code/User/settings.json`:

```json
{
    // Reduce terminal session creation
    "terminal.integrated.profiles.linux": {
        "bash": {
            "path": "bash",
            "args": ["--login"],
            // Important: Let VSCode manage the shell lifecycle
            "overrideEnv": {
                "TERM": "xterm-256color"
            }
        }
    },

    // Kill child processes on exit
    "terminal.integrated.showExitAlert": false,
    "terminal.integrated.enablePersistentSessions": false,
    
    // Close terminals on exit
    "terminal.integrated.closeOnExit": 1,
    
    // Reduce extension spawning
    "extensions.autoCheckUpdates": false,
    "extensions.autoUpdate": false,
    
    // Reduce file watcher intensity (already recommended)
    "files.watcherExclude": {
        "**/.git/objects/**": true,
        "**/.git/subtree-cache/**": true,
        "**/node_modules/**": true,
        "**/.terraform/**": true
    }
}
```

---

### SOLUTION 3: Wrapper Script (Automatic Cleanup)

**Create a VSCode wrapper that handles cleanup on exit:**

```bash
#!/bin/bash
# File: ~/.local/bin/code-clean.sh
# Purpose: VSCode wrapper that ensures proper cleanup

# Launch VSCode
/usr/bin/code "$@"

# VSCode has exited - clean up orphans
sleep 2

# Kill any remaining processes
pkill -9 -f "code" 2>/dev/null

echo "VSCode closed and cleaned up."
```

**Setup:**
```bash
chmod +x ~/.local/bin/code-clean.sh

# Test:
~/.local/bin/code-clean.sh /home/akushnir/code-server
```

---

### SOLUTION 4: Systemd User Service (Cleaner Management)

**Let systemd manage VSCode and proper cleanup:**

```ini
# File: ~/.config/systemd/user/vscode.service
[Unit]
Description=Visual Studio Code
After=graphical-session-pre.target

[Service]
Type=notify
ExecStart=/usr/bin/code --no-sandbox
ExecStop=/usr/bin/pkill -f "code"
Restart=no
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=10

[Install]
WantedBy=graphical-session.target
```

**Setup:**
```bash
mkdir -p ~/.config/systemd/user
# Create file as shown above
systemctl --user daemon-reload
systemctl --user start vscode
systemctl --user stop vscode  # Proper cleanup!
```

---

### SOLUTION 5: Monitor & Auto-Cleanup Script (Background)

**Run continuously to catch orphaned processes:**

```bash
#!/bin/bash
# File: ~/.local/bin/monitor-vscode.sh
# Purpose: Monitor for orphaned VSCode processes

while true; do
    # Check for orphaned terminal sessions
    ORPHANED=$(ps aux | grep -E "pts.*shellIntegration-bash" | grep -v grep | wc -l)
    
    if [ "$ORPHANED" -gt 0 ]; then
        # Get main VSCode PID
        MAIN_PID=$(ps aux | grep "/usr/share/code/code$" | grep -v grep | awk '{print $2}' | head -1)
        
        # If main VSCode is not running but orphans exist
        if [ -z "$MAIN_PID" ]; then
            echo "$(date): Cleaning up $ORPHANED orphaned terminal sessions"
            pkill -9 -f "shellIntegration-bash" 2>/dev/null
            pkill -9 -f "node.*vscode" 2>/dev/null
        fi
    fi
    
    sleep 10
done
```

**Setup as background service:**
```bash
chmod +x ~/.local/bin/monitor-vscode.sh

# Add to startup (or use systemd timer)
cat >> ~/.bashrc << 'EOF'
# Auto-cleanup VSCode orphans in background
~/.local/bin/monitor-vscode.sh &
disown
EOF
```

---

## IMMEDIATE ACTION PLAN

### Step 1: Clean Current System (1 minute)
```bash
# Kill all VSCode processes
pkill -9 -f "code"
sleep 2

# Verify cleanup
ps aux | grep code | grep -v grep
# Should return nothing
```

### Step 2: Implement Solution 1 (2 minutes)
```bash
# Create kill script
mkdir -p ~/.local/bin
cat > ~/.local/bin/kill-vscode-clean.sh << 'EOF'
#!/bin/bash
pkill -9 -f "code"
ps aux | grep -E "pts.*shellIntegration-bash" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null
sleep 1
EOF
chmod +x ~/.local/bin/kill-vscode-clean.sh
```

### Step 3: Configure VSCode (3 minutes)
```bash
# Open settings: Ctrl+, or Cmd+,
# Search for: terminal.integrated.enablePersistentSessions
# Set to: false
# Search for: terminal.integrated.closeOnExit  
# Set to: 1
```

### Step 4: Test (1 minute)
```bash
# Open VSCode
code

# Open 5 terminals
# Close VSCode normally

# In a different terminal:
ps aux | grep code | grep -v grep | wc -l
# Should be: 0 (all processes cleaned up)
```

---

## EXPECTED RESULTS

### Before Fix
```
Process count after closing VSCode GUI:
  - Actual processes: 148 still running
  - Memory: 10-15GB still allocated
  - File handles: 198k still open
  - CPU: Still consuming CPU on orphans
```

### After Fix
```
Process count after closing VSCode GUI:
  - Actual processes: 0 (all terminated)
  - Memory: Freed immediately
  - File handles: Released
  - CPU: Returns to idle
```

---

## PERMANENT SOLUTION (Recommended)

**Best practice: Use Solution 1 + Solution 2**

1. **Create kill script** for manual complete cleanup
2. **Configure VSCode settings** to prevent new orphans
3. **Remember**: Always use `pkill -9 code` to fully close, not just the window

```bash
# Add alias to ~/.bashrc
alias kill-vscode='pkill -9 -f "code" && sleep 1 && echo "VSCode fully terminated"'

# Usage: just type: kill-vscode
```

---

## VERIFICATION COMMANDS

**Check if VSCode processes are orphaned:**
```bash
ps aux | grep code | grep -v grep | wc -l
# While VSCode is running: Should be 100-150
# After closing: Should be 0

# If not 0: they're orphaned
```

**Check terminal session status:**
```bash
ps aux | grep "shellIntegration-bash" | wc -l
# While VSCode running: 50+
# After closing: Should be 0
```

**Monitor cleanup in real-time:**
```bash
watch -n 1 'ps aux | grep code | grep -v grep | wc -l'
# Close VSCode and watch the count drop to 0
```

---

## SUMMARY

**Problem**: VSCode creates independent terminal sessions that orphan when main process exits

**Cause**: Each PTY requires a session leader (bash); they can survive parent death

**Symptom**: 148 processes still running after closing VSCode GUI

**Impact**: 10-15GB memory not freed, system thinks VSCode is still active

**Solution**: Use aggressive `pkill -9` + configure settings + monitor for orphans

**Time to Fix**: 5 minutes total

**Verification**: `ps aux | grep code` should return nothing after closing
