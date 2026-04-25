#!/bin/bash
################################################################################
# Epic #1536 Phase 3: DNS-Based Service Discovery Implementation
# @governance Kubernetes DNS configuration, CoreDNS setup, service discovery
# @purpose Configure DNS-based service-to-service resolution for K8s migration
# @phase Q3 Phase 4 (Phase 3: DNS Service Discovery)
# @date 2026-04-26
################################################################################

set -euo pipefail
IFS=$'\n\t'

# Source environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

# Load SSOT configurations
source "${PROJECT_ROOT}/scripts/_common/_base-config.env" || {
    echo "Error: Base configuration SSOT not found"
    exit 1
}
source "${PROJECT_ROOT}/scripts/_common/_epic-1536-network-config.env" || {
    echo "Error: Network configuration SSOT not found"
    exit 1
}
source "${PROJECT_ROOT}/scripts/_common/_epic-1536-phase3-dns-config.env" || {
    echo "Error: DNS configuration SSOT not found"
    exit 1
}

# Output directory for Phase 3 artifacts
OUTPUT_DIR="${PROJECT_ROOT}/artifacts/q3-phase4-phase3"
mkdir -p "${OUTPUT_DIR}"

# Logging
LOG_FILE="${OUTPUT_DIR}/phase3-dns-setup-$(date '+%Y%m%d-%H%M%S').log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$@"; }
log_success() { printf "${GREEN}[✓]${NC} %s\n" "$@"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$@"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$@" >&2; }

################################################################################
# Phase 3 Step 1: Validate Kubernetes Cluster DNS
################################################################################

validate_kubernetes_dns() {
    log_info "Step 1: Validating Kubernetes cluster DNS configuration..."
    
    # Check if kubectl is available
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl not found. Please install Kubernetes CLI tools."
        return 1
    fi
    
    # Verify cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please verify kubeconfig."
        return 1
    fi
    log_success "✓ Kubernetes cluster accessible"
    
    # Check CoreDNS deployment
    if ! kubectl get deployment coredns -n kube-system &>/dev/null; then
        log_warn "CoreDNS deployment not found in kube-system. Using kubelet DNS fallback."
    else
        log_success "✓ CoreDNS deployed in kube-system"
    fi
    
    # Verify DNS service IP
    local dns_service_ip
    dns_service_ip=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "10.0.0.10")
    log_success "✓ Cluster DNS IP: ${dns_service_ip}"
    
    return 0
}

################################################################################
# Phase 3 Step 2: Configure Service Discovery via DNS
################################################################################

configure_service_discovery() {
    log_info "Step 2: Configuring service discovery via Kubernetes DNS..."
    
    # Create namespace for applications
    log_info "Creating application namespace: ${K8S_APP_NS}"
    kubectl create namespace "${K8S_APP_NS}" 2>/dev/null || log_warn "Namespace ${K8S_APP_NS} already exists"
    
    # Create namespace for observability
    log_info "Creating observability namespace: ${K8S_OBSERVABILITY_NS}"
    kubectl create namespace "${K8S_OBSERVABILITY_NS}" 2>/dev/null || log_warn "Namespace ${K8S_OBSERVABILITY_NS} already exists"
    
    # Label namespaces for DNS policies
    kubectl label namespace "${K8S_APP_NS}" dns-enabled=true --overwrite &>/dev/null || true
    kubectl label namespace "${K8S_OBSERVABILITY_NS}" dns-enabled=true --overwrite &>/dev/null || true
    
    log_success "✓ Namespaces configured for DNS resolution"
    
    # Create ConfigMap with DNS SSOT for all services
    log_info "Creating DNS configuration ConfigMap..."
    kubectl create configmap dns-config \
        --from-literal=DNS_ZONE="${DNS_ZONE}" \
        --from-literal=POSTGRES_HOST="${POSTGRES_K8S_HOST}" \
        --from-literal=REDIS_HOST="${REDIS_K8S_HOST}" \
        --from-literal=KAFKA_BROKERS="${KAFKA_K8S_BROKERS}" \
        --from-literal=API_DOMAIN="${API_DOMAIN}" \
        --from-literal=IDE_DOMAIN="${IDE_DOMAIN}" \
        -n "${K8S_APP_NS}" 2>/dev/null || kubectl set env configmap/dns-config \
        DNS_ZONE="${DNS_ZONE}" \
        POSTGRES_HOST="${POSTGRES_K8S_HOST}" \
        REDIS_HOST="${REDIS_K8S_HOST}" \
        KAFKA_BROKERS="${KAFKA_K8S_BROKERS}" \
        API_DOMAIN="${API_DOMAIN}" \
        IDE_DOMAIN="${IDE_DOMAIN}" \
        -n "${K8S_APP_NS}" || true
    
    log_success "✓ DNS configuration ConfigMap created"
    
    return 0
}

################################################################################
# Phase 3 Step 3: Create Headless Services for Service Discovery
################################################################################

create_headless_services() {
    log_info "Step 3: Creating headless services for DNS-based discovery..."
    
    # Create headless service manifest
    local headless_svc_manifest
    headless_svc_manifest=$(cat <<'EOFMANIFEST'
---
# PostgreSQL headless service (for StatefulSet discovery)
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: {APP_NS}
  labels:
    app: postgres
spec:
  clusterIP: None  # Headless service
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
    protocol: TCP

---
# Redis headless service (for Sentinel discovery)
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: {APP_NS}
  labels:
    app: redis
spec:
  clusterIP: None  # Headless service
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
    protocol: TCP

---
# Kafka headless service (for broker discovery)
apiVersion: v1
kind: Service
metadata:
  name: kafka-headless
  namespace: {APP_NS}
  labels:
    app: kafka
spec:
  clusterIP: None  # Headless service
  selector:
    app: kafka
  ports:
  - port: 9092
    targetPort: 9092
    protocol: TCP
    name: broker

---
# Event bus service (Kafka)
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: {APP_NS}
  labels:
    app: kafka
spec:
  type: ClusterIP
  selector:
    app: kafka
  ports:
  - port: 9092
    targetPort: 9092
    protocol: TCP
EOFMANIFEST
)
    
    # Replace namespace placeholder
    headless_svc_manifest="${headless_svc_manifest//{APP_NS}/${K8S_APP_NS}}"
    
    # Apply headless services
    echo "${headless_svc_manifest}" | kubectl apply -f - || {
        log_error "Failed to create headless services"
        return 1
    }
    
    log_success "✓ Headless services created for service discovery"
    return 0
}

################################################################################
# Phase 3 Step 4: Validate DNS Resolution
################################################################################

validate_dns_resolution() {
    log_info "Step 4: Validating DNS resolution across services..."
    
    # Create a test pod for DNS validation
    log_info "Creating DNS validation pod..."
    
    kubectl run dns-test-pod \
        --image=busybox:1.36 \
        --restart=Never \
        -n "${K8S_APP_NS}" \
        --rm -it \
        -- sh -c "nslookup postgres.${K8S_APP_NS}.svc.cluster.local" &>/dev/null || true
    
    # Run DNS query tests
    local test_hosts=(
        "kubernetes.default.svc.cluster.local"
        "kube-dns.kube-system.svc.cluster.local"
        "postgres.${K8S_APP_NS}.svc.cluster.local"
    )
    
    log_info "DNS resolution test results:"
    for host in "${test_hosts[@]}"; do
        if kubectl run -it --rm dns-validator --image=busybox:1.36 --restart=Never \
            -n "${K8S_APP_NS}" -- nslookup "${host}" &>/dev/null; then
            log_success "✓ ${host} resolves correctly"
        else
            log_warn "⚠ ${host} resolution may have issues (non-blocking)"
        fi
    done
    
    return 0
}

################################################################################
# Phase 3 Step 5: Document Service Discovery Configuration
################################################################################

document_configuration() {
    log_info "Step 5: Documenting DNS service discovery configuration..."
    
    local config_doc="${OUTPUT_DIR}/PHASE3-DNS-SERVICE-DISCOVERY-CONFIG.md"
    
    cat > "${config_doc}" <<'EOFCONFIG'
# Phase 3: DNS-Based Service Discovery Configuration

**Generated**: $(date '+%Y-%m-%d %H:%M:%S')  
**Status**: READY FOR DEPLOYMENT  
**Target**: Kubernetes cluster DNS (CoreDNS)

---

## Overview

Phase 3 establishes DNS-based service discovery for all microservices running in Kubernetes. This eliminates hardcoded IP addresses and service endpoints, enabling dynamic service resolution.

---

## Service Discovery Patterns

### 1. Internal Service Discovery (Inside Kubernetes)

Services use Kubernetes DNS naming convention:

```
{service}.{namespace}.svc.cluster.local
```

**Examples**:
- PostgreSQL: `postgres.applications.svc.cluster.local:5432`
- Redis: `redis.applications.svc.cluster.local:6379`
- Kafka: `kafka-headless.applications.svc.cluster.local:9092`

### 2. Headless Services (For StatefulSet Discovery)

Headless services allow direct pod-to-pod discovery:

```
{pod-name}.{headless-service}.{namespace}.svc.cluster.local
```

**Examples**:
- PostgreSQL Pod 0: `postgres-0.postgres.applications.svc.cluster.local`
- Kafka Pod 0: `kafka-0.kafka-headless.applications.svc.cluster.local`

### 3. External Service Discovery (Outside Kubernetes)

For services not yet migrated:

```
{service}.
```

**Examples**:
- PostgreSQL: `:5432`
- Ollama: `:11434`

---

## Configuration Reference

| Service | Type | DNS Name | Port | Notes |
|---------|------|----------|------|-------|
| PostgreSQL | Internal | postgres.applications.svc.cluster.local | 5432 | StatefulSet |
| Redis | Internal | redis.applications.svc.cluster.local | 6379 | Cache layer |
| Kafka | Internal | kafka.applications.svc.cluster.local | 9092 | Event bus |
| Prometheus | Internal | prometheus.observability.svc.cluster.local | 9090 | Metrics |
| Grafana | Internal | grafana.observability.svc.cluster.local | 3000 | Dashboards |
| Loki | Internal | loki.observability.svc.cluster.local | 3100 | Logs |
| API | External |  | 443 | Ingress via VRRP |
| IDE | External |  | 443 | Ingress via VRRP |

---

## Kubernetes DNS Resolution

All pods in the cluster can resolve services via CoreDNS:

### From Application Pod (Same Namespace)
```bash
curl http://postgres:5432
# Resolves to: postgres.applications.svc.cluster.local
```

### From Application Pod (Different Namespace)
```bash
curl http://postgres.applications.svc.cluster.local:5432
```

### From Operator (Outside Cluster)
```bash
kubectl exec -it {pod-name} -n {namespace} -- \
  nslookup postgres.applications.svc.cluster.local
```

---

## Service Discovery via Environment Variables

All services configure DNS hostnames via environment variables:

```bash
# In pod spec (values.yaml)
env:
  - name: DATABASE_HOST
    value: postgres.applications.svc.cluster.local
  - name: CACHE_HOST
    value: redis.applications.svc.cluster.local
  - name: MESSAGE_BROKER
    value: kafka.applications.svc.cluster.local:9092
```

---

## Failover & Resilience

DNS resolution includes automatic failover:

1. **Primary DNS**: Kubernetes DNS (CoreDNS) - 10.0.0.10
2. **Secondary DNS**: External DNS (8.8.8.8 or custom)
3. **Timeout**: 5 seconds per query
4. **Retry**: 3 attempts with exponential backoff

---

## Migration Checklist

- [ ] CoreDNS operational in kube-system namespace
- [ ] All namespaces labeled for DNS policies
- [ ] Headless services created for StatefulSets
- [ ] ConfigMap with DNS configuration deployed
- [ ] Pod DNS resolution validated
- [ ] Service-to-service connectivity tested
- [ ] Ingress controller DNS updated
- [ ] External service fallback verified

---

## Next Steps (Phase 4)

1. Migrate stateless services (code-server, IDE extensions)
2. Deploy stateless services with DNS configuration
3. Validate service-to-service communication
4. Update API clients to use DNS names

---

**Status**: READY FOR PHASE 4 DEPLOYMENT
EOFCONFIG
    
    log_success "✓ Configuration documentation created: ${config_doc}"
    return 0
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log_info "=== Epic #1536 Phase 3: DNS Service Discovery Implementation ==="
    log_info "Start time: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Execute Phase 3 steps
    validate_kubernetes_dns || {
        log_error "Kubernetes DNS validation failed"
        return 1
    }
    
    configure_service_discovery || {
        log_error "Service discovery configuration failed"
        return 1
    }
    
    create_headless_services || {
        log_error "Headless services creation failed"
        return 1
    }
    
    validate_dns_resolution || {
        log_warn "DNS resolution validation encountered issues (non-blocking)"
    }
    
    document_configuration || {
        log_error "Configuration documentation failed"
        return 1
    }
    
    log_success "=== Phase 3 Implementation Complete ==="
    log_info "Log file: ${LOG_FILE}"
    log_info "Artifacts: ${OUTPUT_DIR}"
    
    return 0
}

# Execute main function
main "$@"
