#!/usr/bin/env bash
# @file        scripts/ops/validate-cluster-parity.sh
# @module      infrastructure/validation
# @description Validate that both replicas are at parity for production failover

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
SECONDARY_HOST="${SECONDARY_HOST:-192.168.168.42}"
SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa_onprem}"

log_info "Starting cluster parity validation..."

# Test R1
log_info "Validating Replica 1 ($PRIMARY_HOST)..."
SERVICES_R1=$(ssh -i "$SSH_KEY" "akushnir@$PRIMARY_HOST" \
  "cd code-server-enterprise && docker-compose ps --filter 'status=running' --format='{{.Service}}' 2>&1 | wc -l")

if [ "$SERVICES_R1" -ge 18 ]; then
  log_info "R1 has $SERVICES_R1 running services ✓"
else
  log_error "R1 has insufficient running services: $SERVICES_R1"
  exit 1
fi

# Test R2
log_info "Validating Replica 2 ($SECONDARY_HOST)..."
SERVICES_R2=$(ssh -i "$SSH_KEY" "akushnir@$PRIMARY_HOST" \
  "ssh akushnir@$SECONDARY_HOST \"cd code-server-enterprise && docker-compose ps --filter 'status=running' --format='{{.Service}}' 2>&1 | wc -l\"")

if [ "$SERVICES_R2" -ge 18 ]; then
  log_info "R2 has $SERVICES_R2 running services ✓"
else
  log_error "R2 has insufficient running services: $SERVICES_R2"
  exit 1
fi

# Verify git sync
log_info "Validating git synchronization..."
GIT_R1=$(ssh -i "$SSH_KEY" "akushnir@$PRIMARY_HOST" "cd code-server-enterprise && git rev-parse HEAD")
GIT_R2=$(ssh -i "$SSH_KEY" "akushnir@$PRIMARY_HOST" "ssh akushnir@$SECONDARY_HOST \"cd code-server-enterprise && git rev-parse HEAD\"")

if [ "$GIT_R1" = "$GIT_R2" ]; then
  log_info "Git commits match: $GIT_R1 ✓"
else
  log_error "Git commits differ: R1=$GIT_R1, R2=$GIT_R2"
  exit 1
fi

# Test code-server health
log_info "Validating code-server health..."
HEALTH_R1=$(ssh -i "$SSH_KEY" "akushnir@$PRIMARY_HOST" "curl -s http://localhost:8080/healthz 2>&1" | grep -o '"status":"alive"' || echo "FAIL")
HEALTH_R2=$(ssh -i "$SSH_KEY" "akushnir@$PRIMARY_HOST" "ssh akushnir@$SECONDARY_HOST \"curl -s http://localhost:8080/healthz 2>&1\"" | grep -o '"status":"alive"' || echo "FAIL")

if [ "$HEALTH_R1" = '"status":"alive"' ]; then
  log_info "R1 code-server health: OK ✓"
else
  log_error "R1 code-server health check failed"
  exit 1
fi

if [ "$HEALTH_R2" = '"status":"alive"' ]; then
  log_info "R2 code-server health: OK ✓"
else
  log_error "R2 code-server health check failed"
  exit 1
fi

log_info "✓ Cluster parity validation PASSED"
log_info "Both replicas are production-ready for failover"
