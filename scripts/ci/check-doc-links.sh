#!/usr/bin/env bash
# @file        scripts/ci/check-doc-links.sh
# @module      ci/docs
# @description Unified documentation link checker for all Markdown files
# @governance  GOV-002: deterministic, idempotent, env-driven checks

set -euo pipefail
IFS=$'\n\t'

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly LINK_CONFIG="${LINK_CONFIG:-${REPO_ROOT}/.markdown-link-check.json}"
readonly DOCS_SCOPE="${DOCS_SCOPE:-all}"  # all | docs

if ! command -v markdown-link-check >/dev/null 2>&1; then
  echo "ERROR: markdown-link-check is not installed."
  echo "Install with: npm install -g markdown-link-check"
  exit 1
fi

if [[ ! -f "${LINK_CONFIG}" ]]; then
  echo "ERROR: Link checker config not found at ${LINK_CONFIG}"
  exit 1
fi

collect_markdown_files() {
  if [[ "${DOCS_SCOPE}" == "docs" ]]; then
    find "${REPO_ROOT}/docs" -type f -name "*.md" 2>/dev/null | sort
    return
  fi

  find "${REPO_ROOT}" -type f -name "*.md" \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/htmlcov/*" \
    -not -path "*/test-results/*" \
    -not -path "*/.venv/*" \
    | sort
}

mapfile -t markdown_files < <(collect_markdown_files)

if [[ ${#markdown_files[@]} -eq 0 ]]; then
  echo "No markdown files found for scope=${DOCS_SCOPE}."
  exit 0
fi

echo "Unified docs link-checker"
echo "- Scope: ${DOCS_SCOPE}"
echo "- Files: ${#markdown_files[@]}"
echo "- Config: ${LINK_CONFIG}"

failed=0
for md_file in "${markdown_files[@]}"; do
  rel_path="${md_file#${REPO_ROOT}/}"
  echo "Checking: ${rel_path}"
  if ! markdown-link-check "${md_file}" -q -c "${LINK_CONFIG}"; then
    failed=1
  fi
done

if [[ ${failed} -ne 0 ]]; then
  echo "ERROR: broken links detected in markdown files."
  exit 1
fi

echo "SUCCESS: no broken links found."
