#!/bin/bash
# Code-Server Container Diagnostics
# Run this to diagnose code-server container issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

echo "=== Code-Server Container Diagnostics ==="
echo "Time: $(date -u)"
echo ""

# 1. Check container status
echo "[1] Container Status..."
if docker-compose ps code-server | grep -q "Up"; then
    echo "✓ code-server container is running"
    docker-compose ps code-server
else
    echo "⚠️  code-server container is NOT running"
    echo "Last exit code:"
    docker-compose ps code-server
fi
echo ""

# 2. Check recent logs
echo "[2] Recent Container Logs..."
echo "Last 20 log lines:"
docker-compose logs code-server --tail 20 2>/dev/null || echo "⚠️  Cannot read logs (container may not be running)"
echo ""

# 3. Check resource usage
echo "[3] Resource Usage..."
if docker ps --format '{{.Names}}' | grep -q code-server; then
    docker stats code-server --no-stream 2>/dev/null || echo "⚠️  Cannot read stats"
else
    echo "⚠️  code-server container not found in running containers"
fi
echo ""

# 4. Check workspace directory
echo "[4] Workspace Directory..."
if [ -d "/home/coder/workspace" ]; then
    echo "✓ Workspace directory exists"
    du -sh /home/coder/workspace 2>/dev/null || echo "(no size info)"
else
    echo "⚠️  Workspace directory not found"
fi
echo ""

# 5. Check NAS mount (if applicable)
echo "[5] NAS Mount Status..."
if docker-compose exec code-server mount 2>/dev/null | grep -q "/mnt"; then
    echo "✓ NAS mount is active"
    docker-compose exec code-server mount | grep "/mnt"
else
    echo "⚠️  NAS mount may not be active"
fi
echo ""

# 6. Check internal processes
echo "[6] Running Processes (inside container)..."
docker-compose exec code-server ps aux 2>/dev/null | head -10 || echo "⚠️  Cannot read processes"

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
