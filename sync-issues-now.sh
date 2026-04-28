#!/usr/bin/env bash
# Wrapper: retrieve a GitHub token from GCP Secret Manager and push local tasks.

set -euo pipefail
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

PROJECT_ID="${GCP_PROJECT:-purebliss-ghl}"
SECRET_CANDIDATES=("github-token" "github-fine-grained-token")

echo "════════════════════════════════════════════════════════════"
echo "GitHub Task Sync - Using GCP Secret Manager Token"
echo "════════════════════════════════════════════════════════════"
echo ""

if ! command -v gcloud >/dev/null 2>&1; then
  echo "❌ gcloud CLI not found"
  exit 1
fi

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
USED_SECRET=""

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Step 1: Retrieving GitHub token from GCP Secret Manager..."
  for secret_name in "${SECRET_CANDIDATES[@]}"; do
    token=$(gcloud secrets versions access latest --secret="$secret_name" --project="$PROJECT_ID" 2>/dev/null || true)
    if [[ -n "$token" ]]; then
      GITHUB_TOKEN="$token"
      USED_SECRET="$secret_name"
      break
    fi
  done
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "❌ Failed to retrieve a usable GitHub token from GCP Secret Manager"
  echo "Checked secrets: ${SECRET_CANDIDATES[*]}"
  exit 1
fi

echo "✅ Token retrieved from ${USED_SECRET:-environment}"
export GITHUB_TOKEN
export GITHUB_OWNER="${GITHUB_OWNER:-kushin77}"
export GITHUB_REPO="${GITHUB_REPO:-code-server}"

echo ""
echo "Step 2: Syncing local tasks to GitHub Issues..."
if [[ -n "${SYNC_PATH_FILTER:-}" ]]; then
  echo "  - SYNC_PATH_FILTER=${SYNC_PATH_FILTER}"
fi
if [[ -n "${SYNC_START_AFTER:-}" ]]; then
  echo "  - SYNC_START_AFTER=${SYNC_START_AFTER}"
fi
if [[ -n "${SYNC_MAX_CREATE:-}" ]]; then
  echo "  - SYNC_MAX_CREATE=${SYNC_MAX_CREATE}"
fi
echo ""

bash sync-issues-to-github.sh
