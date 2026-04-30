#!/bin/bash
#
# Pre-apply validation for code-server deployment
# Runs critical checks BEFORE terraform apply to prevent bad deployments
# Exit codes: 0=all checks pass, 1=validation failure
#

set -euo pipefail

trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/../_common/init.sh"

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
TF_DIR="${REPO_ROOT}/terraform/environments/private"
REQUIRED_DOCKER_IMAGES=(
  "coder/code-server:latest"
  "gitlab/gitlab-ce:latest"
  "minio/minio:latest"
  "appsmith/appsmith-ce:latest"
  "vault:latest"
  "sonatype/nexus3:latest"
  "hashicorp/terraform:latest"
  "postgres:15-alpine"
  "redis:7-alpine"
  "keepalived:latest"
)

CHECKS_PASSED=0
CHECKS_FAILED=0
VALIDATION_ERRORS=()

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_check() {
  local name="$1"
  echo -ne "Checking ${name}... "
}

pass_check() {
  ((CHECKS_PASSED++))
  echo -e "${GREEN}✓${NC}"
}

fail_check() {
  local msg="$1"
  ((CHECKS_FAILED++))
  echo -e "${RED}✗${NC}"
  VALIDATION_ERRORS+=("  • $msg")
}

warn_check() {
  echo -e "${YELLOW}⚠${NC}"
}

# Check 1: Terraform syntax validation
validate_terraform_syntax() {
  log_check "Terraform syntax"
  
  if (cd "${TF_DIR}" && terraform validate >/dev/null 2>&1); then
    pass_check
  else
    fail_check "Terraform validation failed. Run 'terraform validate' for details."
  fi
}

# Check 2: Terraform format check
validate_terraform_format() {
  log_check "Terraform code formatting"
  
  local fmt_output
  fmt_output=$(cd "${TF_DIR}" && terraform fmt -check -recursive 2>&1 || true)
  
  if [[ -z "$fmt_output" ]]; then
    pass_check
  else
    warn_check
    echo "  (run 'terraform fmt -recursive' to auto-fix)"
  fi
}

# Check 3: Docker daemon on primary
check_docker_primary() {
  log_check "Docker daemon on PRIMARY (${PRIMARY_HOST})"
  
  if ssh "akushnir@${PRIMARY_HOST}" 'docker ps >/dev/null 2>&1' 2>/dev/null; then
    pass_check
  else
    fail_check "Docker daemon unreachable on primary host ${PRIMARY_HOST}"
  fi
}

# Check 4: Docker daemon on replica
check_docker_replica() {
  log_check "Docker daemon on REPLICA (${REPLICA_HOST})"
  
  if ssh "akushnir@${REPLICA_HOST}" 'docker ps >/dev/null 2>&1' 2>/dev/null; then
    pass_check
  else
    fail_check "Docker daemon unreachable on replica host ${REPLICA_HOST}"
  fi
}

# Check 5: SSH key access
check_ssh_connectivity() {
  log_check "SSH connectivity to hosts"
  
  local ssh_ok=true
  
  if ! ssh -o StrictHostKeyChecking=no "akushnir@${PRIMARY_HOST}" 'true' 2>/dev/null; then
    VALIDATION_ERRORS+=("  • SSH to primary ${PRIMARY_HOST} failed")
    ssh_ok=false
  fi
  
  if ! ssh -o StrictHostKeyChecking=no "akushnir@${REPLICA_HOST}" 'true' 2>/dev/null; then
    VALIDATION_ERRORS+=("  • SSH to replica ${REPLICA_HOST} failed")
    ssh_ok=false
  fi
  
  if [[ "$ssh_ok" == true ]]; then
    pass_check
  else
    ((CHECKS_FAILED++))
  fi
}

# Check 6: PostgreSQL connectivity on primary
check_postgres_primary() {
  log_check "PostgreSQL connectivity on PRIMARY"
  
  if ssh "akushnir@${PRIMARY_HOST}" \
    'docker exec code-server-postgres psql -U postgres -c "SELECT 1" >/dev/null 2>&1' \
    2>/dev/null; then
    pass_check
  else
    fail_check "PostgreSQL unreachable on primary (container may not be running)"
  fi
}

# Check 7: PostgreSQL connectivity on replica
check_postgres_replica() {
  log_check "PostgreSQL connectivity on REPLICA"
  
  if ssh "akushnir@${REPLICA_HOST}" \
    'docker exec code-server-postgres psql -U postgres -c "SELECT 1" >/dev/null 2>&1' \
    2>/dev/null; then
    pass_check
  else
    warn_check
    echo "  (replica may not have PostgreSQL running yet)"
  fi
}

# Check 8: Redis connectivity
check_redis() {
  log_check "Redis connectivity on PRIMARY"
  
  if ssh "akushnir@${PRIMARY_HOST}" \
    'docker exec code-server-redis redis-cli ping >/dev/null 2>&1' \
    2>/dev/null; then
    pass_check
  else
    warn_check
    echo "  (Redis container may not be running)"
  fi
}

# Check 9: Disk space on primary
check_disk_space_primary() {
  log_check "Disk space on PRIMARY"
  
  local available_gb
  available_gb=$(ssh "akushnir@${PRIMARY_HOST}" 'df /home | tail -1 | awk "{print \$4}" | xargs -I {} expr {} / 1024 / 1024' 2>/dev/null || echo "0")
  
  if (( available_gb > 10 )); then
    pass_check
  elif (( available_gb > 5 )); then
    warn_check
    echo "  (only ${available_gb}GB available, recommend >10GB)"
  else
    fail_check "Insufficient disk space on primary: ${available_gb}GB available"
  fi
}

# Check 10: Disk space on replica
check_disk_space_replica() {
  log_check "Disk space on REPLICA"
  
  local available_gb
  available_gb=$(ssh "akushnir@${REPLICA_HOST}" 'df /home | tail -1 | awk "{print \$4}" | xargs -I {} expr {} / 1024 / 1024' 2>/dev/null || echo "0")
  
  if (( available_gb > 10 )); then
    pass_check
  elif (( available_gb > 5 )); then
    warn_check
    echo "  (only ${available_gb}GB available, recommend >10GB)"
  else
    fail_check "Insufficient disk space on replica: ${available_gb}GB available"
  fi
}

# Check 11: Required Terraform variables set
check_terraform_variables() {
  log_check "Terraform variables"
  
  local vars_ok=true
  
  if ! (cd "${TF_DIR}" && terraform plan -no-color >/dev/null 2>&1); then
    fail_check "Terraform variable validation failed"
    vars_ok=false
  fi
  
  if [[ "$vars_ok" == true ]]; then
    pass_check
  fi
}

# Check 12: Keepalived status
check_keepalived() {
  log_check "Keepalived services"
  
  local keepalived_ok=true
  
  if ! ssh "akushnir@${PRIMARY_HOST}" \
    'docker ps | grep -q code-server-keepalived' 2>/dev/null; then
    warn_check
    echo "  (keepalived not running on primary, will be deployed)"
    keepalived_ok=false
  fi
  
  if ! ssh "akushnir@${REPLICA_HOST}" \
    'docker ps | grep -q code-server-keepalived' 2>/dev/null; then
    warn_check
    echo "  (keepalived not running on replica, will be deployed)"
    keepalived_ok=false
  fi
  
  if [[ "$keepalived_ok" == true ]]; then
    pass_check
  else
    ((CHECKS_PASSED++))
  fi
}

# Check 13: Network connectivity between hosts
check_network_connectivity() {
  log_check "Network connectivity between hosts"
  
  if ssh "akushnir@${PRIMARY_HOST}" "ping -c 1 ${REPLICA_HOST} >/dev/null 2>&1" 2>/dev/null; then
    pass_check
  else
    fail_check "Network connectivity between hosts failed (primary → replica)"
  fi
}

# Check 14: Docker image availability (sample check)
check_docker_images() {
  log_check "Docker images accessible (sample pull test)"
  
  if ssh "akushnir@${PRIMARY_HOST}" \
    'docker pull --quiet alpine:latest >/dev/null 2>&1' \
    2>/dev/null; then
    pass_check
  else
    fail_check "Cannot pull Docker images (check network/registry access)"
  fi
}

# Main execution
main() {
  echo "============================================"
  echo "Pre-Apply Validation for code-server"
  echo "============================================"
  echo ""
  
  # Terraform checks
  echo "[Terraform]"
  validate_terraform_syntax
  validate_terraform_format
  echo ""
  
  # Connectivity checks
  echo "[Connectivity]"
  check_ssh_connectivity
  check_network_connectivity
  echo ""
  
  # Docker and services
  echo "[Docker & Services]"
  check_docker_primary
  check_docker_replica
  check_docker_images
  check_keepalived
  echo ""
  
  # Database checks
  echo "[Databases]"
  check_postgres_primary
  check_postgres_replica
  check_redis
  echo ""
  
  # System resources
  echo "[System Resources]"
  check_disk_space_primary
  check_disk_space_replica
  echo ""
  
  # Summary
  echo "============================================"
  echo "Validation Summary"
  echo "============================================"
  echo -e "Passed: ${GREEN}${CHECKS_PASSED}${NC}"
  echo -e "Failed: ${RED}${CHECKS_FAILED}${NC}"
  
  if (( CHECKS_FAILED > 0 )); then
    echo ""
    echo -e "${RED}Validation Errors:${NC}"
    for error in "${VALIDATION_ERRORS[@]}"; do
      echo "$error"
    done
    echo ""
    echo -e "${RED}Pre-apply validation FAILED${NC}"
    return 1
  else
    echo ""
    echo -e "${GREEN}All critical checks passed ✓${NC}"
    echo "Safe to proceed with: terraform apply"
    return 0
  fi
}

main "$@"
