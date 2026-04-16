#!/bin/bash
# vscode-handle-monitor.sh
# Purpose: Monitor VSCode process health across concurrent sessions
# Usage: bash scripts/vscode-handle-monitor.sh

set -euo pipefail

echo "=== VSCode Process Health Monitor ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Count extension host processes
ext_hosts=$(pgrep -c -f 'extensionHost' 2>/dev/null || echo "0")
echo "Extension hosts: $ext_hosts (max recommended: 3)"

# Count PowerShell processes 
pwsh_count=$(pgrep -c 'pwsh' 2>/dev/null || ps aux | grep -c '[p]wsh' || echo "0")
echo "PowerShell processes: $pwsh_count (max recommended: 4)"

# Count bash processes
bash_count=$(pgrep -c 'bash' 2>/dev/null || ps aux | grep -c '[b]ash' || echo "0")
echo "Bash processes: $bash_count (max recommended: 4)"

# Total file descriptors for Code processes (Linux/WSL)
if command -v lsof &>/dev/null; then
    handles=$(lsof 2>/dev/null | grep -c '[C]ode\.' || echo "N/A")
    echo "VSCode file descriptors: $handles (alert threshold: 1200)"
else
    echo "VSCode file descriptors: N/A (lsof not available)"
fi

# Memory per extension host process
if [ "$ext_hosts" -gt 0 ]; then
    echo ""
    echo "Extension host memory:"
    pgrep -f 'extensionHost' 2>/dev/null | while read pid; do
        if [ -d "/proc/$pid" ]; then
            rss=$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null || echo "N/A")
            echo "  PID $pid: ${rss}KB"
        fi
    done || true
fi

echo ""
echo "Risk Assessment:"

# Risk assessment
risk_level="OK"
if [ "$pwsh_count" -gt 6 ]; then
    echo "⚠️  CRITICAL: Too many PowerShell processes ($pwsh_count). Crash risk HIGH."
    risk_level="CRITICAL"
elif [ "$pwsh_count" -gt 4 ]; then
    echo "⚠️  WARNING: PowerShell count elevated ($pwsh_count). Consider closing excess."
    risk_level="WARNING"
elif [ "$bash_count" -gt 4 ]; then
    echo "⚠️  WARNING: Bash count elevated ($bash_count). Consider closing excess."
    risk_level="WARNING"
elif [ "$ext_hosts" -gt 3 ]; then
    echo "⚠️  WARNING: Multiple extension hosts ($ext_hosts). Consider closing extra windows."
    risk_level="WARNING"
else
    echo "✅ Process counts nominal."
    risk_level="OK"
fi

echo ""
echo "Status: $risk_level"
