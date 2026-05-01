#!/bin/bash
###############################################################################
# @file        scripts/ops/migrate-to-k8s-data.sh
# @description Migrates data from Docker HA stack to Kubernetes StatefulSets
# @governance  GOV-002: Audited data transition protocol
# @usage       bash migrate-to-k8s-data.sh [postgres|redis|all]
###############################################################################

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

trap 'log_error "Migration failed at line $LINENO"; exit 1' ERR

TARGET_SERVICE="${1:-all}"
K8S_NAMESPACE="code-server-enterprise"
TEMP_DIR="/tmp/k8s-migration-$(date +%s)"
mkdir -p "$TEMP_DIR"

log_section "Data Migration: Docker HA → Kubernetes"
log_info "Target Service: $TARGET_SERVICE"
log_info "K8s Namespace: $K8S_NAMESPACE"

# Check prerequisites
command -v kubectl &> /dev/null || { log_error "kubectl not found"; exit 1; }
command -v docker &> /dev/null || log_warn "Local docker not found, assuming remote access via SSH"

migrate_postgres() {
    log_info "🔵 Starting PostgreSQL Migration"
    
    # 1. Create dump from Docker
    log_info "Creating pg_dump from Docker primary (192.168.168.31)..."
    ssh akushnir@192.168.168.31 "docker exec code-server-postgres pg_dump -U postgres -d code_server --format=plain --no-owner --no-privileges | gzip" > "$TEMP_DIR/postgres_dump.sql.gz"
    
    # 2. Upload to K8S (StatefulSet pod 0)
    log_info "Locating target PostgreSQL pod in K8s..."
    PG_POD=$(kubectl get pods -n "$K8S_NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')
    log_info "Uploading to $PG_POD..."
    kubectl cp "$TEMP_DIR/postgres_dump.sql.gz" "$K8S_NAMESPACE/$PG_POD:/tmp/migration_dump.sql.gz"
    
    # 3. Restore in K8S
    log_info "Restoring database in $PG_POD..."
    kubectl exec -n "$K8S_NAMESPACE" "$PG_POD" -- bash -c "gunzip < /tmp/migration_dump.sql.gz | psql -U postgres"
    
    log_success "PostgreSQL migration complete"
}

migrate_redis() {
    log_info "🔴 Starting Redis Migration"
    
    # 1. Trigger BGSAVE and capture snapshot
    log_info "Capturing Redis snapshot from Docker primary..."
    ssh akushnir@192.168.168.31 "docker exec code-server-redis redis-cli BGSAVE && sleep 5 && docker exec code-server-redis cat /data/dump.rdb" > "$TEMP_DIR/dump.rdb"
    
    # 2. Upload to K8S
    log_info "Locating target Redis pod in K8s..."
    REDIS_POD=$(kubectl get pods -n "$K8S_NAMESPACE" -l app=redis -o jsonpath='{.items[0].metadata.name}')
    log_info "Uploading to $REDIS_POD..."
    kubectl cp "$TEMP_DIR/dump.rdb" "$K8S_NAMESPACE/$REDIS_POD:/data/dump.rdb"
    
    # 3. Restart Redis pod to pick up new database
    log_info "Restarting Redis pod to load data..."
    kubectl delete pod "$REDIS_POD" -n "$K8S_NAMESPACE"
    
    log_success "Redis migration complete (pod restarted)"
}

case "$TARGET_SERVICE" in
    postgres)
        migrate_postgres
        ;;
    redis)
        migrate_redis
        ;;
    all)
        migrate_postgres
        migrate_redis
        ;;
    *)
        log_error "Unknown service: $TARGET_SERVICE"
        exit 1
        ;;
esac

log_info "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

log_section "MIGRATION COMPLETE"
log_info "Verify status with: kubectl get pods -n $K8S_NAMESPACE"
