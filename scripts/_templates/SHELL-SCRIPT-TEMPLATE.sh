#!/usr/bin/env bash
# @file: template.sh
# @module: template/example
# @description: Template shell script demonstrating all governance standards.
#               Use this as a boilerplate for new scripts in scripts/ directory.
# @author: DevOps Team
# @updated: 2026-04-15

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# IMPORTS
# =============================================================================

# Source common utilities (adjust paths as needed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/_common/env.sh"
source "${SCRIPT_DIR}/_common/logging.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Parameterize all values - NO HARDCODED IPs, ports, or credentials
readonly TARGET_HOST="${TARGET_HOST:-${PROD_HOST}}"
readonly TARGET_PORT="${TARGET_PORT:-8080}"
readonly TIMEOUT_SEC="${TIMEOUT_SEC:-30}"
readonly MAX_RETRIES="${MAX_RETRIES:-3}"

# =============================================================================
# FUNCTIONS
# =============================================================================

# Print usage information
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

This script demonstrates all governance best practices.

OPTIONS:
  -h, --help            Show this help message
  -v, --verbose         Enable verbose logging
  -d, --dry-run         Run without making changes
  --host HOST           Override target host (default: $TARGET_HOST)
  --port PORT           Override target port (default: $TARGET_PORT)

EXAMPLES:
  # Basic usage
  $0

  # With custom host
  $0 --host 192.168.168.42 --port 9000

  # Dry-run to see what would happen
  $0 --dry-run
EOF
}

# Parse command-line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -v|--verbose)
        export VERBOSE=true
        shift
        ;;
      -d|--dry-run)
        export DRY_RUN=true
        shift
        ;;
      --host)
        shift
        export TARGET_HOST="$1"
        shift
        ;;
      --port)
        shift
        export TARGET_PORT="$1"
        shift
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        log_error "Unexpected argument: $1"
        usage
        exit 1
        ;;
    esac
  done
}

# Validate preconditions
validate_preconditions() {
  log_info "Validating preconditions..."
  
  # Check required tools are available
  for tool in curl; do
    if ! command -v "$tool" &> /dev/null; then
      log_error "Required tool not found: $tool"
      return 1
    fi
  done
  
  log_info "All preconditions met"
  return 0
}

# Perform the main operation
main_operation() {
  local endpoint="${TARGET_HOST}:${TARGET_PORT}"
  
  log_info "Starting main operation on $endpoint..."
  
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would execute: curl http://$endpoint/health"
    return 0
  fi
  
  # Example: Call endpoint with timeout and retry logic
  local retry_count=0
  while [[ $retry_count -lt $MAX_RETRIES ]]; do
    if curl -sf --max-time "$TIMEOUT_SEC" "http://$endpoint/health" > /dev/null 2>&1; then
      log_info "Operation successful"
      return 0
    fi
    
    retry_count=$((retry_count + 1))
    if [[ $retry_count -lt $MAX_RETRIES ]]; then
      log_warn "Attempt $retry_count failed, retrying in 5 seconds..."
      sleep 5
    fi
  done
  
  log_error "Operation failed after $MAX_RETRIES attempts"
  return 1
}

# Cleanup on exit
cleanup() {
  local exit_code=$?
  
  if [[ $exit_code -eq 0 ]]; then
    log_info "Script completed successfully"
  else
    log_error "Script failed with exit code $exit_code"
  fi
  
  # Cleanup temporary files, close connections, etc.
  return $exit_code
}

# =============================================================================
# MAIN
# =============================================================================

# Set up cleanup trap
trap cleanup EXIT

# Main execution flow
main() {
  log_info "Script started: $0"
  
  # Parse arguments
  parse_args "$@"
  
  # Validate preconditions
  if ! validate_preconditions; then
    log_error "Precondition validation failed"
    return 1
  fi
  
  # Perform operation
  if ! main_operation; then
    log_error "Main operation failed"
    return 1
  fi
  
  log_info "All steps completed"
  return 0
}

# Execute main function
# Exit codes:
#   0 = Success
#   1 = Operational failure
#   2 = Configuration/validation error
if ! main "$@"; then
  exit 1
fi

exit 0
