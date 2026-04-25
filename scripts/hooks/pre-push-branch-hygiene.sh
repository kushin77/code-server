#!/usr/bin/env bash
set -euo pipefail

# Git pre-push stdin format:
# <local-ref> <local-sha> <remote-ref> <remote-sha>
# Enforce merged-branch cleanup gate only when pushing main.

run_gate=0

while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
  if [[ "${local_ref}" == "refs/heads/main" ]] || [[ "${remote_ref}" == "refs/heads/main" ]]; then
    run_gate=1
    break
  fi
done

if [[ "${run_gate}" -eq 0 ]]; then
  echo "[branch-hygiene] Skipping cleanup gate (push target is not main)."
  exit 0
fi

echo "[branch-hygiene] Enforcing merged-branch cleanup before push to main..."
exec bash scripts/ci/check-merged-branch-cleanup.sh
