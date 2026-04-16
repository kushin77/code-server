#!/usr/bin/env bash
# Global quality gate for local/CI runs.
# Enforces repo-wide invariants before deploy or release operations.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

GATE_MODE="${GATE_MODE:-incremental}"  # incremental|strict
IP_FILE_PATTERNS=("*.sh" "*.tf" "*.yml" "*.yaml")

echo "[gate] Running global quality gate from: $ROOT_DIR"

collect_incremental_files() {
  local files=()

  if [[ "${CI:-}" == "true" ]]; then
    # PR validation: compare against target branch.
    if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
      git fetch --no-tags --depth=1 origin "${GITHUB_BASE_REF}" >/dev/null 2>&1 || true
      while IFS= read -r f; do files+=("$f"); done < <(git diff --name-only "origin/${GITHUB_BASE_REF}...HEAD" -- "${IP_FILE_PATTERNS[@]}" || true)
    elif [[ -n "${GITHUB_EVENT_BEFORE:-}" && "${GITHUB_EVENT_BEFORE}" != "0000000000000000000000000000000000000000" ]]; then
      while IFS= read -r f; do files+=("$f"); done < <(git diff --name-only "${GITHUB_EVENT_BEFORE}" "HEAD" -- "${IP_FILE_PATTERNS[@]}" || true)
    fi
  else
    # Local runs: only scan local delta to avoid blocking on historical debt.
    while IFS= read -r f; do files+=("$f"); done < <(git diff --name-only -- "${IP_FILE_PATTERNS[@]}" || true)
    while IFS= read -r f; do files+=("$f"); done < <(git diff --cached --name-only -- "${IP_FILE_PATTERNS[@]}" || true)
    while IFS= read -r f; do files+=("$f"); done < <(git ls-files --others --exclude-standard -- "${IP_FILE_PATTERNS[@]}" || true)
  fi

  if [[ ${#files[@]} -eq 0 ]]; then
    return 0
  fi

  printf '%s\n' "${files[@]}" | awk '!seen[$0]++' | while IFS= read -r f; do
    [[ -f "$f" ]] && echo "$f"
  done
}

if ! command -v git >/dev/null 2>&1; then
  echo "[gate] FATAL: git is required" >&2
  exit 2
fi

if ! command -v bash >/dev/null 2>&1; then
  echo "[gate] FATAL: bash is required" >&2
  exit 2
fi

# 1) Hardcoded production IP gate.
if [[ -f "scripts/lib/check-no-ips.sh" ]]; then
  echo "[gate] Checking hardcoded production IPs (mode: ${GATE_MODE})"
  if [[ "${GATE_MODE}" == "strict" ]]; then
    bash scripts/lib/check-no-ips.sh
  else
    mapfile -t incremental_files < <(collect_incremental_files || true)
    if [[ ${#incremental_files[@]} -eq 0 ]]; then
      echo "[gate] No changed shell/terraform/yaml files detected; skipping incremental IP scan"
    else
      PRE_COMMIT_FILES="$(printf '%s\n' "${incremental_files[@]}")" bash scripts/lib/check-no-ips.sh
    fi
  fi
fi

# 2) Shell syntax validation.
echo "[gate] Validating shell syntax (mode: ${GATE_MODE})"
if [[ "${GATE_MODE}" == "strict" ]]; then
  while IFS= read -r -d '' f; do
    bash -n "$f"
  done < <(find scripts -type f -name "*.sh" -print0)
else
  mapfile -t shell_files < <(collect_incremental_files | grep -E '\.sh$' || true)
  if [[ ${#shell_files[@]} -eq 0 ]]; then
    echo "[gate] No changed shell files detected; skipping incremental shell syntax scan"
  else
    for f in "${shell_files[@]}"; do
      bash -n "$f"
    done
  fi
fi

# 3) Check for phase-based script naming violations (Issue #382).
echo "[gate] Checking for deprecated phase-based script naming patterns"
mapfile -t all_scripts < <(find scripts -type f -name "*.sh" -newer /etc/os-release 2>/dev/null || find scripts -type f -name "*.sh" 2>/dev/null | tail -1000 || true)
phase_violations=()
for script in "${all_scripts[@]}"; do
  if [[ "$script" =~ (phase-|deploy-phase-|PHASE-) ]]; then
    # Allow if script already has DEPRECATED header
    if ! head -5 "$script" | grep -q "DEPRECATED"; then
      phase_violations+=("$script")
    fi
  fi
done

if [[ ${#phase_violations[@]} -gt 0 ]]; then
  echo "[gate] WARN: Found ${#phase_violations[@]} script(s) using deprecated phase-based naming:"
  for v in "${phase_violations[@]}"; do
    echo "[gate]   - $v"
  done
  echo "[gate]   See: DEPRECATED-SCRIPTS.md for canonical replacements"
  echo "[gate]   See: scripts/README.md for task mapping"
fi

# 4) Validate key single-source-of-truth inventories (non-fatal: warn on missing yq or file).
if command -v yq >/dev/null 2>&1; then
  echo "[gate] Validating inventory YAML"
  for inv_file in inventory/infrastructure.yaml inventory/dns.yaml; do
    if [[ -f "${inv_file}" ]]; then
      if ! yq eval "." "${inv_file}" >/dev/null 2>&1; then
        echo "[gate] WARN: ${inv_file} failed yq validation -- review YAML syntax" >&2
      fi
    else
      echo "[gate] WARN: ${inv_file} not found -- skipping"
    fi
  done
else
  echo "[gate] WARN: yq not available, skipping YAML structural validation"
fi

echo "[gate] OK: global quality gate passed"
