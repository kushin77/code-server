#!/bin/bash
# vscode-pre-reload-snapshot.sh
# Purpose: Snapshot terminal working directories before VSCode reload
# Usage: bash scripts/vscode-pre-reload-snapshot.sh
# On restart, terminals can be re-opened at snapshotted paths

set -euo pipefail

SNAPSHOT_DIR=".vscode"
SNAPSHOT_FILE="${SNAPSHOT_DIR}/terminal-snapshot.json"

mkdir -p "$SNAPSHOT_DIR"

# Initialize empty snapshot
echo "[]" > "$SNAPSHOT_FILE"

echo "[snapshot] Capturing terminal state..."

# Capture terminal processes and their CWDs
declare -a terminals
i=0

# On Linux/WSL: find processes under conpty/shell parent
if command -v pgrep &> /dev/null; then
  while IFS= read -r pid; do
    if [ -n "$pid" ]; then
      cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "unknown")
      terminals[$i]=$(printf '{"pid":%d,"cwd":"%s"}' "$pid" "$cwd")
      echo "[snapshot] Terminal PID $pid → $cwd"
      ((i++)) || true
    fi
  done < <(pgrep -P "$(pgrep -f extensionHost 2>/dev/null || echo 1)" bash 2>/dev/null || pgrep pwsh 2>/dev/null || true)
fi

# On macOS: use lsof instead
if command -v lsof &> /dev/null && [ "$i" -eq 0 ]; then
  while IFS= read -r pid; do
    if [ -n "$pid" ]; then
      cwd=$(lsof -p "$pid" -Fn 2>/dev/null | grep "^n/" | cut -c2- | head -1 || echo "unknown")
      terminals[$i]=$(printf '{"pid":%d,"cwd":"%s"}' "$pid" "$cwd")
      echo "[snapshot] Terminal PID $pid → $cwd"
      ((i++)) || true
    fi
  done < <(pgrep -f "bash|pwsh|zsh" 2>/dev/null || true)
fi

# Write snapshot JSON
if [ "$i" -gt 0 ]; then
  printf "[\n" > "$SNAPSHOT_FILE"
  for j in "${!terminals[@]}"; do
    printf "  %s" "${terminals[$j]}" >> "$SNAPSHOT_FILE"
    [ "$j" -lt "$((i-1))" ] && printf ",\n" >> "$SNAPSHOT_FILE" || printf "\n" >> "$SNAPSHOT_FILE"
  done
  printf "]\n" >> "$SNAPSHOT_FILE"
  echo "[snapshot] ✅ Snapshot created: $SNAPSHOT_FILE (${#terminals[@]} terminals)"
else
  echo "[snapshot] ⚠ No terminals found to snapshot"
fi
