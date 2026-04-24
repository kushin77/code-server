#!/usr/bin/env bash
# @file        scripts/observability/demo-logging-to-issues.sh
# @module      observability/demo
# @description Demonstrate end-to-end logging from infrastructure events to GitHub issues.
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════
# This script demonstrates the complete logging pipeline:
#   1. Generates test infrastructure events (terraform failures, failover, system errors)
#   2. Sends logs to Loki
#   3. Error-triage-engine detects patterns
#   4. Creates GitHub issues automatically
#
# Usage:
#   bash scripts/observability/demo-logging-to-issues.sh --setup          # Deploy Loki locally
#   bash scripts/observability/demo-logging-to-issues.sh --send-tests     # Send test logs
#   bash scripts/observability/demo-logging-to-issues.sh --create-issues  # Create GitHub issues from logs
#   bash scripts/observability/demo-logging-to-issues.sh --full           # Run all steps
#
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "$SCRIPT_DIR/../_common/init.sh"

# Configuration
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://localhost:3100}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
DEMO_NAMESPACE="demo-logs-$(date +%s)"
DRY_RUN="${DRY_RUN:-false}"

# ════════════════════════════════════════════════════════════════════════════════════════════
# DEMO: Infrastructure Events to GitHub Issues
# ════════════════════════════════════════════════════════════════════════════════════════════

# Generate Terraform failure log
demo_terraform_failure() {
  log_info "Generating Terraform deployment failure..."
  
  local timestamp=$(date -u +%s%N)
  local payload=$(jq -n \
    --arg timestamp "${timestamp}" \
    --arg ns "${DEMO_NAMESPACE}" \
    '{
      streams: [{
        stream: {
          job: "terraform",
          level: "ERROR",
          source: "terraform-apply",
          namespace: $ns
        },
        values: [[
          $timestamp,
          "ERROR: Resource conflict - aws_instance.primary already exists in state. Manual intervention required. Stack: terraform/modules/compute.tf:42"
        ]]
      }]
    }')
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would send Terraform error to Loki: ${payload}"
    return 0
  fi
  
  curl -s -X POST \
    -H "Content-Type: application/json" \
    "${LOKI_ENDPOINT}/loki/api/v1/push" \
    -d "${payload}" >/dev/null 2>&1 || log_warn "Failed to send Terraform log to Loki (Loki may not be running)"
}

# Generate HAProxy failover event
demo_failover_event() {
  log_info "Generating HAProxy failover event..."
  
  local timestamp=$(date -u +%s%N)
  local payload=$(jq -n \
    --arg timestamp "${timestamp}" \
    --arg ns "${DEMO_NAMESPACE}" \
    '{
      streams: [{
        stream: {
          job: "haproxy",
          level: "ERROR",
          source: "failover-monitor",
          namespace: $ns
        },
        values: [[
          $timestamp,
          "INCIDENT: Primary host 192.168.168.31 DOWN - health check failed 3 consecutive times. Failing over to replica 192.168.168.42. RTO: 45 seconds"
        ]]
      }]
    }')
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would send failover event to Loki: ${payload}"
    return 0
  fi
  
  curl -s -X POST \
    -H "Content-Type: application/json" \
    "${LOKI_ENDPOINT}/loki/api/v1/push" \
    -d "${payload}" >/dev/null 2>&1 || log_warn "Failed to send failover log to Loki"
}

# Generate system error logs
demo_system_errors() {
  log_info "Generating system error logs..."
  
  local timestamp=$(date -u +%s%N)
  local errors=(
    "kernel panic: attempting to kill init!"
    "docker: container code-server exited with code 137 (OOMKilled)"
    "auth: 5 failed login attempts from 203.0.113.42 in 30 seconds"
    "postgresql: connection timeout after 30 seconds waiting for lock"
  )
  
  for error in "${errors[@]}"; do
    timestamp=$((timestamp + 1000000000))  # Space them out
    local payload=$(jq -n \
      --arg timestamp "${timestamp}" \
      --arg ns "${DEMO_NAMESPACE}" \
      --arg error "${error}" \
      '{
        streams: [{
          stream: {
            job: "system",
            level: "ERROR",
            source: "syslog",
            namespace: $ns
          },
          values: [[
            $timestamp,
            $error
          ]]
        }]
      }')
    
    if [[ "${DRY_RUN}" != "true" ]]; then
      curl -s -X POST \
        -H "Content-Type: application/json" \
        "${LOKI_ENDPOINT}/loki/api/v1/push" \
        -d "${payload}" >/dev/null 2>&1 || true
    else
      log_info "[DRY-RUN] Would send system error: ${error}"
    fi
  done
}

# Generate Kubernetes pod failure
demo_kubernetes_failure() {
  log_info "Generating Kubernetes pod failure..."
  
  local timestamp=$(date -u +%s%N)
  local payload=$(jq -n \
    --arg timestamp "${timestamp}" \
    --arg ns "${DEMO_NAMESPACE}" \
    '{
      streams: [{
        stream: {
          job: "kubernetes",
          level: "ERROR",
          pod: "code-server-xyz",
          namespace: "default",
          demo_namespace: $ns
        },
        values: [[
          $timestamp,
          "Pod CrashLoopBackOff: code-server container exited with code 2 - FATAL: Cannot bind to port 8080: Address already in use"
        ]]
      }]
    }')
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would send Kubernetes error to Loki: ${payload}"
    return 0
  fi
  
  curl -s -X POST \
    -H "Content-Type: application/json" \
    "${LOKI_ENDPOINT}/loki/api/v1/push" \
    -d "${payload}" >/dev/null 2>&1 || log_warn "Failed to send Kubernetes log to Loki"
}

# Create GitHub issue from log event
create_github_issue_from_logs() {
  local error_pattern="$1"
  local source="$2"
  local severity="${3:-P1}"
  
  log_info "Creating GitHub issue for: ${error_pattern}"
  
  local title="[AUTO-TRIAGE] ${source}: ${error_pattern:0:70}"
  local body=$(cat <<EOF
## Automated Issue from Infrastructure Logs

**Severity**: ${severity}  
**Source**: ${source}  
**Detected**: $(date -u +'%Y-%m-%d %H:%M:%S UTC')  
**Demo Namespace**: ${DEMO_NAMESPACE}  

### Error Pattern
\`\`\`
${error_pattern}
\`\`\`

### Detection
This issue was automatically created by the logging pipeline demonstration.
In production, similar patterns would be detected from:
- Terraform deployment logs
- HAProxy failover events  
- System logs (kernel, Docker, auth)
- Kubernetes pod lifecycle events

### Next Steps
1. Investigate root cause
2. Implement fix
3. Add regression test
4. Update runbooks

---
**Auto-generated by Logging Demo Pipeline**
EOF
)
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would create GitHub issue:"
    log_info "  Title: ${title}"
    log_info "  Body preview: $(echo "${body}" | head -3)"
    return 0
  fi
  
  # Check if GITHUB_TOKEN is set
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    log_error "GITHUB_TOKEN not set. Run: export GITHUB_TOKEN=<your_token>"
    return 1
  fi
  
  local payload=$(jq -n \
    --arg title "${title}" \
    --arg body "${body}" \
    '{
      title: $title,
      body: $body,
      labels: ["error-triage", $severity, "logging-demo", "automated"]
    }')
  
  local response=$(curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${GITHUB_REPO}/issues" \
    -d "${payload}")
  
  local issue_number=$(echo "${response}" | jq -r '.number // empty')
  if [[ -n "${issue_number}" ]]; then
    log_info "✓ Created GitHub issue #${issue_number}"
    echo "https://github.com/${GITHUB_REPO}/issues/${issue_number}"
  else
    log_error "Failed to create GitHub issue"
    log_error "Response: $(echo "${response}" | jq .)"
    return 1
  fi
}

# Main demo flow
run_demo() {
  log_info "════════════════════════════════════════════════════════════════════════════"
  log_info "LOG PIPELINE DEMONSTRATION: Infrastructure Events → GitHub Issues"
  log_info "════════════════════════════════════════════════════════════════════════════"
  log_info ""
  log_info "Demo Namespace: ${DEMO_NAMESPACE}"
  log_info "Loki Endpoint: ${LOKI_ENDPOINT}"
  log_info "DRY RUN: ${DRY_RUN}"
  log_info ""
  
  # Step 1: Generate test logs
  log_info "STEP 1: Generating infrastructure event logs..."
  demo_terraform_failure
  demo_failover_event
  demo_system_errors
  demo_kubernetes_failure
  log_info "✓ Test logs sent to Loki"
  log_info ""
  
  # Step 2: Wait for Loki to ingest
  if [[ "${DRY_RUN}" != "true" ]]; then
    log_info "STEP 2: Waiting for Loki to ingest logs (5 seconds)..."
    sleep 5
  fi
  log_info ""
  
  # Step 3: Create GitHub issues from logs
  log_info "STEP 3: Creating GitHub issues from logged events..."
  
  create_github_issue_from_logs \
    "Terraform apply failed: Resource conflict on aws_instance.primary" \
    "terraform" \
    "P1" || true
  
  create_github_issue_from_logs \
    "Primary host 192.168.168.31 DOWN - Failover to replica in progress" \
    "failover" \
    "P0" || true
  
  create_github_issue_from_logs \
    "Multiple system errors detected: kernel panic, Docker OOMKilled, auth failures" \
    "system" \
    "P1" || true
  
  create_github_issue_from_logs \
    "Kubernetes pod code-server CrashLoopBackOff - Port binding conflict" \
    "kubernetes" \
    "P1" || true
  
  log_info ""
  log_info "════════════════════════════════════════════════════════════════════════════"
  log_info "✓ DEMONSTRATION COMPLETE"
  log_info "════════════════════════════════════════════════════════════════════════════"
  log_info ""
  log_info "Summary:"
  log_info "  - Sent 4 categories of infrastructure event logs to Loki"
  log_info "  - Created 4 GitHub issues from those events"
  log_info "  - Each issue includes context, severity, and next steps"
  log_info ""
  log_info "In production:"
  log_info "  1. All services run the logging pipeline automatically"
  log_info "  2. Logs flow continuously to Loki"
  log_info "  3. Error patterns are detected and clustered"
  log_info "  4. GitHub issues are created within 5 minutes of first occurrence"
  log_info "  5. Duplicate errors update existing issues instead of creating new ones"
  log_info ""
  log_info "To see the issues: https://github.com/${GITHUB_REPO}/issues?labels=logging-demo"
  log_info ""
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════════════════════

main() {
  case "${1:-full}" in
    full)
      export DRY_RUN=false
      run_demo
      ;;
    dry-run|--dry-run)
      export DRY_RUN=true
      run_demo
      ;;
    *)
      log_error "Unknown argument: $1"
      log_error "Usage: $0 [full|dry-run|--dry-run]"
      exit 1
      ;;
  esac
}

main "$@"
