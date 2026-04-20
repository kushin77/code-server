#!/usr/bin/env bash
# @file        scripts/ci/check-no-powershell.sh
# @module      ci/governance
# @description Enforce Linux-native mandate by detecting PowerShell/Windows artifacts in the repo.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Track violations
violations=0
violation_file="${VIOLATIONS_FILE:-artifacts/triage/powershell-violations.log}"

mkdir -p "$(dirname "$violation_file")"
: > "$violation_file"

log_info "Checking for PowerShell/Windows artifacts (Linux-native mandate enforcement)"

# 1. Detect .ps1, .psm1, .psd1, .bat, .cmd files (excluding deprecated/ and archives)
log_info "Scanning for PowerShell/batch script files..."
while IFS= read -r file; do
  if [[ ! "$file" =~ deprecated|archive ]]; then
    echo "[VIOLATION] Found PowerShell/batch file: $file" | tee -a "$violation_file"
    violations=$((violations + 1))
  fi
done < <(git ls-files | grep -E '\.(ps1|psm1|psd1|bat|cmd)$' || true)

# 2. Detect PowerShell references in bash/shell scripts
log_info "Scanning for PowerShell/Windows references in shell scripts..."
while IFS= read -r file; do
  if git grep -l 'pwsh\|powershell\.exe\|Set-Location\|Get-ChildItem\|\$env:' -- "$file" >/dev/null 2>&1; then
    violations=$((violations + 1))
    echo "[VIOLATION] Found PowerShell references in: $file" | tee -a "$violation_file"
    # Show the matching lines
    git grep -n 'pwsh\|powershell\.exe\|Set-Location\|Get-ChildItem\|\$env:' -- "$file" | sed 's/^/  /' >> "$violation_file"
  fi
done < <(git ls-files | grep -E '\.(sh|bash)$' | grep -v deprecated | head -100 || true)

# 3. Detect windows-* runners in GitHub Actions workflows
log_info "Scanning for Windows runners in CI workflows..."
while IFS= read -r file; do
  if git grep -l 'runs-on.*windows' -- "$file" >/dev/null 2>&1; then
    violations=$((violations + 1))
    echo "[VIOLATION] Found Windows runner in: $file" | tee -a "$violation_file"
    git grep -n 'runs-on.*windows' -- "$file" | sed 's/^/  /' >> "$violation_file"
  fi
done < <(git ls-files | grep -E '\.github/workflows/.*\.yml$' || true)

# 4. Detect Windows paths in scripts/configs
log_info "Scanning for hardcoded Windows paths..."
while IFS= read -r file; do
  if git grep -l 'C:\\|\\Users\\|%APPDATA%|%USERPROFILE%|Program Files|Windows/System' -- "$file" >/dev/null 2>&1; then
    # Except for documentation explaining the Windows policy
    if [[ ! "$file" =~ CONTRIBUTING\.md|Windows.*\.md|adr.*\.md ]]; then
      violations=$((violations + 1))
      echo "[VIOLATION] Found Windows paths in: $file" | tee -a "$violation_file"
      git grep -n 'C:\\|\\Users\\|%APPDATA%|%USERPROFILE%|Program Files|Windows/System' -- "$file" | sed 's/^/  /' >> "$violation_file"
    fi
  fi
done < <(git ls-files | grep -v '\.(md|png|jpg)$' || true)

# Summary
log_info ""
if [[ $violations -eq 0 ]]; then
  log_info "✓ Linux-native enforcement passed: zero PowerShell/Windows artifacts detected"
  exit 0
else
  log_error "✗ Linux-native enforcement FAILED: $violations violation(s) detected"
  log_error "See violation details in: $violation_file"
  exit 1
fi
