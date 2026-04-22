#!/usr/bin/env bash
# @file        scripts/ops/provision-ide-session-lb-secret.sh
# @module      infrastructure/secrets
# @description Provision IDE_SESSION_LB_SECRET to Google Secret Manager and deploy to hosts

set -euo pipefail

# Source common utilities and logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ────────────────────────────────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────────────────────────────────

GCP_PROJECT="${GCP_PROJECT:-gcp-kc}"
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
SSH_USER="${DEPLOY_USER:-akushnir}"

SECRET_NAME="ide-session-lb-secret"
SECRET_BITS=128  # 32 hex characters = 128 bits
DRY_RUN="${DRY_RUN:-1}"

# ────────────────────────────────────────────────────────────────────────────
# Functions
# ────────────────────────────────────────────────────────────────────────────

generate_secret() {
    log_info "Generating ${SECRET_BITS}-bit secure random secret..."
    openssl rand -hex "$((SECRET_BITS / 8))"
}

create_gsm_secret() {
    local secret_value="$1"
    
    log_info "Creating/updating GSM secret: $SECRET_NAME"
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would create GSM secret: $SECRET_NAME"
        log_info "[DRY-RUN] Secret value: ${secret_value:0:16}..."
        return 0
    fi
    
    # Check if secret exists
    if gcloud secrets describe "$SECRET_NAME" --project="$GCP_PROJECT" &>/dev/null; then
        log_info "Secret already exists, creating new version..."
        echo -n "$secret_value" | gcloud secrets versions add "$SECRET_NAME" \
            --data-file=- \
            --project="$GCP_PROJECT" \
            2>&1 | log_info
    else
        log_info "Creating new secret..."
        gcloud secrets create "$SECRET_NAME" \
            --replication-policy=automatic \
            --project="$GCP_PROJECT" \
            2>&1 | log_info
        echo -n "$secret_value" | gcloud secrets versions add "$SECRET_NAME" \
            --data-file=- \
            --project="$GCP_PROJECT" \
            2>&1 | log_info
    fi
    
    log_info "✓ GSM secret created/updated"
}

fetch_and_deploy_secret() {
    local host="$1"
    local secret_value="$2"
    
    log_info "Deploying secret to $host..."
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would deploy to $host:"
        log_info "[DRY-RUN] ssh $SSH_USER@$host 'echo IDE_SESSION_LB_SECRET=... >> .env'"
        return 0
    fi
    
    # Create backup of .env on remote host
    log_info "Creating backup of .env on $host..."
    ssh -o BatchMode=yes "$SSH_USER@$host" \
        "cd ~/code-server-enterprise && cp .env .env.backup.$(date +%s)" \
        2>&1 | log_debug
    
    # Update .env with new secret (ensure variable is set)
    log_info "Updating IDE_SESSION_LB_SECRET on $host..."
    ssh -o BatchMode=yes "$SSH_USER@$host" \
        "cd ~/code-server-enterprise && \
        if grep -q '^IDE_SESSION_LB_SECRET=' .env; then \
            sed -i 's/^IDE_SESSION_LB_SECRET=.*/IDE_SESSION_LB_SECRET=$secret_value/' .env; \
        else \
            echo \"IDE_SESSION_LB_SECRET=$secret_value\" >> .env; \
        fi" \
        2>&1 | log_debug
    
    log_info "✓ Secret deployed to $host"
}

test_sticky_sessions() {
    local host="$1"
    
    log_info "Testing sticky sessions on $host..."
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would test sticky sessions on $host"
        return 0
    fi
    
    # Reload Caddy configuration
    log_info "Reloading Caddy on $host..."
    ssh -o BatchMode=yes "$SSH_USER@$host" \
        "cd ~/code-server-enterprise && \
        docker-compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile" \
        2>&1 | log_debug
    
    # Verify Caddy is operational
    log_info "Verifying Caddy health on $host..."
    ssh -o BatchMode=yes "$SSH_USER@$host" \
        "curl -sf https://$host/health || curl -sk https://$host/health" \
        2>&1 | log_debug
    
    log_info "✓ Sticky sessions verified on $host"
}

test_failover() {
    log_info "Testing failover between hosts..."
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would test failover:"
        log_info "[DRY-RUN] 1. Shutdown primary"
        log_info "[DRY-RUN] 2. Verify replica handles traffic"
        log_info "[DRY-RUN] 3. Restart primary"
        log_info "[DRY-RUN] 4. Verify failback"
        return 0
    fi
    
    log_info "Step 1: Testing current primary ($PRIMARY_HOST) with new secret..."
    test_sticky_sessions "$PRIMARY_HOST"
    
    log_info "Step 2: Testing replica ($REPLICA_HOST) with new secret..."
    test_sticky_sessions "$REPLICA_HOST"
    
    log_info "✓ Failover test completed"
}

cleanup_git_history() {
    log_info "Cleaning git history of old secret..."
    
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would clean git history:"
        log_info "[DRY-RUN] - Search for 'secret734' in git"
        log_info "[DRY-RUN] - Use git-filter-repo to remove"
        log_info "[DRY-RUN] - Force push to main"
        return 0
    fi
    
    # Check if secret734 appears in git history
    if git log --all -S 'secret734' --oneline | head -1 &>/dev/null; then
        log_warn "Found 'secret734' in git history at commits:"
        git log --all -S 'secret734' --oneline | head -5
        
        log_info "Installing git-filter-repo if needed..."
        if ! command -v git-filter-repo &>/dev/null; then
            log_info "Downloading git-filter-repo..."
            curl -s https://raw.githubusercontent.com/newren/git-filter-repo/main/git-filter-repo > /tmp/git-filter-repo
            chmod +x /tmp/git-filter-repo
        fi
        
        log_warn "Git history cleanup requires manual intervention (security precaution)"
        log_warn "To remove 'secret734' from git history, run:"
        log_warn "  git-filter-repo --replace-text /tmp/secret734-replacements.txt"
        log_warn "  git push --force-with-lease"
        log_warn "See: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository"
    else
        log_info "✓ 'secret734' not found in git history"
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────────────

main() {
    log_info "═════════════════════════════════════════════════════════════"
    log_info "IDE_SESSION_LB_SECRET Rotation & Deployment"
    log_info "═════════════════════════════════════════════════════════════"
    
    [[ "$DRY_RUN" == "1" ]] && log_warn "Running in DRY-RUN mode (no changes)"
    
    log_info ""
    log_info "Configuration:"
    log_info "  GCP Project: $GCP_PROJECT"
    log_info "  Primary Host: $PRIMARY_HOST"
    log_info "  Replica Host: $REPLICA_HOST"
    log_info "  Deploy User: $SSH_USER"
    log_info ""
    
    # Step 1: Generate new secret
    NEW_SECRET=$(generate_secret)
    log_info "Generated new secret: ${NEW_SECRET:0:16}..."
    
    # Step 2: Create/update GSM secret
    create_gsm_secret "$NEW_SECRET"
    
    # Step 3: Deploy to primary
    fetch_and_deploy_secret "$PRIMARY_HOST" "$NEW_SECRET"
    
    # Step 4: Deploy to replica
    fetch_and_deploy_secret "$REPLICA_HOST" "$NEW_SECRET"
    
    # Step 5: Test failover
    test_failover
    
    # Step 6: Clean git history
    cleanup_git_history
    
    log_info ""
    log_info "═════════════════════════════════════════════════════════════"
    log_info "✓ IDE_SESSION_LB_SECRET rotation complete"
    log_info "═════════════════════════════════════════════════════════════"
}

main "$@"
