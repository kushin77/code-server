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

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

trap 'log_error "Migration failed at line $LINENO"; exit 1' ERR

TARGET_SERVICE="${1:-all}"
K8S_NAMESPACE="code-server-enterprise"
TEMP_DIR="/tmp/k8s-migration-$(date +%s)"
mkdir -p "$TEMP_DIR"

run_or_log() {
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] $*"
    else
        "$@"
    fi
}

log_section "Data Migration: Docker HA → Kubernetes"
log_info "Target Service: $TARGET_SERVICE"
log_info "K8s Namespace: $K8S_NAMESPACE"

# Check prerequisites
if [[ "$DRY_RUN" == false ]]; then
    command -v kubectl &> /dev/null || { log_error "kubectl not found"; exit 1; }
    command -v docker &> /dev/null || log_warn "Local docker not found, assuming remote access via SSH"
else
    log_info "[DRY-RUN] Skipping kubectl/docker availability checks"
fi

migrate_postgres() {
    log_info "🔵 Starting PostgreSQL Migration"
    
    # 1. Create dump from Docker
    log_info "Creating pg_dump from Docker primary (192.168.168.31)..."
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would capture PostgreSQL dump from code-server-postgres on 192.168.168.31"
    else
        ssh akushnir@192.168.168.31 "docker exec code-server-postgres pg_dump -U postgres -d code_server --format=plain --no-owner --no-privileges | gzip" > "$TEMP_DIR/postgres_dump.sql.gz"
    fi
    
    # 2. Upload to K8S (StatefulSet pod 0)
    log_info "Locating target PostgreSQL pod in K8s..."
    if [[ "$DRY_RUN" == true ]]; then
        PG_POD="postgres-0"
        log_info "[DRY-RUN] Would upload to $PG_POD"
    else
        PG_POD=$(kubectl get pods -n "$K8S_NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')
        log_info "Uploading to $PG_POD..."
        kubectl cp "$TEMP_DIR/postgres_dump.sql.gz" "$K8S_NAMESPACE/$PG_POD:/tmp/migration_dump.sql.gz"
    fi
    
    # 3. Restore in K8S
    log_info "Restoring database in $PG_POD..."
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would restore PostgreSQL dump inside $PG_POD"
    else
        kubectl exec -n "$K8S_NAMESPACE" "$PG_POD" -- bash -c "gunzip < /tmp/migration_dump.sql.gz | psql -U postgres"
    fi
    
    log_success "PostgreSQL migration complete"
}

migrate_redis() {
    log_info "🔴 Starting Redis Migration"
    
    # 1. Trigger BGSAVE and capture snapshot
    log_info "Capturing Redis snapshot from Docker primary..."
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would capture Redis snapshot from code-server-redis on 192.168.168.31"
    else
        ssh akushnir@192.168.168.31 "docker exec code-server-redis redis-cli BGSAVE && sleep 5 && docker exec code-server-redis cat /data/dump.rdb" > "$TEMP_DIR/dump.rdb"
    fi
    
    # 2. Upload to K8S
    log_info "Locating target Redis pod in K8s..."
    if [[ "$DRY_RUN" == true ]]; then
        REDIS_POD="redis-0"
        log_info "[DRY-RUN] Would upload to $REDIS_POD"
    else
        REDIS_POD=$(kubectl get pods -n "$K8S_NAMESPACE" -l app=redis -o jsonpath='{.items[0].metadata.name}')
        log_info "Uploading to $REDIS_POD..."
        kubectl cp "$TEMP_DIR/dump.rdb" "$K8S_NAMESPACE/$REDIS_POD:/data/dump.rdb"
    fi
    
    # 3. Restart Redis pod to pick up new database
    log_info "Restarting Redis pod to load data..."
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would restart $REDIS_POD"
    else
        kubectl delete pod "$REDIS_POD" -n "$K8S_NAMESPACE"
    fi
    
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
