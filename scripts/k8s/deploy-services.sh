#!/bin/bash
# scripts/k8s/deploy-services.sh
# Automated Helm deployment of all code-server-enterprise services
# Usage: bash deploy-services.sh [environment]

set -euo pipefail

ENVIRONMENT="${1:-production}"
NAMESPACE="code-server-enterprise"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "Starting service deployment for ${ENVIRONMENT}"

# ===== PHASE 1: VERIFY PREREQUISITES =====
log_info "Phase 1: Verifying prerequisites"

if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
  log_error "Namespace ${NAMESPACE} does not exist"
  exit 1
fi

if ! kubectl get secret database-credentials -n ${NAMESPACE} &> /dev/null; then
  log_error "Secrets not configured. Run: kubectl create secret generic database-credentials ..."
  exit 1
fi

if ! helm list -n ${NAMESPACE} &> /dev/null; then
  log_warn "Helm repository not initialized"
fi

log_success "All prerequisites verified"

# ===== PHASE 2: HELM CHART VALIDATION =====
log_info "Phase 2: Validating Helm chart"

cd helm/code-server-enterprise

helm lint .
if [ $? -ne 0 ]; then
  log_error "Helm chart validation failed"
  exit 1
fi

log_success "Helm chart validated"

# ===== PHASE 3: DEPLOY STATELESS SERVICES =====
log_info "Phase 3: Deploying stateless services"

declare -a SERVICES=("frontend" "api" "auth-server" "control-plane" "edge-agent")

for SERVICE in "${SERVICES[@]}"; do
  log_info "Deploying ${SERVICE}..."
  
  helm upgrade --install ${SERVICE} . \
    --namespace ${NAMESPACE} \
    --values values.${ENVIRONMENT}.yaml \
    --set services.${SERVICE}.enabled=true \
    --wait --timeout 5m
  
  if [ $? -eq 0 ]; then
    log_success "${SERVICE} deployed"
    
    # Verify deployment
    REPLICAS=$(kubectl get deployment ${SERVICE} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}')
    log_info "${SERVICE} ready replicas: ${REPLICAS}"
  else
    log_error "${SERVICE} deployment failed"
    exit 1
  fi
done

# ===== PHASE 4: DEPLOY DATA SERVICES =====
log_info "Phase 4: Deploying data services"

DATA_SERVICES=("postgres" "redis" "redpanda")

for SERVICE in "${DATA_SERVICES[@]}"; do
  log_info "Deploying ${SERVICE} StatefulSet..."
  
  kubectl apply -f ../manifests/${SERVICE}-statefulset.yaml
  
  if [ $? -eq 0 ]; then
    log_success "${SERVICE} StatefulSet created"
    
    # Wait for StatefulSet to be ready
    kubectl rollout status statefulset/${SERVICE} -n ${NAMESPACE} --timeout=10m
    log_success "${SERVICE} is ready"
  else
    log_error "${SERVICE} StatefulSet deployment failed"
    exit 1
  fi
done

# ===== PHASE 5: DEPLOY SUPPORTING SERVICES =====
log_info "Phase 5: Deploying supporting services"

kubectl apply -f ../manifests/reputation-engine-deployment.yaml
kubectl apply -f ../manifests/activity-feed-deployment.yaml
kubectl apply -f ../manifests/execution-scheduler-deployment.yaml
kubectl apply -f ../manifests/memory-engine-deployment.yaml

log_success "Supporting services deployed"

# ===== PHASE 6: CREATE INGRESS =====
log_info "Phase 6: Creating Ingress resources"

kubectl apply -f ../manifests/ingress.yaml

# Wait for SSL certificate
log_info "Waiting for SSL certificate issuance..."
ATTEMPTS=0
MAX_ATTEMPTS=60
until kubectl get certificate -n ${NAMESPACE} | grep -q "True"; do
  if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
    log_warn "Certificate not issued within timeout, continuing..."
    break
  fi
  ATTEMPTS=$((ATTEMPTS + 1))
  sleep 10
done

log_success "Ingress configured"

# ===== PHASE 7: VERIFICATION =====
log_info "Phase 7: Verifying deployments"

echo ""
echo -e "${BLUE}=== Pod Status ===${NC}"
kubectl get pods -n ${NAMESPACE}

echo ""
echo -e "${BLUE}=== Service Status ===${NC}"
kubectl get svc -n ${NAMESPACE}

echo ""
echo -e "${BLUE}=== Deployment Status ===${NC}"
kubectl get deployments -n ${NAMESPACE}

echo ""
echo -e "${BLUE}=== StatefulSet Status ===${NC}"
kubectl get statefulsets -n ${NAMESPACE}

# Count running pods
RUNNING_PODS=$(kubectl get pods -n ${NAMESPACE} --field-selector=status.phase=Running --no-headers | wc -l)
TOTAL_PODS=$(kubectl get pods -n ${NAMESPACE} --no-headers | wc -l)

echo ""
if [ ${RUNNING_PODS} -eq ${TOTAL_PODS} ]; then
  log_success "All ${RUNNING_PODS} pods are running"
else
  log_warn "${RUNNING_PODS}/${TOTAL_PODS} pods running. Waiting..."
  sleep 30
  kubectl get pods -n ${NAMESPACE}
fi

# ===== PHASE 8: HEALTH CHECKS =====
log_info "Phase 8: Running health checks"

# Check API endpoint
API_POD=$(kubectl get pods -n ${NAMESPACE} -l app=api -o jsonpath='{.items[0].metadata.name}')
if [ -n "${API_POD}" ]; then
  log_info "Testing API health endpoint"
  kubectl exec -n ${NAMESPACE} ${API_POD} -- curl -s http://localhost:3100/health | head -c 100
  echo ""
  log_success "API responding"
fi

# Check database connectivity
POSTGRES_POD=$(kubectl get pods -n ${NAMESPACE} -l app=postgres -o jsonpath='{.items[0].metadata.name}')
if [ -n "${POSTGRES_POD}" ]; then
  log_info "Testing PostgreSQL connectivity"
  kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- psql -U postgres -c "SELECT version();" | head -2
  log_success "PostgreSQL connected"
fi

# ===== PHASE 9: RESOURCE MONITORING =====
log_info "Phase 9: Checking resource usage"

echo ""
echo -e "${BLUE}=== Node Status ===${NC}"
kubectl top nodes

echo ""
echo -e "${BLUE}=== Pod Resource Usage ===${NC}"
kubectl top pods -n ${NAMESPACE}

# ===== PHASE 10: SUMMARY =====
log_success "Service deployment complete!"

echo ""
echo -e "${BLUE}=== DEPLOYMENT SUMMARY ===${NC}"
echo -e "${GREEN}Environment:${NC} ${ENVIRONMENT}"
echo -e "${GREEN}Namespace:${NC} ${NAMESPACE}"
echo -e "${GREEN}Services Deployed:${NC} ${#SERVICES[@]} stateless + ${#DATA_SERVICES[@]} data"
echo -e "${GREEN}Total Pods Running:${NC} ${RUNNING_PODS}/${TOTAL_PODS}"

echo ""
echo "Next steps:"
echo "1. Update DNS records to point to Ingress NLB"
echo "2. Monitor logs: kubectl logs -n ${NAMESPACE} -l app=api -f"
echo "3. Check metrics: kubectl top pods -n ${NAMESPACE}"
echo "4. Run integration tests: bash scripts/integration-tests.sh"

cd - > /dev/null
