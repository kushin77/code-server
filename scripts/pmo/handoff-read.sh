#!/usr/bin/env bash
# @file        scripts/pmo/handoff-read.sh
# @module      pmo/session
# @description Read structured handoff at start of Copilot session for resumption
# @owner       PMO Framework
# @status      active
#
# Reads /memories/session/epic-N-handoff.md and prints resume instructions.

set -euo pipefail

MEMORIES_DIR="${MEMORIES_DIR:-.}"
EPIC_NUMBER="${1:-1575}"
HANDOFF_FILE="$MEMORIES_DIR/session/epic-${EPIC_NUMBER}-handoff.md"

# Source logging
if [[ -f "scripts/_common/logging.sh" ]]; then
    source scripts/_common/logging.sh
else
    log_info() { echo "[INFO] $*"; }
fi

if [[ ! -f "$HANDOFF_FILE" ]]; then
    log_info "No handoff found for epic #$EPIC_NUMBER"
    log_info "Start new session: bash scripts/pmo/session-start.sh"
    exit 1
fi

echo ""
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ PMO SESSION RESUME                                          │"
echo "├─────────────────────────────────────────────────────────────┤"
cat "$HANDOFF_FILE" | sed 's/^/│ /'
echo "└─────────────────────────────────────────────────────────────┘"
echo ""

log_info "Handoff loaded from: $HANDOFF_FILE"
