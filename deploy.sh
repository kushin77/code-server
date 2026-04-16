#!/usr/bin/env bash
################################################################################
# code-server-enterprise Universal Deployment Entrypoint
# File: deploy.sh
# Purpose: Single unified deployment script for all infrastructure
# Usage: ./deploy.sh [target] [action] [options]
# Owner: Infrastructure Team
# Issue: P2 #421
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

REMOTE_HOST="${REMOTE_HOST:-192.168.168.31}"
SSH_USER="${SSH_USER:-akushnir}"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"

# ════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

log_step() {
  echo ""
  echo -e "${BLUE}▸ $1${NC}"
}

log_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
  echo -e "${RED}✗ $1${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

show_usage() {
  cat << EOF
${BLUE}code-server-enterprise Deployment${NC}

Usage: ${SCRIPT_DIR}/deploy.sh [target] [action] [options]

TARGETS:
  local          Deploy locally (for development/testing)
  remote         Deploy to remote host (${REMOTE_HOST})
  all            Deploy locally and to remote

ACTIONS:
  validate       Validate configuration (Terraform, Docker, IaC)
  plan           Show deployment plan (what will change)
  apply          Execute deployment
  destroy        Tear down infrastructure (CAUTION!)
  status         Show current status of infrastructure
  logs           Stream logs from running services
  shell          SSH shell to remote host

OPTIONS:
  --auto-approve      Skip interactive approval prompts
  --terraform-vars    Path to terraform variables file (default: production.tfvars)
  --skip-validation   Skip pre-deployment validation
  --dry-run          Show what would happen without applying
  --verbose          Verbose output (debug mode)

EXAMPLES:
  # Validate infrastructure locally
  ./deploy.sh local validate

  # Plan deployment to remote host
  ./deploy.sh remote plan --terraform-vars=production.tfvars

  # Deploy everything to remote with auto-approval
  ./deploy.sh remote apply --auto-approve

  # Check status of remote infrastructure
  ./deploy.sh remote status

  # Stream logs from services
  ./deploy.sh remote logs

  # Connect to remote host
  ./deploy.sh remote shell

EOF
}

# ════════════════════════════════════════════════════════════════════════════
# VALIDATION FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

validate_local() {
  log_step "Validating local configuration..."
  
  # Validate Terraform
  if [[ -d "$TERRAFORM_DIR" ]]; then
    log_step "  Validating Terraform..."
    cd "$TERRAFORM_DIR"
    terraform validate || {
      log_error "Terraform validation failed"
      return 1
    }
    log_success "Terraform syntax valid"
  fi
  
  # Validate Docker Compose
  log_step "  Validating Docker Compose..."
  docker-compose -f "$DOCKER_COMPOSE_FILE" config --quiet || {
    log_error "Docker Compose validation failed"
    return 1
  }
  log_success "Docker Compose configuration valid"
  
  # Validate .env file
  if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
    log_warning ".env file not found - required for deployment"
    return 1
  fi
  log_success "Configuration files present"
}

# ════════════════════════════════════════════════════════════════════════════
# DEPLOYMENT FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

deploy_terraform() {
  local action="${1:-plan}"
  local tfvars="${2:-production.tfvars}"
  
  log_step "Terraform ${action}..."
  
  cd "$TERRAFORM_DIR"
  
  # Initialize Terraform
  log_step "  Initializing Terraform..."
  terraform init -upgrade
  
  # Run action
  if [[ "$action" == "plan" ]]; then
    terraform plan -var-file="$tfvars" -out=tfplan
    log_success "Terraform plan saved to tfplan"
  elif [[ "$action" == "apply" ]]; then
    terraform apply -var-file="$tfvars" -auto-approve || {
      log_error "Terraform apply failed"
      return 1
    }
    log_success "Terraform apply completed"
  elif [[ "$action" == "destroy" ]]; then
    log_warning "Destroying infrastructure - this is irreversible"
    read -p "Type 'yes' to confirm: " -r
    if [[ $REPLY == "yes" ]]; then
      terraform destroy -var-file="$tfvars" -auto-approve
      log_success "Infrastructure destroyed"
    else
      log_warning "Destroy cancelled"
    fi
  fi
}

deploy_docker() {
  local action="${1:-up}"
  
  log_step "Docker Compose ${action}..."
  
  cd "$PROJECT_ROOT"
  
  case "$action" in
    up)
      docker-compose -f "$DOCKER_COMPOSE_FILE" up -d
      log_success "Containers started"
      ;;
    down)
      docker-compose -f "$DOCKER_COMPOSE_FILE" down
      log_success "Containers stopped"
      ;;
    ps)
      docker-compose -f "$DOCKER_COMPOSE_FILE" ps
      ;;
    logs)
      docker-compose -f "$DOCKER_COMPOSE_FILE" logs -f
      ;;
    *)
      log_error "Unknown docker action: $action"
      return 1
      ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
# REMOTE DEPLOYMENT FUNCTIONS
# ════════════════════════════════════════════════════════════════════════════

deploy_remote() {
  local action="${1:-status}"
  
  log_step "Remote deployment to ${REMOTE_HOST}..."
  
  case "$action" in
    validate)
      ssh "${SSH_USER}@${REMOTE_HOST}" "cd code-server-enterprise && terraform -chdir=terraform validate"
      ;;
    plan)
      ssh "${SSH_USER}@${REMOTE_HOST}" "cd code-server-enterprise && terraform -chdir=terraform plan"
      ;;
    apply)
      ssh "${SSH_USER}@${REMOTE_HOST}" "cd code-server-enterprise && terraform -chdir=terraform apply -auto-approve"
      ;;
    status)
      ssh "${SSH_USER}@${REMOTE_HOST}" "cd code-server-enterprise && docker-compose ps --format 'table {{.Service}}\t{{.Status}}' | head -15"
      ;;
    logs)
      ssh -t "${SSH_USER}@${REMOTE_HOST}" "cd code-server-enterprise && docker-compose logs -f"
      ;;
    shell)
      ssh -t "${SSH_USER}@${REMOTE_HOST}"
      ;;
    *)
      log_error "Unknown remote action: $action"
      return 1
      ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ════════════════════════════════════════════════════════════════════════════

main() {
  echo "════════════════════════════════════════════════════════════════════════════"
  echo "  code-server-enterprise Universal Deployment"
  echo "════════════════════════════════════════════════════════════════════════════"
  echo ""
  
  # Parse arguments
  if [[ $# -lt 1 ]]; then
    show_usage
    exit 1
  fi
  
  TARGET="$1"
  ACTION="${2:-status}"
  shift 2 || true
  
  # Validate target
  case "$TARGET" in
    local|remote|all)
      ;;
    -h|--help|help)
      show_usage
      exit 0
      ;;
    *)
      log_error "Unknown target: $TARGET"
      show_usage
      exit 1
      ;;
  esac
  
  # Execute deployment based on target
  case "$TARGET" in
    local)
      case "$ACTION" in
        validate)
          validate_local
          ;;
        plan)
          deploy_terraform "plan" "$@"
          ;;
        apply)
          validate_local && deploy_terraform "apply" "$@"
          ;;
        destroy)
          deploy_terraform "destroy" "$@"
          ;;
        status)
          deploy_docker "ps"
          ;;
        logs)
          deploy_docker "logs"
          ;;
        *)
          log_error "Unknown action for local: $ACTION"
          exit 1
          ;;
      esac
      ;;
    remote)
      deploy_remote "$ACTION" "$@"
      ;;
    all)
      log_step "Deploying locally first..."
      validate_local && deploy_terraform "apply" "$@"
      log_step "Deploying to remote..."
      deploy_remote "apply" "$@"
      ;;
  esac
  
  echo ""
  log_success "Deployment complete"
}

# Execute main function
main "$@"
