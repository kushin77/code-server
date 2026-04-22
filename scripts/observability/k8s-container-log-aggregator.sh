#!/usr/bin/env bash
# @file        scripts/observability/k8s-container-log-aggregator.sh
# @module      observability/kubernetes
# @description Aggregates Kubernetes pod logs and container events to Loki.
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════
# Kubernetes Log Aggregator (Phase 22+)
#
# Purpose:
#   - Collect logs from all pods across namespaces
#   - Monitor container events (restart, OOM, crash)
#   - Ship to Loki with pod/namespace/container metadata
#   - Create GitHub issues for CrashLoopBackOff, OOMKilled, etc.
#
# Usage:
#   kubectl apply -f scripts/observability/k8s-log-aggregator-daemonset.yaml
#   ./scripts/observability/k8s-container-log-aggregator.sh --daemon
#
# ════════════════════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

source "${PROJECT_ROOT}/scripts/_common/init.sh" || { echo "FATAL: Cannot source init.sh"; exit 1; }

# Configuration
LOKI_ENDPOINT="${LOKI_ENDPOINT:-http://loki:3100}"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
NAMESPACES="${NAMESPACES:-default,kube-system,monitoring}"
DAEMON_MODE=false
CHECK_INTERVAL=30
GITHUB_ISSUE_ON_CRASH=true

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --daemon)
      DAEMON_MODE=true
      shift
      ;;
    --interval)
      CHECK_INTERVAL="$2"
      shift 2
      ;;
    --namespaces)
      NAMESPACES="$2"
      shift 2
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ════════════════════════════════════════════════════════════════════════════════════════════
# KUBERNETES LOG COLLECTION
# ════════════════════════════════════════════════════════════════════════════════════════════

# Check if kubectl is available
check_kubernetes_availability() {
  if ! command -v kubectl &>/dev/null; then
    log_error "kubectl not found in PATH"
    return 1
  fi
  
  if ! kubectl cluster-info &>/dev/null; then
    log_error "Unable to connect to Kubernetes cluster"
    return 1
  fi
  
  return 0
}

# Send pod logs to Loki
send_pod_logs_to_loki() {
  local namespace="$1"
  local pod="$2"
  local container="${3:-}"
  local timestamp="${4:-$(date -u +%s%N)}"
  
  # Get pod logs
  local logs
  local kubectl_cmd="kubectl logs -n ${namespace} ${pod}"
  
  if [[ -n "${container}" ]]; then
    kubectl_cmd="${kubectl_cmd} -c ${container}"
  fi
  
  # Get last 100 lines
  kubectl_cmd="${kubectl_cmd} --tail=100 2>/dev/null || echo ''"
  logs=$(eval "${kubectl_cmd}")
  
  if [[ -z "${logs}" ]]; then
    return 0
  fi
  
  # Build Loki payload
  local lines_array="[]"
  
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ -z "${line}" ]]; then
      continue
    fi
    
    local entry
    entry=$(jq -n \
      --arg timestamp "${timestamp}" \
      --arg message "${line}" \
      '[($timestamp | tonumber), $message]')
    
    lines_array=$(echo "${lines_array}" | jq --argjson entry "${entry}" '. += [$entry]')
  done <<< "${logs}"
  
  if [[ "${lines_array}" == "[]" ]]; then
    return 0
  fi
  
  local payload
  payload=$(jq -n \
    --arg namespace "${namespace}" \
    --arg pod "${pod}" \
    --arg container "${container}" \
    --argjson values "${lines_array}" \
    '{
      streams: [{
        stream: {
          job: "kubernetes",
          namespace: $namespace,
          pod: $pod,
          container: $container
        },
        values: $values
      }]
    }')
  
  curl -s -X POST \
    -H "Content-Type: application/json" \
    "${LOKI_ENDPOINT}/loki/api/v1/push" \
    -d "${payload}" \
    >/dev/null 2>&1 || log_warn "Failed to send pod logs to Loki"
}

# Monitor pod events
monitor_pod_events() {
  local namespace="$1"
  
  log_debug "Monitoring events in namespace: ${namespace}"
  
  # Get recent events from namespace
  local events
  events=$(kubectl get events -n "${namespace}" \
    --sort-by='.lastTimestamp' \
    -o json 2>/dev/null || echo '{"items":[]}')
  
  local event_count
  event_count=$(echo "${events}" | jq '.items | length' 2>/dev/null || echo 0)
  
  if [[ ${event_count} -eq 0 ]]; then
    return 0
  fi
  
  # Process each event
  echo "${events}" | jq -r '.items[] | @json' | while read -r event_json; do
    local event_type
    event_type=$(echo "${event_json}" | jq -r '.type' 2>/dev/null || echo "Unknown")
    
    local reason
    reason=$(echo "${event_json}" | jq -r '.reason' 2>/dev/null || echo "Unknown")
    
    local message
    message=$(echo "${event_json}" | jq -r '.message' 2>/dev/null || echo "")
    
    # Check for critical events
    if [[ "${reason}" =~ (BackOff|CrashLoopBackOff|OOMKilled|ImagePullBackOff) ]]; then
      log_warn "Critical event detected: ${reason} in namespace ${namespace}"
      create_issue_on_pod_crash "${namespace}" "${reason}" "${message}"
    fi
  done
}

# Create GitHub issue for pod crash/restart
create_issue_on_pod_crash() {
  local namespace="$1"
  local reason="$2"
  local message="$3"
  
  if [[ "${GITHUB_ISSUE_ON_CRASH}" != "true" ]]; then
    return 0
  fi
  
  log_info "Creating GitHub issue for pod crash: ${reason}"
  
  source "${PROJECT_ROOT}/scripts/_common/issue-create-unified.sh" 2>/dev/null || {
    log_warn "Issue creation script not available"
    return 1
  }
  
  copilot_create_issue \
    --title "🔴 CRITICAL: Kubernetes Pod ${reason} in ${namespace}" \
    --body "## Kubernetes Pod Crash Report

**Event Type**: ${reason}
**Namespace**: ${namespace}
**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

### Event Message
\`\`\`
${message}
\`\`\`

### Investigation Steps
1. Get pod status: \`kubectl describe pod -n ${namespace}\`
2. Check pod events: \`kubectl get events -n ${namespace}\`
3. Review pod logs: \`kubectl logs -n ${namespace} <pod-name> --previous\`
4. Check resource requests/limits
5. Verify container image exists and is healthy

### Likely Causes
- **CrashLoopBackOff**: Container exits immediately, check logs
- **OOMKilled**: Pod exceeded memory limit, increase resources
- **ImagePullBackOff**: Image not found or pull failed, check image name
- **ErrImagePull**: Similar to above, check image registry access

### Action Items
- [ ] Identify root cause from logs
- [ ] Implement fix
- [ ] Update pod manifest if needed
- [ ] Redeploy pod
- [ ] Monitor for recurrence

---
*Auto-generated by Kubernetes Log Aggregator*" \
    --priority P1 \
    --type infrastructure
}

# Collect logs from all pods in namespace
collect_namespace_logs() {
  local namespace="$1"
  
  log_info "Collecting logs from namespace: ${namespace}"
  
  # Get list of pods
  local pods
  pods=$(kubectl get pods -n "${namespace}" \
    -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
  
  if [[ -z "${pods}" ]]; then
    log_debug "No pods found in namespace: ${namespace}"
    return 0
  fi
  
  # Collect logs from each pod
  for pod in ${pods}; do
    # Get containers in pod
    local containers
    containers=$(kubectl get pod -n "${namespace}" "${pod}" \
      -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || echo "")
    
    for container in ${containers}; do
      send_pod_logs_to_loki "${namespace}" "${pod}" "${container}"
    done
    
    # Monitor events
    monitor_pod_events "${namespace}"
  done
  
  log_info "Namespace logs collection complete: ${namespace}"
}

# ════════════════════════════════════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════════════════════════════════════

check_k8s_logs() {
  if ! check_kubernetes_availability; then
    return 1
  fi
  
  # Collect logs from each namespace
  for namespace in $(echo "${NAMESPACES}" | tr ',' '\n'); do
    collect_namespace_logs "${namespace}" || true
  done
  
  log_info "Kubernetes log collection complete"
}

run_daemon() {
  log_info "Starting Kubernetes log aggregator daemon (interval: ${CHECK_INTERVAL}s)"
  
  while true; do
    check_k8s_logs || true
    sleep "${CHECK_INTERVAL}"
  done
}

main() {
  log_info "Kubernetes Container Log Aggregator starting..."
  log_info "  Loki Endpoint: ${LOKI_ENDPOINT}"
  log_info "  Namespaces: ${NAMESPACES}"
  
  if [[ "${DAEMON_MODE}" == "true" ]]; then
    run_daemon
  else
    check_k8s_logs
    log_info "Log collection complete. Use --daemon flag to run continuously"
  fi
}

main "$@"
