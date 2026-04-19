#!/usr/bin/env bash
# File: scripts/ci/check-no-windows-content.sh
# Ref: #399 — CI-ENFORCEMENT: block Windows-specific content from Linux-only repo
# Part of: pre-commit (no-windows-content) and CI workflow (linux-mandate)
#
# Usage: called by pre-commit with filenames as args, OR standalone:
#   bash scripts/ci/check-no-windows-content.sh <file...>
#   bash scripts/ci/check-no-windows-content.sh  # scan all tracked files
set -euo pipefail

# ── patterns ──────────────────────────────────────────────────────────────────
# PowerShell indicators (not node_modules stub files)
PS_PATTERNS=(
  'Invoke-Expression'
  'Write-Host'
  'Get-ChildItem'
  'Set-Location'
  '\$PSScriptRoot'
  'param\s*\('
  '\[CmdletBinding'
  'Write-Error'
  'Write-Verbose'
  'Get-Content'
)

# Windows path patterns
WIN_PATH_PATTERNS=(
  '[A-Za-z]:\\\\[A-Za-z]'          # C:\foo\bar
  '\\\\\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9._-]+'  # \\server\share UNC path
)

# CRLF: checked separately via git

# ── helpers ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
NC='\033[0m'

fail=0
violations=()

check_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  # Skip node_modules and archived directories
  if [[ "$f" == *node_modules* || "$f" == */.archived/* || "$f" == */archived/* ]]; then
    return 0
  fi

  # Skip this checker script itself to avoid self-matching regex token definitions.
  if [[ "$f" == "scripts/ci/check-no-windows-content.sh" ]]; then
    return 0
  fi

  # Check PowerShell patterns (only in .sh, .py, .tf — not in PS1 which is expected)
  if [[ "$f" =~ \.(sh|bash|py|tf)$ ]]; then
    for pat in "${PS_PATTERNS[@]}"; do
      if grep -qE "$pat" "$f" 2>/dev/null; then
        violations+=("$f: PowerShell pattern detected: $pat")
        fail=1
      fi
    done
  fi

  # Check Windows paths in all target files
  for pat in "${WIN_PATH_PATTERNS[@]}"; do
    if grep -qE "$pat" "$f" 2>/dev/null; then
      violations+=("$f: Windows path pattern detected: $pat")
      fail=1
    fi
  done

  # CRLF check
  if file "$f" 2>/dev/null | grep -q 'CRLF'; then
    violations+=("$f: CRLF line endings — run: git add --renormalize .")
    fail=1
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
  # pre-commit mode: files passed as args
  for f in "$@"; do
    check_file "$f"
  done
else
  # Standalone scan mode: all tracked non-binary files
  while IFS= read -r f; do
    check_file "$f"
  done < <(git ls-files --cached --others --exclude-standard \
             | grep -E '\.(sh|bash|py|tf|yml|yaml)$')
fi

if [[ ${#violations[@]} -gt 0 ]]; then
  echo -e "${RED}✗ Windows-content violations:${NC}"
  for v in "${violations[@]}"; do
    echo "  $v"
  done
  echo ""
  echo "This is a Linux-only repository. All scripts must use bash/POSIX, LF line endings,"
  echo "and Linux-native paths. See issue #399."
  exit 1
fi

echo "✅ No Windows-specific content detected"
exit 0
