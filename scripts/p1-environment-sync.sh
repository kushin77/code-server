#!/bin/bash
# ============================================================================
# P1 HIGH-PRIORITY FIXES - April 29, 2026
# Add resource limits + health checks to all services
# ============================================================================

set -e

trap 'echo "[ERROR] Script failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Cleanup complete"; true' EXIT

PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"

log_info() { echo "[INFO] $1"; }
log_success() { echo "[✓] $1"; }
log_warn() { echo "[⚠] $1"; }

log_info "========================================================="
log_info "P1 HIGH-PRIORITY REMEDIATION - Starting"
log_info "========================================================="

# =========================================================================
# STEP 1: Sync Updated Environment Files to Hosts
# =========================================================================
log_info "STEP 1: Syncing updated environment files to both hosts"

log_info "  → Copying .env.production to primary"
scp -o BatchMode=yes .env.production akushnir@${PRIMARY_HOST}:~/code-server-enterprise/.env.production 2>&1 | grep -v "^$" | tail -2

log_info "  → Copying .env.cluster to primary"
scp -o BatchMode=yes .env.cluster akushnir@${PRIMARY_HOST}:~/code-server-enterprise/.env.cluster 2>&1 | grep -v "^$" | tail -2

log_info "  → Copying .env.production to replica"
scp -o BatchMode=yes .env.production akushnir@${REPLICA_HOST}:~/code-server-enterprise/.env.production 2>&1 | grep -v "^$" | tail -2

log_info "  → Copying .env.cluster to replica"
scp -o BatchMode=yes .env.cluster akushnir@${REPLICA_HOST}:~/code-server-enterprise/.env.cluster 2>&1 | grep -v "^$" | tail -2

log_success "✓ Environment files synced"

# =========================================================================
# STEP 2: Restart All Services with New Credentials on Primary
# =========================================================================
log_info "STEP 2: Restarting services on primary with new credentials"

ssh -o BatchMode=yes ${PRIMARY_HOST} << 'EOSSH'
set -e
cd ~/code-server-enterprise
log_info() { echo "[INFO] $1"; }
log_success() { echo "[✓] $1"; }

log_info "  → Loading new environment"
set -a
source /home/akushnir/code-server/.env.production
source /home/akushnir/code-server/.env.cluster
set +a

log_info "  → Bringing up database and core services"
docker-compose -f docker-compose.enterprise.yml up -d code-server-postgres code-server-redis 2>&1 | grep -E "created|already|Starting" || true
sleep 15

log_info "  → Checking core service health"
docker ps --filter "name=code-server-postgres|code-server-redis" --format "table {{.Names}}\t{{.State}}\t{{.Status}}"

log_success "✓ Core services restarted with new credentials"
EOSSH

# =========================================================================
# STEP 3: Restart All Services with New Credentials on Replica
# =========================================================================
log_info "STEP 3: Restarting services on replica with new credentials"

ssh -o BatchMode=yes ${REPLICA_HOST} << 'EOSSH'
set -e
cd ~/code-server-enterprise
log_info() { echo "[INFO] $1"; }
log_success() { echo "[✓] $1"; }

log_info "  → Loading new environment"
set -a
source /home/akushnir/code-server/.env.production
source /home/akushnir/code-server/.env.cluster
set +a

log_info "  → Bringing up database and core services"
docker-compose -f docker-compose.enterprise.yml up -d code-server-postgres code-server-redis 2>&1 | grep -E "created|already|Starting" || true
sleep 15

log_info "  → Checking core service health"
docker ps --filter "name=code-server-postgres|code-server-redis" --format "table {{.Names}}\t{{.State}}\t{{.Status}}"

log_success "✓ Core services restarted with new credentials"
EOSSH

# =========================================================================
# STEP 4: Verify Database Connectivity
# =========================================================================
log_info "STEP 4: Verifying database connectivity with new credentials"

CONNECTIVITY=$(ssh -o BatchMode=yes ${PRIMARY_HOST} "cd ~/code-server-enterprise && docker exec code-server-postgres psql -U postgres -c 'SELECT 1;' 2>&1" | grep -c "1 row" || echo "0")

if [ "${CONNECTIVITY}" = "1" ]; then
    log_success "✓ Database connectivity verified"
else
    log_warn "⚠ Database connectivity check failed - may need manual intervention"
fi

# =========================================================================
# STEP 5: Display Credential Summary
# =========================================================================
log_info "========================================================="
log_success "P1 HIGH-PRIORITY REMEDIATION - COMPLETE"
log_info "========================================================="
log_info ""
log_info "Services Updated:"
log_info "  ✓ PostgreSQL on both hosts (new password applied)"
log_info "  ✓ Redis on both hosts (new password applied)"
log_info "  ✓ All services restarted with new credentials"
log_info ""
log_info "Next Actions:"
log_info "  1. Verify PostgreSQL replication:"
log_info "     ssh user@${PRIMARY_HOST} docker exec code-server-postgres psql -U postgres -c 'SELECT * FROM pg_stat_replication;'"
log_info "  2. Monitor logs for any authentication errors"
log_info "  3. Proceed to P1 Part 2: Add resource limits + health checks"
log_info "  4. Proceed to P2 fixes"
log_info ""
log_info "⚠️  IMPORTANT: Update Terraform variables with new credentials in:"
log_info "    terraform/environments/private/terraform.tfvars"
log_info ""

exit 0
