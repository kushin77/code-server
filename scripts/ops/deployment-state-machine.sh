#!/usr/bin/env bash
# @file scripts/ops/deployment-state-machine.sh
# @module ops/orchestration
# @description Finite state machine for deployment state tracking and recovery
# @governance GOV-003: Reliable deployment state management with recovery
# @usage deployment-state-machine.sh [--action STATE] [--state-dir /tmp/deployment]

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Error handling
trap 'log_error "State machine failed at line $LINENO"; exit 1' ERR
trap 'cleanup_state_machine' EXIT

# Configuration
STATE_DIR="${STATE_DIR:-./.deployment-state}"
STATE_MACHINE_ID="STATE-$(date +%s)"
CURRENT_STATE_FILE="${STATE_DIR}/.current-state"
STATE_HISTORY_FILE="${STATE_DIR}/.state-history"

cleanup_state_machine() {
  # State is persistent, no cleanup needed
  :
}

log_info "═══════════════════════════════════════════════════════"
log_info "DEPLOYMENT STATE MACHINE"
log_info "═══════════════════════════════════════════════════════"

# Initialize state directory
init_state_directory() {
  mkdir -p "${STATE_DIR}"
  
  if [[ ! -f "${CURRENT_STATE_FILE}" ]]; then
    echo "INIT" > "${CURRENT_STATE_FILE}"
    log_success "✓ Initialized state directory"
  fi
  
  if [[ ! -f "${STATE_HISTORY_FILE}" ]]; then
    touch "${STATE_HISTORY_FILE}"
  fi
}

# Valid state transitions
get_valid_transitions() {
  local current_state="$1"
  
  case "$current_state" in
    INIT)
      echo "VALIDATION PRE_FLIGHT"
      ;;
    VALIDATION)
      echo "PRE_FLIGHT PREPARING ERROR"
      ;;
    PRE_FLIGHT)
      echo "PREPARING VALIDATING ERROR"
      ;;
    PREPARING)
      echo "DEPLOYING PRE_FLIGHT ERROR"
      ;;
    DEPLOYING)
      echo "DEPLOYED DEPLOYING_ERROR ROLLBACK"
      ;;
    DEPLOYED)
      echo "TESTING STABLE FAILED"
      ;;
    TESTING)
      echo "STABLE DEPLOYED ERROR"
      ;;
    STABLE)
      echo "MONITORING ROLLBACK"
      ;;
    MONITORING)
      echo "STABLE ERROR"
      ;;
    ERROR)
      echo "INIT ROLLBACK"
      ;;
    DEPLOYING_ERROR)
      echo "ROLLBACK ERROR"
      ;;
    ROLLBACK)
      echo "INIT ERROR"
      ;;
    *)
      echo "UNKNOWN"
      ;;
  esac
}

# Validate state transition
is_valid_transition() {
  local from_state="$1"
  local to_state="$2"
  
  local valid_transitions=$(get_valid_transitions "$from_state")
  
  for valid_state in $valid_transitions; do
    if [[ "$valid_state" == "$to_state" ]]; then
      return 0
    fi
  done
  
  return 1
}

# Get current state
get_current_state() {
  if [[ -f "${CURRENT_STATE_FILE}" ]]; then
    cat "${CURRENT_STATE_FILE}"
  else
    echo "UNKNOWN"
  fi
}

# Record state transition
record_state_transition() {
  local from_state="$1"
  local to_state="$2"
  local reason="${3:-}"
  
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local entry="${timestamp} ${from_state} -> ${to_state} (${reason})"
  
  echo "$entry" >> "${STATE_HISTORY_FILE}"
  log_info "State transition recorded: $from_state -> $to_state"
}

# Transition to new state
transition_state() {
  local new_state="$1"
  local reason="${2:-}"
  
  local current_state=$(get_current_state)
  
  if ! is_valid_transition "$current_state" "$new_state"; then
    log_error "Invalid transition: $current_state -> $new_state"
    return 1
  fi
  
  echo "$new_state" > "${CURRENT_STATE_FILE}"
  record_state_transition "$current_state" "$new_state" "$reason"
  
  log_success "✓ Transitioned to: $new_state"
  return 0
}

# Get state metadata
get_state_metadata() {
  local state="$1"
  
  case "$state" in
    INIT)
      echo '{"description": "Initial state", "type": "START", "recoverable": true}'
      ;;
    VALIDATION)
      echo '{"description": "Pre-deployment validation", "type": "CHECK", "recoverable": true}'
      ;;
    PRE_FLIGHT)
      echo '{"description": "Pre-flight checks", "type": "CHECK", "recoverable": true}'
      ;;
    PREPARING)
      echo '{"description": "Service preparation", "type": "SETUP", "recoverable": true}'
      ;;
    DEPLOYING)
      echo '{"description": "Active deployment", "type": "ACTION", "recoverable": true}'
      ;;
    DEPLOYED)
      echo '{"description": "Deployment complete", "type": "CHECK", "recoverable": true}'
      ;;
    TESTING)
      echo '{"description": "Post-deployment testing", "type": "CHECK", "recoverable": true}'
      ;;
    STABLE)
      echo '{"description": "System stable", "type": "STABLE", "recoverable": false}'
      ;;
    MONITORING)
      echo '{"description": "Active monitoring", "type": "OBSERVE", "recoverable": false}'
      ;;
    ERROR)
      echo '{"description": "Error state", "type": "ERROR", "recoverable": true}'
      ;;
    DEPLOYING_ERROR)
      echo '{"description": "Deployment error", "type": "ERROR", "recoverable": true}'
      ;;
    ROLLBACK)
      echo '{"description": "Rollback in progress", "type": "RECOVERY", "recoverable": true}'
      ;;
    *)
      echo '{"description": "Unknown state", "type": "UNKNOWN", "recoverable": false}'
      ;;
  esac
}

# Display state diagram
show_state_diagram() {
  cat <<'EOF'
┌─────────────────────────────────────────────────────┐
│          DEPLOYMENT STATE MACHINE                   │
└─────────────────────────────────────────────────────┘

  INIT
   ├→ VALIDATION
   │   ├→ PRE_FLIGHT
   │   │   ├→ PREPARING
   │   │   │   ├→ DEPLOYING
   │   │   │   │   ├→ DEPLOYED
   │   │   │   │   │   ├→ TESTING
   │   │   │   │   │   │   ├→ STABLE
   │   │   │   │   │   │   │   ├→ MONITORING
   │   │   │   │   │   │   │   │   └→ (cycle)
   │   │   │   │   │   │   │   └→ ROLLBACK
   │   │   │   │   │   │   └→ ERROR
   │   │   │   │   │   └→ ERROR
   │   │   │   │   └→ DEPLOYING_ERROR
   │   │   │   │       └→ ROLLBACK
   │   │   │   └→ ERROR
   │   │   └→ ERROR
   │   └→ ERROR
   └→ ERROR

State Classifications:
  ✓ START:    Initial entry point
  ✓ CHECK:    Validation/verification
  ✓ SETUP:    Preparation/configuration
  ✓ ACTION:   Active operations
  ✓ STABLE:   Operational steady state
  ✓ OBSERVE:  Monitoring operations
  ✓ ERROR:    Error handling
  ✓ RECOVERY: Recovery operations
EOF
}

# Get state history
get_state_history() {
  local limit="${1:-20}"
  
  if [[ ! -f "${STATE_HISTORY_FILE}" ]]; then
    log_warn "No state history available"
    return 0
  fi
  
  log_info "Recent state transitions (last $limit):"
  tail -n "$limit" "${STATE_HISTORY_FILE}"
}

# Can recover from state?
can_recover() {
  local state="$1"
  
  local metadata=$(get_state_metadata "$state")
  local recoverable=$(echo "$metadata" | jq -r '.recoverable')
  
  if [[ "$recoverable" == "true" ]]; then
    return 0
  fi
  
  return 1
}

# Get next valid state
get_next_states() {
  local current_state="$1"
  
  get_valid_transitions "$current_state"
}

# Main action handler
main() {
  init_state_directory
  
  local action="${1:-status}"
  
  case "$action" in
    status)
      local state=$(get_current_state)
      log_info "Current state: $state"
      get_state_metadata "$state" | jq .
      echo
      echo "Valid next states:"
      get_next_states "$state"
      ;;
    
    transition)
      local new_state="$2"
      local reason="${3:-manual transition}"
      transition_state "$new_state" "$reason"
      ;;
    
    diagram)
      show_state_diagram
      ;;
    
    history)
      local limit="${2:-20}"
      get_state_history "$limit"
      ;;
    
    recover)
      local current_state=$(get_current_state)
      if can_recover "$current_state"; then
        log_success "✓ State $current_state is recoverable"
        transition_state "ERROR" "recovery initiated"
        transition_state "INIT" "recovering to init"
      else
        log_error "✗ State $current_state is not recoverable"
        return 1
      fi
      ;;
    
    validate)
      local from="$2"
      local to="$3"
      if is_valid_transition "$from" "$to"; then
        log_success "✓ Valid transition: $from -> $to"
      else
        log_error "✗ Invalid transition: $from -> $to"
        return 1
      fi
      ;;
    
    *)
      log_error "Unknown action: $action"
      log_info "Valid actions: status, transition, diagram, history, recover, validate"
      return 1
      ;;
  esac
}

# Execute
main "$@"
