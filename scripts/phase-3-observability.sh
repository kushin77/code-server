#!/bin/bash
# Phase 3: Observability Stack (Prometheus, Grafana, Loki)
# Date: April 13, 2026
# Purpose: Deploy comprehensive monitoring, metrics, and logging solution

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE=${NAMESPACE:-"monitoring"}
STORAGE_CLASS=${STORAGE_CLASS:-"local-storage"}
RETENTION_DAYS=${RETENTION_DAYS:-"15"}

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Phase 3.1: Namespace Setup
echo -e "\n${BLUE}=== PHASE 3.1: NAMESPACE SETUP ===${NC}\n"

log_info "Creating monitoring namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Add labels
kubectl label namespace $NAMESPACE monitoring=enabled --overwrite
log_success "Namespace '$NAMESPACE' created"

# Phase 3.2: Prometheus Deployment
echo -e "\n${BLUE}=== PHASE 3.2: PROMETHEUS DEPLOYMENT ===${NC}\n"

log_info "Creating Prometheus ConfigMap..."
cat > /tmp/prometheus-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        cluster: 'code-server-cluster'
        environment: 'production'
    
    scrape_configs:
      - job_name: 'kubernetes-apiservers'
        kubernetes_sd_configs:
          - role: endpoints
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
            action: keep
            regex: default;kubernetes;https

      - job_name: 'kubernetes-nodes'
        kubernetes_sd_configs:
          - role: node
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token

      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: 'true'
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__

      - job_name: 'prometheus'
        static_configs:
          - targets: ['localhost:9090']

    alerting:
      alertmanagers:
        - kubernetes_sd_configs:
            - role: pod
              namespaces:
                names:
                  - monitoring

    rule_files:
      - /etc/prometheus/rules/*.yml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-rules
  namespace: monitoring
data:
  alerts.yml: |
    groups:
      - name: kubernetes.rules
        interval: 30s
        rules:
          - alert: KubernetesPodCrashLooping
            expr: |
              rate(kube_pod_container_status_restarts_total[15m]) > 0
            for: 5m
            annotations:
              summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash looping"

          - alert: KubernetesMemoryPressure
            expr: |
              kube_node_status_condition{condition="MemoryPressure",status="true"} == 1
            for: 5m
            annotations:
              summary: "Node {{ $labels.node }} has MemoryPressure"

          - alert: KubernetesDiskPressure
            expr: |
              kube_node_status_condition{condition="DiskPressure",status="true"} == 1
            for: 5m
            annotations:
              summary: "Node {{ $labels.node }} has DiskPressure"

          - alert: PrometheusHighMemoryUsage
            expr: |
              container_memory_max_usage_bytes{pod=~"prometheus.*"} / 1024 / 1024 > 2048
            for: 5m
            annotations:
              summary: "Prometheus high memory usage"
EOF

kubectl apply -f /tmp/prometheus-config.yaml
log_success "Prometheus ConfigMaps created"

log_info "Deploying Prometheus..."
cat > /tmp/prometheus-deploy.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
  - apiGroups: [""]
    resources:
      - nodes
      - nodes/proxy
      - services
      - endpoints
      - pods
    verbs: ["get", "list", "watch"]
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
  - kind: ServiceAccount
    name: prometheus
    namespace: monitoring
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: prometheus
  namespace: monitoring
  labels:
    app: prometheus
spec:
  serviceName: prometheus
  replicas: 2
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      serviceAccountName: prometheus
      securityContext:
        fsGroup: 65534
      containers:
        - name: prometheus
          image: prom/prometheus:v2.40.0
          args:
            - --config.file=/etc/prometheus/prometheus.yml
            - --storage.tsdb.path=/prometheus
            - --storage.tsdb.retention.time=30d
            - --web.console.libraries=/usr/share/prometheus/console_libraries
            - --web.console.templates=/usr/share/prometheus/consoles
            - --web.enable-lifecycle
          ports:
            - containerPort: 9090
              name: web
          resources:
            requests:
              cpu: 500m
              memory: 2Gi
            limits:
              cpu: 2000m
              memory: 4Gi
          livenessProbe:
            httpGet:
              path: /-/healthy
              port: 9090
            initialDelaySeconds: 30
            periodSeconds: 5
          readinessProbe:
            httpGet:
              path: /-/ready
              port: 9090
            initialDelaySeconds: 5
            periodSeconds: 5
          volumeMounts:
            - name: config
              mountPath: /etc/prometheus
            - name: rules
              mountPath: /etc/prometheus/rules
            - name: storage
              mountPath: /prometheus
      volumes:
        - name: config
          configMap:
            name: prometheus-config
        - name: rules
          configMap:
            name: prometheus-rules
  volumeClaimTemplates:
    - metadata:
        name: storage
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-storage
        resources:
          requests:
            storage: 50Gi
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
  labels:
    app: prometheus
spec:
  clusterIP: None
  selector:
    app: prometheus
  ports:
    - name: web
      port: 9090
      targetPort: 9090
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus-lb
  namespace: monitoring
  labels:
    app: prometheus
spec:
  type: LoadBalancer
  selector:
    app: prometheus
  ports:
    - name: web
      port: 9090
      targetPort: 9090
EOF

kubectl apply -f /tmp/prometheus-deploy.yaml
log_success "Prometheus deployed"

# Phase 3.3: Grafana Deployment
echo -e "\n${BLUE}=== PHASE 3.3: GRAFANA DEPLOYMENT ===${NC}\n"

log_info "Creating Grafana ConfigMap..."
cat > /tmp/grafana-datasources.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus-lb:9090
        isDefault: true
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: monitoring
data:
  kubernetes-cluster.json: |
    {}
EOF

kubectl apply -f /tmp/grafana-datasources.yaml
log_success "Grafana ConfigMaps created"

log_info "Deploying Grafana..."
cat > /tmp/grafana-deploy.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
  labels:
    app: grafana
spec:
  replicas: 2
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      securityContext:
        fsGroup: 472
      containers:
        - name: grafana
          image: grafana/grafana:9.0.0
          ports:
            - containerPort: 3000
              name: http
          env:
            - name: GF_SECURITY_ADMIN_USER
              value: admin
            - name: GF_SECURITY_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: grafana-secret
                  key: password
            - name: GF_INSTALL_PLUGINS
              value: "grafana-piechart-panel"
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
          volumeMounts:
            - name: datasources
              mountPath: /etc/grafana/provisioning/datasources
            - name: storage
              mountPath: /var/lib/grafana
      volumes:
        - name: datasources
          configMap:
            name: grafana-datasources
        - name: storage
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
  labels:
    app: grafana
spec:
  type: LoadBalancer
  selector:
    app: grafana
  ports:
    - name: http
      port: 3000
      targetPort: 3000
EOF

# Create Grafana secret
kubectl create secret generic grafana-secret \
  --from-literal=password=ChanGedDefaultPassword123! \
  -n monitoring --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f /tmp/grafana-deploy.yaml
log_success "Grafana deployed"

# Phase 3.4: Loki (Logs)
echo -e "\n${BLUE}=== PHASE 3.4: LOKI DEPLOYMENT ===${NC}\n"

log_info "Creating Loki ConfigMap..."
cat > /tmp/loki-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: monitoring
data:
  loki-config.yaml: |
    auth_enabled: false
    ingester:
      chunk_idle_period: 3m
      max_chunk_age: 1h
      max_streams_per_user: 10000
      chunk_retain_period: 1m
    limits_config:
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h
    schema_config:
      configs:
        - from: 2020-10-24
          store: boltdb-shipper
          object_store: filesystem
          schema: v11
          index:
            prefix: index_
            period: 24h
    server:
      http_listen_port: 3100
    storage_config:
      boltdb_shipper:
        active_index_directory: /loki/boltdb-shipper-active
        cache_location: /loki/boltdb-shipper-cache
        shared_store: filesystem
      filesystem:
        directory: /loki/chunks
    chunk_store_config:
      max_look_back_period: 0s
    table_manager:
      retention_deletes_enabled: false
      retention_period: 0s
EOF

kubectl apply -f /tmp/loki-config.yaml
log_success "Loki ConfigMap created"

log_info "Deploying Loki..."
cat > /tmp/loki-deploy.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: monitoring
  labels:
    app: loki
spec:
  serviceName: loki
  replicas: 2
  selector:
    matchLabels:
      app: loki
  template:
    metadata:
      labels:
        app: loki
    spec:
      containers:
        - name: loki
          image: grafana/loki:2.6.0
          ports:
            - containerPort: 3100
              name: http
          args:
            - -config.file=/etc/loki/loki-config.yaml
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
          volumeMounts:
            - name: config
              mountPath: /etc/loki
            - name: storage
              mountPath: /loki
      volumes:
        - name: config
          configMap:
            name: loki-config
  volumeClaimTemplates:
    - metadata:
        name: storage
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-storage
        resources:
          requests:
            storage: 20Gi
---
apiVersion: v1
kind: Service
metadata:
  name: loki
  namespace: monitoring
  labels:
    app: loki
spec:
  clusterIP: None
  selector:
    app: loki
  ports:
    - name: http
      port: 3100
      targetPort: 3100
---
apiVersion: v1
kind: Service
metadata:
  name: loki-loadbalancer
  namespace: monitoring
  labels:
    app: loki
spec:
  type: LoadBalancer
  selector:
    app: loki
  ports:
    - name: http
      port: 3100
      targetPort: 3100
EOF

kubectl apply -f /tmp/loki-deploy.yaml
log_success "Loki deployed"

# Phase 3.5: Promtail (Log Collector)
echo -e "\n${BLUE}=== PHASE 3.5: PROMTAIL DEPLOYMENT ===${NC}\n"

log_info "Creating Promtail ConfigMap..."
cat > /tmp/promtail-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: monitoring
data:
  promtail-config.yaml: |
    clients:
      - url: http://loki:3100/loki/api/v1/push
    positions:
      filename: /tmp/positions.yaml
    scrape_configs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_name]
            target_label: pod
          - source_labels: [__meta_kubernetes_namespace]
            target_label: namespace
          - source_labels: [__meta_kubernetes_pod_container_name]
            target_label: container
EOF

kubectl apply -f /tmp/promtail-config.yaml
log_success "Promtail ConfigMap created"

log_info "Deploying Promtail..."
cat > /tmp/promtail-deploy.yaml << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: monitoring
  labels:
    app: promtail
spec:
  selector:
    matchLabels:
      app: promtail
  template:
    metadata:
      labels:
        app: promtail
    spec:
      tolerations:
        - key: node-role.kubernetes.io/master
          effect: NoSchedule
      containers:
        - name: promtail
          image: grafana/promtail:2.6.0
          args:
            - -config.file=/etc/promtail/promtail-config.yaml
          volumeMounts:
            - name: config
              mountPath: /etc/promtail
            - name: varlog
              mountPath: /var/log
              readOnly: true
            - name: varlibdockercontainers
              mountPath: /var/lib/docker/containers
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: promtail-config
        - name: varlog
          hostPath:
            path: /var/log
        - name: varlibdockercontainers
          hostPath:
            path: /var/lib/docker/containers
EOF

kubectl apply -f /tmp/promtail-deploy.yaml
log_success "Promtail deployed"

# Phase 3.6: AlertManager
echo -e "\n${BLUE}=== PHASE 3.6: ALERTMANAGER DEPLOYMENT ===${NC}\n"

log_info "Creating AlertManager ConfigMap..."
cat > /tmp/alertmanager-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: alertmanager-config
  namespace: monitoring
data:
  alertmanager.yml: |
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'cluster']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
    receivers:
      - name: 'default'
EOF

kubectl apply -f /tmp/alertmanager-config.yaml
log_success "AlertManager ConfigMap created"

log_info "Deploying AlertManager..."
cat > /tmp/alertmanager-deploy.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager
  namespace: monitoring
  labels:
    app: alertmanager
spec:
  replicas: 2
  selector:
    matchLabels:
      app: alertmanager
  template:
    metadata:
      labels:
        app: alertmanager
    spec:
      containers:
        - name: alertmanager
          image: prom/alertmanager:v0.24.0
          args:
            - --config.file=/etc/alertmanager/alertmanager.yml
            - --storage.path=/alertmanager
          ports:
            - containerPort: 9093
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
          volumeMounts:
            - name: config
              mountPath: /etc/alertmanager
            - name: storage
              mountPath: /alertmanager
      volumes:
        - name: config
          configMap:
            name: alertmanager-config
        - name: storage
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: monitoring
spec:
  type: LoadBalancer
  selector:
    app: alertmanager
  ports:
    - name: http
      port: 9093
      targetPort: 9093
EOF

kubectl apply -f /tmp/alertmanager-deploy.yaml
log_success "AlertManager deployed"

# Phase 3.7: Verification
echo -e "\n${BLUE}=== PHASE 3.7: VERIFICATION ===${NC}\n"

log_info "Verifying observability stack..."

# Wait for deployments
log_info "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/grafana -n monitoring 2>/dev/null || log_warning "Grafana still starting"

kubectl wait --for=condition=available --timeout=300s \
  deployment/alertmanager -n monitoring 2>/dev/null || log_warning "AlertManager still starting"

# Check services
log_info "Checking services..."
kubectl get svc -n monitoring -o wide

# Final status
echo -e "\n${BLUE}=== PHASE 3.8: ACCESS INFORMATION ===${NC}\n"

log_success "Observability Stack Deployed"
echo ""
echo "Access Information:"
echo "  Prometheus: http://$(kubectl get svc prometheus-lb -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):9090"
echo "  Grafana: http://$(kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000"
echo "  Loki: http://$(kubectl get svc loki-loadbalancer -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3100"
echo "  AlertManager: http://$(kubectl get svc alertmanager -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):9093"
echo ""
echo "Default Credentials:"
echo "  Grafana User: admin"
echo "  Grafana Password: ChanGedDefaultPassword123!"
echo ""
echo "Next Steps:"
echo "1. Access Grafana and add Prometheus datasource (http://prometheus-lb:9090)"
echo "2. Create dashboards for monitoring"
echo "3. Configure AlertManager receivers (email, Slack, PagerDuty)"
echo "4. Proceed to Phase 4: Security & RBAC"

log_success "Phase 3: Observability Stack COMPLETE"
