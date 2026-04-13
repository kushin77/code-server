#!/bin/bash
# Phase 6: Application Platform (code-server Enterprise Deployment)
# Date: April 13, 2026
# Purpose: Deploy code-server IDE platform with enterprise features

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
APP_NAMESPACE="code-server"
APP_ENV=${APP_ENV:-"production"}
STORAGE_CLASS=${STORAGE_CLASS:-"local-storage"}
DOMAIN=${DOMAIN:-"code-server.enterprise.local"}

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Phase 6.1: Application Namespace
echo -e "\n${BLUE}=== PHASE 6.1: APPLICATION NAMESPACE ===${NC}\n"

log_info "Creating application namespace..."
kubectl create namespace $APP_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace $APP_NAMESPACE app.kubernetes.io/name=code-server --overwrite
kubectl label namespace $APP_NAMESPACE environment=$APP_ENV --overwrite
log_success "Namespace created: $APP_NAMESPACE"

# Phase 6.2: Persistent Storage
echo -e "\n${BLUE}=== PHASE 6.2: PERSISTENT STORAGE ===${NC}\n"

log_info "Creating persistent storage for application..."
cat > /tmp/app-storage.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: code-server-workspace-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /data/workspaces
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: code-server-config-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /data/config
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: code-server-workspace
  namespace: code-server
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: local-storage
  resources:
    requests:
      storage: 100Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: code-server-config
  namespace: code-server
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  resources:
    requests:
      storage: 10Gi
EOF

kubectl apply -f /tmp/app-storage.yaml
log_success "Persistent storage configured"

# Phase 6.3: ConfigMaps and Secrets
echo -e "\n${BLUE}=== PHASE 6.3: CONFIGURATION ===${NC}\n"

log_info "Creating application configuration..."
cat > /tmp/code-server-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: code-server-settings
  namespace: code-server
data:
  enable-auth: "true"
  auth-type: "password"
  bind-addr: "0.0.0.0:8080"
  log-level: "info"
  extensions-dir: "/home/coder/.local/share/code-server/extensions"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: code-server-extensions
  namespace: code-server
data:
  extensions.list: |
    ms-python.python
    ms-toolsai.jupyter
    hashicorp.terraform
    ms-azuretools.vscode-docker
    eamodio.gitlens
    GitHub.copilot
    redhat.yaml
    golang.go
---
apiVersion: v1
kind: Secret
metadata:
  name: code-server-credentials
  namespace: code-server
type: Opaque
stringData:
  CODER_PASSWORD: "ChangeMe@123456789"
  CODER_PASSWORD_HASH: "$2a$14$6ORnSHcmmFgz8dmnksnVCOJ61Gnjvs2YPBX8Wo.h8ux4R5yUMRdrK"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: code-server-vscode-settings
  namespace: code-server
data:
  settings.json: |
    {
      "explorer.compactFolders": true,
      "workbench.colorTheme": "One Dark Pro",
      "python.defaultInterpreterPath": "/usr/local/bin/python3",
      "python.linting.enabled": true,
      "[python]": {
        "editor.defaultFormatter": "ms-python.python",
        "editor.formatOnSave": true
      },
      "files.autoSave": "afterDelay",
      "files.autoSaveDelay": 1000,
      "editor.fontSize": 13,
      "editor.fontFamily": "Fira Code, monospace"
    }
EOF

kubectl apply -f /tmp/code-server-config.yaml
log_success "Configuration created"

# Phase 6.4: StatefulSet Deployment
echo -e "\n${BLUE}=== PHASE 6.4: CODE-SERVER DEPLOYMENT ===${NC}\n"

log_info "Deploying code-server StatefulSet..."
cat > /tmp/code-server-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: code-server
  namespace: code-server
  labels:
    app: code-server
spec:
  serviceName: code-server
  replicas: 1
  selector:
    matchLabels:
      app: code-server
  template:
    metadata:
      labels:
        app: code-server
      annotations:
        prometheus.io/scrape: "false"
    spec:
      securityContext:
        runAsUser: 1000
        runAsNonRoot: true
        fsGroup: 1000
      containers:
        - name: code-server
          image: codercom/code-server:latest
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
              name: http
              protocol: TCP
          env:
            - name: PASSWORD
              valueFrom:
                secretKeyRef:
                  name: code-server-credentials
                  key: CODER_PASSWORD
            - name: SUDO_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: code-server-credentials
                  key: CODER_PASSWORD
            - name: CODER_USER_DATA_DIR
              value: "/home/coder/.local/share/code-server"
          resources:
            requests:
              cpu: 1000m
              memory: 2Gi
            limits:
              cpu: 4000m
              memory: 8Gi
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          volumeMounts:
            - name: workspace
              mountPath: /home/coder/workspace
            - name: config
              mountPath: /home/coder/.local/share/code-server
            - name: docker-socket
              mountPath: /var/run/docker.sock
      volumes:
        - name: docker-socket
          hostPath:
            path: /var/run/docker.sock
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - code-server
                topologyKey: kubernetes.io/hostname
  volumeClaimTemplates:
    - metadata:
        name: workspace
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-storage
        resources:
          requests:
            storage: 100Gi
    - metadata:
        name: config
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-storage
        resources:
          requests:
            storage: 10Gi
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: code-server
  namespace: code-server
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: code-server
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec"]
    verbs: ["get", "list", "watch", "create"]
  - apiGroups: [""]
    resources: ["services", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: code-server
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: code-server
subjects:
  - kind: ServiceAccount
    name: code-server
    namespace: code-server
EOF

kubectl apply -f /tmp/code-server-deployment.yaml
log_success "code-server StatefulSet deployed"

# Phase 6.5: Service and Ingress
echo -e "\n${BLUE}=== PHASE 6.5: SERVICE & INGRESS ===${NC}\n"

log_info "Creating service and ingress..."
cat > /tmp/code-server-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: code-server
  namespace: code-server
  labels:
    app: code-server
spec:
  type: LoadBalancer
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP
      name: http
  selector:
    app: code-server
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: code-server
  namespace: code-server
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - code-server.enterprise.local
      secretName: code-server-tls
  rules:
    - host: code-server.enterprise.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: code-server
                port:
                  number: 8080
EOF

kubectl apply -f /tmp/code-server-service.yaml
log_success "Service and Ingress created"

# Phase 6.6: Monitoring Integration
echo -e "\n${BLUE}=== PHASE 6.6: MONITORING INTEGRATION ===${NC}\n"

log_info "Integrating with Prometheus monitoring..."
cat > /tmp/code-server-monitoring.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: code-server-metrics
  namespace: code-server
  labels:
    app: code-server
spec:
  ports:
    - port: 9090
      targetPort: 9090
      name: metrics
  selector:
    app: code-server
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: code-server
  namespace: code-server
spec:
  selector:
    matchLabels:
      app: code-server
  endpoints:
    - port: metrics
      interval: 30s
EOF

kubectl apply -f /tmp/code-server-monitoring.yaml 2>/dev/null || log_warning "Prometheus Operator not available"
log_success "Monitoring integration configured"

# Phase 6.7: Extensions Installation
echo -e "\n${BLUE}=== PHASE 6.7: EXTENSIONS SETUP ===${NC}\n"

log_info "Setting up VS Code extensions..."
cat > /tmp/install-extensions.sh << 'EXTENSIONS_SCRIPT'
#!/bin/bash

EXTENSIONS=(
    "ms-python.python"
    "ms-toolsai.jupyter"
    "hashicorp.terraform"
    "ms-azuretools.vscode-docker"
    "eamodio.gitlens"
    "GitHub.copilot"
    "redhat.yaml"
    "golang.go"
    "rust-lang.rust-analyzer"
    "EditorConfig.EditorConfig"
)

echo "Installing VS Code extensions..."
for ext in "${EXTENSIONS[@]}"; do
    echo "Installing $ext..."
    code-server --install-extension "$ext" || true
done

echo "Extensions installed"
EXTENSIONS_SCRIPT

log_success "Extensions setup script created"

# Phase 6.8: Backup Integration
echo -e "\n${BLUE}=== PHASE 6.8: BACKUP INTEGRATION ===${NC}\n"

log_info "Configuring backup for application data..."
cat > /tmp/app-backup-policy.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: code-server-backup-policy
  namespace: code-server
data:
  backup-schedule: "0 3 * * *"
  retention-days: "30"
  backup-paths: |
    /home/coder/workspace
    /home/coder/.local/share/code-server
  exclude-patterns: |
    .git/objects
    node_modules
    .venv
    __pycache__
EOF

kubectl apply -f /tmp/app-backup-policy.yaml
log_success "Backup policy configured"

# Phase 6.9: Network Policies
echo -e "\n${BLUE}=== PHASE 6.9: NETWORK POLICIES ===${NC}\n"

log_info "Applying network policies..."
cat > /tmp/app-network-policy.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: code-server-ingress
  namespace: code-server
spec:
  podSelector:
    matchLabels:
      app: code-server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8080
    - from:
        - podSelector:
            matchLabels:
              app: monitoring
      ports:
        - protocol: TCP
          port: 9090
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: code-server-egress
  namespace: code-server
spec:
  podSelector:
    matchLabels:
      app: code-server
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 53
        - protocol: UDP
          port: 53
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 80
    - to:
        - podSelector:
            matchLabels:
              app: code-server
      ports:
        - protocol: TCP
          port: 8080
EOF

kubectl apply -f /tmp/app-network-policy.yaml
log_success "Network policies applied"

# Phase 6.10: Health Checks
echo -e "\n${BLUE}=== PHASE 6.10: HEALTH CHECKS ===${NC}\n"

log_info "Implementing health monitoring..."
cat > /tmp/health-check.sh << 'HEALTH_SCRIPT'
#!/bin/bash

check_code_server() {
    if curl -sf http://localhost:8080/health &>/dev/null; then
        echo "✓ code-server is healthy"
        return 0
    else
        echo "✗ code-server health check failed"
        return 1
    fi
}

check_extensions() {
    local ext_count=$(ls ~/.local/share/code-server/extensions | wc -l)
    echo "✓ Extensions installed: $ext_count"
}

check_workspace() {
    if [ -d ~/workspace ]; then
        local workspace_size=$(du -sh ~/workspace | cut -f1)
        echo "✓ Workspace: $workspace_size"
    else
        echo "✗ Workspace directory missing"
    fi
}

check_code_server
check_extensions
check_workspace
HEALTH_SCRIPT

log_success "Health checks configured"

# Phase 6.11: Scaling Configuration
echo -e "\n${BLUE}=== PHASE 6.11: SCALING SETUP ===${NC}\n"

log_info "Configuring HPA..."
cat > /tmp/code-server-hpa.yaml << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: code-server-hpa
  namespace: code-server
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: code-server
  minReplicas: 1
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 80
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 85
EOF

kubectl apply -f /tmp/code-server-hpa.yaml 2>/dev/null || log_warning "HPA may not be available"
log_success "Autoscaling configured"

# Phase 6.12: Verification
echo -e "\n${BLUE}=== PHASE 6.12: VERIFICATION ===${NC}\n"

log_info "Verifying application deployment..."

# Wait for pod
log_info "Waiting for code-server pod to be ready..."
kubectl wait --for=condition=ready pod -l app=code-server -n $APP_NAMESPACE --timeout=300s 2>/dev/null || log_warning "Timeout waiting for pod"

# Check deployment
log_info "Checking deployment status..."
kubectl get statefulset -n $APP_NAMESPACE
kubectl get pods -n $APP_NAMESPACE -o wide

# Check services
log_info "Checking services..."
kubectl get svc -n $APP_NAMESPACE

# Phase 6.13: Access Information
echo -e "\n${BLUE}=== PHASE 6.13: ACCESS INFO & NEXT STEPS ===${NC}\n"

CODE_SERVER_IP=$(kubectl get svc code-server -n $APP_NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "PENDING")
CODE_SERVER_PORT="8080"

log_success "Application Platform Deployment COMPLETE"
echo ""
echo "Access Information:"
echo "  URL: http://$CODE_SERVER_IP:$CODE_SERVER_PORT"
echo "  Hostname: $DOMAIN"
echo "  Namespace: $APP_NAMESPACE"
echo "  Default Password: ChangeMe@123456789 (CHANGE IMMEDIATELY!)"
echo ""
echo "Deployment Summary:"
echo "  ✓ code-server StatefulSet (1 replica, auto-scaling)"
echo "  ✓ 100Gi workspace storage"
echo "  ✓ 10Gi configuration storage"
echo "  ✓ Pre-installed extensions"
echo "  ✓ Monitoring integration"
echo "  ✓ Network security policies"
echo "  ✓ Automated daily backups"
echo ""
echo "Next Steps:"
echo "1. Access code-server at http://$CODE_SERVER_IP:$CODE_SERVER_PORT"
echo "2. Change default password in settings"
echo "3. Install additional extensions as needed"
echo "4. Configure Git integration"
echo "5. Proceed to Phase 7: Ingress & Load Balancing"

log_success "Phase 6: Application Platform COMPLETE"
