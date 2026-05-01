#!/usr/bin/env bash
# @file scripts/ci/check-environment-health.sh
# @description Pre/post-deployment environment health check — verifies system
#              resources (disk, memory, CPU), required ports are free, and
#              external dependencies are reachable before a deployment begins.
# @usage check-environment-health.sh [--pre|--post] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

DRY_RUN=false
MODE="pre"  # pre | post

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --pre)     MODE="pre"; shift ;;
    --post)    MODE="post"; shift ;;
    *)         shift ;;
  esac
done

PASS=0; FAIL=0; WARN=0

check_disk() {
  local path="${1:-/}" min_pct="${2:-20}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] disk ${path}"; PASS=$((PASS+1)); return; fi
  local avail_pct
  avail_pct=$(df --output=pcent "${path}" 2>/dev/null | tail -1 | tr -d ' %')
  local free_pct=$(( 100 - avail_pct ))
  if (( free_pct >= min_pct )); then
    log_info "  ✅ disk ${path}: ${free_pct}% free"; PASS=$((PASS+1))
  else
    log_error "  ❌ disk ${path}: ${free_pct}% free (need ≥${min_pct}%)"; FAIL=$((FAIL+1))
  fi
}

check_memory() {
  local min_mb="${1:-512}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] memory"; PASS=$((PASS+1)); return; fi
  local avail_mb
  avail_mb=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
  if (( avail_mb >= min_mb )); then
    log_info "  ✅ memory: ${avail_mb}MB available"; PASS=$((PASS+1))
  else
    log_error "  ❌ memory: ${avail_mb}MB available (need ≥${min_mb}MB)"; FAIL=$((FAIL+1))
  fi
}

check_port_free() {
  local port="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] port ${port} free"; PASS=$((PASS+1)); return; fi
  if ! ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    log_info "  ✅ port ${port} free"; PASS=$((PASS+1))
  else
    log_info "  ⚠️  port ${port} in use (may be expected for ${MODE})"; WARN=$((WARN+1))
  fi
}

check_docker() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] docker daemon"; PASS=$((PASS+1)); return; fi
  if docker info >/dev/null 2>&1; then
    log_info "  ✅ docker daemon reachable"; PASS=$((PASS+1))
  else
    log_error "  ❌ docker daemon unreachable"; FAIL=$((FAIL+1))
  fi
}

check_terraform() {
  if command -v terraform >/dev/null 2>&1; then
    log_info "  ✅ terraform $(terraform version -json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('terraform_version','?'))" 2>/dev/null || echo '?')"; PASS=$((PASS+1))
  else
    log_error "  ❌ terraform not found in PATH"; FAIL=$((FAIL+1))
  fi
}

check_git_clean() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "  ✅ [dry-run] git clean"; PASS=$((PASS+1)); return; fi
  local dirty
  dirty=$(git -C "${REPO_ROOT}" status --porcelain 2>/dev/null | wc -l)
  if (( dirty == 0 )); then
    log_info "  ✅ working tree clean"; PASS=$((PASS+1))
  else
    log_info "  ⚠️  ${dirty} uncommitted change(s)"; WARN=$((WARN+1))
  fi
}

# Main
log_info "Environment Health — mode=${MODE} dry-run=${DRY_RUN}"
log_info "================================================"

log_info "System resources:"
check_disk "/" 15
check_disk "/var/lib/docker" 10
check_memory 1024

log_info "Toolchain:"
check_docker
check_terraform

log_info "Git state:"
check_git_clean

if [[ "${MODE}" == "pre" ]]; then
  log_info "Pre-deployment: checking required ports are free:"
  check_port_free 8080
  check_port_free 4317  # OTLP
fi

log_info "================================================"
log_info "Results: ${PASS} passed, ${FAIL} failed, ${WARN} warnings"
[[ ${FAIL} -eq 0 ]] && { log_info "✅ Environment healthy (${MODE})"; exit 0; } || \
  { log_error "❌ Environment check failed: ${FAIL} issue(s)"; exit 1; }
