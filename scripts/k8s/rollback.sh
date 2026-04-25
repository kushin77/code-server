#!/bin/bash
# scripts/k8s/rollback.sh
# Emergency rollback from Kubernetes back to Docker Compose
# Usage: bash rollback.sh [reason]

set -euo pipefail

REASON="${1:-manual-rollback}"
BACKUP_DIR="/backups/docker-compose-archive"
API_DOMAIN="${API_DOMAIN:?API_DOMAIN must be set}"
DOCKER_COMPOSE_IP="${DOCKER_COMPOSE_IP:?DOCKER_COMPOSE_IP must be set}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "Starting emergency rollback - Reason: ${REASON}"

# ===== PHASE 1: PRE-ROLLBACK CHECKS =====
log_info "Phase 1: Pre-rollback validation"

if [ ! -d "${BACKUP_DIR}" ]; then
  log_error "Docker Compose backup directory not found: ${BACKUP_DIR}"
  exit 1
fi

if [ ! -f "${BACKUP_DIR}/docker-compose.yml" ]; then
  log_error "docker-compose.yml not found in backup"
  exit 1
fi

log_success "Backup verified"

# ===== PHASE 2: CREATE ROLLBACK SNAPSHOT =====
log_info "Phase 2: Creating K8s rollback snapshot"

TIMESTAMP=$(date +%s)
SNAPSHOT_DIR="/backups/k8s-snapshot-${TIMESTAMP}"
mkdir -p ${SNAPSHOT_DIR}

# Export all K8s resources
kubectl get all -n code-server-enterprise -o yaml > ${SNAPSHOT_DIR}/all-resources.yaml
kubectl get configmaps -n code-server-enterprise -o yaml > ${SNAPSHOT_DIR}/configmaps.yaml
kubectl get secrets -n code-server-enterprise -o yaml > ${SNAPSHOT_DIR}/secrets.yaml
kubectl get pvc -n code-server-enterprise -o yaml > ${SNAPSHOT_DIR}/pvc.yaml

log_success "K8s snapshot created: ${SNAPSHOT_DIR}"

# ===== PHASE 3: BACKUP CURRENT DATA =====
log_info "Phase 3: Backing up data from K8s"

# Backup PostgreSQL
POSTGRES_POD=$(kubectl get pods -n code-server-enterprise -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "${POSTGRES_POD}" ]; then
  log_info "Backing up PostgreSQL"
  kubectl exec -n code-server-enterprise ${POSTGRES_POD} -- pg_dump -U postgres cse > ${SNAPSHOT_DIR}/postgres-backup-${TIMESTAMP}.sql
  log_success "PostgreSQL backup: ${SNAPSHOT_DIR}/postgres-backup-${TIMESTAMP}.sql"
fi

# Backup Redis
REDIS_POD=$(kubectl get pods -n code-server-enterprise -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "${REDIS_POD}" ]; then
  log_info "Backing up Redis"
  kubectl exec -n code-server-enterprise ${REDIS_POD} -- redis-cli save
  kubectl cp code-server-enterprise/${REDIS_POD}:/data/dump.rdb ${SNAPSHOT_DIR}/redis-backup-${TIMESTAMP}.rdb
  log_success "Redis backup: ${SNAPSHOT_DIR}/redis-backup-${TIMESTAMP}.rdb"
fi

# ===== PHASE 4: STOP K8S SERVICES =====
log_info "Phase 4: Stopping K8s services"

# Scale down deployments
kubectl scale deployment --all -n code-server-enterprise --replicas=0
log_success "Deployments scaled down"

# Delete services (but keep data)
kubectl delete services --all -n code-server-enterprise --ignore-not-found
log_success "Services deleted"

# ===== PHASE 5: UPDATE DNS ROUTING =====
log_info "Phase 5: Reverting DNS routing"

# Redirect 100% traffic back to Docker Compose
DNS_ZONE_ID="${DNS_ZONE_ID:-Z123456789ABC}"
DC_IP="${DOCKER_COMPOSE_IP}"

aws route53 change-resource-record-sets \
  --hosted-zone-id ${DNS_ZONE_ID} \
  --change-batch '{"Changes": [{"Action": "UPSERT", "ResourceRecordSet": {"Name": "'${API_DOMAIN}'", "Type": "A", "TTL": 60, "ResourceRecords": [{"Value": "'${DC_IP}'"}]}}]}' 2>/dev/null || log_warn "DNS update skipped (not in AWS environment)"

log_success "DNS routing reverted to Docker Compose (${DC_IP})"

# ===== PHASE 6: RESTORE DOCKER COMPOSE =====
log_info "Phase 6: Restoring Docker Compose"

# Copy backup files
cp ${BACKUP_DIR}/docker-compose*.yml .
cp ${BACKUP_DIR}/.env . 2>/dev/null || log_warn ".env not in backup"

log_success "Docker Compose files restored"

# ===== PHASE 7: START DOCKER COMPOSE =====
log_info "Phase 7: Starting Docker Compose services"

docker-compose up -d
sleep 10

# Verify services
docker-compose ps

log_success "Docker Compose services started"

# ===== PHASE 8: RESTORE DATA (if available) =====
log_info "Phase 8: Restoring data to Docker Compose"

if [ -f "final_backup.sql" ]; then
  log_info "Restoring PostgreSQL data"
  docker-compose exec -T postgres psql -U postgres < final_backup.sql
  log_success "PostgreSQL data restored"
fi

# ===== PHASE 9: HEALTH CHECKS =====
log_info "Phase 9: Running health checks"

HEALTH_CHECK_COUNT=0
HEALTH_CHECK_MAX=5

while [ ${HEALTH_CHECK_COUNT} -lt ${HEALTH_CHECK_MAX} ]; do
  HEALTH_CHECK_COUNT=$((HEALTH_CHECK_COUNT + 1))
  
  # Test Docker Compose services
  DOCKER_STATUS=$(docker-compose ps --services --filter "status=running" | wc -l)
  log_info "Running services: ${DOCKER_STATUS} (${HEALTH_CHECK_COUNT}/${HEALTH_CHECK_MAX})"
  
  sleep 5
done

log_success "Health checks completed"

# ===== PHASE 10: COMPLETION SUMMARY =====
log_success "Emergency rollback complete!"

echo ""
echo -e "${BLUE}=== ROLLBACK SUMMARY ===${NC}"
echo -e "${GREEN}Reason:${NC} ${REASON}"
echo -e "${GREEN}K8s Snapshot:${NC} ${SNAPSHOT_DIR}"
echo -e "${GREEN}DNS:${NC} Reverted to Docker Compose (${DC_IP})"
echo -e "${GREEN}Services:${NC} Docker Compose running"
echo -e "${GREEN}Data:${NC} Backup available at ${SNAPSHOT_DIR}"

echo ""
echo "Post-rollback actions:"
echo "1. Monitor Docker Compose logs: docker-compose logs -f"
echo "2. Verify all services: docker-compose ps"
echo "3. Investigate K8s failure: Check ${SNAPSHOT_DIR}/all-resources.yaml"
echo "4. Document incident: Create postmortem report"
echo "5. Fix issues before retry"

log_info "Rollback timestamp: ${TIMESTAMP}"
log_info "For retry: bash cutover.sh 10  (after fixes)"
