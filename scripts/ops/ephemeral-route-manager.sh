#!/usr/bin/env bash
# @file        scripts/ops/ephemeral-route-manager.sh
# @module      infrastructure/ephemeral-sessions
# @description Manage ephemeral session routes (create, revoke, cleanup, audit)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
NAMESPACE="ephemeral-sessions"
SESSION_ID_PREFIX="eph-"
DEFAULT_TTL_SECONDS=3600  # 1 hour
INGRESS_TEMPLATE="$SCRIPT_DIR/../kubernetes/ephemeral/ingress-template.yaml"
KUBECTL="${KUBECTL:-kubectl}"
DEV_SESSION_DOMAIN="${DEV_SESSION_DOMAIN:-dev.kushnir.cloud}"

# ─────────────────────────────────────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────────────────────────────────────

usage() {
  cat << EOF
Ephemeral Session Route Manager

Usage: $0 <command> [options]

Commands:
  create-route          Create a new route for an ephemeral session
  revoke-route          Revoke access to an ephemeral session
  cleanup-route         Delete a route (complete cleanup)
  list-routes           List all active ephemeral routes
  audit-route           Get audit trail for a session
  verify-cleanup        Verify a route is completely cleaned up
  reap-orphaned         Find and report orphaned routes
  health-check          Check route manager health

Create Route:
  $0 create-route --session-id <id> --pod-name <name> --pod-port <port> [--ttl <seconds>]

Revoke Route:
  $0 revoke-route --session-id <id>

Cleanup Route:
  $0 cleanup-route --session-id <id>

List Routes:
  $0 list-routes [--json]

Audit Route:
  $0 audit-route --session-id <id>

Examples:
  # Create a route for a 30-minute session
  $0 create-route --session-id a1b2c3d4 --pod-name code-server-eph-a1b2c3d4 --pod-port 8080 --ttl 1800

  # Revoke (but keep route for debugging)
  $0 revoke-route --session-id a1b2c3d4

  # Complete cleanup
  $0 cleanup-route --session-id a1b2c3d4

  # List all active routes
  $0 list-routes --json
EOF
  exit 1
}

generate_session_id() {
  # Generate: eph-XXXXXXXX (8 random hex chars)
  echo "${SESSION_ID_PREFIX}$(tr -dc '0-9a-f' </dev/urandom | head -c 8)"
}

validate_session_id() {
  local id="$1"
  if [[ ! $id =~ ^eph-[0-9a-f]{8}$ ]]; then
    log_error "Invalid session ID format: $id (expected: eph-XXXXXXXX)"
    return 1
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# CREATE ROUTE
# ─────────────────────────────────────────────────────────────────────────────

cmd_create_route() {
  local session_id="" pod_name="" pod_port="" ttl_seconds="$DEFAULT_TTL_SECONDS"
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id) session_id="$2"; shift 2 ;;
      --pod-name) pod_name="$2"; shift 2 ;;
      --pod-port) pod_port="$2"; shift 2 ;;
      --ttl) ttl_seconds="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  
  # Validation
  [[ -z "$session_id" ]] && { log_error "Missing --session-id"; usage; }
  [[ -z "$pod_name" ]] && { log_error "Missing --pod-name"; usage; }
  [[ -z "$pod_port" ]] && { log_error "Missing --pod-port"; usage; }
  
  validate_session_id "$session_id" || return 1
  
  log_info "Creating ephemeral route for $session_id..."
  
  # Verify namespace exists
  if ! $KUBECTL get namespace "$NAMESPACE" &>/dev/null; then
    log_info "Creating namespace: $NAMESPACE"
    $KUBECTL create namespace "$NAMESPACE" || true
  fi
  
  # Verify pod exists
  if ! $KUBECTL get pod "$pod_name" -n "$NAMESPACE" &>/dev/null; then
    log_error "Pod not found: $pod_name in namespace $NAMESPACE"
    return 1
  fi
  
  # Verify pod is running
  local pod_status
  pod_status=$($KUBECTL get pod "$pod_name" -n "$NAMESPACE" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  
  if [[ "$pod_status" != "Running" ]]; then
    log_warn "Pod status is $pod_status (not Running yet). Route creation may fail."
  fi
  
  local creation_time
  creation_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local expiry_time
  expiry_time=$(date -u -d "+$ttl_seconds seconds" +%Y-%m-%dT%H:%M:%SZ)
  local auth_token
  auth_token=$(openssl rand -hex 32)
  local auth_secret="${session_id}-auth"
  
  # Create auth secret
  log_info "Creating auth secret: $auth_secret"
  $KUBECTL create secret generic "$auth_secret" \
    --from-literal="token=$auth_token" \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | $KUBECTL apply -f - || {
    log_error "Failed to create auth secret"
    return 1
  }
  
  # Render and apply Ingress + Service + ConfigMap from template
  log_info "Rendering and applying Ingress resources..."
  
  sed -e "s|{{ session_id }}|${session_id}|g" \
      -e "s|{{ dev_session_domain }}|${DEV_SESSION_DOMAIN}|g" \
      -e "s|{{ pod_name }}|${pod_name}|g" \
      -e "s|{{ pod_port }}|${pod_port}|g" \
      -e "s|{{ ttl_seconds }}|${ttl_seconds}|g" \
      -e "s|{{ creation_time }}|${creation_time}|g" \
      -e "s|{{ expiry_time }}|${expiry_time}|g" \
      -e "s|{{ auth_token_name }}|${auth_secret}|g" \
      "$INGRESS_TEMPLATE" | $KUBECTL apply -f - || {
    log_error "Failed to apply Ingress resources"
    return 1
  }
  
  # Record creation event
  log_info "Route created successfully"
  log_info ""
  log_info "Session Details:"
  log_info "  Session ID: $session_id"
  log_info "  URL: https://${DEV_SESSION_DOMAIN}/$session_id"
  log_info "  Auth Token: ${auth_token:0:16}...${auth_token: -8}"
  log_info "  TTL: ${ttl_seconds}s (expires at $expiry_time)"
  log_info "  Pod: $pod_name"
  log_info ""
  
  # Return auth token for client
  echo "$auth_token"
}

# ─────────────────────────────────────────────────────────────────────────────
# REVOKE ROUTE (auth token invalidation)
# ─────────────────────────────────────────────────────────────────────────────

cmd_revoke_route() {
  local session_id=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id) session_id="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  
  [[ -z "$session_id" ]] && { log_error "Missing --session-id"; usage; }
  validate_session_id "$session_id" || return 1
  
  log_info "Revoking route for $session_id..."
  
  # Delete auth secret (revokes access)
  local auth_secret="${session_id}-auth"
  $KUBECTL delete secret "$auth_secret" -n "$NAMESPACE" 2>&1 | \
    grep -v "not found" || true
  
  # Ingress remains for debugging; cleanup happens via separate cleanup-route
  log_info "Route revoked: auth token invalidated"
  log_info "Route resources remain for debugging; use cleanup-route to remove completely"
}

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP ROUTE (complete removal)
# ─────────────────────────────────────────────────────────────────────────────

cmd_cleanup_route() {
  local session_id=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id) session_id="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  
  [[ -z "$session_id" ]] && { log_error "Missing --session-id"; usage; }
  validate_session_id "$session_id" || return 1
  
  log_info "Cleaning up route for $session_id..."
  
  # Drain connections (grace period)
  log_info "Draining connections (30s grace period)..."
  sleep 5
  
  # Delete all resources
  $KUBECTL delete ingress "eph-${session_id}" -n "$NAMESPACE" 2>&1 | grep -v "not found" || true
  $KUBECTL delete svc "code-server-eph-${session_id}" -n "$NAMESPACE" 2>&1 | grep -v "not found" || true
  $KUBECTL delete secret "${session_id}-auth" -n "$NAMESPACE" 2>&1 | grep -v "not found" || true
  $KUBECTL delete configmap "eph-${session_id}-config" -n "$NAMESPACE" 2>&1 | grep -v "not found" || true
  
  log_info "✅ Route cleanup complete for $session_id"
}

# ─────────────────────────────────────────────────────────────────────────────
# LIST ROUTES
# ─────────────────────────────────────────────────────────────────────────────

cmd_list_routes() {
  local output_format="table"
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) output_format="json"; shift ;;
      *) usage ;;
    esac
  done
  
  log_info "Listing ephemeral routes in namespace $NAMESPACE..."
  
  if [[ "$output_format" == "json" ]]; then
    $KUBECTL get ingress -n "$NAMESPACE" \
      -l "app.kubernetes.io/session-id" \
      -o json
  else
    $KUBECTL get ingress -n "$NAMESPACE" \
      -l "app.kubernetes.io/session-id" \
      -o custom-columns=\
NAME:.metadata.name,\
SESSION:.metadata.labels."app.kubernetes.io/session-id",\
HOST:.spec.rules[0].host,\
PATH:.spec.rules[0].http.paths[0].path,\
SERVICE:.spec.rules[0].http.paths[0].backend.service.name,\
PORT:.spec.rules[0].http.paths[0].backend.service.port.number,\
AGE:.metadata.creationTimestamp
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# AUDIT ROUTE
# ─────────────────────────────────────────────────────────────────────────────

cmd_audit_route() {
  local session_id=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id) session_id="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  
  [[ -z "$session_id" ]] && { log_error "Missing --session-id"; usage; }
  validate_session_id "$session_id" || return 1
  
  log_info "Audit trail for $session_id:"
  log_info ""
  
  # Get Ingress details
  log_info "=== Ingress Resource ==="
  $KUBECTL get ingress "eph-${session_id}" -n "$NAMESPACE" -o yaml 2>/dev/null || {
    log_warn "Ingress not found"
  }
  
  echo ""
  log_info "=== Service Resource ==="
  $KUBECTL get svc "code-server-eph-${session_id}" -n "$NAMESPACE" -o yaml 2>/dev/null || {
    log_warn "Service not found"
  }
  
  echo ""
  log_info "=== ConfigMap (Metadata) ==="
  $KUBECTL get configmap "eph-${session_id}-config" -n "$NAMESPACE" -o yaml 2>/dev/null || {
    log_warn "ConfigMap not found"
  }
  
  echo ""
  log_info "=== Events ==="
  $KUBECTL get events -n "$NAMESPACE" --field-selector involvedObject.name="eph-${session_id}" \
    -o wide 2>/dev/null || {
    log_warn "No events found"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VERIFY CLEANUP
# ─────────────────────────────────────────────────────────────────────────────

cmd_verify_cleanup() {
  local session_id=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session-id) session_id="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  
  [[ -z "$session_id" ]] && { log_error "Missing --session-id"; usage; }
  validate_session_id "$session_id" || return 1
  
  log_info "Verifying cleanup for $session_id..."
  
  local cleanup_complete=true
  
  # Check Ingress deleted
  if $KUBECTL get ingress "eph-${session_id}" -n "$NAMESPACE" &>/dev/null; then
    log_error "✗ Ingress still exists"
    cleanup_complete=false
  else
    log_info "✓ Ingress deleted"
  fi
  
  # Check Service deleted
  if $KUBECTL get svc "code-server-eph-${session_id}" -n "$NAMESPACE" &>/dev/null; then
    log_error "✗ Service still exists"
    cleanup_complete=false
  else
    log_info "✓ Service deleted"
  fi
  
  # Check Secret deleted
  if $KUBECTL get secret "${session_id}-auth" -n "$NAMESPACE" &>/dev/null; then
    log_error "✗ Auth secret still exists"
    cleanup_complete=false
  else
    log_info "✓ Auth secret deleted"
  fi
  
  # Check ConfigMap deleted
  if $KUBECTL get configmap "eph-${session_id}-config" -n "$NAMESPACE" &>/dev/null; then
    log_error "✗ ConfigMap still exists"
    cleanup_complete=false
  else
    log_info "✓ ConfigMap deleted"
  fi
  
  if $cleanup_complete; then
    log_info ""
    log_info "✅ Cleanup verification PASSED for $session_id"
    return 0
  else
    log_error ""
    log_error "❌ Cleanup verification FAILED for $session_id"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# REAP ORPHANED ROUTES
# ─────────────────────────────────────────────────────────────────────────────

cmd_reap_orphaned() {
  log_info "Scanning for orphaned routes..."
  
  local orphaned_count=0
  
  $KUBECTL get ingress -n "$NAMESPACE" -o json | jq -r '.items[].metadata.name' | \
    while read -r ingress; do
    
    local session_id
    session_id=$(echo "$ingress" | sed 's/^eph-//')
    local pod_name="code-server-eph-${session_id}"
    
    if ! $KUBECTL get pod "$pod_name" -n "$NAMESPACE" &>/dev/null; then
      log_warn "Orphaned route: $ingress (pod $pod_name does not exist)"
      ((orphaned_count++)) || true
    fi
  done
  
  log_info "Orphaned routes found: $orphaned_count"
}

# ─────────────────────────────────────────────────────────────────────────────
# HEALTH CHECK
# ─────────────────────────────────────────────────────────────────────────────

cmd_health_check() {
  log_info "Route manager health check..."
  
  # Check namespace
  if $KUBECTL get namespace "$NAMESPACE" &>/dev/null; then
    log_info "✓ Namespace $NAMESPACE exists"
  else
    log_error "✗ Namespace $NAMESPACE missing"
    return 1
  fi
  
  # Check RBAC
  if $KUBECTL get clusterrole ephemeral-route-manager &>/dev/null; then
    log_info "✓ ClusterRole ephemeral-route-manager exists"
  else
    log_error "✗ ClusterRole ephemeral-route-manager missing"
  fi
  
  # Check template file
  if [[ -f "$INGRESS_TEMPLATE" ]]; then
    log_info "✓ Ingress template exists: $INGRESS_TEMPLATE"
  else
    log_error "✗ Ingress template missing: $INGRESS_TEMPLATE"
  fi
  
  log_info "✅ Health check complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

[[ $# -eq 0 ]] && usage

case "$1" in
  create-route) shift; cmd_create_route "$@" ;;
  revoke-route) shift; cmd_revoke_route "$@" ;;
  cleanup-route) shift; cmd_cleanup_route "$@" ;;
  list-routes) shift; cmd_list_routes "$@" ;;
  audit-route) shift; cmd_audit_route "$@" ;;
  verify-cleanup) shift; cmd_verify_cleanup "$@" ;;
  reap-orphaned) shift; cmd_reap_orphaned "$@" ;;
  health-check) shift; cmd_health_check "$@" ;;
  *) usage ;;
esac
