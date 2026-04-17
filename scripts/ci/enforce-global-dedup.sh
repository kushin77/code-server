#!/usr/bin/env bash
# @file        scripts/ci/enforce-global-dedup.sh
# @module      governance/duplication
# @description Enforce global SSOT and block overlap-prone changes in CI.
# @owner       platform
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

cd "${REPO_ROOT}"

ALLOW_LEGACY_OVERLAP_EDIT="${ALLOW_LEGACY_OVERLAP_EDIT:-false}"

readonly CANONICAL_COMPOSE="docker-compose.yml"
readonly CANONICAL_CADDYFILE="Caddyfile"
readonly CANONICAL_TERRAFORM="terraform/main.tf"

# Legacy/overlap-prone files are blocked by default in CI to prevent new drift.
readonly BLOCKED_FILES=(
  "docker/docker-compose.yml"
  "scripts/docker-compose.yml"
  "docker-compose.production.yml"
  "docker-compose.prod.yml"
  "docker-compose.base.yml"
  "docker-compose.dev.yml"
  "Caddyfile.production"
  "Caddyfile.tpl"
)

# Some files intentionally document legacy paths and are exempt from reference checks.
readonly REFERENCE_ALLOWLIST=(
  "scripts/ci/enforce-global-dedup.sh"
  "docs/governance/GLOBAL-DEDUP-GOVERNANCE.md"
  "docs/governance/GLOBAL-DEDUP-TRIAGE.md"
)

# Determine a robust diff range for both PR and push events.
resolve_diff_range() {
  local base_ref=""

  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    base_ref="origin/${GITHUB_BASE_REF}"
  elif git show-ref --verify --quiet refs/remotes/origin/main; then
    base_ref="origin/main"
  fi

  if [[ -n "${base_ref}" ]]; then
    echo "${base_ref}...HEAD"
  else
    # Fallback for local/offline execution: scan tracked files as "changed" scope.
    echo ""
  fi
}

collect_changed_files() {
  local range="$1"
  if [[ -n "${range}" ]]; then
    git diff --name-only "${range}" | sed '/^$/d'
  else
    git ls-files
  fi
}

collect_added_files() {
  local range="$1"
  if [[ -n "${range}" ]]; then
    git diff --name-status "${range}" | awk '$1 ~ /^A/ {print $2}'
  fi
}

is_blocked_file() {
  local f="$1"
  local blocked
  for blocked in "${BLOCKED_FILES[@]}"; do
    if [[ "${f}" == "${blocked}" ]]; then
      return 0
    fi
  done
  return 1
}

is_changed_file() {
  local needle="$1"
  local file
  for file in "${CHANGED_FILES[@]}"; do
    if [[ "${file}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

is_allowlisted_reference_file() {
  local f="$1"
  local allowed
  for allowed in "${REFERENCE_ALLOWLIST[@]}"; do
    if [[ "${f}" == "${allowed}" ]]; then
      return 0
    fi
  done
  return 1
}

is_archived_file() {
  local f="$1"
  [[ "${f}" == archived/* || "${f}" == .archived/* || "${f}" == scripts/_archive/* ]]
}

failures=0

DIFF_RANGE="$(resolve_diff_range)"
mapfile -t CHANGED_FILES < <(collect_changed_files "${DIFF_RANGE}")
mapfile -t ADDED_FILES < <(collect_added_files "${DIFF_RANGE}")

log_info "Global dedup guard started"
log_info "Canonical compose: ${CANONICAL_COMPOSE}"
log_info "Canonical Caddyfile: ${CANONICAL_CADDYFILE}"
log_info "Canonical Terraform entrypoint: ${CANONICAL_TERRAFORM}"

# 1) Block modifications to legacy overlap files unless explicitly waived.
if [[ "${ALLOW_LEGACY_OVERLAP_EDIT}" != "true" ]]; then
  for file in "${CHANGED_FILES[@]}"; do
    if is_blocked_file "${file}"; then
      log_error "Blocked overlap-prone file modified: ${file}"
      log_error "Use canonical files (${CANONICAL_COMPOSE}, ${CANONICAL_CADDYFILE}, ${CANONICAL_TERRAFORM}) instead."
      log_error "If absolutely required, rerun with ALLOW_LEGACY_OVERLAP_EDIT=true and document waiver."
      failures=$((failures + 1))
    fi
  done
fi

# 2) Prevent adding new duplicate top-level compose/caddy variants.
for file in "${ADDED_FILES[@]}"; do
  if [[ "${file}" =~ ^docker-compose.*\.ya?ml$ ]] && [[ "${file}" != "${CANONICAL_COMPOSE}" ]]; then
    log_error "New duplicate compose variant added: ${file}"
    failures=$((failures + 1))
  fi

  if [[ "${file}" =~ ^Caddyfile.*$ ]] && [[ "${file}" != "${CANONICAL_CADDYFILE}" ]]; then
    log_error "New duplicate Caddyfile variant added: ${file}"
    failures=$((failures + 1))
  fi

done

# 3) Ensure root Terraform mirror cannot drift when either mirror is changed.
if is_changed_file "main.tf" || is_changed_file "terraform/main.tf"; then
  if [[ -f "main.tf" && -f "terraform/main.tf" ]]; then
    if ! cmp -s "main.tf" "terraform/main.tf"; then
      log_error "Terraform mirror drift detected between main.tf and terraform/main.tf"
      log_error "When changing either mirror, sync both files in the same PR."
      failures=$((failures + 1))
    fi
  fi
fi

# 4) Enforce single callback variable pattern in canonical compose auth blocks.
if [[ -f "${CANONICAL_COMPOSE}" ]]; then
  callback_count="$(grep -c 'OAUTH2_PROXY_REDIRECT_URL:' "${CANONICAL_COMPOSE}" || true)"
  callback_var_count="$(grep -c 'OAUTH2_PROXY_REDIRECT_URL: "${OAUTH2_REDIRECT_URL:-https://ide.kushnir.cloud/oauth2/callback}"' "${CANONICAL_COMPOSE}" || true)"

  if [[ "${callback_count}" -lt 2 ]]; then
    log_error "Expected at least 2 OAUTH2_PROXY_REDIRECT_URL entries in ${CANONICAL_COMPOSE}, found ${callback_count}"
    failures=$((failures + 1))
  fi

  if [[ "${callback_var_count}" -lt 2 ]]; then
    log_error "Auth callback in ${CANONICAL_COMPOSE} is not centralized via OAUTH2_REDIRECT_URL in both proxy blocks"
    failures=$((failures + 1))
  fi
fi

# 5) Prevent newly-added docs with normalized-name collisions in docs/.
normalize_name() {
  local s="$1"
  echo "${s}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+//g'
}

if [[ "${#ADDED_FILES[@]}" -gt 0 ]]; then
  mapfile -t EXISTING_DOCS < <(git ls-files 'docs/**/*.md' 'docs/*.md' 2>/dev/null || true)

  for file in "${ADDED_FILES[@]}"; do
    if [[ "${file}" == docs/*.md || "${file}" == docs/**/*.md ]]; then
      added_base="$(basename "${file}")"
      added_norm="$(normalize_name "${added_base}")"

      for existing in "${EXISTING_DOCS[@]}"; do
        if [[ "${existing}" == "${file}" ]]; then
          continue
        fi

        existing_base="$(basename "${existing}")"
        existing_norm="$(normalize_name "${existing_base}")"

        if [[ -n "${added_norm}" && "${added_norm}" == "${existing_norm}" ]]; then
          log_error "Documentation name collision detected: ${file} ~= ${existing}"
          failures=$((failures + 1))
          break
        fi
      done
    fi
  done
fi

# 6) Block new references to blocked legacy files in changed, non-archived files.
for file in "${CHANGED_FILES[@]}"; do
  if [[ ! -f "${file}" ]]; then
    continue
  fi

  if is_blocked_file "${file}" || is_archived_file "${file}" || is_allowlisted_reference_file "${file}"; then
    continue
  fi

  blocked_ref=""
  for blocked_ref in "${BLOCKED_FILES[@]}"; do
    if grep -Fq "${blocked_ref}" "${file}"; then
      log_error "New/updated file references blocked legacy path: ${file} -> ${blocked_ref}"
      log_error "Use canonical files (${CANONICAL_COMPOSE}, ${CANONICAL_CADDYFILE}, ${CANONICAL_TERRAFORM}) instead."
      failures=$((failures + 1))
      break
    fi
  done
done

if [[ "${failures}" -gt 0 ]]; then
  log_fatal "Global dedup guard failed with ${failures} violation(s)."
fi

log_info "Global dedup guard passed"
