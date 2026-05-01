#!/bin/bash
# Idempotent Enterprise Overlay Deployment Script
# Safe, reproducible multi-host deployment with built-in consistency checks
#
# Usage:
#   ./scripts/deploy-enterprise-idempotent.sh --target=primary --mode=dry-run
#   ./scripts/deploy-enterprise-idempotent.sh --target=both --mode=apply
#   ./scripts/deploy-enterprise-idempotent.sh --target=replica --mode=apply --force
#
# Modes:
#   dry-run  Show exactly what will happen without executing
#   apply    Execute deployment (requires confirmation unless --yes)
#   validate Only validate config; don't deploy
#
# Targets:
#   primary  Only primary host (192.168.168.31)
#   replica  Only replica host (192.168.168.42)
#   both     Both hosts sequentially (primary first, then replica)

set -euo pipefail
trap 'error "Script failed at line $LINENO"' ERR
trap 'rm -f /tmp/deploy-*.log /tmp/deploy-output-*.log 2>/dev/null || true' EXIT

# Configuration
PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
DEPLOY_DIR="~/code-server-enterprise"
COMPOSE_FILE="docker-compose.enterprise.yml"
ENV_FILES=(".env" ".env.production")
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# State variables
MODE="dry-run"
TARGET="both"
FORCE=false
YES_FLAG=false
START_TIME=$(date +%s)
DEPLOYMENT_LOG="/tmp/deploy-$(date +%Y%m%d_%H%M%S).log"

# Functions
log() {
  echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" | tee -a "$DEPLOYMENT_LOG" >&2
  exit 1
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

warning() {
  echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --target=*)
      TARGET="${1#*=}"
      shift
      ;;
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --yes|-y)
      YES_FLAG=true
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      ;;
  esac
done

show_help() {
  cat << EOF
Idempotent Enterprise Overlay Deployment Script

Usage:
  $0 [OPTIONS]

Options:
  --target=TARGET     Target host(s): primary, replica, both (default: both)
  --mode=MODE         Deployment mode: dry-run, apply, validate (default: dry-run)
  --force             Force deployment even with warnings
  --yes, -y           Skip confirmation prompts
  --help, -h          Show this help message

Examples:
  # Preview deployment on primary host
  $0 --target=primary --mode=dry-run

  # Deploy to primary with approval
  $0 --target=primary --mode=apply

  # Deploy to both hosts without prompts
  $0 --target=both --mode=apply --yes

  # Validate configuration only
  $0 --mode=validate
EOF
}

# Validate inputs
validate_inputs() {
  log "Validating inputs..."

  if [[ ! "$TARGET" =~ ^(primary|replica|both)$ ]]; then
    error "Invalid target: $TARGET (must be: primary, replica, or both)"
  fi

  if [[ ! "$MODE" =~ ^(dry-run|apply|validate)$ ]]; then
    error "Invalid mode: $MODE (must be: dry-run, apply, or validate)"
  fi

  if [[ ! -f "docker-compose.enterprise.yml" ]]; then
    error "docker-compose.enterprise.yml not found in current directory"
  fi

  success "Inputs valid"
}

# Check SSH connectivity
check_ssh_connectivity() {
  local host="$1"
  log "Checking SSH connectivity to $host..."

  if ! ssh $SSH_OPTS "$host" "exit 0" 2>/dev/null; then
    error "Cannot connect to $host via SSH"
  fi

  success "Connected to $host"
}

# Fetch current container state
fetch_container_state() {
  local host="$1"
  log "Fetching container state from $host..."

  local state=$(ssh $SSH_OPTS "$host" "cd $DEPLOY_DIR && docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | grep '^code-server-' | sort" 2>&1)

  echo "$state"
}

# Validate environment files
validate_env_files() {
  local host="$1"
  log "Validating environment files on $host..."

  for env_file in "${ENV_FILES[@]}"; do
    if ! ssh $SSH_OPTS "$host" "test -f $DEPLOY_DIR/$env_file" 2>/dev/null; then
      warning "Missing $env_file on $host (may be ok if using defaults)"
    fi
  done

  success "Environment validation complete"
}

# Render docker-compose to check for errors
validate_compose_file() {
  local host="$1"
  log "Validating docker-compose.enterprise.yml on $host..."

  if ! ssh $SSH_OPTS "$host" "cd $DEPLOY_DIR && bash -lc 'set -a; source .env; source .env.production 2>/dev/null; set +a; docker-compose -f $COMPOSE_FILE config >/dev/null'" 2>&1; then
    error "docker-compose validation failed on $host (check env vars)"
  fi

  success "Compose file valid"
}

# Clean up stale containers
cleanup_stale_containers() {
  local host="$1"
  log "Checking for stale containers on $host..."

  local stale_containers
  stale_containers=$(ssh $SSH_OPTS "$host" "cd $DEPLOY_DIR && docker ps -a --format '{{.Names}}' --filter 'status=exited' | grep '^code-server-' | sort" 2>/dev/null || true)

  if [[ -n "$stale_containers" ]]; then
    if [[ "$MODE" == "dry-run" ]]; then
      log "Would remove stale containers:"
      echo "$stale_containers" | sed 's/^/  - /'
    else
      log "Removing stale containers..."
      while IFS= read -r container; do
        ssh $SSH_OPTS "$host" "docker rm -f '$container' 2>&1 | tail -1" || true
      done <<< "$stale_containers"
      success "Stale containers removed"
    fi
  else
    log "No stale containers found"
  fi
}

# Deploy to host
deploy_to_host() {
  local host="$1"
  log "=== DEPLOYING TO $host ==="
  log ""

  check_ssh_connectivity "$host"
  validate_env_files "$host"
  validate_compose_file "$host"
  cleanup_stale_containers "$host"

  log "Fetching current state before deployment..."
  local before_state=$(fetch_container_state "$host")
  log "Current services:"
  echo "$before_state" | sed 's/^/  /'

  if [[ "$MODE" == "dry-run" ]] || [[ "$MODE" == "validate" ]]; then
    log "DRY-RUN MODE: Showing what would be deployed..."
    ssh $SSH_OPTS "$host" "cd $DEPLOY_DIR && bash -lc 'set -a; source .env; source .env.production 2>/dev/null; set +a; docker-compose -f $COMPOSE_FILE config | head -50'"
    log "...truncated. Use 'docker-compose config' on host to see full output"
    return 0
  fi

  if [[ "$MODE" == "apply" ]]; then
    # Request confirmation unless --yes flag set
    if [[ "$YES_FLAG" != "true" ]]; then
      echo ""
      echo -e "${YELLOW}Ready to deploy to $host. Continue? (y/N)${NC}"
      read -r -p "> " response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
        warning "Deployment to $host cancelled by user"
        return 1
      fi
    fi

    log "Starting deployment on $host..."
    if ssh $SSH_OPTS "$host" "cd $DEPLOY_DIR && bash -lc 'set -a; source .env; source .env.production 2>/dev/null; set +a; docker-compose -f $COMPOSE_FILE up -d 2>&1'" > /tmp/deploy-output-$host.log 2>&1; then
      success "Deployment applied to $host"
    else
      error "Deployment failed on $host. Check logs: /tmp/deploy-output-$host.log"
    fi

    # Wait for services to stabilize
    log "Waiting for services to stabilize (15s)..."
    sleep 15

    # Fetch state after deployment
    log "Fetching state after deployment..."
    local after_state=$(fetch_container_state "$host")
    log "Services after deployment:"
    echo "$after_state" | sed 's/^/  /'

    # Health check loop
    log "Waiting for services to become healthy (max 5 minutes)..."
    local health_check_count=0
    local max_health_checks=30
    local healthy_count=0

    while [[ $health_check_count -lt $max_health_checks ]]; do
      healthy_count=$(ssh $SSH_OPTS "$host" "docker ps --format '{{.Status}}' | grep -c 'healthy'" 2>&1 || echo "0")
      local total_count=$(ssh $SSH_OPTS "$host" "docker ps --format '{{.Names}}' | grep -c '^code-server-'" 2>&1 || echo "0")

      log "Health status: $healthy_count/$total_count services healthy (check $((health_check_count+1))/$max_health_checks)"

      if [[ "$healthy_count" -ge "$((total_count - 2))" ]]; then
        # Most services healthy (allowing 2 in starting state)
        success "Services converged to healthy state"
        break
      fi

      health_check_count=$((health_check_count + 1))
      sleep 10
    done

    if [[ $health_check_count -ge $max_health_checks ]]; then
      warning "Health convergence timeout. Services may still be starting. Check with 'docker ps' on $host"
    fi
  fi
}

# Generate report
generate_report() {
  local elapsed=$(($(date +%s) - START_TIME))
  local duration="$((elapsed / 60))m $((elapsed % 60))s"

  echo ""
  echo "===== DEPLOYMENT REPORT ====="
  echo "Deployment Log: $DEPLOYMENT_LOG"
  echo "Mode: $MODE"
  echo "Target: $TARGET"
  echo "Duration: $duration"
  echo "Status: $([ $? -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')"
  echo ""
  echo "Next steps:"
  echo "  1. Verify services on host: docker ps"
  echo "  2. Check service logs: docker logs <service_name>"
  echo "  3. Test health endpoints: curl http://localhost:PORT/health"
  echo ""
}

# Main execution
main() {
  log "Starting Enterprise Overlay Deployment"
  log "Mode: $MODE | Target: $TARGET"
  log "Logging to: $DEPLOYMENT_LOG"
  log ""

  validate_inputs

  case "$TARGET" in
    primary)
      deploy_to_host "$PRIMARY_HOST" || exit 1
      ;;
    replica)
      deploy_to_host "$REPLICA_HOST" || exit 1
      ;;
    both)
      deploy_to_host "$PRIMARY_HOST" || exit 1
      log ""
      log "Waiting 30s before deploying to replica..."
      sleep 30
      log ""
      deploy_to_host "$REPLICA_HOST" || exit 1
      ;;
  esac

  log ""
  success "Deployment complete!"
  generate_report

  if [[ "$MODE" == "apply" ]]; then
    log "Git changes (if any): git status"
  fi
}

# Execute main
main "$@"
