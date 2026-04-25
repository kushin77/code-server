#!/bin/bash
# @file validate-windows-artifact-policy.sh
# @module governance/compliance
# @description P0-1850: Enforce Linux-only runtime policy by blocking Windows/PowerShell artifacts in production execution paths
# @governance D07: No Windows/PowerShell operational artifacts in production/runtime CI/CD paths
# @usage validate-windows-artifact-policy.sh [--fix]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Paths that MUST NOT contain Windows/PowerShell artifacts (production contexts)
PRODUCTION_PATHS=(
  ".github/workflows"
  "scripts/ops"
  "scripts/ci"
  "scripts/deploy"
  "docker/"
  "terraform/"
)

# Paths where dev-local utilities are acceptable (local development only)
DEVELOPER_PATHS=(
  ".vscode"
)

VIOLATIONS=0
WARNINGS=0

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2
}

log_warning() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*"
}

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*"
}

# Check production paths for Windows/PowerShell violations
check_production_paths() {
  log_info "Checking production paths for Windows/PowerShell artifacts..."
  
  for path in "${PRODUCTION_PATHS[@]}"; do
    if [[ ! -d "${REPO_ROOT}/${path}" ]]; then
      continue
    fi
    
    # Check for .ps1, .psm1, .cmd, .bat files in production paths
    while IFS= read -r file; do
      if [[ -n "${file}" ]]; then
        log_error "Production path violation: Found Windows artifact in ${path}: ${file}"
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
    done < <(find "${REPO_ROOT}/${path}" -type f \( -name "*.ps1" -o -name "*.psm1" -o -name "*.cmd" -o -name "*.bat" \) 2>/dev/null || true)
    
    # Check for PowerShell command references in production scripts
    while IFS= read -r file; do
      if [[ -n "${file}" ]]; then
        local ps_refs=$(grep -c "powershell\|Get-Content\|Set-Content\|Write-Output\|Select-Object" "${file}" || true)
        if [[ ${ps_refs} -gt 0 ]]; then
          log_error "Production path violation: Found PowerShell commands in ${file} (${ps_refs} references)"
          VIOLATIONS=$((VIOLATIONS + 1))
        fi
      fi
    done < <(find "${REPO_ROOT}/${path}" -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" \) 2>/dev/null || true)
  done
}

# Check developer paths for proper isolation markers
check_developer_paths() {
  log_info "Checking developer paths for proper isolation..."
  
  for path in "${DEVELOPER_PATHS[@]}"; do
    if [[ ! -d "${REPO_ROOT}/${path}" ]]; then
      continue
    fi
    
    # Check if .vscode/tasks.json exists
    if [[ -f "${REPO_ROOT}/${path}/tasks.json" ]]; then
      # Verify it has a clear comment indicating dev-local only
      if ! grep -q "@dev-local-only\|@description.*dev.*local\|LOCAL DEVELOPMENT" "${REPO_ROOT}/${path}/tasks.json"; then
        log_warning "Developer path not clearly marked as dev-local: ${path}/tasks.json"
        WARNINGS=$((WARNINGS + 1))
      fi
    fi
  done
}

# Ensure no .gitignore violations (PowerShell files shouldn't be committed anyway)
check_tracked_artifacts() {
  log_info "Checking git tracking for Windows artifacts..."
  
  cd "${REPO_ROOT}"
  
  local tracked_windows_files=$(git ls-files --exclude-standard | grep -E '\.(ps1|psm1|cmd|bat)$' || true)
  
  if [[ -n "${tracked_windows_files}" ]]; then
    while IFS= read -r file; do
      if [[ -n "${file}" ]]; then
        log_error "Git tracking violation: Windows artifact is tracked in git: ${file}"
        VIOLATIONS=$((VIOLATIONS + 1))
      fi
    done <<< "${tracked_windows_files}"
  fi
}

# Main validation
main() {
  log_info "Starting Windows Artifact Policy Validation (D07 Governance)"
  log_info "Checking $(pwd)"
  
  check_production_paths
  check_developer_paths
  check_tracked_artifacts
  
  echo ""
  log_info "Validation Results:"
  log_info "  Production path violations: ${VIOLATIONS}"
  log_info "  Developer path warnings: ${WARNINGS}"
  
  if [[ ${VIOLATIONS} -gt 0 ]]; then
    log_error "FAILED: Policy enforcement violations detected"
    return 1
  else
    log_info "PASSED: No production-path Windows artifacts detected"
    return 0
  fi
}

main "$@"
