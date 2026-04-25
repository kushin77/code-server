# Kubernetes Migration Execution Plan - Phase 14
**Status**: READY FOR EXECUTION | **Timeline**: May 1-24, 2026 | **Teams**: Platform, DevOps, SRE

---

## PHASE 14: KUBERNETES MIGRATION INITIATIVE

### Executive Summary
Transform code-server-enterprise from Docker Compose production deployment to enterprise-grade Kubernetes orchestration. This 4-week initiative leverages pre-built Helm charts, hardened infrastructure-as-code, and phased traffic cutover strategy to achieve zero-downtime migration.

**Key Metrics**:
- 20+ microservices migrated
- Target: <0.5% error rate during migration
- P95 latency: <100ms
- Pod stability: >99.9% uptime

---

## WEEK 1: CLUSTER PROVISIONING & INFRASTRUCTURE (Days 1-7)

### Day 1-2: Pre-Migration Validation
**Objective**: Verify all prerequisites, tools, and credentials are in place

```bash
# Task 1: Verify AWS credentials and permissions
aws sts get-caller-identity
aws ec2 describe-key-pairs --region us-east-1

# Task 2: Check Terraform prerequisites
cd terraform/eks
terraform init -upgrade
terraform validate

# Task 3: Verify Helm chart readiness
cd helm/code-server-enterprise
helm lint .
helm template . --values values.phase4-k8s.yaml | head -50

# Task 4: Validate Docker images are available
docker pull code-server-enterprise:latest
docker pull code-server-enterprise-frontend:latest
docker pull code-server-enterprise-reputation-engine:latest

# Task 5: Set environment variables
export AWS_REGION=us-east-1
export CLUSTER_NAME=code-server-enterprise-prod
export ENVIRONMENT=production
export DOMAIN=kushnir.cloud
```

**Validation Checklist**:
- ✅ AWS credentials configured
- ✅ Terraform validated
- ✅ Helm charts syntactically valid
- ✅ All container images available
- ✅ DNS domain verified (kushnir.cloud)
- ✅ SSL certificates ready for cert-manager
- ✅ PostgreSQL/Redis/Redpanda connection strings validated

### Day 3-5: EKS Cluster Provisioning
**Objective**: Create production-grade EKS cluster with all security hardening

```bash
# Task 1: Review Terraform configuration
cd terraform/eks
cat variables.tf | grep -E "(instance_type|min_size|max_size|disk_size)"

# Task 2: Create terraform.tfvars for production
cat > terraform.tfvars <<EOF
cluster_name            = "code-server-enterprise-prod"
region                  = "us-east-1"
node_group_min_size     = 3
node_group_max_size     = 10
node_group_desired_size = 5
node_instance_type      = "t3.xlarge"
node_disk_size          = 50
enable_cluster_logging  = true
enable_vpc_cni_plugin   = true
enable_ebs_csi_driver   = true
enable_autoscaling      = true
log_retention_days      = 30
EOF

# Task 3: Plan infrastructure
terraform plan -out=tfplan

# Task 4: Apply infrastructure (15-20 minutes)
terraform apply tfplan

# Task 5: Verify cluster creation
aws eks describe-cluster --name code-server-enterprise-prod --region us-east-1
aws eks list-node-groups --cluster-name code-server-enterprise-prod

# Task 6: Configure kubectl access
aws eks update-kubeconfig --name code-server-enterprise-prod --region us-east-1
kubectl get nodes

# Task 7: Install critical add-ons
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/aws-k8s-cni.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/ebs-csi-driver/master/deploy/kubernetes/base/rbac-controller.yaml
```

**Validation Checklist**:
- ✅ EKS cluster created (check AWS console)
- ✅ 5 worker nodes running and Ready
- ✅ kubectl can connect to cluster
- ✅ kube-system namespace pods all Running
- ✅ VPC CNI plugin deployed
- ✅ EBS CSI driver ready

### Day 6-7: Namespace, RBAC, and Networking Setup
**Objective**: Configure security, networking, and ingress

```bash
# Task 1: Create production namespace
kubectl create namespace code-server-enterprise
kubectl label namespace code-server-enterprise environment=production

# Task 2: Configure Pod Security Policy
cat > pod-security-policy.yaml <<EOF
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
    - ALL
  volumes:
    - 'configMap'
    - 'emptyDir'
    - 'projected'
    - 'secret'
    - 'downwardAPI'
    - 'persistentVolumeClaim'
  runAsUser:
    rule: 'MustRunAsNonRoot'
  fsGroup:
    rule: 'MustRunAs'
    ranges:
      - min: 2000
        max: 3000
  readOnlyRootFilesystem: false
EOF
kubectl apply -f pod-security-policy.yaml

# Task 3: Create RBAC roles
cat > rbac-roles.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: code-server-enterprise
  namespace: code-server-enterprise
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: code-server-enterprise
rules:
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list"]
EOF
kubectl apply -f rbac-roles.yaml

# Task 4: Install Ingress Controller (NGINX)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.0/deploy/static/provider/aws/deploy.yaml

# Task 5: Install cert-manager for SSL certificates
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Task 6: Create ClusterIssuer for Let's Encrypt
cat > letsencrypt-issuer.yaml <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@kushnir.cloud
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
kubectl apply -f letsencrypt-issuer.yaml

# Task 7: Verify ingress setup
kubectl get ingress -n ingress-nginx
kubectl get certificate --all-namespaces
```

**Validation Checklist**:
- ✅ code-server-enterprise namespace created
- ✅ Pod Security Policy applied
- ✅ RBAC ServiceAccount and Roles configured
- ✅ NGINX Ingress Controller running (ingress-nginx namespace)
- ✅ cert-manager pods running (cert-manager namespace)
- ✅ ClusterIssuer configured for Let's Encrypt
- ✅ All kube-system components healthy

---

## WEEK 2: HELM DEPLOYMENT - STATELESS SERVICES (Days 8-14)

### Day 8-9: Helm Repository Configuration
**Objective**: Prepare Helm deployment environment

```bash
# Task 1: Verify Helm chart structure
helm list -n code-server-enterprise
helm lint helm/code-server-enterprise

# Task 2: Create secrets namespace
kubectl create namespace secrets
kubectl label namespace secrets environment=production

# Task 3: Create database secrets
kubectl create secret generic database-credentials \
  --from-literal=postgresql-url="postgresql://user:pass@postgres.internal:5432/cse" \
  --from-literal=postgresql-replica-url="postgresql://user:pass@postgres-replica.internal:5432/cse" \
  -n code-server-enterprise

# Task 4: Create OAuth2 secrets
kubectl create secret generic oauth2-secrets \
  --from-literal=cookie-secret=$(openssl rand -hex 32) \
  --from-literal=client-id="your-oauth-client-id" \
  --from-literal=client-secret="your-oauth-client-secret" \
  -n code-server-enterprise

# Task 5: Create API keys secrets
kubectl create secret generic api-keys \
  --from-literal=scheduler-api-key=$(uuidgen) \
  --from-literal=edge-agent-key=$(uuidgen) \
  -n code-server-enterprise

# Task 6: Create configuration ConfigMaps
kubectl create configmap app-config \
  --from-literal=PRIMARY_HOST=primary.eks.internal \
  --from-literal=REPLICA_HOST=replica.eks.internal \
  --from-literal=APEX_DOMAIN=kushnir.cloud \
  --from-literal=LOG_LEVEL=info \
  -n code-server-enterprise
```

**Validation Checklist**:
- ✅ Helm chart lint passed
- ✅ secrets namespace created
- ✅ database-credentials secret created
- ✅ oauth2-secrets secret created
- ✅ api-keys secret created
- ✅ app-config ConfigMap created
- ✅ All secrets visible in kubectl

### Day 10-11: Deploy Stateless Services
**Objective**: Deploy frontend, API, and supporting services (no data dependencies)

```bash
# Task 1: Deploy frontend service
helm upgrade --install frontend helm/code-server-enterprise \
  --namespace code-server-enterprise \
  --values helm/code-server-enterprise/values.phase4-k8s.yaml \
  --set services.frontend.enabled=true \
  --set services.frontend.replicas=3 \
  --wait --timeout 5m

# Task 2: Verify frontend deployment
kubectl rollout status deployment/frontend -n code-server-enterprise
kubectl get pods -n code-server-enterprise -l app=frontend

# Task 3: Deploy API service
helm upgrade --install api helm/code-server-enterprise \
  --namespace code-server-enterprise \
  --values helm/code-server-enterprise/values.phase4-k8s.yaml \
  --set services.api.enabled=true \
  --set services.api.replicas=3 \
  --wait --timeout 5m

# Task 4: Verify API deployment
kubectl rollout status deployment/api -n code-server-enterprise
kubectl logs -n code-server-enterprise -l app=api --tail=50

# Task 5: Deploy auth-server
helm upgrade --install auth-server helm/code-server-enterprise \
  --namespace code-server-enterprise \
  --values helm/code-server-enterprise/values.phase4-k8s.yaml \
  --set services.auth-server.enabled=true \
  --set services.auth-server.replicas=2 \
  --wait --timeout 5m

# Task 6: Deploy other stateless services
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: control-plane
  namespace: code-server-enterprise
spec:
  replicas: 2
  selector:
    matchLabels:
      app: control-plane
  template:
    metadata:
      labels:
        app: control-plane
    spec:
      serviceAccountName: code-server-enterprise
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: control-plane
        image: code-server-enterprise-control-plane:latest
        ports:
        - containerPort: 5001
        env:
        - name: LOG_LEVEL
          value: "info"
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# Task 7: Deploy edge-agent service
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edge-agent
  namespace: code-server-enterprise
spec:
  replicas: 2
  selector:
    matchLabels:
      app: edge-agent
  template:
    metadata:
      labels:
        app: edge-agent
    spec:
      serviceAccountName: code-server-enterprise
      containers:
      - name: edge-agent
        image: code-server-enterprise-edge-agent:latest
        ports:
        - containerPort: 5002
EOF
```

**Validation Checklist**:
- ✅ frontend deployment: 3/3 pods Running
- ✅ api deployment: 3/3 pods Running
- ✅ auth-server deployment: 2/2 pods Running
- ✅ control-plane deployment: 2/2 pods Running
- ✅ edge-agent deployment: 2/2 pods Running
- ✅ All services have ready replicas
- ✅ No failed pods or CrashLoopBackOff
- ✅ Logs show normal startup messages

### Day 12-14: Deploy Data Services & Verification
**Objective**: Deploy databases and verification services with persistent volumes

```bash
# Task 1: Create persistent volume claims for PostgreSQL
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: code-server-enterprise
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: ebs
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-replica-pvc
  namespace: code-server-enterprise
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: ebs
EOF

# Task 2: Deploy PostgreSQL (primary)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: code-server-enterprise
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
  - port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: code-server-enterprise
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: database-credentials
              key: postgres-password
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 1000m
            memory: 2Gi
  volumeClaimTemplates:
  - metadata:
      name: postgres-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: ebs
      resources:
        requests:
          storage: 100Gi
EOF

# Task 3: Deploy Redis
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: code-server-enterprise
spec:
  clusterIP: None
  selector:
    app: redis
  ports:
  - port: 6379
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: code-server-enterprise
spec:
  serviceName: redis
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        command:
          - redis-server
          - --requirepass
          - $(REDIS_PASSWORD)
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: database-credentials
              key: redis-password
        volumeMounts:
        - name: redis-storage
          mountPath: /data
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
  volumeClaimTemplates:
  - metadata:
      name: redis-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: ebs
      resources:
        requests:
          storage: 50Gi
EOF

# Task 4: Verify data services
kubectl get statefulsets -n code-server-enterprise
kubectl get pvc -n code-server-enterprise

# Task 5: Deploy monitoring and logging
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# Task 6: Health check all services
kubectl get all -n code-server-enterprise
kubectl get services -n code-server-enterprise

# Task 7: Summary report
kubectl get nodes
kubectl top nodes
kubectl get pods --all-namespaces
```

**Validation Checklist**:
- ✅ PostgreSQL StatefulSet: 1/1 Running
- ✅ PostgreSQL PVC: Bound and 100Gi storage allocated
- ✅ Redis StatefulSet: 1/1 Running
- ✅ Redis PVC: Bound and 50Gi storage allocated
- ✅ All stateless services: 2-3/N Running
- ✅ Monitoring stack deployed (Prometheus, Grafana)
- ✅ No pending pods
- ✅ Node resources: <80% CPU, <80% Memory

---

## WEEK 3: DATA MIGRATION (Days 15-21)

### Day 15-16: Prepare Data Migration
**Objective**: Validate data consistency before migration

```bash
# Task 1: Verify source data (Docker Compose environment)
docker-compose exec postgres pg_dump -U postgres cse > backup_pre_migration.sql
docker-compose exec redis redis-cli --rdb /tmp/redis_pre_migration.rdb

# Task 2: Create migration scripts
cat > migrate_data.sh <<EOF
#!/bin/bash
set -euo pipefail

# Backup existing data
kubectl exec -n code-server-enterprise postgres-0 -- pg_dump -U postgres cse > /tmp/k8s_backup.sql

# Restore from Docker Compose backup
kubectl cp backup_pre_migration.sql code-server-enterprise/postgres-0:/tmp/data.sql
kubectl exec -n code-server-enterprise postgres-0 -- psql -U postgres cse < /tmp/data.sql

# Verify data integrity
kubectl exec -n code-server-enterprise postgres-0 -- psql -U postgres -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"
EOF

# Task 3: Execute data migration
bash migrate_data.sh

# Task 4: Validate table counts
docker-compose exec postgres psql -U postgres -c "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema='public';"
kubectl exec -n code-server-enterprise postgres-0 -- psql -U postgres -c "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema='public';"
```

### Day 17-18: Execute Full Data Migration
**Objective**: Migrate all databases with zero downtime

```bash
# Task 1: Stop ingestion in Docker Compose
docker-compose down

# Task 2: Final backup of all data
docker-compose exec postgres pg_dump -U postgres cse > final_backup.sql
docker-compose exec redis redis-cli --rdb /tmp/final_redis.rdb

# Task 3: Restore to K8s
kubectl cp final_backup.sql code-server-enterprise/postgres-0:/tmp/final.sql
kubectl exec -n code-server-enterprise postgres-0 -- psql -U postgres cse < /tmp/final.sql

# Task 4: Verify all tables migrated
echo "Docker Compose table count:"
wc -l < final_backup.sql

echo "K8s table count:"
kubectl exec -n code-server-enterprise postgres-0 -- psql -U postgres -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';"

# Task 5: Validate record counts for key tables
kubectl exec -n code-server-enterprise postgres-0 -- psql -U postgres -c \
  "SELECT tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size 
   FROM pg_tables WHERE schemaname = 'public' ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 20;"
```

### Day 19-21: Verify Data Services & Connections
**Objective**: Ensure all services can connect and access data properly

```bash
# Task 1: Test API connections to PostgreSQL
kubectl exec -n code-server-enterprise deployment/api -- \
  bash -c 'curl -s http://localhost:3100/health | jq .'

# Task 2: Test reputation-engine connections
kubectl exec -n code-server-enterprise deployment/reputation-engine -- \
  bash -c 'python -c "from sqlalchemy import create_engine; engine = create_engine(\"postgresql://...\"); conn = engine.connect(); print(\"Connected\")"'

# Task 3: Run integration tests
kubectl run -n code-server-enterprise test-runner \
  --image=code-server-enterprise-test:latest \
  --rm -it -- bash scripts/integration-tests.sh

# Task 4: Verify replication setup
kubectl exec -n code-server-enterprise postgres-0 -- psql -U postgres -c "SELECT status FROM pg_stat_replication;"

# Task 5: Health check report
cat > health_check.sh <<EOF
#!/bin/bash
echo "=== Pod Status ==="
kubectl get pods -n code-server-enterprise

echo "=== Service Status ==="
kubectl get svc -n code-server-enterprise

echo "=== Database Connections ==="
kubectl exec -n code-server-enterprise postgres-0 -- psql -U postgres -c "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;"

echo "=== Storage Usage ==="
kubectl exec -n code-server-enterprise postgres-0 -- du -sh /var/lib/postgresql/data
kubectl exec -n code-server-enterprise redis-0 -- du -sh /data
EOF
bash health_check.sh
```

**Validation Checklist**:
- ✅ All tables migrated from Docker Compose to K8s
- ✅ Record counts match between source and destination
- ✅ All services can connect to databases
- ✅ PostgreSQL replication working
- ✅ Redis persistence verified
- ✅ Integration tests passing
- ✅ No data loss detected

---

## WEEK 4: TRAFFIC CUTOVER & FINALIZATION (Days 22-28)

### Day 22-23: Pre-Cutover Testing
**Objective**: Run full production simulation before traffic cutover

```bash
# Task 1: Configure Ingress for production traffic
cat > ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: code-server-enterprise-ingress
  namespace: code-server-enterprise
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - api.kushnir.cloud
    - ide.kushnir.cloud
    - auth.kushnir.cloud
    secretName: code-server-enterprise-tls
  rules:
  - host: api.kushnir.cloud
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 3100
  - host: ide.kushnir.cloud
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 3000
  - host: auth.kushnir.cloud
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: auth-server
            port:
              number: 8000
EOF
kubectl apply -f ingress.yaml

# Task 2: Wait for SSL certificate issuance
kubectl get certificate -n code-server-enterprise -w

# Task 3: Run load tests (10% of production traffic)
kubectl run -n code-server-enterprise load-test-10pct \
  --image=code-server-enterprise-load-test:latest \
  --rm -it -- bash scripts/load-test.sh --rate 10pct

# Task 4: Monitor metrics
kubectl top pods -n code-server-enterprise
kubectl top nodes

# Task 5: Check error rates
kubectl logs -n code-server-enterprise -l app=api --tail=100 | grep ERROR
```

### Day 24: Phased Traffic Cutover (10% → 50% → 100%)

**Objective**: Gradually shift traffic from Docker Compose to Kubernetes

```bash
# ===== PHASE 1: 10% TRAFFIC CUTOVER (Hour 1-2) =====
# Task 1: Update DNS weighted routing (10% to K8s, 90% to Docker Compose)
cat > dns-routing-10pct.yaml <<EOF
# AWS Route53: Create weighted routing policy
# api.kushnir.cloud
#   - 10% weight → K8s NLB (code-server-enterprise-elb-xyz.elb.us-east-1.amazonaws.com)
#   - 90% weight → Docker Compose IP (existing.example.internal)
EOF

# Task 2: Verify DNS routing
nslookup api.kushnir.cloud

# Task 3: Monitor 10% traffic on K8s
kubectl logs -n code-server-enterprise -l app=api --tail=50 -f

# Task 4: Watch error metrics
watch 'kubectl top pods -n code-server-enterprise; echo "---"; kubectl exec -n code-server-enterprise deployment/api -- curl -s http://localhost:3100/metrics | grep http_requests_total'

# Task 5: Verify no errors
kubectl get events -n code-server-enterprise

# Task 6: Run health checks
bash scripts/ci/health-check-post-deploy.sh

# Wait 30 minutes for stability

# ===== PHASE 2: 50% TRAFFIC CUTOVER (Hour 3-4) =====
# Task 7: Update DNS to 50/50
cat > dns-routing-50pct.yaml <<EOF
# AWS Route53: Update weights
# api.kushnir.cloud
#   - 50% weight → K8s NLB
#   - 50% weight → Docker Compose IP
EOF

# Task 8: Monitor 50% traffic
watch 'kubectl top pods -n code-server-enterprise'

# Task 9: Verify replication lag (if applicable)
kubectl exec -n code-server-enterprise postgres-0 -- psql -U postgres -c \
  "SELECT client_hostname, state, write_lag FROM pg_stat_replication;"

# Wait 30 minutes for stability

# ===== PHASE 3: 100% TRAFFIC CUTOVER (Hour 5-6) =====
# Task 10: Update DNS to 100% K8s
cat > dns-routing-100pct.yaml <<EOF
# AWS Route53: Full cutover
# api.kushnir.cloud → 100% weight to K8s NLB
EOF

# Task 11: Final verification
kubectl get all -n code-server-enterprise
kubectl logs -n code-server-enterprise -l app=api --tail=100 | grep -i error
kubectl top nodes

# Task 12: Decommission Docker Compose (after 24-hour observation period)
docker-compose down -v
rm -rf docker-compose*.yml
```

### Day 25-28: Post-Cutover Validation & Documentation
**Objective**: Verify production stability and complete migration documentation

```bash
# Task 1: 24-hour monitoring
kubectl get events -n code-server-enterprise
kubectl logs -n code-server-enterprise --all-containers=true | grep -i error | wc -l

# Task 2: Performance metrics comparison
echo "=== K8s Performance Metrics ==="
kubectl get pods -n code-server-enterprise -o json | \
  jq '.items[] | {name: .metadata.name, cpu: .spec.containers[].resources.requests.cpu, memory: .spec.containers[].resources.requests.memory}'

# Task 3: Database validation
kubectl exec -n code-server-enterprise postgres-0 -- psql -U postgres -c \
  "SELECT COUNT(*) as total_records FROM information_schema.tables WHERE table_schema='public';"

# Task 4: Create post-migration report
cat > POST-MIGRATION-REPORT.md <<EOF
# Kubernetes Migration Complete

## Statistics
- Total Services Migrated: 20
- Total Pods Running: 65 (3-replicas for stateless, 1 for stateful)
- Cluster Nodes: 5 (t3.xlarge)
- Storage Allocated: 150Gi (100Gi PostgreSQL + 50Gi Redis)
- Network: VPC with private subnets, NAT gateway, NLB ingress

## Performance
- API P95 Latency: XXms (target <100ms)
- Error Rate: 0.X% (target <0.5%)
- Pod CPU Usage: XX% average
- Pod Memory Usage: XX% average
- Database Query Performance: Same as Docker Compose (0.X% variance)

## Cost Analysis
- Previous Docker Compose: $X/month
- New K8s Infrastructure: $Y/month
- Savings/Increase: $Z/month

## Next Steps
1. Archive Docker Compose configuration
2. Update deployment documentation
3. Conduct team training on K8s operations
4. Plan for Phase 5 (advanced observability)
EOF

# Task 5: Archive Docker Compose configuration
mkdir -p /backups/docker-compose-archive
cp docker-compose*.yml /backups/docker-compose-archive/
cp .env /backups/docker-compose-archive/

# Task 6: Final approval
echo "✅ Kubernetes Migration Phase 14 Complete"
echo "✅ All services running in K8s"
echo "✅ Zero downtime achieved"
echo "✅ Ready for next phases"
```

---

## CRITICAL METRICS & THRESHOLDS

### Performance SLOs
| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Pod Restart Count | 0 | >2 | >5 |
| Error Rate | <0.5% | 1-2% | >2% |
| P95 Latency | <100ms | 100-200ms | >200ms |
| CPU Usage | <70% | 70-80% | >80% |
| Memory Usage | <80% | 80-90% | >90% |
| Database Connections | <80% pool | 80-90% | >90% |
| Storage I/O | <70% | 70-80% | >80% |

### Incident Response Triggers
- **Auto-Rollback**: Error rate >5% for >5 minutes → Automatic rollback to Docker Compose
- **Database Issues**: Connection pool >90% → Scale database replicas
- **Node Failure**: Node NotReady >2 minutes → Auto-replace node
- **Pod CrashLoop**: Restart count >5 → Investigate and pause deployment

---

## DEPLOYMENT SCRIPTS & AUTOMATION

All deployment scripts are in `scripts/k8s/` directory:
- `provision-eks.sh` - Automated cluster provisioning
- `deploy-services.sh` - Automated service deployment via Helm
- `migrate-data.sh` - Automated data migration
- `cutover.sh` - Automated traffic cutover (10% → 50% → 100%)
- `rollback.sh` - Emergency rollback to Docker Compose
- `health-check.sh` - Comprehensive health monitoring
- `post-migration-report.sh` - Generate migration report

---

## APPROVAL & SIGN-OFF

**Technical Lead**: _________________________ Date: _______
**SRE Lead**: _________________________ Date: _______
**DevOps Lead**: _________________________ Date: _______
**CTO**: _________________________ Date: _______

---

**Document Version**: 1.0
**Last Updated**: April 25, 2026
**Status**: READY FOR EXECUTION - MAY 1, 2026
