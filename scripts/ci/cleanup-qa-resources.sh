#!/usr/bin/env bash
# @file        scripts/ci/cleanup-qa-resources.sh
# @module      ci/e2e
# @description Clean up QA sessions, workspaces, and test containers after E2E runs.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REDIS_HOST="${REDIS_HOST:-redis}"
WORKSPACE_BASE="${WORKSPACE_BASE:-/var/lib/code-server/workspaces}"
QA_SESSION_PATTERN="${QA_SESSION_PATTERN:-session:qa:*}"
QA_WORKSPACE_PATTERN="${QA_WORKSPACE_PATTERN:-qa-test-*}"
QA_CONTAINER_LABEL="${QA_CONTAINER_LABEL:-qa-test=true}"
DRY_RUN="${DRY_RUN:-1}"

cleanup_redis_sessions() {
  log_info "Cleaning up QA sessions from Redis"

  if ! command -v redis-cli >/dev/null 2>&1; then
    log_warn "redis-cli is not available; skipping Redis cleanup"
    return 0
  fi

  local keys
  keys="$(redis-cli -h "$REDIS_HOST" --scan --pattern "$QA_SESSION_PATTERN" 2>/dev/null || true)"

  if [[ -z "$keys" ]]; then
    log_info "No QA sessions found in Redis"
    return 0
  fi

  local count
  count="$(printf '%s\n' "$keys" | sed '/^$/d' | wc -l | tr -d ' ')"
  log_info "Found ${count} QA session key(s)"

  if [[ "$DRY_RUN" == "1" ]]; then
    while IFS= read -r key; do
      [[ -n "$key" ]] || continue
      log_info "[DRY-RUN] Would delete Redis key: ${key}"
    done <<< "$keys"
    return 0
  fi

  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    redis-cli -h "$REDIS_HOST" DEL "$key" >/dev/null
  done <<< "$keys"

  log_info "Deleted ${count} QA session key(s)"
}

cleanup_workspaces() {
  log_info "Cleaning up QA workspaces"

  if [[ ! -d "$WORKSPACE_BASE" ]]; then
    log_warn "Workspace directory not found: ${WORKSPACE_BASE}"
    return 0
  fi

  local matched=0
  while IFS= read -r workspace_dir; do
    [[ -n "$workspace_dir" ]] || continue
    matched=1

    if [[ "$DRY_RUN" == "1" ]]; then
      log_info "[DRY-RUN] Would delete workspace: ${workspace_dir}"
      continue
    fi

    rm -rf "$workspace_dir"
    log_info "Deleted workspace: ${workspace_dir}"
  done < <(find "$WORKSPACE_BASE" -maxdepth 1 -type d -name "$QA_WORKSPACE_PATTERN" 2>/dev/null || true)

  if [[ "$matched" -eq 0 ]]; then
    log_info "No QA workspaces found"
  fi
}

cleanup_containers() {
  log_info "Cleaning up QA containers"

  if ! command -v docker >/dev/null 2>&1; then
    log_warn "docker is not available; skipping container cleanup"
    return 0
  fi

  local containers
  containers="$(docker ps -a --filter "label=${QA_CONTAINER_LABEL}" --format '{{.ID}}' 2>/dev/null || true)"

  if [[ -z "$containers" ]]; then
    log_info "No QA containers found"
    return 0
  fi

  local count
  count="$(printf '%s\n' "$containers" | sed '/^$/d' | wc -l | tr -d ' ')"
  log_info "Found ${count} QA container(s)"

  if [[ "$DRY_RUN" == "1" ]]; then
    while IFS= read -r container_id; do
      [[ -n "$container_id" ]] || continue
      log_info "[DRY-RUN] Would remove container: ${container_id}"
    done <<< "$containers"
    return 0
  fi

  while IFS= read -r container_id; do
    [[ -n "$container_id" ]] || continue
    docker rm -f "$container_id" >/dev/null
  done <<< "$containers"

  log_info "Removed ${count} QA container(s)"
}

main() {
  log_info "Starting QA resource cleanup (DRY_RUN=${DRY_RUN})"

  cleanup_redis_sessions
  cleanup_workspaces
  cleanup_containers

  log_info "QA resource cleanup complete"
}

main "$@"
