#!/usr/bin/env bash
# @file        scripts/ops/preflight.sh
# @module      ops/deployment
# @description unified preflight gate for deploy paths and CI gating
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# Initialize repository context
init_repo

LOCAL_ONLY=false
FORWARD_ARGS=()
DEEP_PREFLIGHT="$REPO_ROOT/scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh"

usage() {
  cat <<'EOF'
Usage: preflight.sh [--local-only] [--help] [forwarded preflight args...]

Options:
  --local-only   Run repo-local assertions only; skip remote on-host preflight.
  -h, --help     Show this help text.

The default mode runs local assertions first and then delegates to the on-prem
redeploy preflight implementation for remote host checks.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --local-only)
        LOCAL_ONLY=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        FORWARD_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

check_env_schema() {
  log_section "Environment Schema Validation"
  if [[ "$LOCAL_ONLY" == "true" ]]; then
    bash "$REPO_ROOT/scripts/validate-env.sh" --allow-placeholders
  else
    bash "$REPO_ROOT/scripts/validate-env.sh"
  fi
  log_success "Environment schema validation passed"
}

check_dns_resolution() {
  log_section "DNS Resolution"

  local -a hosts=()
  local apex_domain="${APEX_DOMAIN:-${DOMAIN#*.}}"

  [[ -n "${DOMAIN:-}" ]] && hosts+=("${DOMAIN}")
  [[ -n "${apex_domain:-}" && "${apex_domain}" != "${DOMAIN:-}" ]] && hosts+=("${apex_domain}")
  [[ -n "${DEPLOY_HOST:-}" ]] && hosts+=("${DEPLOY_HOST}")
  [[ -n "${STANDBY_HOST:-}" ]] && hosts+=("${STANDBY_HOST}")
  [[ -n "${NAS_HOST:-}" ]] && hosts+=("${NAS_HOST}")

  local seen=()
  local host
  for host in "${hosts[@]}"; do
    [[ -z "$host" ]] && continue
    if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      continue
    fi
    if [[ " ${seen[*]} " == *" ${host} "* ]]; then
      continue
    fi
    seen+=("$host")

    if getent hosts "$host" >/dev/null 2>&1; then
      log_success "DNS resolved: $host"
    elif command -v nslookup >/dev/null 2>&1 && nslookup "$host" >/dev/null 2>&1; then
      log_success "DNS resolved: $host"
    else
      log_fatal "DNS resolution failed for $host"
    fi
  done
}

check_git_state() {
  log_section "Git State"
  require_command git

  local branch
  branch="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
  if [[ -n "$branch" && "$branch" != "main" ]]; then
    log_fatal "Expected main branch, found: ${branch}"
  fi

  if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    log_fatal "Working tree is dirty; commit or stash changes before redeploy"
  fi

  git -C "$REPO_ROOT" fetch --quiet origin main >/dev/null 2>&1 || true
  if git -C "$REPO_ROOT" rev-parse --verify origin/main >/dev/null 2>&1; then
    if ! git -C "$REPO_ROOT" merge-base --is-ancestor HEAD origin/main >/dev/null 2>&1; then
      log_fatal "Local checkout is not up to date with origin/main"
    fi
  fi

  log_success "Git state is clean and aligned"
}

check_docker_daemon() {
  log_section "Docker Reachability"
  require_command docker
  if ! docker info >/dev/null 2>&1; then
    log_fatal "Docker daemon is not reachable"
  fi
  log_success "Docker daemon reachable"
}

check_disk_space() {
  log_section "Disk Space"

  local available_mb
  available_mb="$(df -Pm "$REPO_ROOT" | awk 'NR==2 {print $4}')"
  if [[ -z "$available_mb" || ! "$available_mb" =~ ^[0-9]+$ ]]; then
    log_fatal "Unable to determine available disk space"
  fi

  if (( available_mb < 10240 )); then
    log_fatal "Insufficient disk space: ${available_mb}MB free (need at least 10240MB)"
  fi

  log_success "Disk space available: ${available_mb}MB"
}

check_terraform_state() {
  log_section "Terraform State"

  if ! compgen -G "$REPO_ROOT/*.tf" >/dev/null 2>&1; then
    log_info "No Terraform root module detected; skipping state checks"
    return 0
  fi

  require_command terraform

  if ! terraform -chdir="$REPO_ROOT" init -input=false -lock-timeout=10s >/dev/null; then
    log_fatal "Terraform backend initialization failed"
  fi

  if ! terraform -chdir="$REPO_ROOT" state pull >/dev/null; then
    log_fatal "Terraform state backend is unreachable or locked"
  fi

  log_success "Terraform state backend reachable and unlocked"
}

check_existing_services_health() {
  log_section "Existing Service Health"

  local -a containers=(
    "$CONTAINER_CODE_SERVER"
    "$CONTAINER_CADDY"
    "$CONTAINER_OLLAMA"
    "$CONTAINER_POSTGRES"
    "$CONTAINER_REDIS"
    "$CONTAINER_PROMETHEUS"
    "$CONTAINER_GRAFANA"
    "$CONTAINER_ALERTMANAGER"
  )

  local container
  for container in "${containers[@]}"; do
    if ! docker ps -a --format '{{.Names}}' | grep -qx "$container"; then
      continue
    fi

    local health_status
    local has_healthcheck
    health_status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"
    has_healthcheck="$(docker inspect -f '{{if .State.Health}}yes{{else}}no{{end}}' "$container" 2>/dev/null || true)"

    if [[ "$has_healthcheck" == "yes" && "$health_status" != "healthy" ]]; then
      log_fatal "$container is not healthy: ${health_status:-unknown}"
    fi

    if [[ "$has_healthcheck" != "yes" && "$health_status" != "running" ]]; then
      log_fatal "$container is not running: ${health_status:-unknown}"
    fi

    log_success "$container is healthy: ${health_status:-unknown}"
  done
}

check_image_availability() {
  log_section "Image Availability"

  local compose_config_output=""
  if command -v docker-compose >/dev/null 2>&1; then
    compose_config_output="$(docker-compose -f "$REPO_ROOT/docker-compose.yml" config --images 2>/dev/null || true)"
  elif docker compose version >/dev/null 2>&1; then
    compose_config_output="$(docker compose -f "$REPO_ROOT/docker-compose.yml" config --images 2>/dev/null || true)"
  fi

  if [[ -z "$compose_config_output" ]]; then
    log_info "No compose image list available; skipping image pullability check"
    return 0
  fi

  local image
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    if docker pull --quiet "$image" >/dev/null; then
      log_success "Image pullable: $image"
    else
      log_fatal "Unable to pull image: $image"
    fi
  done <<< "$(printf '%s\n' "$compose_config_output" | sort -u)"
}

check_ssl_certificate_validity() {
  log_section "SSL Certificate Validity"
  require_command openssl
  require_command date

  local -a hosts=()
  local apex_domain="${APEX_DOMAIN:-${DOMAIN#*.}}"

  [[ -n "${DOMAIN:-}" ]] && hosts+=("${DOMAIN}")
  [[ -n "${apex_domain:-}" && "${apex_domain}" != "${DOMAIN:-}" ]] && hosts+=("${apex_domain}")

  local host
  for host in "${hosts[@]}"; do
    if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$host" == localhost ]]; then
      continue
    fi

    local expiry_line
    expiry_line="$(echo | timeout 20 openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null || true)"
    if [[ -z "$expiry_line" ]]; then
      log_fatal "Unable to read SSL certificate for $host"
    fi

    local expiry_value expiry_epoch now_epoch remaining_days
    expiry_value="${expiry_line#notAfter=}"
    expiry_epoch="$(date -d "$expiry_value" +%s)"
    now_epoch="$(date +%s)"
    remaining_days=$(( (expiry_epoch - now_epoch) / 86400 ))

    if (( remaining_days < 14 )); then
      log_fatal "SSL certificate for $host expires in ${remaining_days} day(s)"
    fi

    log_success "SSL certificate for $host is valid for ${remaining_days} more day(s)"
  done
}

run_local_preflight() {
  check_env_schema
  check_dns_resolution
  check_git_state
  check_docker_daemon
  check_disk_space
  check_terraform_state
  check_existing_services_health
  check_image_availability
  check_ssl_certificate_validity
}

main() {
  parse_args "$@"

  if [[ "$LOCAL_ONLY" == "true" ]]; then
    run_local_preflight
    log_success "Local-only preflight completed"
    return 0
  fi

  run_local_preflight
  bash "$DEEP_PREFLIGHT" "${FORWARD_ARGS[@]}"
  log_success "Unified preflight completed"
}

main "$@"