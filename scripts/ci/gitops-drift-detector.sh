#!/bin/bash
# @file gitops-drift-detector.sh
# @module infrastructure/continuous-reconciliation
# @description P3-1531: GitOps continuous reconciliation - detect infrastructure drift vs. code state
# @governance GOV-002: Drift detection runs on schedule (daily minimum), alerts on divergence, auto-remediates or files issues
# @usage gitops-drift-detector.sh [--check] [--remediate] [--alert] [--schedule]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DRIFT_LOG="${REPO_ROOT}/logs/drift-detection.log"
DRIFT_REPORT="${REPO_ROOT}/artifacts/drift-report.json"
DRIFT_THRESHOLD_HOURS=24

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
  
  local drift_items=()
  
  # Compare running containers with docker-compose.yml
  local running=$(docker compose -f "${REPO_ROOT}/docker-compose.yml" ps --format json 2>/dev/null | jq -r '.[] | .Service' | sort)
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
    local running_image=$(docker compose -f "${REPO_ROOT}/docker-compose.yml" ps --format json 2>/dev/null | jq -r ".[] | select(.Service == \"${service}\") | .Image" | head -1)
    
    if [[ -n "${running_image}" ]] && [[ "${image}" != "${running_image}" ]]; then
      drift_items+=("docker-compose-image-drift:${service}")
      log_warning "Image drift for ${service}: config=${image}, running=${running_image}"
    fi
  done <<< "${images_config}"
  
  return $([ ${#drift_items[@]} -eq 0 ] && echo 0 || echo 1)
}

# Check Terraform state vs. code
check_terraform_drift() {
  log_info "Checking Terraform drift..."
  
  local drift_items=()
  
  cd "${REPO_ROOT}/terraform"
  
  # Run terraform plan in no-changes mode
  local plan_output=$(terraform plan -json 2>/dev/null | jq -r 'select(.type=="resource_drift") | .address' || echo "")
  
  while IFS= read -r resource; do
    [[ -z "${resource}" ]] && continue
    drift_items+=("terraform-drift:${resource}")
    log_warning "Terraform drift detected: ${resource}"
  done <<< "${plan_output}"
  
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
  if ! caddy validate --config "${REPO_ROOT}/Caddyfile" 2>/dev/null; then
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
  
  # Create GitHub issue if drift exceeds threshold
  if command -v gh &> /dev/null; then
    local issue_title="🚨 Infrastructure Drift Detected - $(date -u +'%Y-%m-%d %H:%M:%SZ')"
    local issue_body="Automated drift detection found ${drift_count} divergences between infrastructure code (Git) and running state.

**Actions:**
- Review drift-report.json artifact
- Run \`gitops-drift-detector.sh --remediate\` to auto-correct
- Or manually reconcile changes

**Time:** $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    
    gh issue create --repo kushin77/code-server --title "${issue_title}" --body "${issue_body}" --label "infrastructure,drift" 2>/dev/null || log_warning "Could not create GitHub issue"
  fi
}

# Generate report
generate_report() {
  local compose_drift="$1"
  local terraform_drift="$2"
  local caddy_drift="$3"
  
  local total_drift=$((compose_drift + terraform_drift + caddy_drift))
  local status=$([ ${total_drift} -eq 0 ] && echo "IN_SYNC" || echo "DRIFTED")
  
  mkdir -p "$(dirname "${DRIFT_REPORT}")"
  
  jq -n \
    --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --arg status "${status}" \
    --argjson compose_drift "${compose_drift}" \
    --argjson terraform_drift "${terraform_drift}" \
    --argjson caddy_drift "${caddy_drift}" \
    '{
      timestamp: $timestamp,
      status: $status,
      total_drift_items: ($compose_drift + $terraform_drift + $caddy_drift),
      details: {
        docker_compose: $compose_drift,
        terraform: $terraform_drift,
        caddy: $caddy_drift
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
  
  check_docker_compose_drift && compose_drift=0 || compose_drift=1
  check_terraform_drift && terraform_drift=0 || terraform_drift=1
  check_caddy_drift && caddy_drift=0 || caddy_drift=1
  
  local total_drift=$((compose_drift + terraform_drift + caddy_drift))
  
  generate_report "${compose_drift}" "${terraform_drift}" "${caddy_drift}"
  
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