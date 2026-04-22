#!/usr/bin/env bash
# @file        scripts/observability/terraform-log-collector.sh
# @module      observability/log-collection
# @description Collects Terraform apply/plan logs and ships them to Loki for automated issue detection.
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════
# Terraform Log Collection (Phase 22+)
#
# Purpose:
#   - Capture terraform apply/plan/destroy logs
#   - Parse error/warning/info messages
#   - Ship to Loki with proper labels
#   - Trigger GitHub issues on critical changes/failures
#
# Usage:
#   ./scripts/observability/terraform-log-collector.sh --operation apply --log-file /path/to/tf.log
#   TERRAFORM_LOG=DEBUG terraform apply | ./scripts/observability/terraform-log-collector.sh --stream
#
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${PROJECT_ROOT}/scripts/_common/init.sh" || { echo "FATAL: Cannot source init.sh"; exit 1; }

# Configuration
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://loki:3100}"
TERRAFORM_LOG_DIR="${PROJECT_ROOT}/logs/terraform"
OPERATION="${OPERATION:-unknown}"  # apply, plan, destroy, init, validate
LOG_FILE="${LOG_FILE:-}"
STREAM_MODE=false
GITHUB_ISSUE_ON_ERROR=true

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --operation)
      OPERATION="$2"
      shift 2
      ;;
    --log-file)
      LOG_FILE="$2"
      shift 2
      ;;
    --stream)
      STREAM_MODE=true
      shift
      ;;
    --loki-endpoint)
      LOKI_ENDPOINT="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p "${TERRAFORM_LOG_DIR}"

# ════════════════════════════════════════════════════════════════════════════════════════════
# LOG PARSING & LOKI SHIPPING
# ════════════════════════════════════════════════════════════════════════════════════════════

# Ship log lines to Loki
send_to_loki() {
  local message="$1"
  local level="${2:-INFO}"
  local timestamp="${3:-$(date -u +%s%N)}"
  
  # Build JSON payload for Loki push API
  local payload
  payload=$(jq -n \
    --arg timestamp "${timestamp}" \
    --arg message "${message}" \
    --arg level "${level}" \
    --arg operation "${OPERATION}" \
    '{
      streams: [{
        stream: {
          job: "terraform",
          level: $level,
          operation: $operation,
          host: env.HOSTNAME
        },
        values: [[
          $timestamp,
          $message
        ]]
      }]
    }')
  
  curl -s -X POST \
    -H "Content-Type: application/json" \
    "${LOKI_ENDPOINT}/loki/api/v1/push" \
    -d "${payload}" \
    >/dev/null 2>&1 || log_warn "Failed to send log to Loki"
}

# Parse Terraform output lines
parse_terraform_output() {
  local line="$1"
  local level="INFO"
  local should_log=false
  
  # Detect error patterns
  if [[ "${line}" =~ (Error|ERROR|fatal|FATAL|panic|PANIC|failed|FAILED) ]]; then
    level="ERROR"
    should_log=true
  # Detect warning patterns
  elif [[ "${line}" =~ (Warning|WARNING|warn|WARN|deprecated|DEPRECATED) ]]; then
    level="WARN"
    should_log=true
  # Detect resource operations
  elif [[ "${line}" =~ Apply\ complete|aws_|google_|azurerm_|docker_|postgresql_|random_ ]]; then
    level="INFO"
    should_log=true
  # Detect plan operations
  elif [[ "${line}" =~ (#\ will\ be|#\ must\ be|#\ will\ be\ added|#\ will\ be\ destroyed) ]]; then
    level="DEBUG"
    should_log=true
  # Detect network/timeout issues
  elif [[ "${line}" =~ (timeout|Timeout|TIMEOUT|connection\ refused|503|502|504) ]]; then
    level="ERROR"
    should_log=true
  fi
  
  if [[ "${should_log}" == "true" ]]; then
    send_to_loki "${line}" "${level}"
  fi
}

# Process log file
process_log_file() {
  local log_file="$1"
  
  if [[ ! -f "${log_file}" ]]; then
    log_error "Log file not found: ${log_file}"
    return 1
  fi
  
  log_info "Processing Terraform log: ${log_file}"
  
  # Read and parse each line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    parse_terraform_output "${line}"
  done < "${log_file}"
  
  # Also save a copy for reference
  cp "${log_file}" "${TERRAFORM_LOG_DIR}/$(date +%Y%m%d_%H%M%S)_${OPERATION}.log"
  
  log_info "Terraform log processing complete"
}

# Stream mode: read from stdin and process in real-time
process_stdin_stream() {
  log_info "Terraform log stream mode activated (operation: ${OPERATION})"
  
  while IFS= read -r line || [[ -n "${line}" ]]; do
    parse_terraform_output "${line}"
  done
  
  log_info "Terraform stream processing complete"
}

# Create GitHub issue for Terraform errors
create_issue_on_error() {
  local error_count="$1"
  local error_message="$2"
  local operation="$3"
  
  if [[ "${GITHUB_ISSUE_ON_ERROR}" != "true" ]] || [[ ${error_count} -eq 0 ]]; then
    return 0
  fi
  
  log_info "Creating GitHub issue for Terraform ${operation} error (${error_count} errors detected)"
  
  source "${PROJECT_ROOT}/scripts/_common/issue-create-unified.sh" 2>/dev/null || {
    log_warn "Issue creation script not available, skipping GitHub issue creation"
    return 1
  }
  
  copilot_create_issue \
    --title "[TERRAFORM] ${operation} operation failed: ${error_message:0:80}" \
    --body "## Terraform ${operation} Failure

**Operation**: terraform ${operation}
**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Error Count**: ${error_count}

### Error Details
\`\`\`
${error_message}
\`\`\`

### Investigation Steps
1. Check Terraform logs: \`terraform show -json\`
2. Verify provider credentials
3. Check resource dependencies
4. Review recent changes in git

### Action Items
- [ ] Identify root cause
- [ ] Apply fix
- [ ] Re-run terraform apply
- [ ] Verify all resources created
- [ ] Update runbooks if needed

---
*Auto-generated by Terraform Log Collector*" \
    --priority P1 \
    --type infrastructure
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════════════════════

main() {
  log_info "Terraform Log Collector starting..."
  log_info "  Operation: ${OPERATION}"
  log_info "  Loki Endpoint: ${LOKI_ENDPOINT}"
  
  if [[ "${STREAM_MODE}" == "true" ]]; then
    # Read from stdin (piped terraform command output)
    process_stdin_stream
  elif [[ -n "${LOG_FILE}" ]]; then
    # Process file
    process_log_file "${LOG_FILE}"
  else
    log_error "Either --stream or --log-file must be specified"
    exit 1
  fi
  
  log_info "Terraform log collection complete"
}

main "$@"
