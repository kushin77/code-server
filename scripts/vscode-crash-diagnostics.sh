#!/bin/bash
# VS Code Crash Diagnostics for code-server-enterprise
# Run this script to identify the cause of VS Code crashes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

echo "=== VS Code Crash Diagnostics ==="
echo "Time: $(date -u)"
echo ""

# 1. Check extension host logs
echo "[1] Checking Extension Host Logs..."
LOG_DIR="$APPDATA/Code/logs"
if [ -d "$LOG_DIR" ]; then
    echo "Recent logs found:"
    ls -lt "$LOG_DIR" | head -5
    
    if grep -r "ERROR\|FATAL\|crash" "$LOG_DIR" 2>/dev/null | head -3; then
        echo "⚠️  Errors detected in logs"
    else
        echo "✓ No errors in recent logs"
    fi
else
    echo "⚠️  No logs directory found"
fi
echo ""

# 2. Check VS Code process crash dumps
echo "[2] Checking for Crash Dumps..."
CRASH_DIR="$APPDATA/Code/CrashDumps"
if [ -d "$CRASH_DIR" ]; then
    DUMP_COUNT=$(find "$CRASH_DIR" -type f | wc -l)
    echo "Found $DUMP_COUNT crash dump files:"
    ls -lt "$CRASH_DIR" | head -3
else
    echo "✓ No crash dumps found"
fi
echo ""

# 3. Check VS Code processes
echo "[3] Checking VS Code Processes..."
if pgrep -f "Code.exe|code" > /dev/null; then
    ps aux | grep -i code | grep -v grep
else
    echo "✓ No VS Code processes running"
fi
echo ""

# 4. Check disk space
echo "[4] Checking Disk Space..."
df -h | grep -E "/$|code-server"
echo ""

# 5. Check file watcher limits
echo "[5] Checking File Watcher Limits..."
if [ -f "/proc/sys/fs/inotify/max_user_watches" ]; then
    MAX_WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches)
    echo "Max inotify watches: $MAX_WATCHES"
    if [ "$MAX_WATCHES" -lt 524288 ]; then
        echo "⚠️  File watch limit may be too low. Increase with:"
        echo "   echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf"
    fi
fi
echo ""

# 6. Summary
echo "[6] Recommended Actions:"
echo "   A) Disable extensions: code --disable-extensions"
echo "   B) Clear cache: rm -rf ~/.config/Code/User/workspaceStorage"
echo "   C) Check logs: cat ~/.config/Code/logs/*/window*.log | grep -i error"
echo "   D) Update VS Code: code --update-extensions"
echo ""

echo "=== Diagnostics Complete ==="
