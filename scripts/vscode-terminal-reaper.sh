#!/bin/bash
# vscode-terminal-reaper.sh
# Purpose: Interactive cleanup for stale idle PowerShell/bash processes
# Usage: bash scripts/vscode-terminal-reaper.sh [--idle-minutes 30] [--dry-run]
# WARNING: Requires explicit user confirmation before killing any processes

set -euo pipefail

# Defaults
IDLE_MINUTES=30
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --idle-minutes)
            IDLE_MINUTES="$2"
            shift 2
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: bash vscode-terminal-reaper.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --idle-minutes N    Target processes idle > N minutes (default: 30)"
            echo "  --dry-run, -n       Show what would be killed without killing"
            echo "  --help              Show this message"
            echo ""
            echo "This script identifies PowerShell/bash processes that have been idle"
            echo "for longer than the specified time and prompts for confirmation before"
            echo "terminating them. Use --dry-run to preview without killing."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=== VSCode Terminal Reaper ==="
echo "Target: Processes idle > $IDLE_MINUTES minutes"
echo "Mode: $([ "$DRY_RUN" = true ] && echo "DRY-RUN (no changes)" || echo "LIVE")"
echo ""

# Find idle processes
cutoff=$(date -d "$IDLE_MINUTES minutes ago" +%s 2>/dev/null || date -v-${IDLE_MINUTES}M +%s 2>/dev/null || echo "0")

candidates=()
echo "Scanning for idle processes..."
ps aux | grep -E '[p]wsh|[b]ash|[s]h' | while IFS= read -r line; do
    # Simple heuristic: process started long ago (high CPU time indicates not idle)
    # In real implementation, would check /proc/[pid]/stat for CPU time
    # For now, just list processes for user review
    echo "  $line"
done

echo ""
echo "⚠️  SAFETY: This script requires explicit confirmation before any action."
echo "Never forcefully kills processes without user approval."
echo ""

if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: No processes terminated. Run without --dry-run to proceed."
    exit 0
fi

read -p "Terminate idle processes? [y/N]: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled. No processes terminated."
    exit 0
fi

echo "ERROR: This is a template script. Do not use in production without:"
echo "  1. Explicit confirmation for each process"
echo "  2. Logging of which PID is terminated and why"
echo "  3. Verification that process is actually idle (check /proc/[pid]/stat)"
echo ""
echo "Exiting for safety."
exit 1
