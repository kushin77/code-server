#!/usr/bin/env bash
# Wrapper: retrieve a GitHub token and push grouped SLOG findings.

set -euo pipefail
trap 'echo "Script failed at line $LINENO"; exit 1' ERR
trap 'echo "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

PROJECT_ID="${GCP_PROJECT:-purebliss-ghl}"
SECRET_CANDIDATES=("github-token" "github-fine-grained-token")

echo "════════════════════════════════════════════════════════════"
echo "GitHub SLOG Sync - Grouped Error Triage"
echo "════════════════════════════════════════════════════════════"
echo ""

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
USED_SECRET=""

if [[ -z "$GITHUB_TOKEN" && -n "$(command -v gcloud 2>/dev/null || true)" ]]; then
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

if [[ -z "$GITHUB_TOKEN" && -n "$(command -v git 2>/dev/null || true)" ]]; then
  echo "Step 2: Retrieving GitHub token from git credential helper..."
  token=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | awk -F= '/^password=/{print $2; exit}')
  if [[ -n "$token" ]]; then
    GITHUB_TOKEN="$token"
    USED_SECRET="git-credential-helper"
  fi
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "❌ Failed to retrieve a usable GitHub token"
  echo "Checked GCP secrets: ${SECRET_CANDIDATES[*]}"
  exit 1
fi

echo "✅ Token retrieved from ${USED_SECRET:-environment}"
export GITHUB_TOKEN
export GITHUB_OWNER="${GITHUB_OWNER:-kushin77}"
export GITHUB_REPO="${GITHUB_REPO:-code-server}"

echo ""
echo "Step 3: Syncing grouped slog issues..."
echo "  - default runtime sources: logs/*.log, logs/**/*.log, *.log, artifacts/**/*.log"
echo "  - default markdown log scanning: enabled"
echo "  - default severities: warning,error,critical,issue"
if [[ -n "${SLOG_PATH_FILTER:-}" ]]; then
  echo "  - SLOG_PATH_FILTER=${SLOG_PATH_FILTER}"
fi
if [[ -n "${SLOG_MAX_CREATE:-}" ]]; then
  echo "  - SLOG_MAX_CREATE=${SLOG_MAX_CREATE}"
fi
if [[ -n "${SLOG_INCLUDE_PATTERNS:-}" ]]; then
  echo "  - SLOG_INCLUDE_PATTERNS=${SLOG_INCLUDE_PATTERNS}"
fi
if [[ -n "${SLOG_SEVERITIES:-}" ]]; then
  echo "  - SLOG_SEVERITIES=${SLOG_SEVERITIES}"
fi
if [[ -n "${SLOG_INCLUDE_MARKDOWN_LOGS:-}" ]]; then
  echo "  - SLOG_INCLUDE_MARKDOWN_LOGS=${SLOG_INCLUDE_MARKDOWN_LOGS}"
fi
if [[ -n "${SLOG_DRY_RUN:-}" ]]; then
  echo "  - SLOG_DRY_RUN=${SLOG_DRY_RUN}"
fi
echo ""

bash sync-slog-to-github.sh "$@"