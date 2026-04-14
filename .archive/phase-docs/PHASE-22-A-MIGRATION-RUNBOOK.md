# PHASE-22-A-MIGRATION-RUNBOOK.md
# Phase 22-A: Docker Compose → Kubernetes Migration Runbook

**Effective Date**: April 14, 2026  
**Status**: DRAFT - Ready for Phase 22-A Implementation  
**Audience**: DevOps, SRE, Platform Engineers  
**Severity**: P1 (Production Cutover)

---

## EXECUTIVE SUMMARY

This runbook provides step-by-step procedures to migrate code-server production infrastructure from Docker Compose (single-host orchestration) to Kubernetes (distributed orchestration) with:

- **Zero downtime**: Blue-green deployment strategy
- **Data preservation**: Pre-migration backup & validation
- **Automatic scaling**: HPA configured (2-10 pods)
- **Health monitoring**: Prometheus integrations
- **Rollback capability**: Safe fallback to Docker Compose

**Timeline**: ~4 hours (including validation)
**Risk Level**: Medium (mitigated with rollback plan)
**Team Size**: 2-3 engineers (DevOps lead + SRE + QA)

---

## PREREQUISITES

### Infrastructure
- [ ] AWS account with permissions to create EKS clusters
- [ ] Terraform state backend configured
- [ ] IAM roles created (EKS cluster role, node role)
- [ ] VPC CIDR planning complete (10.0.0.0/16)
- [ ] Domain and TLS certificate ready

### Tools
- [ ] `aws` CLI configured (credentials, region)
- [ ] `terraform` >= 1.0 installed
- [ ] `kubectl` >= 1.28 installed
- [ ] `helm` >= 3.12 installed
- [ ] `docker` CLI (for local testing)
- [ ] `git` configured

### Backups
- [ ] PostgreSQL full backup created
- [ ] Redis snapshots exported
- [ ] SSH private keys backed up
- [ ] OAuth2-Proxy configuration backed up
- [ ] Caddy configuration backed up
- [ ] Code-Server workspace volumes backed up

### Verification
- [ ] Docker Compose environment running and healthy
- [ ] All health checks passing
- [ ] No pending deployments
- [ ] Monitoring receiving metrics from all services
- [ ] AlertManager notifications functional

---

## PHASE 1: PREPARATION (30 minutes)

### 1.1 Create Pre-Migration Snapshot

```bash
# ---- EXECUTE ON PRODUCTION HOST (192.168.168.31) ----

# 1. Stop accepting new connections (drain)
ssh akushnir@192.168.168.31 << 'EOF'

# Create backup directory
mkdir -p /home/akushnir/.backups/pre-k8s-migration-$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=/home/akushnir/.backups/pre-k8s-migration-$(date +%Y%m%d_%H%M%S)

# PostgreSQL backup
docker-compose exec -T db pg_dump -U postgres code_server > "$BACKUP_DIR/postgres-backup.sql"

# Redis snapshot
docker-compose exec -T redis redis-cli BGSAVE
docker-compose cp redis:/var/lib/redis/dump.rdb "$BACKUP_DIR/redis-dump.rdb"

# Caddy configuration
cp Caddyfile.production "$BACKUP_DIR/"
cp Caddyfile.base "$BACKUP_DIR/"

# OAuth2-Proxy config
cp oauth2-proxy-config.json "$BACKUP_DIR/"

# Code-Server workspace
docker-compose exec -T code-server tar czf /tmp/coder-workspace.tar.gz /home/coder/
docker-compose cp code-server:/tmp/coder-workspace.tar.gz "$BACKUP_DIR/"

# Verify backups
ls -lh "$BACKUP_DIR"
echo "Backup created: $BACKUP_DIR"

EOF
```

### 1.2 Document Current State

```bash
# Capture running container details
docker-compose ps -a > /tmp/docker-compose-running-services.txt
docker-compose config > /tmp/docker-compose-full-config.yaml

# Capture environment variables
docker-compose exec -T code-server env > /tmp/code-server-env.txt
docker-compose exec -T oauth2-proxy env > /tmp/oauth2-proxy-env.txt
docker-compose exec -T caddy env > /tmp/caddy-env.txt

# Network configuration
docker network ls > /tmp/docker-networks.txt
docker network inspect code-server-network > /tmp/docker-network-details.json
```

### 1.3 Create DNS Entry for KubernetesIngress

```bash
# Update DNS to point to EKS load balancer (after cluster is created)
# Record type: CNAME
# Name: ide-k8s.kushnir.cloud (temporary, for testing)
# Value: <EKS Load Balancer Endpoint>

# OR keep ide.kushnir.cloud pointing to old Docker environment
# and test on ide-k8s.kushnir.cloud first
```

### 1.4 Terraform Validation

```bash
cd terraform/

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan the deployment (review before applying)
terraform plan -out=phase-22-a.tfplan

# Approve plan (review resources to be created)
echo "Review plan above. Press Enter to continue or Ctrl+C to abort."
read
```

---

## PHASE 2: KUBERNETES CLUSTER DEPLOYMENT (45 minutes)

### 2.1 Deploy EKS Cluster Using Terraform

```bash
# From terraform/ directory

# Apply the plan
terraform apply phase-22-a.tfplan

# Outputs should include:
# - EKS cluster endpoint
# - EKS cluster name
# - Worker nodes count
# - Kubeconfig (base64)

# ⏳ Wait 10-15 minutes for cluster to be ready
echo "Waiting for EKS cluster to be operational..."
sleep 900

# Verify cluster is ready
aws eks describe-cluster \
  --name code-server-k8s-prod \
  --region us-east-1 \
  --query 'cluster.status'
# Should output: "ACTIVE"
```

### 2.2 Configure kubectl Access

```bash
# Update local kubeconfig
aws eks update-kubeconfig \
  --name code-server-k8s-prod \
  --region us-east-1

# Verify connection
kubectl cluster-info
kubectl get nodes
# Should show 3 nodes (desired_size = 3)

# Wait for all nodes to be Ready
kubectl get nodes --watch
# Press Ctrl+C when all nodes show "Ready"
```

### 2.3 Install Required Add-ons

```bash
# 1. Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update ingress-nginx

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Wait for Load Balancer IP assignment
kubectl get svc -n ingress-nginx --watch

# 2. Install Cert-Manager (for TLS)
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

# 3. Install Metrics Server (for HPA)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify all add-ons are running
kubectl get pods --all-namespaces | grep -E "nginx|cert-manager|metrics-server"
```

### 2.4 Create Kubernetes Namespace and Secrets

```bash
# Create namespace for code-server
kubectl create namespace code-server

# Create secret for code-server credentials
kubectl create secret generic code-server-credentials \
  --from-literal=password='<strong-password>' \
  --from-literal=sudo_password='<strong-password>' \
  -n code-server

# Create secrets for external integrations
kubectl create secret generic code-server-config \
  --from-literal=GITHUB_TOKEN='<github-token>' \
  --from-literal=CLOUDFLARE_API_TOKEN='<cloudflare-token>' \
  --from-literal=ACME_EMAIL='security@kushnir.cloud' \
  -n code-server

# Verify secrets created
kubectl get secrets -n code-server
```

---

## PHASE 3: DATA MIGRATION (45 minutes)

### 3.1 Create Persistent Storage

```bash
# AWS EBS Storage Class (for persistent volumes)
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
allowVolumeExpansion: true
EOF

# Verify storage class
kubectl get storageclass gp3
```

### 3.2 Restore Databases in PostGres Pod

```bash
# Create a temporary pod for database restoration
kubectl run pg-restore \
  --image=postgres:15 \
  --env="PGPASSWORD=<password>" \
  -n code-server \
  -it \
  -- /bin/bash

# Inside the pod:
# 1. Connect to PostgreSQL service
psql -h postgresql.code-server.svc.cluster.local -U postgres -d code_server < postgres-backup.sql

# 2. Verify data restored
psql -h postgresql.code-server.svc.cluster.local -U postgres -c "SELECT COUNT(*) FROM users;"

# Exit pod
exit
```

### 3.3 Restore Redis Data

```bash
# Copy Redis dump into PVC
kubectl cp redis-dump.rdb code-server/redis-0:/data/dump.rdb

# Restart Redis pod to reload data
kubectl delete pod redis-0 -n code-server

# Verify data restored
kubectl exec -it redis-0 -n code-server -- redis-cli INFO keyspace
```

### 3.4 Migrate Code-Server Workspace

```bash
# Create persistent volume for workspace
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: coder-workspace-pv
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  hostPath:
    path: /mnt/workspace
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: coder-workspace-pvc
  namespace: code-server
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 50Gi
EOF

# Extract workspace into mounted volume
kubectl cp coder-workspace.tar.gz code-server/code-server-0:/tmp/
kubectl exec -it code-server-0 -n code-server -- tar xzf /tmp/coder-workspace.tar.gz -C /

# Verify workspace content
kubectl exec code-server-0 -n code-server -- ls -la /home/coder/
```

---

## PHASE 4: APPLICATION DEPLOYMENT (30 minutes)

### 4.1 Deploy code-server via Helm

```bash
# Add Helm chart repository (local)
helm repo add code-server ./kubernetes/helm

# Create values override file (production config)
cat > values-production.yaml <<EOF
replicaCount: 3

image:
  repository: codercom/code-server
  tag: "4.20.1"
  digest: "sha256:abc123..."  # Update with actual digest
  pullPolicy: IfNotPresent

resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "2000m"
    memory: "2Gi"

persistence:
  enabled: true
  size: "50Gi"
  mountPath: /home/coder

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

ingress:
  enabled: true
  className: "nginx"
  hosts:
    - host: "ide.kushnir.cloud"
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: code-server-tls
      hosts:
        - ide.kushnir.cloud
EOF

# Deploy via Helm
helm install code-server ./kubernetes/helm/code-server-chart \
  -f values-production.yaml \
  -n code-server

# Monitor deployment rollout
kubectl rollout status deployment/code-server -n code-server

# Verify pods are running
kubectl get pods -n code-server
# Should show 3 pods in "Running" state
```

### 4.2 Deploy Supporting Services (OAuth2-Proxy, Caddy)

```bash
# Deploy OAuth2-Proxy
helm install oauth2-proxy ./kubernetes/helm/oauth2-proxy-chart \
  -f values-oauth2-production.yaml \
  -n code-server

# Deploy Caddy (if needed for reverse proxy)
helm install caddy ./kubernetes/helm/caddy-chart \
  -f values-caddy-production.yaml \
  -n code-server

# Verify all deployments
kubectl get deployments -n code-server
```

### 4.3 Expose Services via Ingress

```bash
# Get Load Balancer endpoint
kubectl get svc -n ingress-nginx

# Update DNS to point to Load Balancer (if using temporary hostname)
# Record: ide-k8s.kushnir.cloud → <Load Balancer IP>

# Verify Ingress created
kubectl get ingress -n code-server

# Test connectivity
curl https://ide-k8s.kushnir.cloud/health
# Should return 200 OK
```

---

## PHASE 5: VALIDATION & TESTING (30 minutes)

### 5.1 Health Checks

```bash
# 1. Kubernetes cluster health
kubectl get nodes
# All nodes should be "Ready"

# 2. Pods health
kubectl get pods -n code-server
# All pods should be "Running" with Ready count matching replicas

# 3. Services health
kubectl get svc -n code-server
# Services should have external IPs/endpoints

# 4. Ingress health
kubectl get ingress -n code-server
# Ingress should have an IP address in the "ADDRESS" column

# Detailed ingress status
kubectl describe ingress code-server -n code-server
```

### 5.2 Application Testing

```bash
# Test code-server accessibility
curl -I https://ide.kushnir.cloud

# Test health endpoint
curl https://ide.kushnir.cloud/health

# Test OAuth2-Proxy login flow (smoke test)
curl -I https://ide.kushnir.cloud/oauth2/start

# Test workspace file access
# Login via browser and verify files are accessible
```

### 5.3 Data Integrity

```bash
# Verify database
kubectl exec -it postgresql-0 -n code-server -- psql -U postgres -c "SELECT COUNT(*) FROM users;"

# Verify Redis
kubectl exec -it redis-0 -n code-server -- redis-cli DBSIZE

# Verify workspace files
kubectl exec code-server-0 -n code-server -- ls -la /home/coder/
```

### 5.4 Performance Baseline

```bash
# Create load test (500 concurrent users, 5 min duration)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: load-test-locust
  namespace: code-server
spec:
  containers:
  - name: locust
    image: locustio/locust:latest
    command: ["locust"]
    args:
      - "-f"
      - "/locustfile.py"
      - "-u"
      - "500"
      - "-r"
      - "50"
      - "-t"
      - "5m"
      - "--csv=results"
      - "https://ide.kushnir.cloud"
    volumeMounts:
    - name: locustfile
      mountPath: /
  volumes:
  - name: locustfile
    configMap:
      name: load-test-config
EOF

# Monitor metrics during load test
kubectl top nodes     # Node CPU/memory
kubectl top pods -n code-server  # Pod CPU/memory

# Collect results
kubectl logs load-test-locust -n code-server
```

### 5.5 Monitoring Integration

```bash
# Verify Prometheus is scraping Kubernetes metrics
kubectl port-forward -n monitoring prometheus-0 9090:9090

# Visit http://localhost:9090/targets
# Should show:
# - kubernetes-apiservers (UP)
# - kubernetes-nodes-kubelet (UP)
# - code-server pods (UP)

# Check for metrics
# Query: up{namespace="code-server"}
# Should return 1 for each pod

# Verify Grafana dashboards
kubectl port-forward -n monitoring grafana-0 3000:3000

# Visit http://localhost:3000
# Check: Kubernetes Cluster Overview, Pod CPU/Memory, Node Overview
```

---

## PHASE 6: TRAFFIC MIGRATION (Canary Deployment)

### 6.1 Blue-Green Deployment Setup

**Timeline**: 2 hours  
**Goal**: Gradually shift traffic from Docker Compose (Blue) to Kubernetes (Green)

```bash
# Step 1: DNS weight distribution (start)
# ide.kushnir.cloud → 95% Docker Compose, 5% Kubernetes

# Step 2: Monitor Kubernetes for 30 minutes
# Check: error rate, latency, database connectivity

# Step 3: Increase Kubernetes traffic
# ide.kushnir.cloud → 50% Docker Compose, 50% Kubernetes

# Step 4: Monitor for another 30 minutes
# Check: all metrics nominal, no errors

# Step 5: Full traffic cutover
# ide.kushnir.cloud → 100% Kubernetes (DNS points to Load Balancer)

# Step 6: Monitor after cutover for 1 hour
# If issues detected: revert DNS back to Docker Compose LB
```

### 6.2 DNS Update Commands

```bash
# Using AWS Route53 (assuming ide.kushnir.cloud is in Route53)

# Get current weight for Docker Compose record
aws route53 list-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --query "ResourceRecordSets[?Name=='ide.kushnir.cloud.']"

# Update DNS records with weights
# Blue (Docker Compose) record: weight 50
# Green (Kubernetes) record: weight 50

aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '...weighted routing policy...'
```

---

## PHASE 7: DOCKER COMPOSE DECOMMISSIONING (After 24hr monitoring)

### 7.1 Wait for Stability

```bash
# Monitor for 24 hours
# - Zero errors for 1 hour windows
# - Error rate < 0.01%
# - Latency p99 < 100ms
# - Database replication lag < 10ms

# If issues detected: run ROLLBACK procedure (see below)
```

### 7.2 Archive Docker Compose Environment

```bash
# On production host (192.168.168.31)
ssh akushnir@192.168.168.31 << 'EOF'

# Create archive
cd /home/akushnir/code-server-enterprise
tar czf /home/akushnir/.backups/docker-compose-archive-$(date +%Y%m%d).tar.gz \
  docker-compose.yml \
  docker-compose.base.yml \
  .env \
  Caddyfile.production

# Stop Docker Compose services (keep data)
docker-compose down

# Remove containers (data persists in volumes)
docker container prune -f

# Verify no containers running
docker ps

echo "Docker Compose environment archived and stopped"

EOF
```

### 7.3 Cleanup Resources

```bash
# Delete unused AWS EBS volumes
aws ec2 describe-volumes --region us-east-1 | jq -r '.Volumes[] | select(.State=="available") | .VolumeId' | xargs -I {} aws ec2 delete-volume --region us-east-1 --volume-id {}

# Remove unused security groups
aws ec2 delete-security-group --region us-east-1 --group-id sg-xxxxxxx

# Archive Terraform state for Docker Compose environment
cd terraform/
terraform state pull > backup/terraform-state-docker-compose-$(date +%Y%m%d).json
```

---

## ROLLBACK PROCEDURE (If Issues Detected)

### Emergency Rollback to Docker Compose

**Trigger**: Any of the following conditions met for >5 minutes:
- Error rate > 1%
- Latency p99 > 500ms
- Database connectivity failures
- Data loss detected
- Authentication failures > 10%

```bash
```bash
# 1. IMMEDIATE: Route traffic back to Docker Compose
# Update DNS immediately to point back to Docker Compose load balancer

aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"ide.kushnir.cloud.","Type":"CNAME","TTL":300,"ResourceRecords":[{"Value":"<docker-compose-lb>.region.elb.amazonaws.com"}]}}]}'

# 2. Stop Kubernetes accepting new connections
kubectl patch deployment code-server -n code-server -p '{"spec":{"replicas":0}}'

# 3. Restore Docker Compose on production host
ssh akushnir@192.168.168.31 << 'EOF'

cd /home/akushnir/code-server-enterprise

# Restart Docker Compose
docker-compose up -d

# Wait for services to be ready
docker-compose ps

# Verify health endpoints
curl http://localhost/health

EOF

# 4. Monitor for stability
# Watch error rates, latency, database connectivity for 10 minutes

# 5. Post-mortem
# Root cause analysis within 24 hours
# Document issues, resolution, and prevention strategies
```

---

## MONITORING & ONGOING OPERATIONS

### Prometheus Queries for Monitoring

```promql
# Pod CPU Usage
sum(rate(container_cpu_usage_seconds_total{namespace="code-server"}[5m])) by (pod)

# Pod Memory Usage
sum(container_memory_usage_bytes{namespace="code-server"}) by (pod)

# HTTP Request Rate
sum(rate(http_requests_total{namespace="code-server"}[5m])) by (pod)

# Error Rate
sum(rate(http_requests_total{status=~"5.."}[5m])) by (pod) / sum(rate(http_requests_total[5m])) by (pod)

# Database Query Latency
histogram_quantile(0.99, rate(postgresql_query_duration_seconds_bucket[5m]))

# Node CPU Usage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

### Regular Maintenance Tasks

```bash
# Daily checks (automated via cron or scheduled pod)
- kubectl get nodes
- kubectl get pods -n code-server --field-selector=status.phase!=Running
- kubectl get events -n code-server --sort-by='.lastTimestamp'

# Weekly checks (manual)
- Verify backup integrity
- Review error logs and alerts
- Check storage usage (PVC filling up?)

# Monthly checks (manual)
- Update Kubernetes cluster version (rolling update, plan 1 hour)
- Update Helm charts and application images
- Run disaster recovery drill (failover to backup region)
```

---

## SUCCESS CRITERIA

- ✅ All code-server pods running (3+ replicas)
- ✅ No errors in pod logs
- ✅ HTTP 200 responses on health endpoint
- ✅ Workspace files accessible and intact
- ✅ Database queries returning correct data
- ✅ Redis cache functional
- ✅ SSL/TLS certificate valid
- ✅ Error rate < 0.1% for 1 hour
- ✅ Latency p99 < 100ms
- ✅ Auto-scaling scaling correctly on load
- ✅ Prometheus metrics being collected
- ✅ Grafana dashboards displaying data

---

## DOCUMENTATION & HANDOFF

After successful migration:

1. **Update Infrastructure Documentation**
   - Architecture diagram (Docker Compose → Kubernetes)
   - Network topology (VPC, subnets, security groups)
   - DNS configuration

2. **Create Runbooks for:**
   - Scaling cluster (add/remove nodes)
   - Updating application (Helm chart upgrades)
   - Disaster recovery
   - Certificate renewal
   - Database backup/restore

3. **Training**
   - Operations team on Kubernetes basics
   - Troubleshooting common Kubernetes issues
   - pagerduty escalation procedures

4. **Archive**
   - Docker Compose files (for reference only)
   - Terraform state from previous environment
   - Migration logs and timelines

---

## CONTACTS & ESCALATION

| Role | Name | Contact | Availability |
|------|------|---------|--------------|
| DevOps Lead | [TBD] | [TBD] | 24/7 on-call |
| SRE Manager | [TBD] | [TBD] | Business hours |
| AWS TAM | [TBD] | [TBD] | Email response |

---

**Approval Checklist** (Complete before starting migration):

- [ ] All stakeholders approved
- [ ] Backups verified and tested
- [ ] Monitoring configured
- [ ] Rollback plan reviewed and tested
- [ ] Team trained on Kubernetes
- [ ] DNS/CDN team notified
- [ ] Maintenance window communicated to users
- [ ] On-call engineers available

---

**Document Version**: 1.0  
**Last Updated**: April 14, 2026  
**Next Review**: May 14, 2026
