# Cost Optimization Runbook

## Goal
Reduce monthly cloud spend while maintaining 99.95% SLO.

## Cost Baseline (Monthly Estimate)

| Component | Count | Size | Cost/Month |
|-----------|-------|------|-----------|
| **Compute (GKE)** | — | — | **$5,000** |
| Node pool (3x n2-standard-4) | 3 | 4vCPU, 16GB | $1,800 |
| Pod resources (burst reserves) | — | — | $2,000 |
| Load balancer ingress | 1 | — | $1,200 |
| **Storage** | — | — | **$800** |
| Persistent volumes (20GB) | 4 | 5GB each | $400 |
| GCS buckets (backups) | 2 | 50GB total | $300 |
| Snapshots (daily) | 5 | — | $100 |
| **Networking** | — | — | **$600** |
| Egress (100GB/month) | 100GB | — | $400 |
| VPN tunnels | 2 | — | $200 |
| **Database** | — | — | **$1,500** |
| Cloud SQL (db-custom-4-16gb) | 1 | — | $1,500 |
| **Observability** | — | — | **$800** |
| Prometheus retention (7d) | — | — | $300 |
| Grafana Cloud nodes | 2 | — | $400 |
| Logs (Cloud Logging 100GB) | 100GB | — | $100 |
| **TOTAL** | — | — | **~$8,700/month** |

## Optimization Strategies

### 1. Rightsizing Compute (Save ~$800/month)

**Current State**:
- Node pool: 3x n2-standard-4 (4vCPU, 16GB each)
- Average utilization: 30% CPU, 35% memory

**Optimization**:
```bash
# Switch to preemptible (spot) nodes for non-critical workloads
# Saves 70% on compute cost

# Use node affinity to separate workloads
# - code-server (always-on): standard nodes
# - agent-api (burstable): preemptible nodes
# - embeddings (batch): preemptible nodes

# Modify kustomization
kubectl patch nodepool production \
  --type merge -p '{
    "spec": {
      "nodeConfig": {
        "preemptible": true,
        "machineType": "n2-standard-2"
      }
    }
  }'
```

**Expected Savings**: $600-800/month

**Risk**: Preemptible nodes can be terminated → use pod disruption budgets

```yaml
# Already in kubernetes/base/embeddings-service.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: agent-api-pdb
spec:
  minAvailable: 2  # Keep at least 2 replicas running
```

### 2. Autoscaling Optimization (Save ~$500/month)

**Current State**:
- Static HPA: min=2, max=10 for agent-api
- Running minimum 2 replicas 24/7, even at 5% utilization

**Optimization**:
```yaml
# Use GMSA (Google Managed Service for Anthos) for automated scaling
# Or implement more aggressive scale-down policy

apiVersion: autoscaling.k8s.io/v2
kind: HorizontalPodAutoscaler
metadata:
  name: agent-api-hpa
spec:
  minReplicas: 1  # Reduce from 2
  maxReplicas: 10
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60  # Faster scale-down
      policies:
        - type: Percent
          value: 50
          periodSeconds: 60
        - type: Pods
          value: 1
          periodSeconds: 120
      selectPolicy: Min  # Choose most aggressive scale-down
```

**Expected Savings**: $300-500/month (2-3 fewer pods running 24/7)

### 3. Database Optimization (Save ~$400/month)

**Current State**:
- Cloud SQL: db-custom-4-16gb ($1,500/month)
- High-memory allocated but 40% utilized

**Optimization Strategies**:

**A. Downsize instance**:
```bash
# Test db-custom-2-8gb in staging
gcloud sql instances patch code-server \
  --tier=db-custom-2-8gb \
  --no-backup-fail-on-backup-error
```
Expected savings: $400-600/month

**B. Switch to Cloud Firestore** (if applicable):
- No server to manage
- Pay per operation
- OK for <100M operations/month
Expected savings: $300-800/month

**C. Enable automated backups rotation**:
```bash
# Keep only 7-day backups instead of 30-day
gcloud sql instances patch code-server \
  --retained-backups-count=7 \
  --transaction-log-retention-days=5
```
Expected savings: $100-150/month

### 4. Storage Optimization (Save ~$200/month)

**Current State**:
- 20GB persistent volumes @ $0.17/GB = $3.4/GB month
- Old snapshots retained indefinitely

**Optimization**:

```bash
# Delete old snapshots (>30 days)
gcloud compute snapshots list --filter="creationTimestamp<"$(date -d '30 days ago' -Iseconds)"" \
  --format="value(name)" | xargs -I {} gcloud compute snapshots delete {} --quiet

# Archive old logs to Cloud Storage (cheaper)
# $0.004/GB in Archive storage vs $0.020/GB in Standard
gcloud logging describe sink projects/_/sinks/archive-old-logs \
  --bucket-name=gs://archive-logs-bucket
```

Expected savings: $100-200/month

### 5. Networking Optimization (Save ~$200/month)

**Current State**:
- 100GB egress/month @ $0.12/GB = $12/GB
- All traffic routed through load balancer

**Optimization**:

```bash
# Use Cloud CDN for static assets
# Cache at edge, reduce origin egress

gcloud compute backend-services create static-assets \
  --global \
  --enable-cdn \
  --cache-mode=CACHE_ALL_STATIC \
  --default-ttl=3600

# Compress response bodies
# 70% reduction for JSON/text responses
# Do in application layer or Nginx ingress
```

Expected savings: $150-300/month

### 6. Observability Cost Reduction (Save ~$100/month)

**Current State**:
- Prometheus 7-day retention: expensive on fully-managed
- Grafana Cloud nodes: 2 nodes @ $200/month

**Optimization**:

```bash
# Reduce Prometheus retention to 3 days
kubectl patch statefulset prometheus -n observability -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "prometheus",
          "args": [
            "--storage.tsdb.retention.time=3d"
          ]
        }]
      }
    }
  }
}'

# Use Grafana Loki for logs instead of Cloud Logging
# $0.003/GB ingested (vs $0.50/GB in Cloud Logging)
```

Expected savings: $200-300/month

## Monthly Savings Summary

| Optimization | Savings | Effort |
|--------------|---------|--------|
| Preemptible nodes + Pod Disruption | $700 | Medium |
| Aggressive autoscaling | $400 | Low |
| Database downsize | $400 | Medium |
| Storage/snapshot cleanup | $200 | Low |
| Networking/CDN | $200 | Medium |
| Observability tuning | $250 | Low |
| **TOTAL POTENTIAL** | **$2,150/month** | — |
| **% Reduction** | **25%** | — |

## Implementation Roadmap

### Week 1: Quick Wins (Low Risk)
- [ ] Enable automated snapshot deletion
- [ ] Reduce log retention
- [ ] Optimize database backups
- [ ] Expected savings: $300-400/month

### Week 2: Compute Optimization (Medium Risk)
- [ ] Test preemptible nodes in staging
- [ ] Deploy to 50% of agent-api pool
- [ ] Monitor for preemptions, adjust PDB
- [ ] Expected savings: $300-500/month

### Week 3: Autoscaling Enhancement (Low Risk)
- [ ] Adjust HPA parameters
- [ ] Monitor scale-down events
- [ ] Fine-tune stabilization windows
- [ ] Expected savings: $200-300/month

### Week 4: Database/Networking (Medium Risk)
- [ ] Load test with smaller DB tier
- [ ] Implement Cloud CDN
- [ ] Monitor performance metrics
- [ ] Expected savings: $400-600/month

## Monitoring & Alerts

Track cost impact with these metrics:

```yaml
# Prometheus queries
# Daily cost trend
rate(total_cost_usd[1d])

# Cost by service
sum by (service) (resource_cost_monthly)

# Cost per request/user
cost_per_request = total_cost_usd / total_requests
cost_per_user = total_cost_usd / active_users
```

## Cost Targets (SLO)

| Metric | Target | Frequency |
|--------|--------|-----------|
| Cost per request | < $0.001 | Monthly |
| Cost per active user | < $0.10 | Monthly |
| Total monthly spend | < $7,500 | Daily |
| Cost variance | ±10% month-over-month | Monthly |

## Escalation for Cost Spikes

```bash
# Alert if cost increases > 20% in 1 day
if (current_daily_cost > previous_avg * 1.2) {
  slack_notify("alert", "Cost spike: $X detected")
}
```

If spike detected:
1. Check recent deployments (new replicas?)
2. Check for storage leaks (logs, snapshots?)
3. Check traffic patterns (DDoS?)
4. Query GCP Billing API for detailed breakdown
