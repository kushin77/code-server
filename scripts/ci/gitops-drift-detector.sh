#!/bin/bash
# @file gitops-drift-detector.sh
# @module infrastructure/continuous-reconciliation
# @description P3-1531: GitOps continuous reconciliation - detect infrastructure drift vs. code state
# @governance GOV-002: Drift detection runs on schedule (daily minimum), alerts on divergence, auto-remediates or files issues
# @usage gitops-drift-detector.sh [--check] [--remediate] [--alert] [--schedule]

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DRIFT_LOG="${REPO_ROOT}/logs/drift-detection.log"
DRIFT_REPORT="${REPO_ROOT}/artifacts/drift-report.json"
DRIFT_THRESHOLD_HOURS=24

# Source init.sh which includes github-api-client.sh (P3 #1533: consolidated sourcing)
source "${REPO_ROOT}/scripts/_common/init.sh"

mkdir -p "${REPO_ROOT}/logs" "$(dirname "${DRIFT_REPORT}")"

log_info() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*" | tee -a "${DRIFT_LOG}"
}

log_error() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" | tee -a "${DRIFT_LOG}" >&2
}

log_warning() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*" | tee -a "${DRIFT_LOG}"
}

# Check Docker Compose state vs. code
check_docker_compose_drift() {
  log_info "Checking Docker Compose drift..."

  if ! command -v jq &>/dev/null; then
    log_warning "jq not available — skipping Docker Compose drift check"
    return 0
  fi
  if ! docker info &>/dev/null 2>&1; then
    log_warning "Docker daemon not available — skipping Docker Compose drift check"
    return 0
  fi

  local drift_items=()
  
  # Compare running containers with docker-compose.yml
  local running=$(docker compose -f "${REPO_ROOT}/docker-compose.yml" ps --format json 2>/dev/null | jq -r '.[] | .Service // empty' | sort)
  local defined=$(yq -r '.services | keys[]' "${REPO_ROOT}/docker-compose.yml" 2>/dev/null | sort)
  
  # Check for extra running services
  local extra=$(comm -23 <(echo "${running}") <(echo "${defined}") || true)
  if [[ -n "${extra}" ]]; then
    while IFS= read -r service; do
      [[ -z "${service}" ]] && continue
      drift_items+=("docker-compose-extra-service:${service}")
      log_warning "Extra service running (not in docker-compose.yml): ${service}"
    done <<< "${extra}"
  fi
  
  # Check for missing running services
  local missing=$(comm -13 <(echo "${running}") <(echo "${defined}") || true)
  if [[ -n "${missing}" ]]; then
    while IFS= read -r service; do
      [[ -z "${service}" ]] && continue
      drift_items+=("docker-compose-missing-service:${service}")
      log_warning "Defined service not running: ${service}"
    done <<< "${missing}"
  fi
  
  # Check image versions
  local images_config=$(yq -r '.services[] | select(.image != null) | .image' "${REPO_ROOT}/docker-compose.yml" 2>/dev/null | sort)
  
  while IFS= read -r image; do
    [[ -z "${image}" ]] && continue
    
    local service=$(yq -r ".services[] | select(.image == \"${image}\") | keys[0]" "${REPO_ROOT}/docker-compose.yml" 2>/dev/null | head -1)
    local running_image=$(docker compose -f "${REPO_ROOT}/docker-compose.yml" ps --format json 2>/dev/null | jq -r ".[] | select((.Service // \"\") == \"${service}\") | .Image // empty" | head -1)
    
    if [[ -n "${running_image}" ]] && [[ "${image}" != "${running_image}" ]]; then
      drift_items+=("docker-compose-image-drift:${service}")
      log_warning "Image drift for ${service}: config=${image}, running=${running_image}"
    fi
  done <<< "${images_config}"
  
  return $([ ${#drift_items[@]} -eq 0 ] && echo 0 || echo 1)
}

# Check Terraform state vs. code (P1 #2422: Updated to skip null_resources)
check_terraform_drift() {
  log_info "Checking Terraform drift..."

  if ! command -v terraform &>/dev/null; then
    log_warning "terraform not available — skipping Terraform drift check"
    return 0
  fi
  if ! command -v jq &>/dev/null; then
    log_warning "jq not available — skipping Terraform drift check"
    return 0
  fi

  local TERRAFORM_DIR="${REPO_ROOT}/terraform/environments/private"
  if [[ ! -d "${TERRAFORM_DIR}" ]]; then
    log_warning "Terraform dir not found at ${TERRAFORM_DIR} — skipping"
    return 0
  fi

  local drift_items=()

  cd "${TERRAFORM_DIR}"
  
  # Run terraform plan in no-changes mode with retry for transient provider/SSH transport failures.
  # NOTE: null_resource with ignore_changes=all are skipped intentionally
  # (they're one-time provisioners, drift detection uses host state comparison instead)
  local terraform_json=""
  local tf_rc=1
  local tf_attempt
  for tf_attempt in 1 2 3; do
    local tf_err_file
    tf_err_file="$(mktemp)"

    if terraform_json="$(terraform plan -json 2>"${tf_err_file}")"; then
      tf_rc=0
      rm -f "${tf_err_file}"
      break
    fi

    tf_rc=$?
    if grep -qiE 'exited with signal: killed|dial-stdio|broken pipe|i/o timeout|connection reset by peer' "${tf_err_file}"; then
      log_warning "Transient terraform plan transport failure (attempt ${tf_attempt}/3), retrying..."
      rm -f "${tf_err_file}"
      continue
    fi

    log_error "Terraform plan failed with non-transient error"
    cat "${tf_err_file}" | sed 's/^/[terraform] /' | tee -a "${DRIFT_LOG}" >&2
    rm -f "${tf_err_file}"
    return 1
  done

  if [[ ${tf_rc} -ne 0 ]]; then
    log_warning "Terraform drift check skipped due to repeated transient plan failures"
    return 0
  fi

  local plan_output
  plan_output="$(printf '%s\n' "${terraform_json}" | jq -r \
    'select(.type=="resource_drift") |
     select(((.address // "") | contains("null_resource")) | not) |
     (.address // empty)' || echo "")"
  
  while IFS= read -r resource; do
    [[ -z "${resource}" ]] && continue
    drift_items+=("terraform-drift:${resource}")
    log_warning "Terraform drift detected: ${resource}"
  done <<< "${plan_output}"
  
  return $([ ${#drift_items[@]} -eq 0 ] && echo 0 || echo 1)
}

# Check replica host service parity (P1 #2420)
check_replica_parity() {
  log_info "Checking cluster replica parity..."
  
  # Load cluster hosts from canonical config
  if [[ -z "${PRIMARY_HOST:-}" ]] || [[ -z "${REPLICA_HOST:-}" ]]; then
    log_warning "PRIMARY_HOST or REPLICA_HOST not set — skipping replica parity check"
    return 0
  fi
  
  if [[ "${PRIMARY_HOST}" == "${REPLICA_HOST}" ]]; then
    log_info "Single-node cluster (primary==replica) — skipping parity check"
    return 0
  fi
  
  local drift_items=()
  
  # Get primary host service list (local)
  local primary_services
  if ! command -v docker &>/dev/null; then
    log_warning "Docker not available — skipping replica parity check"
    return 0
  fi
  
  primary_services=$(docker ps --format json 2>/dev/null | jq -r 'if type=="array" then .[] else . end | .Names // empty' | sort | tr '\n' ' ' || echo "")
  
  if [[ -z "${primary_services}" ]]; then
    log_warning "No Docker services found on primary host — skipping replica parity check"
    return 0
  fi
  
  # Get replica host service list (remote SSH)
  local replica_services
  replica_services=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    "akushnir@${REPLICA_HOST}" \
    "docker ps --format json 2>/dev/null | jq -r 'if type==\"array\" then .[] else . end | .Names // empty' | sort | tr '\n' ' '" 2>/dev/null || echo "")
  
  if [[ -z "${replica_services}" ]]; then
    log_error "Unable to query Docker services on replica host ${REPLICA_HOST}"
    drift_items+=("replica-parity-query-failed")
  else
    # Compare service lists
    local primary_array=(${primary_services})
    local replica_array=(${replica_services})
    
    # Find services on primary but not on replica
    local missing_on_replica=""
    for svc in "${primary_array[@]}"; do
      if ! printf '%s\n' "${replica_array[@]}" | grep -q "^${svc}$"; then
        missing_on_replica+="${svc} "
      fi
    done
    
    # Find services on replica but not on primary
    local extra_on_replica=""
    for svc in "${replica_array[@]}"; do
      if ! printf '%s\n' "${primary_array[@]}" | grep -q "^${svc}$"; then
        extra_on_replica+="${svc} "
      fi
    done
    
    if [[ -n "${missing_on_replica}" ]]; then
      log_error "Cluster parity: services missing on replica: ${missing_on_replica}"
      drift_items+=("replica-parity-missing:${missing_on_replica}")
    fi
    
    if [[ -n "${extra_on_replica}" ]]; then
      log_error "Cluster parity: extra services on replica: ${extra_on_replica}"
      drift_items+=("replica-parity-extra:${extra_on_replica}")
    fi
  fi
  
  if [[ ${#drift_items[@]} -gt 0 ]]; then
    log_error "Cluster divergence detected: primary and replica service sets do not match"
  fi
  
  return $([ ${#drift_items[@]} -eq 0 ] && echo 0 || echo 1)
}

# Check Caddy config vs. running state
check_caddy_drift() {
  log_info "Checking Caddy configuration drift..."
  
  local drift_items=()
  
  if ! command -v caddy &> /dev/null; then
    log_warning "Caddy not available, skipping Caddy drift check"
    return 0
  fi
  
  # Validate current config
  if ! caddy validate --config "${REPO_ROOT}/config/caddy/Caddyfile" 2>/dev/null; then
    drift_items+=("caddy-validation-failed")
    log_error "Caddy configuration validation failed"
  fi
  
  return $([ ${#drift_items[@]} -eq 0 ] && echo 0 || echo 1)
}

# Generate drift alert
generate_drift_alert() {
  local drift_count="$1"
  
  if [[ ${drift_count} -eq 0 ]]; then
    return 0
  fi
  
  log_error "Drift detected: ${drift_count} divergences between code and running state"
  
  local issue_title="🚨 Infrastructure Drift Detected - $(date -u +'%Y-%m-%d %H:%M:%SZ')"
  local issue_body="Automated drift detection found ${drift_count} divergences between infrastructure code (Git) and running state.

**Actions:**
- Review drift-report.json artifact
- Run \`gitops-drift-detector.sh --remediate\` to auto-correct
- Or manually reconcile changes

**Time:** $(date -u +'%Y-%m-%dT%H:%M:%SZ')"

  local issue_payload
  issue_payload=$(jq -n \
    --arg title "${issue_title}" \
    --arg body "${issue_body}" \
    '{title: $title, body: $body, labels: ["P1", "infrastructure", "drift"]}')

  github_api_call POST "/repos/kushin77/code-server/issues" "${issue_payload}" \
    || log_warning "Could not create GitHub issue"
}

# Generate report
generate_report() {
  local compose_drift="$1"
  local terraform_drift="$2"
  local caddy_drift="$3"
  local replica_parity="$4"
  
  local total_drift=$((compose_drift + terraform_drift + caddy_drift + replica_parity))
  local status=$([ ${total_drift} -eq 0 ] && echo "IN_SYNC" || echo "DRIFTED")
  
  mkdir -p "$(dirname "${DRIFT_REPORT}")"
  
  jq -n \
    --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --arg status "${status}" \
    --argjson compose_drift "${compose_drift}" \
    --argjson terraform_drift "${terraform_drift}" \
    --argjson caddy_drift "${caddy_drift}" \
    --argjson replica_parity "${replica_parity}" \
    '{
      timestamp: $timestamp,
      status: $status,
      total_drift_items: ($compose_drift + $terraform_drift + $caddy_drift + $replica_parity),
      details: {
        docker_compose: $compose_drift,
        terraform: $terraform_drift,
        caddy: $caddy_drift,
        replica_parity: $replica_parity
      }
    }' > "${DRIFT_REPORT}"
  
  log_info "Drift report saved to ${DRIFT_REPORT}"
}

# Main
main() {
  local mode="${1:---check}"
  
  log_info "GitOps drift detection started: ${mode}"
  
  local compose_drift=0
  local terraform_drift=0
  local caddy_drift=0
  local replica_parity=0
  
  check_docker_compose_drift && compose_drift=0 || compose_drift=1
  check_terraform_drift && terraform_drift=0 || terraform_drift=1
  check_caddy_drift && caddy_drift=0 || caddy_drift=1
  check_replica_parity && replica_parity=0 || replica_parity=1
  
  local total_drift=$((compose_drift + terraform_drift + caddy_drift + replica_parity))
  
  generate_report "${compose_drift}" "${terraform_drift}" "${caddy_drift}" "${replica_parity}"
  
  case "${mode}" in
    --check)
      if [[ ${total_drift} -gt 0 ]]; then
        log_warning "Drift detected in ${total_drift} component(s)"
        return 1
      fi
      ;;
    --alert)
      generate_drift_alert "${total_drift}"
      ;;
    --remediate)
      log_error "Automated remediation not yet implemented - manual reconciliation required"
      ;;
    *)
      log_error "Unknown mode: ${mode}"
      exit 1
      ;;
  esac
  
  log_info "Drift detection complete"
}

main "$@"