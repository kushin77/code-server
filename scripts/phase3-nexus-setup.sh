#!/bin/bash
# Phase 3 Issue #175 - Nexus Repository Manager (Dependency Caching)
# Enterprise-grade artifact repository for Maven, NPM, Docker, Python, etc.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NEXUS_VERSION=${NEXUS_VERSION:-"3.60.0-02"}
NAMESPACE="nexus"
NEXUS_DOMAIN=${NEXUS_DOMAIN:-"nexus.192.168.168.31.nip.io"}
STORAGE_SIZE=${STORAGE_SIZE:-"200Gi"}

print_header() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_step() { echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# ============================================================================
# Prerequisites Check
# ============================================================================

check_prerequisites() {
    print_header "Prerequisites Check"
    
    local errors=0
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found"
        ((errors++))
    else
        print_success "kubectl available"
    fi
    
    if ! command -v helm &> /dev/null; then
        print_error "Helm not installed"
        ((errors++))
    else
        print_success "Helm available"
    fi
    
    if [ $errors -gt 0 ]; then
        return 1
    fi
}

# ============================================================================
# Nexus Installation via Helm
# ============================================================================

install_nexus() {
    print_header "Nexus Repository Manager Installation"
    
    print_step "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    print_step "Adding Sonatype Helm repository..."
    helm repo add sonatype https://sonatype.github.io/helm3-charts || true
    helm repo update
    
    print_step "Installing Nexus Repository Manager..."
    
    helm upgrade --install nexus sonatype/nexus-repository-manager \
        --namespace "$NAMESPACE" \
        --set nexus.docker.enabled=true \
        --set nexus.imageTag="$NEXUS_VERSION" \
        --set persistence.storageSize="$STORAGE_SIZE" \
        --set persistence.storageClass="local-path" \
        --set persistence.accessMode="ReadWriteOnce" \
        --set replicaCount=1 \
        --set resources.requests.cpu=1000m \
        --set resources.requests.memory=2Gi \
        --set resources.limits.cpu=2000m \
        --set resources.limits.memory=4Gi \
        --wait
    
    print_success "Nexus installed"
}

# ============================================================================
# Repository Configuration
# ============================================================================

configure_repositories() {
    print_header "Repository Configuration"
    
    print_step "Creating repository configuration script..."
    
    # Wait for Nexus to be ready
    kubectl wait --for=condition=ready pod \
        -l app=nexus-repository-manager \
        -n "$NAMESPACE" \
        --timeout=300s
    
    print_step "Configuring artifact repositories..."
    
    # Get Nexus pod
    local nexus_pod=$(kubectl get pods -n "$NAMESPACE" -l app=nexus-repository-manager -o jsonpath='{.items[0].metadata.name}')
    
    # Configure NPM repositories
    kubectl exec -it "$nexus_pod" -n "$NAMESPACE" -- bash -c '
cat > /tmp/configure-npm.sh <<EOF
#!/bin/bash
curl -X POST http://localhost:8081/service/rest/v1/repositories/npm/proxy \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"npm-proxy\",
    \"online\": true,
    \"storage\": {
      \"blobStoreName\": \"default\",
      \"strictContentTypeValidation\": false
    },
    \"proxy\": {
      \"remoteUrl\": \"https://registry.npmjs.org\",
      \"contentMaxAge\": 1440,
      \"metadataMaxAge\": 1440
    },
    \"negativeCache\": {
      \"enabled\": true,
      \"timeToLive\": 1440
    }
  }"
EOF
bash /tmp/configure-npm.sh
    '
    
    # Configure Docker repositories
    kubectl exec -it "$nexus_pod" -n "$NAMESPACE" -- bash -c '
curl -X POST http://localhost:8081/service/rest/v1/repositories/docker/hosted \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"docker-hosted\",
    \"online\": true,
    \"storage\": {
      \"blobStoreName\": \"default\",
      \"strictContentTypeValidation\": false,
      \"writePolicy\": \"allow_once\"
    },
    \"docker\": {
      \"httpPort\": 8081,
      \"httpsPort\": 8443,
      \"forceBasicAuth\": false,
      \"v1Enabled\": false
    }
  }"
    '
    
    # Configure Maven repositories
    kubectl exec -it "$nexus_pod" -n "$NAMESPACE" -- bash -c '
curl -X POST http://localhost:8081/service/rest/v1/repositories/maven/proxy \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"maven-central-proxy\",
    \"online\": true,
    \"storage\": {
      \"blobStoreName\": \"default\",
      \"strictContentTypeValidation\": false
    },
    \"proxy\": {
      \"remoteUrl\": \"https://repo1.maven.org/maven2\",
      \"contentMaxAge\": 1440,
      \"metadataMaxAge\": 1440
    }
  }"
    '
    
    print_success "Repositories configured"
}

# ============================================================================
# Ingress & Network Configuration
# ============================================================================

configure_ingress() {
    print_header "Ingress & Network Configuration"
    
    print_step "Creating Ingress for Nexus UI..."
    
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nexus-ingress
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/ingress.class: "traefik"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
    - hosts:
        - $NEXUS_DOMAIN
      secretName: nexus-tls
  rules:
    - host: $NEXUS_DOMAIN
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nexus-repository-manager
                port:
                  number: 8081
EOF
    
    print_success "Ingress configured at $NEXUS_DOMAIN"
}

# ============================================================================
# RBAC & Security
# ============================================================================

setup_rbac_and_security() {
    print_header "RBAC & Security Configuration"
    
    print_step "Creating Nexus service account..."
    
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nexus
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: nexus-role
  namespace: $NAMESPACE
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: nexus-rolebinding
  namespace: $NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: nexus-role
subjects:
  - kind: ServiceAccount
    name: nexus
    namespace: $NAMESPACE
EOF
    
    print_step "Creating Nexus credentials secret..."
    
    kubectl create secret generic nexus-admin \
        --from-literal=username=admin \
        --from-literal=password=Nexus12345 \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    print_success "Security configured"
}

# ============================================================================
# Backup & Recovery
# ============================================================================

configure_backup() {
    print_header "Backup & Recovery Configuration"
    
    print_step "Configuring automated backups..."
    
    kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nexus-backup
  namespace: $NAMESPACE
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: bitnami/kubectl:latest
              command:
                - /bin/sh
                - -c
                - |
                  POD=\$(kubectl get pods -n $NAMESPACE -l app=nexus-repository-manager -o jsonpath='{.items[0].metadata.name}')
                  kubectl exec -n $NAMESPACE \$POD -- /bin/bash -c 'cd /nexus-data && tar czf backup-\$(date +%Y%m%d).tar.gz .'
                  kubectl cp $NAMESPACE/\$POD:/nexus-data/backup-\$(date +%Y%m%d).tar.gz /backups/nexus-\$(date +%Y%m%d).tar.gz
          restartPolicy: OnFailure
EOF
    
    print_success "Backup job configured"
}

# ============================================================================
# Integration with CI/CD
# ============================================================================

configure_cicd_integration() {
    print_header "CI/CD Integration Configuration"
    
    print_step "Creating .npmrc for NPM integration..."
    
    cat > ~/.npmrc <<'EOF'
registry=http://nexus-repository-manager.nexus.svc.cluster.local:8081/repository/npm/
strict-ssl=false
always-auth=true
_auth=YWRtaW46TmV4dXMxMjM0NQ==
email=ci@kushnir.cloud
EOF
    
    print_step "Creating Maven settings.xml..."
    
    mkdir -p ~/.m2
    cat > ~/.m2/settings.xml <<'EOF'
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 
  http://maven.apache.org/xsd/settings-1.0.0.xsd">
  
  <servers>
    <server>
      <id>nexus</id>
      <username>admin</username>
      <password>Nexus12345</password>
    </server>
  </servers>
  
  <mirrors>
    <mirror>
      <id>nexus</id>
      <mirrorOf>*</mirrorOf>
      <url>http://nexus-repository-manager.nexus.svc.cluster.local:8081/repository/maven-central/</url>
    </mirror>
  </mirrors>
</settings>
EOF
    
    print_step "Creating Docker config for Nexus..."
    
    mkdir -p ~/.docker
    cat >> ~/.docker/config.json <<'EOF'
{
  "auths": {
    "nexus-repository-manager.nexus.svc.cluster.local": {
      "auth": "YWRtaW46TmV4dXMxMjM0NQ==",
      "email": "ci@kushnir.cloud"
    }
  }
}
EOF
    
    print_success "CI/CD integration configured"
}

# ============================================================================
# Health Check
# ============================================================================

health_check() {
    print_header "Health Check"
    
    local errors=0
    
    print_step "Checking Nexus pod status..."
    if kubectl get pods -n "$NAMESPACE" -l app=nexus-repository-manager &> /dev/null; then
        local ready=$(kubectl get pods -n "$NAMESPACE" -l app=nexus-repository-manager -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
        if [ "$ready" == "True" ]; then
            print_success "Nexus pod ready"
        else
            print_error "Nexus pod not ready"
            ((errors++))
        fi
    fi
    
    print_step "Checking Nexus service..."
    if kubectl get svc -n "$NAMESPACE" nexus-repository-manager &> /dev/null; then
        print_success "Nexus service available"
    else
        print_error "Nexus service not found"
        ((errors++))
    fi
    
    print_step "Checking storage..."
    if kubectl get pvc -n "$NAMESPACE" nexus-repository-manager &> /dev/null; then
        local storage=$(kubectl get pvc -n "$NAMESPACE" nexus-repository-manager -o jsonpath='{.status.capacity.storage}')
        print_success "Storage configured: $storage"
    else
        print_error "Storage not configured"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        print_success "All health checks passed"
        return 0
    else
        print_error "Health check failed"
        return 1
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_header "Phase 3 Issue #175: Nexus Repository Manager Setup"
    
    local start_time=$(date +%s)
    
    check_prerequisites || exit 1
    install_nexus || exit 1
    configure_repositories || exit 1
    configure_ingress || exit 1
    setup_rbac_and_security || exit 1
    configure_backup || exit 1
    configure_cicd_integration || exit 1
    health_check || exit 1
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_header "✅ Nexus Repository Setup Complete"
    print_success "Total deployment time: ${duration}s"
    print_info "Access Nexus UI at: http://$NEXUS_DOMAIN"
    print_info "Default credentials: admin / Nexus12345"
}

main "$@"
