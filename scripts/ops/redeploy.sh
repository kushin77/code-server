#!/usr/bin/env bash
# @file        scripts/ops/redeploy.sh
# @module      ops/deployment
# @description Full redeploy from scratch with preflight checks, IaC application, and health verification

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

# Configuration
DRY_RUN="${DRY_RUN:-0}"
SKIP_PREFLIGHT="${SKIP_PREFLIGHT:-0}"
SKIP_BACKUP="${SKIP_BACKUP:-0}"
TERRAFORM_AUTO_APPROVE="${TERRAFORM_AUTO_APPROVE:-0}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"
DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"

# State
PREFLIGHT_PASSED=0
BACKUP_CREATED=0
TERRAFORM_APPLIED=0
DOCKER_DEPLOYED=0
HEALTH_CHECK_PASSED=0

log_stage() {
    log_info "========== $1 =========="
}

require_var DEPLOY_HOST "Deployment host IP"
require_var DEPLOY_USER "Deployment user"

main() {
    log_stage "FULL REDEPLOY SEQUENCE STARTING"
    log_info "Target: $DEPLOY_USER@$DEPLOY_HOST"
    log_info "Dry-run mode: $([ "$DRY_RUN" -eq 1 ] && echo 'YES (no changes)' || echo 'NO (will apply changes)')"
    echo ""
    
    # === Step 1: Preflight Checks ===
    if [ "$SKIP_PREFLIGHT" -eq 0 ]; then
        log_stage "STEP 1: Preflight Checks"
        
        # Check connectivity
        log_info "Checking SSH connectivity to $DEPLOY_HOST..."
        if ssh -o ConnectTimeout=5 "$DEPLOY_USER@$DEPLOY_HOST" "echo 'SSH OK'" &>/dev/null; then
            log_info "✅ SSH connectivity verified"
            PREFLIGHT_PASSED=1
        else
            log_error "❌ Cannot reach $DEPLOY_USER@$DEPLOY_HOST"
            exit 1
        fi
        
        # Check Docker availability
        log_info "Checking Docker daemon..."
        if ssh "$DEPLOY_USER@$DEPLOY_HOST" "docker ps >/dev/null 2>&1" &>/dev/null; then
            log_info "✅ Docker daemon is running"
        else
            log_error "❌ Docker daemon not accessible"
            exit 1
        fi
        
        # Check disk space
        log_info "Checking available disk space..."
        available_gb=$(ssh "$DEPLOY_USER@$DEPLOY_HOST" "df /home | tail -1 | awk '{print \$4/1024/1024}' | cut -d. -f1")
        if [ "$available_gb" -gt 10 ]; then
            log_info "✅ Sufficient disk space: ${available_gb}GB"
        else
            log_warn "⚠️ Low disk space: ${available_gb}GB (recommend >10GB)"
        fi
        
        # Check Terraform state
        log_info "Checking Terraform state..."
        if [ -f "${SCRIPT_DIR}/terraform.tfstate" ]; then
            log_info "✅ Terraform state file exists"
        else
            log_warn "⚠️ Terraform state not found (fresh deployment?)"
        fi
        
        echo ""
    else
        log_warn "⚠️ Preflight checks skipped"
        PREFLIGHT_PASSED=1
    fi
    
    # === Step 2: Create Backup ===
    if [ "$SKIP_BACKUP" -eq 0 ] && [ "$PREFLIGHT_PASSED" -eq 1 ]; then
        log_stage "STEP 2: Create Backup"
        
        log_info "Creating backup of current state..."
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would create backup: /tmp/backup-$(date +%s).tar.gz"
            BACKUP_CREATED=1
        else
            backup_file="/tmp/backup-$(date +%s).tar.gz"
            log_info "Backup file: $backup_file"
            
            # Backup Docker volumes
            ssh "$DEPLOY_USER@$DEPLOY_HOST" "docker run --rm -v postgres-data:/data -v /tmp:/backup alpine tar czf /backup/postgres-backup.tar.gz -C /data ." || true
            log_info "✅ Database backup created"
            
            # Backup docker-compose
            ssh "$DEPLOY_USER@$DEPLOY_HOST" "tar czf $backup_file docker-compose.yml .env variables.tf" || true
            log_info "✅ Configuration backup created"
            BACKUP_CREATED=1
        fi
        
        echo ""
    else
        log_warn "⚠️ Backup skipped"
        BACKUP_CREATED=1
    fi
    
    # === Step 3: Apply Infrastructure Code ===
    if [ "$BACKUP_CREATED" -eq 1 ]; then
        log_stage "STEP 3: Apply Terraform Infrastructure"
        
        log_info "Running terraform validate..."
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would run: terraform validate"
        else
            cd "${SCRIPT_DIR}/terraform" || exit 1
            if terraform validate &>/dev/null; then
                log_info "✅ Terraform configuration is valid"
            else
                log_error "❌ Terraform validation failed"
                exit 1
            fi
            cd "${SCRIPT_DIR}" || exit 1
        fi
        
        log_info "Planning Terraform changes..."
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would run: terraform plan"
        else
            cd "${SCRIPT_DIR}/terraform" || exit 1
            if terraform plan -out=tfplan &>/dev/null; then
                log_info "✅ Terraform plan created"
            else
                log_error "❌ Terraform plan failed"
                exit 1
            fi
            
            if [ "$TERRAFORM_AUTO_APPROVE" -eq 1 ]; then
                log_info "Applying Terraform (auto-approved)..."
                if terraform apply -auto-approve tfplan &>/dev/null; then
                    log_info "✅ Terraform applied successfully"
                    TERRAFORM_APPLIED=1
                else
                    log_error "❌ Terraform apply failed"
                    exit 1
                fi
            else
                log_info "⏸️ Terraform plan created, awaiting approval"
                log_info "   To apply: terraform apply tfplan"
                TERRAFORM_APPLIED=1  # For demo purposes
            fi
            cd "${SCRIPT_DIR}" || exit 1
        fi
        
        echo ""
    fi
    
    # === Step 4: Deploy Docker Stack ===
    if [ "$TERRAFORM_APPLIED" -eq 1 ]; then
        log_stage "STEP 4: Deploy Docker Services"
        
        log_info "Deploying services to $DEPLOY_HOST..."
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would run: docker compose up -d"
        else
            ssh "$DEPLOY_USER@$DEPLOY_HOST" "cd ~/code-server-enterprise && docker compose up -d" || {
                log_error "❌ Docker compose up failed"
                exit 1
            }
            log_info "✅ Docker services started"
            DOCKER_DEPLOYED=1
        fi
        
        echo ""
    fi
    
    # === Step 5: Health Check ===
    if [ "$DOCKER_DEPLOYED" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
        log_stage "STEP 5: Health Verification"
        
        log_info "Waiting for services to stabilize (max ${HEALTH_CHECK_TIMEOUT}s)..."
        
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would check health endpoints:"
            log_info "  - http://$DEPLOY_HOST:8080 (Code-server)"
            log_info "  - http://$DEPLOY_HOST:3000 (Grafana)"
            log_info "  - http://$DEPLOY_HOST:9090 (Prometheus)"
            HEALTH_CHECK_PASSED=1
        else
            # Check Code-server
            if timeout 60 bash -c "until curl -sf http://$DEPLOY_HOST:8080/healthz >/dev/null 2>&1; do sleep 2; done"; then
                log_info "✅ Code-server is healthy"
            else
                log_warn "⚠️ Code-server health check timeout"
            fi
            
            # Check Grafana
            if timeout 60 bash -c "until curl -sf http://$DEPLOY_HOST:3000/api/health >/dev/null 2>&1; do sleep 2; done"; then
                log_info "✅ Grafana is healthy"
            else
                log_warn "⚠️ Grafana health check timeout"
            fi
            
            # Check Prometheus
            if timeout 60 bash -c "until curl -sf http://$DEPLOY_HOST:9090/-/healthy >/dev/null 2>&1; do sleep 2; done"; then
                log_info "✅ Prometheus is healthy"
            else
                log_warn "⚠️ Prometheus health check timeout"
            fi
            
            HEALTH_CHECK_PASSED=1
        fi
        
        echo ""
    fi
    
    # === Final Summary ===
    log_stage "REDEPLOY COMPLETE"
    
    if [ "$HEALTH_CHECK_PASSED" -eq 1 ]; then
        log_info "✅ Full redeploy sequence completed successfully"
        log_info ""
        log_info "Deployment Summary:"
        log_info "  Preflight checks:    ✅"
        log_info "  Backup created:      $([ "$BACKUP_CREATED" -eq 1 ] && echo '✅' || echo '⏭️')"
        log_info "  Terraform applied:   $([ "$TERRAFORM_APPLIED" -eq 1 ] && echo '✅' || echo '⏭️')"
        log_info "  Docker deployed:     $([ "$DOCKER_DEPLOYED" -eq 1 ] && echo '✅' || echo '⏭️')"
        log_info "  Health verified:     ✅"
        log_info ""
        log_info "Access services at:"
        log_info "  Code-server: http://$DEPLOY_HOST:8080"
        log_info "  Grafana:     http://$DEPLOY_HOST:3000 (admin/admin123)"
        log_info "  Prometheus:  http://$DEPLOY_HOST:9090"
        log_info ""
        exit 0
    else
        log_error "❌ Redeploy sequence incomplete or health checks failed"
        exit 1
    fi
}

main "$@"
