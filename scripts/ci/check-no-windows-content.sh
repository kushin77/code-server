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
  'powershell\.exe'
  'node\.exe'
  'npx\.cmd'
  'npx\.exe'
  'gh\.exe'
  'ssh\.exe'
  'wslpath'
)

# Windows path patterns
WIN_PATH_PATTERNS=(
  '[A-Za-z]:\\\\[A-Za-z]'          # C:\foo\bar
  '\\\\\\\\[A-Za-z0-9._-]+\\[A-Za-z0-9._-]+'  # \\server\share UNC path
  '/mnt/c/'                         # WSL Windows host path
  '\$APPDATA'                       # Windows env var
  '\$USERPROFILE'                   # Windows env var
  '\$LOCALAPPDATA'                  # Windows env var
)

# CRLF: checked separately via git

fail=0
violations=()

# ── check for .ps1 files outside deprecated/windows/ ──────────────────────────
PS1_FILES="$(find . -name "*.ps1" ! -path "*/deprecated/windows/*" ! -path "*/node_modules/*" -type f 2>/dev/null || true)"
if [[ -n "$PS1_FILES" ]]; then
  while IFS= read -r f; do
    violations+=("$f: PowerShell file (.ps1) found outside deprecated/windows/")
    fail=1
  done <<< "$PS1_FILES"
fi

# ── check for .bat files anywhere ───────────────────────────────────────────────
BAT_FILES="$(find . -name "*.bat" ! -path "*/node_modules/*" -type f 2>/dev/null || true)"
if [[ -n "$BAT_FILES" ]]; then
  while IFS= read -r f; do
    violations+=("$f: Batch file (.bat) found")
    fail=1
  done <<< "$BAT_FILES"
fi

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

  # Check PowerShell patterns (in .sh, .bash, .py, .tf, .ts, .js)
  if [[ "$f" =~ \.(sh|bash|py|tf|ts|js)$ ]]; then
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

  # CRLF check (tracked content): inspect git blob/index to avoid false positives
  # from local checkout conversion (e.g., core.autocrlf on Windows).
  if git cat-file -e ":$f" 2>/dev/null; then
    if git show ":$f" | LC_ALL=C grep -q $'\r'; then
      violations+=("$f: CRLF line endings in tracked content")
      # shellcheck disable=SC2034
      fail=1
    fi
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
  printf '[ERROR] Windows-content violations:\n' >&2
  for v in "${violations[@]}"; do
    printf '[ERROR]   %s\n' "$v" >&2
  done
  printf '[ERROR]\n' >&2
  printf '[ERROR] This is a Linux-only repository. All scripts must use bash/POSIX, LF line endings,\n' >&2
  printf '[ERROR] and Linux-native paths. See issue #399.\n' >&2
  exit 1
fi

log_info "No Windows-specific content detected"
exit 0
