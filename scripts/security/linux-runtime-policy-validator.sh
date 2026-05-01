#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Linux runtime policy validation failed at line $LINENO"; exit 1' ERR

readonly WINDOWS_ARTIFACT_PATTERN='\.ps1$|\.bat$|\.cmd$|pwsh|powershell\.exe|cmd\.exe|Write-Host|Get-ChildItem|Set-Location|Import-Module'

log_info "Validating Linux-only runtime policy..."

mapfile -t runtime_files < <(
  git ls-files -- \
    'scripts/**' \
    '.github/workflows/**' \
    'terraform/**' \
    'apps/**' \
    'config/**' \
    'docker-compose.yml' \
    'docker-compose.*.yml'
)

violations=()

for file in "${runtime_files[@]}"; do
  if [[ "$file" =~ \.ps1$|\.bat$|\.cmd$ ]]; then
    violations+=("$file")
  fi
done

content_hits=()
if [ "${#runtime_files[@]}" -gt 0 ]; then
  while IFS= read -r hit_file; do
    [ -n "$hit_file" ] || continue
    content_hits+=("$hit_file")
  done < <(
    grep -nEI "$WINDOWS_ARTIFACT_PATTERN" "${runtime_files[@]}" 2>/dev/null | cut -d: -f1 | sort -u || true
  )
fi

if [ "${#violations[@]}" -gt 0 ] || [ "${#content_hits[@]}" -gt 0 ]; then
  log_error "Windows-only runtime artifacts detected in Linux runtime surface:"
  if [ "${#violations[@]}" -gt 0 ]; then
    printf '  - %s\n' "${violations[@]}"
  fi
  if [ "${#content_hits[@]}" -gt 0 ]; then
    printf '  - %s\n' "${content_hits[@]}"
  fi
  exit 1
fi

log_success "Linux-only runtime policy passed"