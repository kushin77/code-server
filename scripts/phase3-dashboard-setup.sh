#!/bin/bash
# Phase 3 Issue #176 - Developer Experience Dashboard
# Unified view of platform status, metrics, and activity

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="dev-dashboard"
DASHBOARD_VERSION="1.0.0"
DASHBOARD_DOMAIN=${DASHBOARD_DOMAIN:-"dev.192.168.168.31.nip.io"}

print_header() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_step() { echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# ============================================================================
# Dashboard Backend Setup
# ============================================================================

create_dashboard_backend() {
    print_header "Developer Dashboard Backend"
    
    print_step "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    print_step "Creating dashboard backend deployment..."
    
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dev-dashboard-api
  namespace: dev-dashboard
spec:
  replicas: 2
  selector:
    matchLabels:
      app: dev-dashboard-api
  template:
    metadata:
      labels:
        app: dev-dashboard-api
    spec:
      containers:
        - name: api
          image: 192.168.168.31:8443/code-server/dashboard:latest
          ports:
            - name: http
              containerPort: 3000
          env:
            - name: PROMETHEUS_URL
              value: "http://prometheus.monitoring.svc.cluster.local:9090"
            - name: GRAFANA_URL
              value: "http://grafana.monitoring.svc.cluster.local:3000"
            - name: ARGOCD_URL
              value: "http://argocd-server.argocd.svc.cluster.local:80"
            - name: KUBERNETES_API
              value: "https://kubernetes.default.svc.cluster.local:443"
          volumeMounts:
            - name: config
              mountPath: /app/config
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
      volumes:
        - name: config
          configMap:
            name: dashboard-config
---
apiVersion: v1
kind: Service
metadata:
  name: dev-dashboard-api
  namespace: dev-dashboard
spec:
  selector:
    app: dev-dashboard-api
  ports:
    - port: 3000
      targetPort: http
  type: ClusterIP
EOF
    
    print_success "Dashboard backend deployed"
}

# ============================================================================
# Dashboard Frontend Setup
# ============================================================================

create_dashboard_frontend() {
    print_header "Developer Dashboard Frontend"
    
    print_step "Creating dashboard frontend..."
    
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dev-dashboard-ui
  namespace: dev-dashboard
spec:
  replicas: 2
  selector:
    matchLabels:
      app: dev-dashboard-ui
  template:
    metadata:
      labels:
        app: dev-dashboard-ui
    spec:
      containers:
        - name: ui
          image: nginx:1.25-alpine
          ports:
            - name: http
              containerPort: 80
          volumeMounts:
            - name: app
              mountPath: /usr/share/nginx/html
            - name: config
              mountPath: /etc/nginx/conf.d
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
      volumes:
        - name: app
          configMap:
            name: dashboard-ui
            items:
              - key: index.html
                path: index.html
        - name: config
          configMap:
            name: nginx-config
---
apiVersion: v1
kind: Service
metadata:
  name: dev-dashboard-ui
  namespace: dev-dashboard
spec:
  selector:
    app: dev-dashboard-ui
  ports:
    - port: 80
      targetPort: http
  type: ClusterIP
EOF
    
    print_success "Dashboard frontend deployed"
}

# ============================================================================
# Configuration
# ============================================================================

create_dashboard_config() {
    print_header "Dashboard Configuration"
    
    print_step "Creating dashboard configuration..."
    
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: dashboard-config
  namespace: dev-dashboard
data:
  config.json: |
    {
      "title": "Code-Server Developer Platform",
      "version": "1.0.0",
      "refreshInterval": 30000,
      "panels": [
        {
          "name": "Cluster Status",
          "type": "status",
          "queries": [
            "node_up",
            "pod_count{namespace!='kube-system'}"
          ]
        },
        {
          "name": "Service Health",
          "type": "health",
          "services": [
            "code-server",
            "prometheus",
            "grafana",
            "argocd",
            "harbor"
          ]
        },
        {
          "name": "Build Metrics",
          "type": "chart",
          "queries": [
            "build_duration_seconds",
            "build_success_ratio"
          ]
        },
        {
          "name": "Deployment Activity",
          "type": "timeline",
          "queries": [
            "deployment_events",
            "rollout_status"
          ]
        },
        {
          "name": "Resource Utilization",
          "type": "gauge",
          "queries": [
            "cpu_usage_percent",
            "memory_usage_percent",
            "disk_usage_percent"
          ]
        },
        {
          "name": "Git Activity",
          "type": "feed",
          "source": "github",
          "repository": "kushin77/code-server"
        }
      ]
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: dashboard-ui
  namespace: dev-dashboard
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
      <title>Developer Platform Dashboard</title>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0d1117; color: #c9d1d9; }
        header { background: #161b22; padding: 1rem; border-bottom: 1px solid #30363d; }
        h1 { font-size: 1.5rem; }
        .container { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1rem; padding: 1rem; }
        .card { background: #161b22; border: 1px solid #30363d; border-radius: 6px; padding: 1.5rem; }
        .card h2 { font-size: 1rem; margin-bottom: 1rem; color: #79c0ff; }
        .status { font-size: 2rem; font-weight: bold; }
        .status.healthy { color: #3fb950; }
        .status.warning { color: #d29922; }
        .status.error { color: #f85149; }
        .metric { display: flex; justify-content: space-between; padding: 0.5rem 0; border-bottom: 1px solid #30363d; }
        .metric:last-child { border-bottom: none; }
        .label { color: #8b949e; }
        .value { font-weight: bold; }
      </style>
    </head>
    <body>
      <header>
        <h1>🚀 Developer Platform Dashboard</h1>
        <p>Real-time cluster status & deployment metrics</p>
      </header>
      <div class="container" id="dashboard"></div>
      <script>
        const API_URL = '/api';
        
        async function loadDashboard() {
          try {
            const response = await fetch(API_URL + '/status');
            const data = await response.json();
            const dashboard = document.getElementById('dashboard');
            
            // Cluster Status Card
            dashboard.innerHTML += `
              <div class="card">
                <h2>Cluster Status</h2>
                <div class="status ${data.cluster.healthy ? 'healthy' : 'error'}">
                  ${data.cluster.healthy ? '✓ Healthy' : '✗ Degraded'}
                </div>
                <div class="metric">
                  <span class="label">Nodes:</span>
                  <span class="value">${data.cluster.nodes}/${data.cluster.nodeCapacity}</span>
                </div>
                <div class="metric">
                  <span class="label">Pods:</span>
                  <span class="value">${data.cluster.pods}</span>
                </div>
              </div>
            `;
            
            // Services Health
            dashboard.innerHTML += `
              <div class="card">
                <h2>Services Health</h2>
                ${data.services.map(s => `
                  <div class="metric">
                    <span class="label">${s.name}</span>
                    <span class="status ${s.healthy ? 'healthy' : 'error'}">${s.healthy ? '✓' : '✗'}</span>
                  </div>
                `).join('')}
              </div>
            `;
            
            // Build Metrics
            dashboard.innerHTML += `
              <div class="card">
                <h2>Build Metrics</h2>
                <div class="metric">
                  <span class="label">Avg Duration:</span>
                  <span class="value">${data.builds.avgDuration}s</span>
                </div>
                <div class="metric">
                  <span class="label">Success Rate:</span>
                  <span class="value">${data.builds.successRate}%</span>
                </div>
              </div>
            `;
            
            // Resource Utilization
            dashboard.innerHTML += `
              <div class="card">
                <h2>Resource Utilization</h2>
                <div class="metric">
                  <span class="label">CPU:</span>
                  <span class="value">${data.resources.cpu}%</span>
                </div>
                <div class="metric">
                  <span class="label">Memory:</span>
                  <span class="value">${data.resources.memory}%</span>
                </div>
                <div class="metric">
                  <span class="label">Disk:</span>
                  <span class="value">${data.resources.disk}%</span>
                </div>
              </div>
            `;
            
          } catch (error) {
            console.error('Failed to load dashboard:', error);
          }
        }
        
        loadDashboard();
        setInterval(loadDashboard, 30000);
      </script>
    </body>
    </html>
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: dev-dashboard
data:
  default.conf: |
    server {
      listen 80;
      server_name _;
      root /usr/share/nginx/html;
      
      location / {
        try_files $uri /index.html;
      }
      
      location /api {
        proxy_pass http://dev-dashboard-api:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
      }
      
      location /prometheus {
        proxy_pass http://prometheus.monitoring.svc.cluster.local:9090;
      }
      
      location /grafana {
        proxy_pass http://grafana.monitoring.svc.cluster.local:3000;
      }
    }
EOF
    
    print_success "Dashboard configuration created"
}

# ============================================================================
# Ingress Setup
# ============================================================================

create_ingress() {
    print_header "Dashboard Ingress Configuration"
    
    print_step "Creating Ingress..."
    
    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: dev-dashboard
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/ingress.class: "traefik"
spec:
  rules:
    - host: $DASHBOARD_DOMAIN
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: dev-dashboard-ui
                port:
                  number: 80
EOF
    
    print_success "Ingress configured at $DASHBOARD_DOMAIN"
}

# ============================================================================
# Health Check
# ============================================================================

health_check() {
    print_header "Health Check"
    
    local errors=0
    
    print_step "Checking dashboard pods..."
    if kubectl get pods -n "$NAMESPACE" -l app=dev-dashboard-api &> /dev/null; then
        print_success "Dashboard API pods running"
    else
        print_error "Dashboard API pods not found"
        ((errors++))
    fi
    
    if kubectl get pods -n "$NAMESPACE" -l app=dev-dashboard-ui &> /dev/null; then
        print_success "Dashboard UI pods running"
    else
        print_error "Dashboard UI pods not found"
        ((errors++))
    fi
    
    print_step "Checking services..."
    if kubectl get svc -n "$NAMESPACE" dev-dashboard-api &> /dev/null; then
        print_success "API service available"
    else
        print_error "API service not found"
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
    print_header "Phase 3 Issue #176: Developer Experience Dashboard"
    
    local start_time=$(date +%s)
    
    create_dashboard_backend || exit 1
    create_dashboard_frontend || exit 1
    create_dashboard_config || exit 1
    create_ingress || exit 1
    health_check || exit 1
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_header "✅ Developer Dashboard Setup Complete"
    print_success "Total deployment time: ${duration}s"
    print_info "Access dashboard at: http://$DASHBOARD_DOMAIN"
}

main "$@"
