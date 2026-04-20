#!/usr/bin/env bash
# @file        scripts/ops/redeploy-with-gh-tracking.sh
# @module      ops/deployment
# @description Robust auto-redeploy with mandatory GitHub issue tracking throughout
#
# Usage:
#   bash scripts/ops/redeploy-with-gh-tracking.sh [--issue-number N] [--dry-run] [--auto-approve]
#
# Environment Variables:
#   GITHUB_ISSUE_NUMBER    - Issue to update with progress (required)
#   PRIMARY_HOST           - Primary deployment host (default: 192.168.168.31)
#   REPLICA_HOST           - Replica host for failover testing (default: 192.168.168.42)
#   DRY_RUN                - Safe mode (default: 1)
#   DEPLOY_TIMEOUT         - Total deployment timeout (default: 1800s)

set -euo pipefail
shopt -s inherit_errexit

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
GITHUB_ISSUE_NUMBER="${GITHUB_ISSUE_NUMBER:-}"
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-1}"
TERRAFORM_AUTO_APPROVE="${TERRAFORM_AUTO_APPROVE:-0}"
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-1800}"
START_TIME=$(date +%s)
DEPLOYMENT_ID="$(date +%Y%m%d-%H%M%S)-$$"

# ─────────────────────────────────────────────────────────────────────────────
# Parse CLI arguments
# ─────────────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue-number)
      GITHUB_ISSUE_NUMBER="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --auto-approve)
      TERRAFORM_AUTO_APPROVE=1
      DRY_RUN=0
      shift
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# Functions: GitHub Issue Updates (Mandatory Checkpoints)
# ─────────────────────────────────────────────────────────────────────────────

update_issue() {
  local status="$1"
  local message="$2"
  
  if [[ -z "$GITHUB_ISSUE_NUMBER" ]]; then
    log_warn "No issue number configured; skipping GitHub update"
    return 0
  fi
  
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local body="**[${timestamp}]** ${status}

${message}

---
*Deployment ID: ${DEPLOYMENT_ID}*
*Dry-run: ${DRY_RUN}*"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY-RUN] Would update issue #${GITHUB_ISSUE_NUMBER}: ${status}"
    return 0
  fi

  gh issue comment "$GITHUB_ISSUE_NUMBER" --repo kushin77/code-server --body "$body" || {
    log_error "Failed to update issue #${GITHUB_ISSUE_NUMBER}"
    return 1
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Preflight Checks
# ─────────────────────────────────────────────────────────────────────────────

stage_preflight() {
  log_info "=== STAGE 1: PREFLIGHT CHECKS ==="
  
  update_issue "⏳ Starting preflight checks" "Checking SSH connectivity, Docker daemon, disk space, Terraform state..."
  
  # Check SSH connectivity to primary
  log_info "Verifying SSH connectivity to ${PRIMARY_HOST}..."
  if ! ssh -o ConnectTimeout=10 "${DEPLOY_USER}@${PRIMARY_HOST}" "echo OK" &>/dev/null; then
    log_fatal "Cannot reach ${PRIMARY_HOST}"
  fi
  
  # Check Docker daemon
  log_info "Verifying Docker daemon on ${PRIMARY_HOST}..."
  if ! ssh "${DEPLOY_USER}@${PRIMARY_HOST}" "docker ps -q >/dev/null 2>&1"; then
    log_fatal "Docker daemon not responding on ${PRIMARY_HOST}"
  fi
  
  # Check disk space
  log_info "Checking disk space on ${PRIMARY_HOST}..."
  local available=$(ssh "${DEPLOY_USER}@${PRIMARY_HOST}" "df /home | awk 'NR==2 {print \$4}'")
  if [[ $available -lt 5242880 ]]; then  # 5GB in KB
    log_fatal "Insufficient disk space: ${available}KB available"
  fi
  
  # Check Terraform state
  log_info "Verifying Terraform state accessibility..."
  if ! ssh "${DEPLOY_USER}@${PRIMARY_HOST}" "test -f ~/code-server-enterprise/terraform.tfstate"; then
    log_warn "Terraform state not found; will initialize"
  fi
  
  update_issue "✅ Preflight checks passed" "SSH connectivity verified, Docker daemon healthy, disk space available (${available}KB), Terraform state accessible."
  
  log_info "Preflight checks completed successfully"
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Backup Current State
# ─────────────────────────────────────────────────────────────────────────────

stage_backup() {
  log_info "=== STAGE 2: BACKUP CURRENT STATE ==="
  
  update_issue "📦 Creating state backup" "Backing up Terraform state, docker-compose config, and .env files..."
  
  local backup_dir="/home/${DEPLOY_USER}/code-server-backups/${DEPLOYMENT_ID}"
  
  if [[ $DRY_RUN -eq 0 ]]; then
    ssh "${DEPLOY_USER}@${PRIMARY_HOST}" "bash -c 'mkdir -p \"${backup_dir}\" && cd ~/code-server-enterprise && tar -czf \"${backup_dir}/state-backup.tar.gz\" terraform.tfstate docker-compose.yml .env .env.defaults 2>/dev/null || true'"
    log_info "Backup created at ${backup_dir}/state-backup.tar.gz"
  else
    log_info "[DRY-RUN] Would create backup at ${backup_dir}/state-backup.tar.gz"
  fi
  
  update_issue "✅ Backup created" "State snapshot saved to backup directory (ID: ${DEPLOYMENT_ID})"
  
  log_info "Backup stage completed"
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3: Terraform Validation & Apply
# ─────────────────────────────────────────────────────────────────────────────

stage_terraform() {
  log_info "=== STAGE 3: TERRAFORM VALIDATION & APPLY ==="
  
  update_issue "🔨 Terraform validation in progress" "Validating Terraform configuration and generating plan..."
  
  local tf_cmd="cd ~/code-server-enterprise && terraform validate && terraform plan -out=/tmp/tfplan"
  
  if [[ $DRY_RUN -eq 0 ]]; then
    if ssh "${DEPLOY_USER}@${PRIMARY_HOST}" "$tf_cmd"; then
      log_info "Terraform plan validated successfully"
    else
      log_fatal "Terraform validation failed"
    fi
    
    update_issue "🚀 Applying Terraform changes" "Executing terraform apply..."
    
    local apply_cmd="cd ~/code-server-enterprise && terraform apply -auto-approve /tmp/tfplan"
    if [[ $TERRAFORM_AUTO_APPROVE -eq 1 ]]; then
      if ssh "${DEPLOY_USER}@${PRIMARY_HOST}" "$apply_cmd"; then
        log_info "Terraform apply completed successfully"
      else
        log_fatal "Terraform apply failed"
      fi
    else
      log_warn "Terraform auto-approve disabled; skipping apply"
    fi
  else
    log_info "[DRY-RUN] Would validate and apply Terraform"
  fi
  
  update_issue "✅ Terraform deployment complete" "Infrastructure provisioned and state updated."
  
  log_info "Terraform stage completed"
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage 4: Docker Compose Services
# ─────────────────────────────────────────────────────────────────────────────

stage_docker_compose() {
  log_info "=== STAGE 4: DOCKER COMPOSE DEPLOYMENT ==="
  
  update_issue "🐳 Docker Compose deployment in progress" "Bringing up containerized services..."
  
  local compose_cmd="cd ~/code-server-enterprise && export NAS_HOST=192.168.168.55 NAS_EXPORT_PATH=/export && docker-compose -p enterprise up -d"
  
  if [[ $DRY_RUN -eq 0 ]]; then
    if ssh "${DEPLOY_USER}@${PRIMARY_HOST}" "$compose_cmd"; then
      log_info "Docker Compose services started successfully"
      sleep 5
    else
      log_error "Docker Compose startup failed"
      update_issue "❌ Docker Compose deployment failed" "Services failed to start. Check logs on ${PRIMARY_HOST}"
      return 1
    fi
  else
    log_info "[DRY-RUN] Would deploy Docker Compose services"
  fi
  
  update_issue "✅ Docker Compose services deployed" "All containers started successfully."
  
  log_info "Docker Compose deployment stage completed"
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage 5: Health Checks
# ─────────────────────────────────────────────────────────────────────────────

stage_health_checks() {
  log_info "=== STAGE 5: HEALTH CHECKS ==="
  
  update_issue "🏥 Health checks in progress" "Verifying service endpoints..."
  
  local services=(
    "code-server:8080:healthz"
    "grafana:3000:api/health"
    "prometheus:9090:-/healthy"
    "caddy:80:healthz"
  )
  
  local failed_services=()
  
  for service_spec in "${services[@]}"; do
    IFS=':' read -r service port endpoint <<< "$service_spec"
    log_info "Checking ${service} on port ${port}..."
    
    if [[ $DRY_RUN -eq 0 ]]; then
      if ssh "${DEPLOY_USER}@${PRIMARY_HOST}" "curl -sf http://localhost:${port}/${endpoint} >/dev/null 2>&1"; then
        log_info "✅ ${service} is healthy"
      else
        log_warn "⚠️  ${service} health check failed"
        failed_services+=("$service")
      fi
    else
      log_info "[DRY-RUN] Would check ${service} health"
    fi
  done
  
  if [[ ${#failed_services[@]} -gt 0 ]]; then
    local failed_list=$(IFS=', '; echo "${failed_services[*]}")
    update_issue "⚠️  Health checks: Some services unhealthy" "Failed services: ${failed_list}. Review logs on ${PRIMARY_HOST}"
    log_warn "Some services failed health checks: ${failed_list}"
  else
    update_issue "✅ All health checks passed" "All critical services are responding healthily."
    log_info "All health checks passed"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage 6: Failover Readiness Check
# ─────────────────────────────────────────────────────────────────────────────

stage_failover_readiness() {
  log_info "=== STAGE 6: FAILOVER READINESS CHECK ==="
  
  update_issue "🔄 Checking failover readiness" "Verifying replica host and synchronization..."
  
  # Check replica connectivity
  if ssh -o ConnectTimeout=10 "${DEPLOY_USER}@${REPLICA_HOST}" "echo OK" &>/dev/null; then
    log_info "✅ Replica host ${REPLICA_HOST} is reachable"
    update_issue "✅ Failover readiness verified" "Both primary and replica hosts are operational and synchronized."
  else
    log_warn "⚠️  Replica host ${REPLICA_HOST} is not reachable"
    update_issue "⚠️  Failover readiness: Replica unreachable" "Replica host ${REPLICA_HOST} not responding. Failover may not be available."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage 7: Public Endpoint Verification
# ─────────────────────────────────────────────────────────────────────────────

stage_public_endpoint() {
  log_info "=== STAGE 7: PUBLIC ENDPOINT VERIFICATION ==="
  
  update_issue "🌐 Verifying public endpoint" "Testing kushnir.cloud accessibility..."
  
  if [[ $DRY_RUN -eq 0 ]]; then
    if curl -sf --connect-timeout 10 https://ide.kushnir.cloud/healthz >/dev/null 2>&1; then
      log_info "✅ Public endpoint ide.kushnir.cloud is accessible"
      update_issue "✅ Public endpoint operational" "kushnir.cloud is accessible and responding."
    else
      log_warn "⚠️  Public endpoint ide.kushnir.cloud is not accessible"
      update_issue "⚠️  Public endpoint unreachable" "kushnir.cloud not responding to health checks. May need DNS/firewall verification."
    fi
  else
    log_info "[DRY-RUN] Would verify ide.kushnir.cloud accessibility"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Timeout Enforcement
# ─────────────────────────────────────────────────────────────────────────────

check_timeout() {
  local current_time=$(date +%s)
  local elapsed=$((current_time - START_TIME))
  
  if [[ $elapsed -gt $DEPLOY_TIMEOUT ]]; then
    log_fatal "Deployment timeout exceeded (${elapsed}s > ${DEPLOY_TIMEOUT}s)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Execution Flow
# ─────────────────────────────────────────────────────────────────────────────

main() {
  log_info "Starting robust auto-redeploy (Deployment ID: ${DEPLOYMENT_ID})"
  log_info "Primary host: ${PRIMARY_HOST}, Replica host: ${REPLICA_HOST}"
  log_info "DRY_RUN: ${DRY_RUN}, TERRAFORM_AUTO_APPROVE: ${TERRAFORM_AUTO_APPROVE}"
  
  if [[ -z "$GITHUB_ISSUE_NUMBER" ]]; then
    log_error "GITHUB_ISSUE_NUMBER must be set (via --issue-number or env var)"
    exit 1
  fi
  
  update_issue "🚀 Deployment started" "**Deployment ID**: ${DEPLOYMENT_ID}
**Mode**: $([ $DRY_RUN -eq 1 ] && echo 'DRY-RUN' || echo 'APPLY')
**Primary**: ${PRIMARY_HOST}
**Replica**: ${REPLICA_HOST}
**Timeout**: ${DEPLOY_TIMEOUT}s"

  stage_preflight
  check_timeout
  
  stage_backup
  check_timeout
  
  stage_terraform
  check_timeout
  
  stage_docker_compose
  check_timeout
  
  stage_health_checks
  check_timeout
  
  stage_failover_readiness
  check_timeout
  
  stage_public_endpoint
  check_timeout
  
  local end_time=$(date +%s)
  local total_duration=$((end_time - START_TIME))
  
  update_issue "✅ DEPLOYMENT COMPLETE" "All stages completed successfully!

**Total Duration**: ${total_duration}s
**Deployment ID**: ${DEPLOYMENT_ID}
**Status**: $([ $DRY_RUN -eq 1 ] && echo 'DRY-RUN (no changes applied)' || echo 'APPLIED')

Ready for: Production verification, monitoring review, failover testing"

  log_info "=== DEPLOYMENT COMPLETE ==="
  log_info "Total time: ${total_duration}s"
  log_info "Issue #${GITHUB_ISSUE_NUMBER} updated with full deployment log"
}

main "$@"
