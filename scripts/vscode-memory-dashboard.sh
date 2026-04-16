#!/bin/bash
# vscode-memory-dashboard.sh
# Purpose: Quick memory summary for VSCode processes
# Usage: bash scripts/vscode-memory-dashboard.sh

set -euo pipefail

echo "=== VSCode Memory Dashboard ==="
echo "Timestamp: $(date)"
echo ""

# Try to get process list (works on Linux/WSL, may fail on pure Windows)
if command -v ps &>/dev/null; then
    printf "%-45s %12s %8s\n" "PROCESS" "MEM(MB)" "CPU%"
    printf "%-45s %12s %8s\n" "-------" "-------" "----"
    
    # Sort by memory usage (descending)
    ps aux --sort=-rss 2>/dev/null | grep -E '(Code|extension|pwsh|bash)' | head -15 | \
        awk '{
            mem_kb = $6
            mem_mb = mem_kb / 1024
            cmd = substr($11 " " $12 " " $13, 1, 45)
            printf "%-45s %12.1f %8s\n", cmd, mem_mb, $3
        }' || true
else
    echo "ps command not available (Windows native)"
    echo ""
    echo "Use: Get-Process Code,extensionHost,pwsh | Sort-Object WorkingSet -Descending"
    exit 1
fi

echo ""
echo "Summary:"
echo "- Recommended total VSCode budget: ≤4GB across all sessions"
echo "- Per-extension-host cap: 1GB"
echo "- Action if exceeded: Close stale editor groups, kill idle terminals"
echo ""

# Check if any process exceeds threshold
if command -v ps &>/dev/null; then
    max_mem=$(ps aux 2>/dev/null | grep -E '(Code|extensionHost)' | awk '{print $6}' | sort -rn | head -1 | awk '{print int($1/1024)}')
    if [ "$max_mem" -gt 1500 ]; then
        echo "⚠️  WARNING: Largest process using >1.5GB. Consider intervention."
    elif [ "$max_mem" -gt 1000 ]; then
        echo "ℹ️  INFO: Largest process using >1GB. Monitor closely."
    fi
fi
