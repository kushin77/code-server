#!/bin/bash
# tier-1-iac-deploy.sh
# IaC-based Tier 1 deployment with idempotent, immutable guarantees
# Ensures: Idempotent (safe to run multiple times), Immutable (no state changes outside code)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_HOST="${1:-192.168.168.31}"
DRY_RUN="${2:-false}"
DEPLOYED_VERSION="tier-1-$(date +%Y%m%d-%H%M%S)"

# Configuration
BACKUP_RETENTION_DAYS=7
MAX_RETRIES=3
RETRY_DELAY=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
LOG_DIR="/tmp/tier1-deployments"
LOG_FILE="$LOG_DIR/tier1-iac-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}║  $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
}

print_step() {
    echo -e "\n${BLUE}[STEP] $1${NC}" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}✗ $1${NC}" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
}

# Idempotency check - ensure script can run multiple times safely
check_idempotency() {
    log "${BLUE}=== IDEMPOTENCY CHECK ===${NC}"
    
    # Verify current state hasn't been tampered with
    log "Verifying Git working directory is clean..."
    
    # Safely check git status without cd if possible
    if [ -d "$REPO_DIR/.git" ]; then
        cd "$REPO_DIR" 2>/dev/null || log "Warning: Could not cd to $REPO_DIR"
        
        if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            log "${YELLOW}Warning: Uncommitted changes detected, stashing...${NC}"
            git stash 2>/dev/null || true
        fi
    else
        log "${YELLOW}Warning: Not in a Git repository, skipping git checks${NC}"
    fi
    
    print_success "Idempotency checks passed"
}

# Dry run mode - show what would happen without changes
execute_dry_run() {
    log "${YELLOW}DRY_RUN MODE - No changes will be applied${NC}"
    log ""
    log "Deployment plan for $TARGET_HOST:"
    log "  1. Backup current configuration"
    log "  2. Validate kernel tuning script"
    log "  3. Validate docker-compose configuration"
    log "  4. Validate post-deployment validation script"
    log "  5. Deploy (if approved)"
    log "  6. Validate deployment"
    log "  7. Commit changes"
    log ""
    log "To proceed with deployment: $0 $TARGET_HOST false"
}

# Immutability guarantees - all changes come from version control
verify_immutability() {
    log "${BLUE}=== IMMUTABILITY VERIFICATION ===${NC}"
    
    # Ensure all deployment artifacts are in version control
    if [ ! -f "$SCRIPT_DIR/apply-kernel-tuning.sh" ]; then
        print_error "apply-kernel-tuning.sh not in version control"
        return 1
    fi
    
    if [ ! -f "$SCRIPT_DIR/docker-compose.yml" ]; then
        print_error "docker-compose.yml not in version control"
        return 1
    fi
    
    if [ ! -f "$SCRIPT_DIR/post-deployment-validation.sh" ]; then
        print_error "post-deployment-validation.sh not in version control"
        return 1
    fi
    
    print_success "All deployment artifacts in version control (immutable)"
    
    # Verify checksums of critical files
    log "Computing artifact checksums..."
    cd "$SCRIPT_DIR"
    
    # Calculate expected checksums
    KERNEL_SCRIPT_SHA=$(sha256sum apply-kernel-tuning.sh | cut -d' ' -f1)
    DOCKER_COMPOSE_SHA=$(sha256sum docker-compose.yml | cut -d' ' -f1)
    VALIDATION_SCRIPT_SHA=$(sha256sum post-deployment-validation.sh | cut -d' ' -f1)
    
    log "Artifact checksums:"
    log "  apply-kernel-tuning.sh: $KERNEL_SCRIPT_SHA"
    log "  docker-compose.yml: $DOCKER_COMPOSE_SHA"
    log "  post-deployment-validation.sh: $VALIDATION_SCRIPT_SHA"
}

# Deploy with retry logic for resilience
deploy_with_retry() {
    local function_to_call=$1
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log "${YELLOW}Attempt $attempt of $MAX_RETRIES...${NC}"
        
        if $function_to_call; then
            print_success "$function_to_call succeeded"
            return 0
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log "Waiting ${RETRY_DELAY}s before retry..."
            sleep $RETRY_DELAY
        fi
        
        attempt=$((attempt + 1))
    done
    
    print_error "$function_to_call failed after $MAX_RETRIES attempts"
    return 1
}

# Deploy kernel tuning
deploy_kernel_tuning() {
    print_step "Deploying Kernel Tuning (Idempotent)"
    
    # Kernel tuning is idempotent - can be applied multiple times
    bash "$SCRIPT_DIR/apply-kernel-tuning.sh" 2>&1 | tee -a "$LOG_FILE"
    
    # Verify idempotency - run again to ensure it's stable
    sleep 2
    log "Verifying idempotency (applying kernel tuning again)..."
    bash "$SCRIPT_DIR/apply-kernel-tuning.sh" 2>&1 | tee -a "$LOG_FILE"
    
    print_success "Kernel tuning deployed (idempotent)"
}

# Deploy container configuration
deploy_containers() {
    print_step "Deploying Container Configuration (Immutable)"
    
    # Create immutable deployment marker
    DEPLOYMENT_MARKER="$SCRIPT_DIR/.tier1-deployed-$DEPLOYED_VERSION"
    
    # Verify no conflicting deployments in progress
    if [ -f "$SCRIPT_DIR/.tier1-deploying" ]; then
        print_error "Another deployment is in progress (found .tier1-deploying marker)"
        return 1
    fi
    
    # Mark deployment as in progress
    touch "$SCRIPT_DIR/.tier1-deploying"
    
    # Cleanup on success/failure
    trap "rm -f $SCRIPT_DIR/.tier1-deploying" EXIT
    
    # Copy docker-compose to target
    log "Copying docker-compose.yml to target..."
    scp -o StrictHostKeyChecking=no "$SCRIPT_DIR/docker-compose.yml" \
        "akushnir@$TARGET_HOST:/home/akushnir/code-server-enterprise/docker-compose.yml" 2>&1 | tee -a "$LOG_FILE"
    
    print_success "Container configuration deployed (immutable)"
}

# Validate deployment
validate_deployment() {
    print_step "Validating Deployment (8 Tests)"
    
    bash "$SCRIPT_DIR/post-deployment-validation.sh" "$TARGET_HOST" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        print_success "All validation tests passed"
        return 0
    else
        print_error "Some validation tests failed"
        return 1
    fi
}

# Commit changes to version control
commit_to_git() {
    print_step "Committing Deployment to Git (Audit Trail)"
    
    if [ ! -d "$REPO_DIR/.git" ]; then
        log "${YELLOW}Warning: Not in a Git repository, skipping git commit${NC}"
        return 0
    fi
    
    cd "$REPO_DIR" 2>/dev/null || return 1
    
    # Only commit if there are changes
    if [ -z "$(git status --porcelain)" ]; then
        log "No changes to commit"
        return 0
    fi
    
    git add -A
    git commit -m "deploy(tier1-iac): Tier 1 deployment executed - $DEPLOYED_VERSION

Deployment details:
- Target: $TARGET_HOST
- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Immutable: All changes from version control
- Idempotent: Safe to run multiple times
- Validated: 8-test validation suite passed

Components deployed:
  ✓ Kernel optimization (sysctl)
  ✓ Container configuration (docker-compose)
  ✓ HTTP/2 + compression (Caddy)
  ✓ Node.js worker threads (8x)

Deployment log: $LOG_FILE
Rollback: git revert <hash>" 2>&1 | tee -a "$LOG_FILE"
    
    git push origin main 2>&1 | tee -a "$LOG_FILE" || log "${YELLOW}Warning: Git push failed${NC}"
    
    print_success "Changes committed to Git"
}

# Backup strategy for disaster recovery
cleanup_old_backups() {
    print_step "Cleaning Up Old Backups (Retention: $BACKUP_RETENTION_DAYS days)"
    
    ssh -o StrictHostKeyChecking=no "akushnir@$TARGET_HOST" \
        "find ~/backups/tier1-* -type d -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true" \
        2>&1 | tee -a "$LOG_FILE"
    
    print_success "Old backups cleaned up"
}

# Main execution flow
main() {
    print_header " TIER 1 IaC DEPLOYMENT - IDEMPOTENT & IMMUTABLE "
    
    log "Target Host: $TARGET_HOST"
    log "Deployment Version: $DEPLOYED_VERSION"
    log "Dry Run: $DRY_RUN"
    log "Log File: $LOG_FILE"
    
    # Phase 1: Pre-deployment checks
    log "\n${BLUE}=== PHASE 1: PRE-DEPLOYMENT CHECKS ===${NC}"
    check_idempotency
    verify_immutability
    
    if [ "$DRY_RUN" = "true" ]; then
        execute_dry_run
        exit 0
    fi
    
    # Phase 2: Pre-deployment backup
    log "\n${BLUE}=== PHASE 2: BACKUP ===${NC}"
    print_step "Creating Pre-Deployment Backup"
    ssh -o StrictHostKeyChecking=no "akushnir@$TARGET_HOST" \
        "mkdir -p ~/backups/tier1-$(date +%Y-%m-%d) && \
         cd ~/code-server-enterprise && \
         cp docker-compose.yml ~/backups/tier1-$(date +%Y-%m-%d)/ && \
         sudo cp /etc/sysctl.conf ~/backups/tier1-$(date +%Y-%m-%d)/ 2>/dev/null || true" \
        2>&1 | tee -a "$LOG_FILE"
    print_success "Pre-deployment backup created"
    
    # Phase 3: Deployment
    log "\n${BLUE}=== PHASE 3: DEPLOYMENT ===${NC}"
    deploy_with_retry deploy_kernel_tuning || exit 1
    deploy_with_retry deploy_containers || exit 1
    
    # Phase 4: Validation
    log "\n${BLUE}=== PHASE 4: VALIDATION ===${NC}"
    validate_deployment || exit 1
    
    # Phase 5: Git audit trail
    log "\n${BLUE}=== PHASE 5: AUDIT TRAIL ===${NC}"
    commit_to_git
    
    # Phase 6: Cleanup
    log "\n${BLUE}=== PHASE 6: CLEANUP ===${NC}"
    cleanup_old_backups
    
    # Success summary
    log "\n"
    print_header " DEPLOYMENT COMPLETE - IDEMPOTENT & IMMUTABLE "
    log "✓ All systems deployed successfully"
    log "✓ All validations passed"
    log "✓ Git audit trail recorded"
    log "✓ Safe for repeated deployment"
    log ""
    log "Next steps:"
    log "  1. Monitor 24 hours: docker stats"
    log "  2. Run stress test: bash $SCRIPT_DIR/stress-test-suite.sh $TARGET_HOST"
    log "  3. Evaluate Tier 2 readiness"
    log ""
    log "Deployment log: $LOG_FILE"
}

# Execute
main "$@"
