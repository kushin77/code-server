#!/usr/bin/env bash

################################################################################
# @file check-local-git-hook-integrity.sh
# @module github-governance
# @description Enforce repository-managed local hook integrity for branch hygiene
# @governance GOV-002: Immutable, version-controlled, idempotent infrastructure
################################################################################

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "${REPO_ROOT}"

required_files=(
  ".githooks/pre-push"
  "scripts/hooks/pre-push-branch-hygiene.sh"
  "scripts/hooks/install-local-git-hooks.sh"
  "scripts/ci/check-merged-branch-cleanup.sh"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "${file}" ]]; then
    echo "❌ Missing required hook file: ${file}"
    exit 1
  fi
done

# Executable bit must be preserved for shell hook assets.
executable_files=(
  ".githooks/pre-push"
  "scripts/hooks/pre-push-branch-hygiene.sh"
  "scripts/hooks/install-local-git-hooks.sh"
  "scripts/ci/check-merged-branch-cleanup.sh"
)

for file in "${executable_files[@]}"; do
  if [[ ! -x "${file}" ]]; then
    echo "❌ File must be executable: ${file}"
    exit 1
  fi
done

if ! grep -q "core.hooksPath .githooks" scripts/hooks/install-local-git-hooks.sh; then
  echo "❌ Installer must configure core.hooksPath to .githooks"
  exit 1
fi

if ! grep -q "pre-push-branch-hygiene.sh" .githooks/pre-push; then
  echo "❌ .githooks/pre-push must invoke pre-push branch hygiene script"
  exit 1
fi

if ! grep -q "check-merged-branch-cleanup.sh" scripts/hooks/pre-push-branch-hygiene.sh; then
  echo "❌ pre-push branch hygiene script must invoke merged-branch cleanup checker"
  exit 1
fi

if ! grep -q '"hooks:install"' package.json; then
  echo "❌ package.json must expose hooks:install script"
  exit 1
fi

echo "✓ Local git hook integrity checks passed"
