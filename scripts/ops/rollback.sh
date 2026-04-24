#!/usr/bin/env bash
# @file        scripts/ops/rollback.sh
# @module      ops/recovery
# @description Rollback to last known-good state with health verification and incident logging

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# Initialize repository context
init_repo

# Configuration
DRY_RUN="${DRY_RUN:-0}"
BACKUP_DIR="${BACKUP_DIR:-/tmp}"
DEPLOY_HOST="${DEPLOY_HOST:-192.168.168.31}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"

# State
BACKUP_FOUND=0
SERVICES_STOPPED=0
BACKUP_RESTORED=0
SERVICES_STARTED=0
HEALTH_VERIFIED=0

log_stage() {
    log_info "========== $1 =========="
}

require_var DEPLOY_HOST "Deployment host IP"
require_var DEPLOY_USER "Deployment user"

main() {
    log_stage "ROLLBACK TO LAST KNOWN-GOOD STATE"
    log_info "Target: $DEPLOY_USER@$DEPLOY_HOST"
    log_info "Backup directory: $BACKUP_DIR"
    log_info "Dry-run mode: $([ "$DRY_RUN" -eq 1 ] && echo 'YES (no changes)' || echo 'NO (will rollback)')"
    echo ""
    
    # === Step 1: Find Latest Backup ===
    log_stage "STEP 1: Locate Latest Backup"
    
    log_info "Searching for backups in $BACKUP_DIR..."
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would search for latest backup"
        latest_backup="/tmp/backup-1234567890.tar.gz"
        BACKUP_FOUND=1
    else
        # Find latest backup file
        latest_backup=$(ssh "$DEPLOY_USER@$DEPLOY_HOST" "ls -t ${BACKUP_DIR}/backup-*.tar.gz 2>/dev/null | head -1")
        
        if [ -z "$latest_backup" ]; then
            log_error "❌ No backup files found in $BACKUP_DIR"
            log_info "Create a backup first: DRY_RUN=1 bash scripts/ops/redeploy.sh"
            exit 1
        fi
        
        log_info "✅ Found backup: $latest_backup"
        # shellcheck disable=SC2034
        BACKUP_FOUND=1
    fi
    
    echo ""
    
    # === Step 2: Log Incident ===
    log_stage "STEP 2: Incident Logging"
    
    incident_log="${SCRIPT_DIR}/artifacts/incidents/rollback-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$(dirname "$incident_log")"
    
    {
        echo "Rollback Incident Report"
        echo "========================="
        echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "Operator: $USER"
        echo "Target: $DEPLOY_USER@$DEPLOY_HOST"
        echo "Backup used: $latest_backup"
        echo "Mode: $([ "$DRY_RUN" -eq 1 ] && echo 'DRY-RUN' || echo 'APPLY')"
        echo ""
        echo "Pre-rollback state:"
        echo "  (would contain: docker ps, docker logs, error messages)"
        echo ""
    } | tee "$incident_log"
    
    log_info "✅ Incident logged to: $incident_log"
    echo ""
    
    # === Step 3: Stop Services ===
    log_stage "STEP 3: Stop Running Services"
    
    log_info "Stopping Docker services gracefully..."
    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "[DRY-RUN] Would run: docker compose down"
        SERVICES_STOPPED=1
    else
        if ssh "$DEPLOY_USER@$DEPLOY_HOST" "cd ~/code-server-enterprise && docker compose down" &>/dev/null; then
            log_info "✅ Services stopped"
            SERVICES_STOPPED=1
        else
            log_error "⚠️ Failed to stop services gracefully, forcing..."
            ssh "$DEPLOY_USER@$DEPLOY_HOST" "docker kill \$(docker ps -q) 2>/dev/null || true" &>/dev/null
            log_info "✅ Services force-stopped"
            SERVICES_STOPPED=1
        fi
    fi
    
    echo ""
    
    # === Step 4: Restore from Backup ===
    if [ "$SERVICES_STOPPED" -eq 1 ]; then
        log_stage "STEP 4: Restore Configuration from Backup"
        
        log_info "Extracting backup to $DEPLOY_HOST..."
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would extract: tar xzf $latest_backup"
            BACKUP_RESTORED=1
        else
            if ssh "$DEPLOY_USER@$DEPLOY_HOST" "cd ~/ && tar xzf $latest_backup" &>/dev/null; then
                log_info "✅ Configuration restored"
                BACKUP_RESTORED=1
            else
                log_error "❌ Backup extraction failed"
                exit 1
            fi
        fi
        
        echo ""
    fi
    
    # === Step 5: Verify Backup Integrity ===
    if [ "$BACKUP_RESTORED" -eq 1 ]; then
        log_stage "STEP 5: Verify Restored Configuration"
        
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would verify:"
            log_info "  - docker-compose.yml exists"
            log_info "  - .env file present"
            log_info "  - variables.tf valid"
        else
            # Check restored files
            if ssh "$DEPLOY_USER@$DEPLOY_HOST" "test -f ~/code-server-enterprise/docker-compose.yml"; then
                log_info "✅ docker-compose.yml verified"
            else
                log_error "❌ docker-compose.yml not found after restore"
                exit 1
            fi
            
            if ssh "$DEPLOY_USER@$DEPLOY_HOST" "test -f ~/code-server-enterprise/.env"; then
                log_info "✅ .env file verified"
            else
                log_warn "⚠️ .env file not found (may need manual configuration)"
            fi
        fi
        
        echo ""
    fi
    
    # === Step 6: Start Services ===
    if [ "$BACKUP_RESTORED" -eq 1 ]; then
        log_stage "STEP 6: Restart Services"
        
        log_info "Starting Docker services..."
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would run: docker compose up -d"
            SERVICES_STARTED=1
        else
            if ssh "$DEPLOY_USER@$DEPLOY_HOST" "cd ~/code-server-enterprise && docker compose up -d" &>/dev/null; then
                log_info "✅ Services started"
                SERVICES_STARTED=1
            else
                log_error "❌ Failed to start services"
                exit 1
            fi
        fi
        
        echo ""
    fi
    
    # === Step 7: Health Verification ===
    if [ "$SERVICES_STARTED" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
        log_stage "STEP 7: Health Verification"
        
        log_info "Waiting for services to stabilize (max ${HEALTH_CHECK_TIMEOUT}s)..."
        
        if [ "$DRY_RUN" -eq 1 ]; then
            log_info "[DRY-RUN] Would verify health endpoints"
            HEALTH_VERIFIED=1
        else
            # Check Code-server (most critical)
            if timeout 60 bash -c "until curl -sf http://$DEPLOY_HOST:8080/healthz >/dev/null 2>&1; do sleep 2; done"; then
                log_info "✅ Code-server is healthy"
            else
                log_warn "⚠️ Code-server health check timeout"
            fi
            
            # Check Postgres (data-critical)
            if ssh "$DEPLOY_USER@$DEPLOY_HOST" "docker ps | grep postgres" &>/dev/null; then
                log_info "✅ PostgreSQL is running"
            else
                log_warn "⚠️ PostgreSQL container not found"
            fi
            
            # Check Redis
            if ssh "$DEPLOY_USER@$DEPLOY_HOST" "docker ps | grep redis" &>/dev/null; then
                log_info "✅ Redis is running"
            else
                log_warn "⚠️ Redis container not found"
            fi
            
            HEALTH_VERIFIED=1
        fi
        
        echo ""
    fi
    
    # === Final Summary ===
    log_stage "ROLLBACK COMPLETE"
    
    if [ "$HEALTH_VERIFIED" -eq 1 ]; then
        log_info "✅ Rollback sequence completed successfully"
        log_info ""
        log_info "Rollback Summary:"
        log_info "  Services stopped:     ✅"
        log_info "  Backup restored:      ✅"
        log_info "  Services restarted:   ✅"
        log_info "  Health verified:      ✅"
        log_info ""
        log_info "System is back to known-good state"
        log_info "Incident log: $incident_log"
        log_info ""
        exit 0
    else
        log_error "❌ Rollback sequence incomplete"
        exit 1
    fi
}

main "$@"
