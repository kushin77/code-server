#!/usr/bin/env bash
# @file        scripts/ci/check-no-windows-content.sh
# @module      ci/content
# @description Block Windows-specific content from Linux-only repository files
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

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
  log_error "Windows-content violations:"
  for v in "${violations[@]}"; do
    log_error "  $v"
  done
  log_error ""
  log_error "This is a Linux-only repository. All scripts must use bash/POSIX, LF line endings,"
  log_error "and Linux-native paths. See issue #399."
  exit 1
fi

log_info "No Windows-specific content detected"
exit 0
