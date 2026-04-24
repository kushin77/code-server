#!/usr/bin/env bash
################################################################################
# @file        scripts/ops/check-replica-parity.sh
# @module      ops/validation
# @description Compares running services and env config across all cluster replicas
# @owner       platform
# @status      active
#
# USAGE
#   bash scripts/ops/check-replica-parity.sh
#
# OUTPUTS
#   - Green: all replicas identical
#   - Red: divergence found with diff output
#   - Exit code 0 = parity, 1 = divergence
#
# CHECKS
#   1. Git commit hash (all replicas on same commit)
#   2. Running service names (docker ps --format {{.Names}})
#   3. COMPOSE_PROFILES configuration
#
# EXIT CODES
#   0 = All replicas in perfect parity
#   1 = Parity divergence detected
#   2 = Configuration or connectivity error
#
# NOTES
#   - Does NOT compare env var values (security concern)
#   - Requires id_rsa_onprem SSH key in ~/.ssh/
#   - Uses canonical logging from scripts/_common/logging.sh
#
# Last Updated: April 23, 2026
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

SCRIPT_NAME="$(basename "$0")"

################################################################################
# CONFIGURATION
################################################################################

# Production cluster replicas
REPLICAS=(
  "akushnir@192.168.168.31"
  "akushnir@192.168.168.42"
)

SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa_onprem}"
SSH_OPTS="-i ${SSH_KEY} -o ConnectTimeout=10 -o StrictHostKeyChecking=no"

# Work directory for temp files
WORK_DIR="/tmp/replica-parity-$$"

# Tracking
DIVERGENCE_FOUND=0
CRITICAL_ERROR=0

################################################################################
# CLEANUP TRAP
################################################################################

cleanup() {
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

################################################################################
# HELPER FUNCTIONS
################################################################################

# Query a replica via SSH
query_replica() {
  local host=$1
  shift
  local cmd="$@"
  local -a ssh_opts_array
  read -r -a ssh_opts_array <<< "$SSH_OPTS"
  ssh "${ssh_opts_array[@]}" "$host" "$cmd" 2>/dev/null || echo "ERROR"
}

# Log section header
log_section() {
  log_info ""
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "$1"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

################################################################################
# CONNECTIVITY CHECK
################################################################################

check_replica_connectivity() {
  log_info "Verifying all replicas are reachable..."
  
  local all_reachable=1
  local -a ssh_opts_array
  read -r -a ssh_opts_array <<< "$SSH_OPTS"
  for replica in "${REPLICAS[@]}"; do
    if ssh "${ssh_opts_array[@]}" "$replica" "true" 2>/dev/null; then
      log_info "  ✓ $replica reachable"
    else
      log_error "  ✗ $replica unreachable"
      all_reachable=0
    fi
  done
  
  if [[ $all_reachable -eq 0 ]]; then
    log_fatal "Some replicas are unreachable. Cannot proceed with parity check."
    return 2
  fi
  
  return 0
}

################################################################################
# PARITY CHECKS
################################################################################

check_git_commit_parity() {
  log_section "Check 1: Git Commit Parity"
  
  local work_file="$WORK_DIR/git-commits"
  mkdir -p "$(dirname "$work_file")"
  
  # Collect git commits from all replicas
  declare -A commits
  for replica in "${REPLICAS[@]}"; do
    log_debug "  Getting git commit from $replica..."
    local commit
    commit=$(query_replica "$replica" "cd code-server-enterprise && git rev-parse HEAD 2>/dev/null" | head -1)
    
    if [[ "$commit" == "ERROR" ]] || [[ -z "$commit" ]]; then
      log_error "  ✗ Failed to get git commit from $replica"
      CRITICAL_ERROR=1
      return 1
    fi
    
    commits["$replica"]="$commit"
    echo "$replica: $commit" >> "$work_file"
    log_info "  $replica: $commit"
  done
  
  # Compare all to first replica
  local first_replica="${REPLICAS[0]}"
  local first_commit="${commits[$first_replica]}"
  
  for replica in "${REPLICAS[@]}"; do
    if [[ "$replica" != "$first_replica" ]]; then
      if [[ "${commits[$replica]}" != "$first_commit" ]]; then
        log_error "  ✗ DIVERGENCE: $replica on ${commits[$replica]:0:7}... vs $first_replica on ${first_commit:0:7}..."
        DIVERGENCE_FOUND=1
        return 1
      fi
    fi
  done
  
  log_info "  ✓ All replicas on same commit: ${first_commit:0:7}..."
  return 0
}

check_running_services_parity() {
  log_section "Check 2: Running Services Parity"
  
  local work_dir="$WORK_DIR/services"
  mkdir -p "$work_dir"
  
  # Collect service lists from all replicas
  for replica in "${REPLICAS[@]}"; do
    log_debug "  Getting running services from $replica..."
    local services
    services=$(query_replica "$replica" "docker ps --format '{{.Names}}' 2>/dev/null | sort" | head -50)
    
    if [[ "$services" == "ERROR" ]] || [[ -z "$services" ]]; then
      log_warn "  ⊘ Could not retrieve service list from $replica (docker may not be running)"
      continue
    fi
    
    echo "$services" > "$work_dir/${replica//@/_}"
    
    local count
    count=$(echo "$services" | wc -l)
    log_info "  $replica: $count services"
  done
  
  # Compare service lists
  if [[ $(find "$work_dir" -type f | wc -l) -lt 2 ]]; then
    log_warn "  ⊘ Could not retrieve service lists from both replicas"
    return 0
  fi
  
  local first_file
  first_file=$(find "$work_dir" -type f | head -1)
  
  local first_replica=$(basename "$first_file" | sed 's/_/@/')
  
  for service_file in "$work_dir"/*; do
    local replica=$(basename "$service_file" | sed 's/_/@/')
    
    if [[ "$service_file" != "$first_file" ]]; then
      if ! diff -q "$first_file" "$service_file" >/dev/null 2>&1; then
        log_error "  ✗ DIVERGENCE: Services differ between replicas"
        log_error "    Diff:"
        diff -u <(sed 's/^/      /' "$first_file") <(sed 's/^/      /' "$service_file") || true
        DIVERGENCE_FOUND=1
        return 1
      fi
    fi
  done
  
  local count
  count=$(wc -l < "$first_file")
  log_info "  ✓ All replicas running identical $count services"
  return 0
}

check_compose_profiles_parity() {
  log_section "Check 3: COMPOSE_PROFILES Parity"
  
  local work_file="$WORK_DIR/profiles"
  mkdir -p "$(dirname "$work_file")"
  
  # Collect COMPOSE_PROFILES from all replicas
  declare -A profiles
  for replica in "${REPLICAS[@]}"; do
    log_debug "  Getting COMPOSE_PROFILES from $replica..."
    local profile
    profile=$(query_replica "$replica" "cd code-server-enterprise && grep -E '^COMPOSE_PROFILES=' .env 2>/dev/null | cut -d= -f2- || echo 'NONE'")
    
    profiles["$replica"]="$profile"
    echo "$replica: $profile" >> "$work_file"
    log_info "  $replica: ${profile:-NONE}"
  done
  
  # Compare all profiles
  local first_replica="${REPLICAS[0]}"
  local first_profile="${profiles[$first_replica]}"
  
  for replica in "${REPLICAS[@]}"; do
    if [[ "$replica" != "$first_replica" ]]; then
      if [[ "${profiles[$replica]}" != "$first_profile" ]]; then
        log_error "  ✗ DIVERGENCE: $replica has '${profiles[$replica]}' vs $first_replica has '$first_profile'"
        DIVERGENCE_FOUND=1
        return 1
      fi
    fi
  done
  
  log_info "  ✓ All replicas have same COMPOSE_PROFILES: ${first_profile:-NONE}"
  return 0
}

################################################################################
# MAIN EXECUTION
################################################################################

log_section "Starting Replica Parity Check"
log_info "Replicas: ${REPLICAS[*]}"
log_info ""

# Connectivity check first
if ! check_replica_connectivity; then
  log_fatal "Cannot proceed without replica connectivity"
fi

log_info ""

# Run all parity checks
check_git_commit_parity || true
check_running_services_parity || true
check_compose_profiles_parity || true

################################################################################
# FINAL SUMMARY
################################################################################

log_section "Parity Check Summary"

if [[ $DIVERGENCE_FOUND -eq 0 ]]; then
  log_info "✓ All replicas are in perfect parity"
  exit 0
elif [[ $CRITICAL_ERROR -ne 0 ]]; then
  log_error "✗ Critical errors encountered during parity check"
  exit 2
else
  log_error "✗ Divergence detected across replicas - manual intervention required"
  exit 1
fi
