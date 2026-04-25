#!/bin/bash
# scripts/k8s/cutover.sh
# Automated phased traffic cutover from Docker Compose to K8s
# Usage: bash cutover.sh [10|50|100]

set -euo pipefail

CUTOVER_PERCENT="${1:-100}"
DNS_ZONE_ID="${DNS_ZONE_ID:-Z123456789ABC}"
PRIMARY_DOMAIN="api.kushnir.cloud"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "${CUTOVER_PERCENT}" != "10" ] && [ "${CUTOVER_PERCENT}" != "50" ] && [ "${CUTOVER_PERCENT}" != "100" ]; then
  log_error "Invalid cutover percentage. Use 10, 50, or 100"
  exit 1
fi

log_info "Starting ${CUTOVER_PERCENT}% traffic cutover"

# ===== PHASE 1: PRE-CUTOVER VALIDATION =====
log_info "Phase 1: Pre-cutover validation"

# Verify K8s services are ready
RUNNING_PODS=$(kubectl get pods -n code-server-enterprise --field-selector=status.phase=Running --no-headers | wc -l)
if [ ${RUNNING_PODS} -lt 10 ]; then
  log_error "Not enough pods running (${RUNNING_PODS}). Expected >10"
  exit 1
fi
log_success "K8s services verified (${RUNNING_PODS} pods running)"

# Verify Docker Compose still running (for rollback capability)
if ! docker-compose ps &> /dev/null; then
  if [ "${CUTOVER_PERCENT}" != "100" ]; then
    log_warn "Docker Compose not running. Cannot proceed with phased cutover"
    exit 1
  fi
  log_info "Docker Compose not available (expected for 100% cutover)"
fi

# Test K8s service connectivity
API_POD=$(kubectl get pods -n code-server-enterprise -l app=api -o jsonpath='{.items[0].metadata.name}')
if [ -z "${API_POD}" ]; then
  log_error "No API pods found"
  exit 1
fi

kubectl exec -n code-server-enterprise ${API_POD} -- curl -s http://localhost:3100/health > /dev/null
log_success "K8s API service responding"

# ===== PHASE 2: GET CURRENT NLB ENDPOINT =====
log_info "Phase 2: Getting K8s NLB endpoint"

NLB_ENDPOINT=$(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -z "${NLB_ENDPOINT}" ]; then
  log_error "NLB endpoint not available"
  exit 1
fi

log_success "NLB endpoint: ${NLB_ENDPOINT}"

# Get current Docker Compose IP
DC_IP="${DOCKER_COMPOSE_IP:-192.168.1.100}"
log_info "Docker Compose endpoint: ${DC_IP}"

# ===== PHASE 3: UPDATE DNS ROUTING =====
log_info "Phase 3: Updating DNS routing (${CUTOVER_PERCENT}% → K8s, $((100 - CUTOVER_PERCENT))% → Docker Compose)"

# Calculate weights
K8S_WEIGHT=${CUTOVER_PERCENT}
DC_WEIGHT=$((100 - CUTOVER_PERCENT))

# Create Route53 weighted routing policy using AWS CLI
cat > route53-update.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${PRIMARY_DOMAIN}",
        "Type": "CNAME",
        "SetIdentifier": "k8s-ncp",
        "Weight": ${K8S_WEIGHT},
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "${NLB_ENDPOINT}"
          }
        ]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${PRIMARY_DOMAIN}",
        "Type": "CNAME",
        "SetIdentifier": "docker-compose-dc",
        "Weight": ${DC_WEIGHT},
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "${DC_IP}"
          }
        ]
      }
    }
  ]
}
EOF

log_info "Applying DNS changes..."
aws route53 change-resource-record-sets \
  --hosted-zone-id ${DNS_ZONE_ID} \
  --change-batch file://route53-update.json

log_success "DNS routing updated (${CUTOVER_PERCENT}% K8s / $((100 - CUTOVER_PERCENT))% Docker Compose)"

# ===== PHASE 4: MONITOR TRAFFIC SHIFT =====
log_info "Phase 4: Monitoring traffic shift"

echo ""
echo -e "${BLUE}=== K8s Metrics ===${NC}"
kubectl top pods -n code-server-enterprise | head -10

echo ""
echo -e "${BLUE}=== API Pod Logs (Last 20 lines) ===${NC}"
kubectl logs -n code-server-enterprise ${API_POD} --tail=20

# ===== PHASE 5: HEALTH CHECKS =====
log_info "Phase 5: Running health checks"

HEALTH_CHECK_COUNT=0
HEALTH_CHECK_MAX=10

while [ ${HEALTH_CHECK_COUNT} -lt ${HEALTH_CHECK_MAX} ]; do
  HEALTH_CHECK_COUNT=$((HEALTH_CHECK_COUNT + 1))
  
  # Test API endpoint
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://${PRIMARY_DOMAIN}/health 2>/dev/null || echo "000")
  
  if [ "${HTTP_CODE}" = "200" ]; then
    log_success "API health check passed (${HEALTH_CHECK_COUNT}/${HEALTH_CHECK_MAX})"
  else
    log_warn "API health check returned ${HTTP_CODE} (${HEALTH_CHECK_COUNT}/${HEALTH_CHECK_MAX})"
  fi
  
  # Check pod restart count
  RESTART_COUNT=$(kubectl get pods -n code-server-enterprise -l app=api -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')
  if [ "${RESTART_COUNT}" -gt 3 ]; then
    log_warn "High restart count detected: ${RESTART_COUNT}"
  fi
  
  sleep 5
done

log_success "Health checks completed"

# ===== PHASE 6: ERROR RATE MONITORING =====
log_info "Phase 6: Checking error rates"

# Get error count from API logs
ERROR_COUNT=$(kubectl logs -n code-server-enterprise ${API_POD} --tail=1000 | grep -ic "error" || echo "0")
TOTAL_LINES=$(kubectl logs -n code-server-enterprise ${API_POD} --tail=1000 | wc -l)

if [ ${TOTAL_LINES} -gt 0 ]; then
  ERROR_RATE=$((ERROR_COUNT * 100 / TOTAL_LINES))
  log_info "Error rate: ${ERROR_RATE}% (${ERROR_COUNT}/${TOTAL_LINES})"
  
  if [ ${ERROR_RATE} -gt 5 ]; then
    log_warn "High error rate detected! Consider rollback"
  fi
fi

# ===== PHASE 7: COMPLETION SUMMARY =====
log_success "Traffic cutover to ${CUTOVER_PERCENT}% complete!"

echo ""
echo -e "${BLUE}=== CUTOVER SUMMARY ===${NC}"
echo -e "${GREEN}DNS Updated:${NC} Yes"
echo -e "${GREEN}K8s Weight:${NC} ${K8S_WEIGHT}%"
echo -e "${GREEN}Docker Compose Weight:${NC} ${DC_WEIGHT}%"
echo -e "${GREEN}NLB Endpoint:${NC} ${NLB_ENDPOINT}"
echo -e "${GREEN}Running Pods:${NC} ${RUNNING_PODS}"
echo -e "${GREEN}Error Rate:${NC} ${ERROR_RATE}% (acceptable if <0.5%)"

echo ""
if [ "${CUTOVER_PERCENT}" = "100" ]; then
  log_success "Full traffic cutover complete!"
  log_info "Next: Monitor for 24 hours, then decommission Docker Compose"
else
  log_info "Next: Run 'bash cutover.sh $((CUTOVER_PERCENT + 40))' in 30 minutes"
fi

rm -f route53-update.json
