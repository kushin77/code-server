# On-Premises Deployment Guide

## Architecture Overview

This guide covers deploying code-server on an on-premises Kubernetes cluster without relying on cloud services (GCP, AWS, Azure).

### Self-Managed Components

```
┌─────────────────────────────────────────────────────┐
│         On-Premises Kubernetes Cluster               │
│                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ code-server │  │  agent-api  │  │ embeddings  │ │
│  │ (3 replicas)│  │ (5 replicas)│  │ (3 replicas)│ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘ │
│         │                │                │         │
│  ┌──────────────────────────────────────────┐      │
│  │     Redis Cache (2GB, RDB persistence)    │      │
│  └──────────────────────────────────────────┘      │
│         │                                           │
│  ┌──────────────────────────────────────────┐      │
│  │  PostgreSQL (On-Prem, HA with Patroni)   │      │
│  └──────────────────────────────────────────┘      │
│         │                                           │
│  ┌──────────────────────────────────────────┐      │
│  │   Observability Stack (On-Prem)          │      │
│  │  - Prometheus (metrics)                  │      │
│  │  - Grafana (dashboards)                  │      │
│  │  - Loki (logs)                           │      │
│  │  - Jaeger (tracing)                      │      │
│  └──────────────────────────────────────────┘      │
│                                                      │
│  ┌──────────────────────────────────────────┐      │
│  │  Storage (On-Prem NAS/SAN)               │      │
│  │  - PersistentVolumes for DB               │      │
│  │  - Backups to local NAS                   │      │
│  └──────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────┘
         │
    ┌────┴────┐
    │ Firewall│ (Internal network only)
    └─────────┘
```

## Infrastructure Requirements

### Kubernetes Cluster

**Minimum 3 nodes** (HA recommended):
- Master node: 4 CPU, 16GB RAM (control plane components)
- Worker node 1: 8 CPU, 32GB RAM
- Worker node 2: 8 CPU, 32GB RAM
- Worker node 3: 8 CPU, 32GB RAM

**Supported K8s Versions**: 1.27+

**Installation Options**:
1. kubeadm (recommended for on-prem)
2. Rancher K3s (lightweight alternative)
3. OpenShift (enterprise option)

### Storage

**Options**:
1. **NAS/SAN** (recommended): NFS mount for persistent volumes
2. **Local storage** with Replicated Storage (e.g., Longhorn)
3. **Ceph** (distributed storage)

**Minimum Capacity**: 100GB for databases + logs

### Networking

- **Internal network connectivity** between all nodes
- **Firewall rules**: Allow Kubernetes API (6443), CNI traffic (10.0.0.0/8)
- **DNS**: Corefile configuration for local .local domains
- **Load Balancer**: MetalLB (on-prem load balancing for ingress)

### Database (PostgreSQL)

**On-Premises HA Setup**:
```
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│  Patroni     │        │  Patroni     │        │  Patroni     │
│ PostgreSQL-1 │─┬──────│ PostgreSQL-2 │─┬──────│ PostgreSQL-3 │
│  (Primary)   │ │      │  (Replica)   │ │      │  (Replica)   │
└──────────────┘ │      └──────────────┘ │      └──────────────┘
                 │ Raft consensus        │
            ┌────┴─── ─────┬─────────────┘
            │               │
        ┌───┴───┐       ┌───┴────┐
        │ etcd  │       │ etcd   │
        │ node1 │       │ node2  │
        └───────┘       └────────┘
```

**Setup Steps**:
```bash
# 1. Install PostgreSQL on each node (or as StatefulSet)
apt-get install -y postgresql-14

# 2. Install Patroni for HA
pip install patroni[etcd]

# 3. Configure Patroni YAML (see below)

# 4. Initialize cluster
patronictl -c patroni.yml initdb

# 5. Verify
patronictl -c patroni.yml list
```

## Deployment Steps

### Step 1: Prepare On-Premises Cluster

```bash
# 1.1 Verify cluster health
kubectl cluster-info
kubectl get nodes -o wide
kubectl get storageclass

# 1.2 Install MetalLB for on-prem load balancing
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml

# 1.3 Configure MetalLB IP pool (your internal network range)
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.200-192.168.1.250  # Adjust to your network
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
    - default
EOF

# 1.4 Install storage provisioner (NFS example)
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage
provisioner: nfs.csi.k8s.io
parameters:
  server: 192.168.1.100  # Your NAS IP
  share: /exports/k8s
allowVolumeExpansion: true
EOF
```

### Step 2: Deploy Observability Stack

```bash
# 2.1 Create monitoring namespace
kubectl create namespace monitoring

# 2.2 Deploy Prometheus
kubectl apply -f kubernetes/base/prometheus-deployment.yaml -n monitoring

# 2.3 Deploy Grafana
kubectl apply -f kubernetes/base/grafana-deployment.yaml -n monitoring

# 2.4 Deploy Loki (logs)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Deployment
metadata:
  name: loki
  namespace: monitoring
spec:
  replicas: 1
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
        image: grafana/loki:2.9
        ports:
        - containerPort: 3100
        volumeMounts:
        - name: loki-config
          mountPath: /etc/loki
        - name: loki-storage
          mountPath: /loki
      volumes:
      - name: loki-config
        configMap:
          name: loki-config
      - name: loki-storage
        persistentVolumeClaim:
          claimName: loki-pvc
EOF

# 2.5 Deploy Jaeger (tracing)
helm install jaeger jaegertracing/jaeger --namespace monitoring
```

### Step 3: Deploy PostgreSQL with Patroni HA

```bash
# 3.1 Create database namespace
kubectl create namespace databases

# 3.2 Create Patroni ConfigMap
kubectl create configmap patroni-config -n databases --from-literal=patroni.yml="$(cat <<'EOF'
scope: postgresql
namespace: databases
name: postgresql

# DCS (Distributed Configuration Store)
dcs:
  type: etcd
  etcd:
    hosts:
      - 192.168.1.101:2379
      - 192.168.1.102:2379
      - 192.168.1.103:2379

# PostgreSQL parameters
postgresql:
  data_dir: /var/lib/postgresql/14/main
  bin_dir: /usr/lib/postgresql/14/bin
  port: 5432
  parameters:
    max_connections: 200
    shared_buffers: '4GB'
    effective_cache_size: '12GB'
    work_mem: '20MB'

# REST API
restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.1.101:8008
EOF
)"

# 3.3 Deploy PostgreSQL StatefulSet with Patroni
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
  namespace: databases
spec:
  serviceName: postgresql
  replicas: 3
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: postgres:14
        ports:
        - containerPort: 5432
        env:
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: postgresql-storage
          mountPath: /var/lib/postgresql/data
        - name: patroni-config
          mountPath: /etc/patroni
      - name: patroni
        image: patroni:latest
        command:
        - patroni
        - /etc/patroni/patroni.yml
        ports:
        - containerPort: 8008
        volumeMounts:
        - name: postgresql-storage
          mountPath: /var/lib/postgresql/data
        - name: patroni-config
          mountPath: /etc/patroni
      volumes:
      - name: patroni-config
        configMap:
          name: patroni-config
  volumeClaimTemplates:
  - metadata:
      name: postgresql-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: nfs-storage
      resources:
        requests:
          storage: 100Gi
EOF
```

### Step 4: Deploy Redis

```bash
# 4.1 Deploy Redis with persistence
kubectl apply -f kubernetes/base/redis-statefulset.yaml -n code-server

# 4.2 Verify Redis is ready
kubectl get statefulset redis -n code-server
kubectl get pvc -n code-server | grep redis
```

### Step 5: Deploy Applications

```bash
# 5.1 Deploy to production overlay
kustomize build kubernetes/overlays/production | kubectl apply -f -

# 5.2 Wait for rollout
kubectl rollout status deployment/code-server -n code-server --timeout=5m
kubectl rollout status deployment/agent-api -n agents --timeout=5m

# 5.3 Verify services
kubectl get svc -n code-server
kubectl get svc -n agents
```

### Step 6: Configure Ingress (MetalLB)

```bash
# 6.1 Create Ingress controller (NGINX on-prem)
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# 6.2 Create Ingress resources
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: code-server-ingress
  namespace: code-server
spec:
  ingressClassName: nginx
  rules:
  - host: code-server.internal.company.com
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

# 6.3 Get LoadBalancer IP
kubectl get svc -n ingress-nginx
# Configure DNS: code-server.internal.company.com → <EXTERNAL-IP>
```

## On-Premises Best Practices

### 1. Network Segmentation

```yaml
# Network Policy: Restrict traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: code-server-netpol
  namespace: code-server
spec:
  podSelector:
    matchLabels:
      app: code-server
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 5432  # PostgreSQL
    - protocol: TCP
      port: 6379  # Redis
```

### 2. Resource Quotas

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: code-server-quota
  namespace: code-server
spec:
  hard:
    requests.cpu: "16"
    requests.memory: "64Gi"
    limits.cpu: "32"
    limits.memory: "128Gi"
    pods: "50"
```

### 3. Backup Strategy

```bash
# Daily backup script
#!/bin/bash
set -e

BACKUP_DIR="/mnt/nfs/backups/$(date +%Y-%m-%d)"
mkdir -p $BACKUP_DIR

# Backup PostgreSQL
kubectl exec -n databases postgresql-0 -- \
  pg_dump -U postgres code_server > $BACKUP_DIR/code_server.sql

# Backup Redis
kubectl exec -n code-server redis-0 -- \
  redis-cli BGSAVE

# Backup Kubernetes manifests
kubectl get all -A -o json > $BACKUP_DIR/k8s-resources.json

# Backup etcd (if needed)
kubectl -n kube-system exec -it etcd-master -- \
  etcdctl snapshot save /var/lib/etcd-backup.db

# Retention: keep 30 days
find $BACKUP_DIR/../ -type d -mtime +30 -exec rm -rf {} \;

echo "Backup completed: $BACKUP_DIR"
```

### 4. Monitoring Thresholds (On-Prem)

```yaml
# PrometheusRule for on-prem alerts
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: onprem-alerts
  namespace: monitoring
spec:
  groups:
  - name: onprem.rules
    interval: 30s
    rules:
    - alert: NodeDiskPressure
      expr: |
        kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85
      for: 5m
      annotations:
        summary: "Node {{ $labels.node }} disk {{ $value | humanizePercentage }} full"
    
    - alert: NodeMemoryPressure
      expr: |
        (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.85
      for: 5m
      annotations:
        summary: "Node memory {{ $value | humanizePercentage }} full"
    
    - alert: PostgreSQLBackupStale
      expr: |
        time() - pg_backup_timestamp_seconds > 86400
      for: 1h
      annotations:
        summary: "PostgreSQL backup older than 24 hours"
```

### 5. Local Authentication

No cloud IAM - use certificate-based auth:

```bash
# Generate client certificate
openssl req -new -newkey rsa:2048 -nodes \
  -keyout c:\code-server-enterprise-admin.key \
  -out c:\code-server-enterprise-admin.csr

# Sign with cluster CA
kubectl certificate approve <CSR_NAME>

# Create kubeconfig
kubectl config set-cluster on-prem --server=https://192.168.1.100:6443
kubectl config set-credentials admin --client-certificate=admin.crt --client-key=admin.key
kubectl config set-context on-prem-admin --cluster=on-prem --user=admin
kubectl config use-context on-prem-admin
```

## Troubleshooting

### Pod won't start

```bash
# Check events
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace> --previous

# Check storage
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>
```

### Network issues

```bash
# Test DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup postgresql.databases.svc.cluster.local

# Test connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  wget -O- http://code-server:8080/health
```

### Performance issues

```bash
# Check node resources
kubectl top nodes
kubectl top pods -n code-server

# Check API server latency
kubectl get --raw /metrics | grep apiserver_latency
```

## Cost Estimation (On-Premises)

| Component | Cost | Notes |
|-----------|------|-------|
| Server hardware (3 nodes @ $2k/node) | $6,000 | One-time |
| NAS storage (10TB) | $3,000 | One-time |
| Networking (switch, cabling) | $2,000 | One-time |
| **Annual Cost** | **~$2,000** | Electricity + maintenance |
| **vs Cloud** | **95% cheaper** | Compared to $100-150k/year cloud |

---

For questions or issues, refer to `docs/runbooks/` for operational procedures.
