# Phase 4.2: Service Deployment & Ingress Configuration

**Status**: Ready for Implementation  
**Timeline**: Week 2 of Phase 4  
**Dependencies**: Phase 4.1 (Kubernetes cluster provisioned)

## Overview

Phase 4.2 focuses on deploying all 20+ microservices to Kubernetes and configuring ingress for external access. This phase bridges infrastructure setup with production deployment.

## Quick Start (5 Steps)

### Step 1: Create Application Namespace
```bash
kubectl create namespace code-server-enterprise
kubectl label namespace code-server-enterprise \
  istio-injection=enabled \
  governance/policy=GOV-002 \
  environment=production
```

### Step 2: Setup Secret Management
```bash
# Create database credentials
kubectl create secret generic database-credentials \
  --from-literal=username=postgres \
  --from-literal=password=$(openssl rand -base64 24) \
  -n code-server-enterprise

# Create OAuth credentials (from your OAuth provider)
kubectl create secret generic oauth-credentials \
  --from-literal=client-id="your-client-id" \
  --from-literal=client-secret="your-client-secret" \
  -n code-server-enterprise

# Create API keys and tokens
kubectl create secret generic api-keys \
  --from-literal=jwt-secret=$(openssl rand -base64 32) \
  --from-literal=encryption-key=$(openssl rand -base64 32) \
  -n code-server-enterprise

# Verify secrets created
kubectl get secrets -n code-server-enterprise
```

### Step 3: Deploy Helm Chart (All Services)
```bash
# Deploy all 20+ services
helm install code-server-enterprise ./helm/code-server-enterprise \
  --namespace code-server-enterprise \
  --values helm/code-server-enterprise/values-production.yaml \
  --wait \
  --timeout 10m

# Expected output: release "code-server-enterprise" deployed

# Monitor deployment progress
watch kubectl get pods -n code-server-enterprise
```

### Step 4: Configure Ingress & TLS

**Option A: Using Istio Gateway (Recommended)**
```bash
# Apply Ingress configuration from template
kubectl apply -f helm/code-server-enterprise/templates/ingress.yaml.example \
  -n code-server-enterprise

# Verify ingress created
kubectl get ingress -n code-server-enterprise
kubectl get gateway -n code-server-enterprise

# Check certificate status
kubectl get certificate -n code-server-enterprise
kubectl describe certificate code-server-certificate -n code-server-enterprise
```

**Option B: Using Nginx Ingress Controller**
```bash
# Install Nginx ingress controller (if not already installed)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Wait for LoadBalancer IP assignment
kubectl get svc -n ingress-nginx
```

### Step 5: Validate Deployment
```bash
# Run comprehensive validation
./scripts/k8s/validate-deployment.sh code-server-enterprise

# Check ingress status
kubectl get ingress -n code-server-enterprise -o wide

# Get LoadBalancer IP/hostname
INGRESS_IP=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Ingress IP/Hostname: $INGRESS_IP"
```

## Service Deployment Details

### 20+ Services Deployed

#### Core Infrastructure
- **api** (API Gateway, port 3100)
  - Primary entry point for all requests
  - Rate limiting, authentication, routing
  - Replicas: 3-20 (HPA enabled)
  
- **frontend** (Web UI, port 3000)
  - React/Vue application
  - Static asset serving
  - Replicas: 2-15

- **postgres** (Database, port 5432)
  - PostgreSQL 16
  - Persistent storage (100GB)
  - Single instance (backup external)

- **redis** (Cache, port 6379)
  - Redis 7+
  - In-memory cache
  - Single instance with persistence

#### Governance & Control
- **paperclip-control-plane** (port 8010)
  - Approval gating engine
  - OPA policy integration
  - Replicas: 2-5

- **reputation-engine** (port 8002)
  - User tier scoring
  - Cost discount calculation
  - Replicas: 2-8

#### Execution & Scheduling
- **execution-scheduler** (port 8080)
  - Task routing engine
  - Resource allocation
  - Replicas: 2-5

- **agent-runtime** (ports 9001-9004)
  - 4 agent types (code-reviewer, incident-responder, doc-writer, test-generator)
  - Autonomous agent execution
  - Replicas: 1-8

#### Observability & Analytics
- **activity-feed** (port 8020)
  - Real-time event streaming
  - Audit logging
  - Replicas: 2-5

- **knowledge-graph** (port 8025)
  - Entity relationship management
  - Graph queries
  - Replicas: 1-3

- **monitoring** services
  - Prometheus, Grafana, Jaeger, Loki
  - Already deployed in Phase 4.1

#### Additional Services
- session-snapshots (port 8030)
- prompt-gateway (port 8035)
- multimodal-ai (port 8040)
- self-healing (port 8045)
- presence-sidecar (port 8050)
- federation (port 8055)
- (and 10+ more)

## Ingress Configuration

### DNS Setup

#### AWS Route53
```bash
# Create A record pointing to Ingress LoadBalancer
aws route53 change-resource-record-sets \
  --hosted-zone-id Z... \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "INGRESS_ZONE_ID",
          "DNSName": "api-nlb-abc.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'

# Create CNAME for additional domains
aws route53 change-resource-record-sets \
  --hosted-zone-id Z... \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "ide.example.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "api.example.com"}]
      }
    }]
  }'
```

#### Google Cloud DNS
```bash
# Get Ingress external IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

# Create DNS record
gcloud dns record-sets create api.example.com \
  --rrdatas=$INGRESS_IP \
  --ttl=300 \
  --type=A \
  --zone=example-zone
```

#### Azure DNS
```bash
# Get Ingress IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

# Create DNS record
az network dns record-set a add-record \
  --resource-group myResourceGroup \
  --zone-name example.com \
  --record-set-name api \
  --ipv4-address $INGRESS_IP
```

### TLS/SSL Certificate Setup

#### Option 1: cert-manager with Let's Encrypt (Recommended)
```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create ClusterIssuer for Let's Encrypt
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: istio
EOF

# Certificate will be auto-provisioned when Ingress is created
kubectl get certificate -n code-server-enterprise
kubectl describe certificate code-server-certificate -n code-server-enterprise
```

#### Option 2: Bring Your Own Certificate
```bash
# Create secret with existing certificate
kubectl create secret tls code-server-enterprise-tls \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem \
  -n code-server-enterprise

# Reference in Ingress
kubectl patch ingress api-gateway -n code-server-enterprise \
  -p '{"spec":{"tls":[{"hosts":["api.example.com"],"secretName":"code-server-enterprise-tls"}]}}'
```

### Traffic Routing (Path-Based)

```
api.example.com/api/*              → api:3100
api.example.com/health             → api:3100
api.example.com/metrics            → api:3100
ide.example.com/*                  → frontend:3000
grafana.example.com/*              → monitoring-grafana:80
```

### Advanced Routing with Istio

```bash
# Canary deployment (5% traffic to canary, 95% to stable)
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-canary
  namespace: code-server-enterprise
spec:
  hosts:
  - api.example.com
  gateways:
  - code-server-gateway
  http:
  - match:
    - headers:
        user-agent:
          prefix: "canary-tester"
    route:
    - destination:
        host: api-canary
        port:
          number: 3100
      weight: 100
  - route:
    - destination:
        host: api
        port:
          number: 3100
      weight: 95
    - destination:
        host: api-canary
        port:
          number: 3100
      weight: 5
EOF
```

## Health Check Configuration

### Liveness Probes
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 3100
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

### Readiness Probes
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 3100
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 2
```

## Monitoring During Deployment

### Watch Pod Rollout
```bash
kubectl rollout status deployment/api -n code-server-enterprise
kubectl rollout status deployment/frontend -n code-server-enterprise

# Monitor all services
watch kubectl get deployments -n code-server-enterprise
```

### Check Resource Usage
```bash
# Pod resource usage
kubectl top pods -n code-server-enterprise

# Node resource usage
kubectl top nodes

# Persistent volume usage
kubectl get pv -n code-server-enterprise
```

### View Events
```bash
# Recent events
kubectl get events -n code-server-enterprise --sort-by='.lastTimestamp'

# Specific pod events
kubectl describe pod api-xyz -n code-server-enterprise
```

## Post-Deployment Verification

### Test Internal Connectivity
```bash
# From one pod, test connectivity to another
POD=$(kubectl get pod -n code-server-enterprise -l app=api -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $POD -n code-server-enterprise -- \
  curl -s http://frontend:3000/health | jq .

kubectl exec -it $POD -n code-server-enterprise -- \
  curl -s http://reputation-engine:8002/health | jq .
```

### Test External Connectivity
```bash
# Get Ingress endpoint
kubectl get ingress -n code-server-enterprise -o wide

# Test external endpoints
curl -k https://api.example.com/health
curl -k https://ide.example.com/
curl -k https://grafana.example.com/

# Check certificate
openssl s_client -connect api.example.com:443 -showcerts
```

### Load Testing
```bash
# Generate load to test autoscaling
kubectl run -it --image=busybox --restart=Never load-gen -- \
  /bin/sh -c "while true; do wget -q -O- https://api.example.com/health; done"

# In another terminal, watch scaling
watch kubectl get pods -n code-server-enterprise

# Monitor metrics in Grafana
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# http://localhost:3000
```

## Rollback Procedures

### Rollback Failed Deployment
```bash
# Check rollout history
kubectl rollout history deployment/api -n code-server-enterprise

# Rollback to previous version
kubectl rollout undo deployment/api -n code-server-enterprise

# Rollback to specific revision
kubectl rollout undo deployment/api --to-revision=2 -n code-server-enterprise
```

### Rollback Helm Release
```bash
# Check release history
helm history code-server-enterprise -n code-server-enterprise

# Rollback to previous release
helm rollback code-server-enterprise -n code-server-enterprise

# Rollback to specific revision
helm rollback code-server-enterprise 1 -n code-server-enterprise
```

## Troubleshooting

### Pods Not Starting
```bash
# Check pod status
kubectl describe pod <pod-name> -n code-server-enterprise

# Common issues:
# - Image pull errors: Check container registry credentials
# - Insufficient resources: Scale down replicas or add nodes
# - ConfigMap/Secret missing: Verify secret creation

# View logs
kubectl logs <pod-name> -n code-server-enterprise
```

### High Latency
```bash
# Check network policies
kubectl get networkpolicy -n code-server-enterprise

# Verify mTLS is working (adds small latency overhead)
kubectl get peerauthentication -n code-server-enterprise

# Check service endpoints
kubectl get endpoints -n code-server-enterprise

# Test direct service connectivity
kubectl exec -it pod/api-xyz -- \
  curl -w "@curl-format.txt" -o /dev/null -s https://reputation-engine:5000
```

### Certificate Issues
```bash
# Check certificate status
kubectl get certificate -n code-server-enterprise

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Manually renew certificate
kubectl delete certificate code-server-certificate \
  -n code-server-enterprise
# cert-manager will recreate it

# Check secret
kubectl get secret code-server-enterprise-tls -n code-server-enterprise -o yaml
```

## Next Steps (Phase 4.3)

### Week 3: Traffic Migration
1. Choose migration strategy (blue-green, canary, or DNS)
2. Execute gradual traffic cutover from Docker Compose
3. Monitor error rates and latency during migration
4. Validate data consistency

### Week 4: Production Stabilization
1. Monitor for anomalies and optimize performance
2. Fine-tune autoscaling parameters
3. Implement comprehensive backup procedures
4. Conduct disaster recovery drills

## Success Criteria

✅ Deployment successful if:
- All 20+ services deployed and running
- All pods passing health checks (liveness + readiness)
- Ingress configured and TLS certificates provisioned
- External endpoints responding correctly
- HPA configured and functional
- Monitoring dashboards showing data
- Load testing passed (sustained baseline)
- No data loss or corruption

---

**Phase Status**: Ready for Implementation  
**Governance**: GOV-002 Enterprise Standards  
**Last Updated**: April 2026
