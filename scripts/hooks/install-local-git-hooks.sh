#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

if [[ ! -d ".githooks" ]]; then
  echo "[hooks] Missing .githooks directory"
  exit 1
fi

git config core.hooksPath .githooks

chmod +x .githooks/pre-push || true
chmod +x scripts/hooks/pre-push-branch-hygiene.sh || true
chmod +x scripts/ci/check-merged-branch-cleanup.sh || true

echo "[hooks] Installed repository-managed git hooks (core.hooksPath=.githooks)"
