#!/usr/bin/env bash
# deploy-iac.sh
# Deterministic Terraform + compose deployment workflow.
#
# Default mode: remote deployment to primary host (192.168.168.31)
# Local mode: run Terraform in local repository checkout.
#
# Usage:
#   bash scripts/deploy/deploy-iac.sh
#   bash scripts/deploy/deploy-iac.sh --plan-only
#   bash scripts/deploy/deploy-iac.sh --local
#   bash scripts/deploy/deploy-iac.sh --host 192.168.168.31 --user akushnir

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_DIR/scripts/_common/init.sh" || {
  echo "FATAL: Cannot source scripts/_common/init.sh"
  exit 1
}

TARGET_HOST="${DEPLOY_HOST}"
TARGET_USER="${DEPLOY_USER}"
TARGET_PORT="22"
TARGET_KEY="${DEPLOY_SSH_KEY:-}"
PLAN_ONLY=0
LOCAL_MODE=0

usage() {
  cat <<'EOF'
Usage: deploy-iac.sh [options]

Options:
  --local             Run Terraform locally instead of remote host
  --plan-only         Run terraform plan only (no apply)
  --host <ip>         Override remote host
  --user <name>       Override remote user
  --port <port>       Override SSH port
  --key <path>        Override SSH key path
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      LOCAL_MODE=1
      shift
      ;;
    --plan-only)
      PLAN_ONLY=1
      shift
      ;;
    --host)
      TARGET_HOST="$2"
      shift 2
      ;;
    --user)
      TARGET_USER="$2"
      shift 2
      ;;
    --port)
      TARGET_PORT="$2"
      shift 2
      ;;
    --key)
      TARGET_KEY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

run_local() {
  log_section "Local IaC Deployment"
  cd "$PROJECT_DIR/terraform"

  log_info "Running terraform init"
  terraform init -upgrade

  log_info "Running terraform validate"
  terraform validate

  log_info "Running terraform plan"
  terraform plan -out=tfplan

  if [[ "$PLAN_ONLY" -eq 1 ]]; then
    log_success "Plan-only mode complete"
    return 0
  fi

  log_info "Running terraform apply"
  terraform apply -auto-approve tfplan
  rm -f tfplan

  log_success "Local IaC deployment complete"
}

run_remote() {
  log_section "Remote IaC Deployment"
  log_info "Target: ${TARGET_USER}@${TARGET_HOST}:${TARGET_PORT}"

  local ssh_opts="$SSH_OPTS"
  if [[ -n "$TARGET_KEY" ]]; then
    ssh_opts="$ssh_opts -i $TARGET_KEY"
  fi

  # shellcheck disable=SC2086
  if ! ssh $ssh_opts -p "$TARGET_PORT" "$TARGET_USER@$TARGET_HOST" "echo remote-ok" >/dev/null 2>&1; then
    log_fatal "Cannot reach ${TARGET_USER}@${TARGET_HOST} with key-only SSH"
  fi

  local remote_cmd
  if [[ "$PLAN_ONLY" -eq 1 ]]; then
    remote_cmd=$(cat <<'EOF'
set -euo pipefail
cd "$DEPLOY_DIR/terraform"
terraform init -upgrade
terraform validate
terraform plan
EOF
)
  else
    remote_cmd=$(cat <<'EOF'
set -euo pipefail
cd "$DEPLOY_DIR/terraform"
terraform init -upgrade
terraform validate
terraform plan -out=tfplan
terraform apply -auto-approve tfplan
rm -f tfplan
cd "$DEPLOY_DIR"
docker compose up -d
docker compose ps
EOF
)
  fi

  # shellcheck disable=SC2086
  ssh $ssh_opts -p "$TARGET_PORT" "$TARGET_USER@$TARGET_HOST" \
    "DEPLOY_DIR='$DEPLOY_DIR' bash -s" <<<"$remote_cmd"

  if [[ "$PLAN_ONLY" -eq 1 ]]; then
    log_success "Remote plan-only run complete"
  else
    log_success "Remote IaC deployment complete"
  fi
}

main() {
  if [[ "$LOCAL_MODE" -eq 1 ]]; then
    run_local
  else
    run_remote
  fi
}

main "$@"
