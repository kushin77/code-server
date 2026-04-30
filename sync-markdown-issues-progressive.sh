#!/usr/bin/env bash
# Progressive GitHub Issue Sync - Handles large task lists with rate limiting
# Usage: ./sync-markdown-issues-progressive.sh [--batch-size N] [--start-after "task name"]

set -euo pipefail
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

export GITHUB_OWNER="${GITHUB_OWNER:-kushin77}"
export GITHUB_REPO="${GITHUB_REPO:-code-server}"
export SYNC_MAX_CREATE="${1:-100}"  # Default: create 100 per run
export SYNC_START_AFTER="${SYNC_START_AFTER:-}"  # Resume checkpoint

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  export GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-token" 2>/dev/null || echo "")
  if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "❌ GITHUB_TOKEN not available"
    exit 1
  fi
fi

echo "🚀 Progressive Markdown Issue Sync"
echo "===================================="
echo "Batch size: $SYNC_MAX_CREATE"
echo "Resume checkpoint: ${SYNC_START_AFTER:-(start from beginning)}"
echo ""

# Run the actual sync with rate limit retry
bash sync-issues-to-github.sh 2>&1 | tee /tmp/markdown-sync-$(date +%s).log

echo ""
echo "✅ Batch completed"
echo ""
echo "To run the next batch, check the log above for the last synced issue"
echo "Then run: SYNC_START_AFTER='<last task name>' ./sync-markdown-issues-progressive.sh"
echo ""
echo "Current rate: ~60 tasks/hour (OAuth limit)"
echo "Total tasks: 1922"
echo "Estimated time to complete all batches: ~32 hours"
