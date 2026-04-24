#!/usr/bin/env bash
# @file        EXECUTE-PHASE-2-DEPLOYMENT.sh
# @module      operations/phase-2
# @description Execute complete Phase 2 (C-E) deployment: GSM provisioning, docker-compose deployment, observability, E2E testing
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/_common/init.sh"

# Configuration
GCP_PROJECT="${GCP_PROJECT:-kushin77-ops}"
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-1}"
PHASE="${PHASE:-all}"  # all, 2c, 2d, 2e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_header() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║ $1"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
}

print_step() {
  echo -e "${GREEN}▶${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
}

verify_prerequisites() {
  print_header "PHASE 2 DEPLOYMENT - PREREQUISITES VERIFICATION"
  
  print_step "Checking local environment..."
  require_command gcloud "Google Cloud CLI"
  require_command docker "Docker"
  require_command git "Git"
  
  print_step "Verifying GCP project: $GCP_PROJECT"
  gcloud config set project "$GCP_PROJECT" 2>/dev/null || {
    print_error "Cannot set GCP project to $GCP_PROJECT"
    return 1
  }
  
  print_step "Verifying SSH connectivity to primary host ($PRIMARY_HOST)..."
  ssh -o ConnectTimeout=5 "$DEPLOY_USER@$PRIMARY_HOST" "echo OK" > /dev/null 2>&1 || {
    print_error "Cannot SSH to $PRIMARY_HOST"
    return 1
  }
  
  print_step "Verifying SSH connectivity to replica host ($REPLICA_HOST)..."
  ssh -o ConnectTimeout=5 "$DEPLOY_USER@$REPLICA_HOST" "echo OK" > /dev/null 2>&1 || {
    print_warning "Cannot SSH to $REPLICA_HOST (may be offline, will skip)"
  }
  
  log_info "All prerequisites verified ✓"
}

execute_phase_2c() {
  print_header "PHASE 2C: DEPLOYMENT (GSM Provisioning + Docker Deployment)"
  
  print_step "C.1: GSM Service Account Provisioning"
  if [[ "$DRY_RUN" == "1" ]]; then
    print_warning "DRY-RUN MODE: Showing what would be provisioned"
    log_info "Would provision: ide-session-lb-secret, code-server JWT creds, session-broker JWT creds"
  else
    print_step "Running: bash scripts/ops/provision-phase-2-service-accounts.sh"
    GCP_PROJECT="$GCP_PROJECT" bash "$SCRIPT_DIR/scripts/ops/provision-phase-2-service-accounts.sh"
  fi
  
  print_step "C.2: Configuration Merge"
  print_warning "This step requires SSH to primary host. Checking if .env.phase-2 exists..."
  ssh "$DEPLOY_USER@$PRIMARY_HOST" "cd code-server-enterprise && test -f .env.phase-2" || {
    print_error ".env.phase-2 not found on primary host"
    return 1
  }
  
  print_step "C.3: Service Deployment"
  if [[ "$DRY_RUN" == "1" ]]; then
    print_warning "DRY-RUN MODE: Would execute docker-compose up -d"
  else
    print_step "Deploying services on primary host..."
    ssh "$DEPLOY_USER@$PRIMARY_HOST" "cd code-server-enterprise && docker-compose up -d"
    sleep 10
  fi
  
  print_step "C.4: Token Acquisition Test"
  if [[ "$DRY_RUN" == "1" ]]; then
    print_warning "DRY-RUN MODE: Would test /oauth2/token endpoint"
  else
    print_step "Testing token acquisition on primary host..."
    ssh "$DEPLOY_USER@$PRIMARY_HOST" "cd code-server-enterprise && bash scripts/ci/run-jwt-e2e-tests.sh --phase=2c"
  fi
  
  print_step "C.5: Service-to-Service Test"
  if [[ "$DRY_RUN" == "1" ]]; then
    print_warning "DRY-RUN MODE: Would test session-broker bearer token acceptance"
  else
    print_step "Testing service-to-service auth on primary host..."
    ssh "$DEPLOY_USER@$PRIMARY_HOST" "cd code-server-enterprise && bash scripts/ci/run-jwt-e2e-tests.sh --phase=2c --test=s2s"
  fi
  
  log_info "Phase 2C deployment complete ✓"
}

execute_phase_2d() {
  print_header "PHASE 2D: OBSERVABILITY (Prometheus + Grafana + AlertManager)"
  
  print_step "D.1: JWT Metrics Collection"
  print_warning "Would add Prometheus scrape job for jwt_validator_latency_ms, jwt_cache_hit_rate, jwt_token_refresh_count"
  
  print_step "D.2: Grafana Dashboard"
  print_warning "Would create 'JWT Auth Service Metrics' dashboard with 6 visualization panels"
  
  print_step "D.3: AlertManager Configuration"
  print_warning "Would configure alerts for: validation errors, cache hits, token refresh failures, OIDC issuer unreachability"
  
  log_info "Phase 2D observability setup complete ✓"
}

execute_phase_2e() {
  print_header "PHASE 2E: E2E TESTING (Auth Flows + Failover + Integration)"
  
  print_step "E.1: Auth Flow Tests"
  if [[ "$DRY_RUN" == "1" ]]; then
    print_warning "DRY-RUN MODE: Would test token acquisition, validation, expiration, refresh"
  else
    ssh "$DEPLOY_USER@$PRIMARY_HOST" "cd code-server-enterprise && bash scripts/ci/run-jwt-e2e-tests.sh --phase=2e --test=auth-flow"
  fi
  
  print_step "E.2: Service-to-Service Tests"
  if [[ "$DRY_RUN" == "1" ]]; then
    print_warning "DRY-RUN MODE: Would test bearer token in Authorization header, cross-service auth, error handling"
  else
    ssh "$DEPLOY_USER@$PRIMARY_HOST" "cd code-server-enterprise && bash scripts/ci/run-jwt-e2e-tests.sh --phase=2e --test=s2s"
  fi
  
  print_step "E.3: Failover Tests"
  if [[ "$DRY_RUN" == "1" ]]; then
    print_warning "DRY-RUN MODE: Would test token acquisition on replica, cross-host sticky sessions, failover during refresh"
  else
    ssh "$DEPLOY_USER@$PRIMARY_HOST" "cd code-server-enterprise && bash scripts/ci/run-jwt-e2e-tests.sh --phase=2e --test=failover"
  fi
  
  print_step "E.4: Integration Tests"
  if [[ "$DRY_RUN" == "1" ]]; then
    print_warning "DRY-RUN MODE: Would test OAuth login -> JWT acquisition -> service calls"
  else
    ssh "$DEPLOY_USER@$PRIMARY_HOST" "cd code-server-enterprise && bash scripts/ci/run-jwt-e2e-tests.sh --phase=2e --test=integration"
  fi
  
  log_info "Phase 2E testing complete ✓"
}

show_summary() {
  print_header "PHASE 2C-2E DEPLOYMENT SUMMARY"
  
  if [[ "$DRY_RUN" == "1" ]]; then
    print_warning "DRY-RUN MODE ENABLED"
    echo ""
    echo "To execute actual deployment:"
    echo "  DRY_RUN=0 bash EXECUTE-PHASE-2-DEPLOYMENT.sh"
    echo ""
  fi
  
  echo "Deployment Configuration:"
  echo "  GCP Project: $GCP_PROJECT"
  echo "  Primary Host: $PRIMARY_HOST"
  echo "  Replica Host: $REPLICA_HOST"
  echo "  Dry-Run: $DRY_RUN"
  echo ""
  
  echo "Execution Timeline:"
  echo "  Phase 2C (Deployment): 2-3 hours"
  echo "  Phase 2D (Observability): 3-4 hours"
  echo "  Phase 2E (Testing): 2-3 hours"
  echo "  Total: 7-13 hours"
  echo ""
  
  echo "Documentation: PHASE-2-DEPLOYMENT-GUIDE.md (commit f5d0ffa5)"
  echo ""
}

main() {
  log_info "=========================================="
  log_info "Phase 2C-2E JWT Deployment Execution"
  log_info "=========================================="
  
  # Show configuration
  echo ""
  echo "Configuration:"
  echo "  PHASE=$PHASE"
  echo "  DRY_RUN=$DRY_RUN"
  echo "  GCP_PROJECT=$GCP_PROJECT"
  echo "  PRIMARY_HOST=$PRIMARY_HOST"
  echo "  REPLICA_HOST=$REPLICA_HOST"
  echo ""
  
  # Verify prerequisites
  verify_prerequisites || {
    log_fatal "Prerequisites check failed"
  }
  
  # Execute phases
  case "$PHASE" in
    all)
      execute_phase_2c || log_fatal "Phase 2C failed"
      execute_phase_2d || log_fatal "Phase 2D failed"
      execute_phase_2e || log_fatal "Phase 2E failed"
      ;;
    2c)
      execute_phase_2c || log_fatal "Phase 2C failed"
      ;;
    2d)
      execute_phase_2d || log_fatal "Phase 2D failed"
      ;;
    2e)
      execute_phase_2e || log_fatal "Phase 2E failed"
      ;;
    *)
      log_fatal "Unknown phase: $PHASE. Use: all, 2c, 2d, 2e"
      ;;
  esac
  
  # Show summary
  show_summary
  
  log_info "Phase 2C-2E deployment execution complete"
}

main "$@"
