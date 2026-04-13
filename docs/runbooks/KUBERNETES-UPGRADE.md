# Kubernetes Upgrade & Rollback Runbook

## Overview

This runbook covers upgrading the Kubernetes cluster from one version to the next while maintaining service availability.

## Pre-Upgrade Checklist

- [ ] Kubernetes version to upgrade to is defined
- [ ] Compatibility verified (all apps compatible with target k8s version)
- [ ] Upgrade window scheduled outside peak hours (not 4pm-6pm EST)
- [ ] Maintenance window announced to users (24-hour notice)
- [ ] Full backup of etcd taken
- [ ] Load balancer pointing to 2+ nodes for HA
- [ ] Pod Disruption Budgets verified (at least 2 replicas per service)
- [ ] Rollback plan tested

**Verification Script**:
```bash
# Check all services have replicas >= 2
kubectl get deployment -A -o json | jq '.items[] | 
  select(.spec.replicas < 2) | 
  {name: .metadata.name, namespace: .metadata.namespace, replicas: .spec.replicas}'

# Check PDBs are properly defined
kubectl get pdb -A

# Verify etcd health
kubectl get componentstatus -n kube-system
```

## Upgrade Strategy: Rolling Update (Blue-Green)

To minimize downtime, we'll upgrade nodes in stages:

1. **Blue Environment** (current): All pods running on old k8s version
2. **Green Environment** (new): New nodes with newer k8s version
3. **Cutover**: Gradually move pods from Blue → Green

## Stage 1: Control Plane Upgrade (Pre-dawn, 2am-4am)

```bash
# 1. Backup etcd
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system $ETCD_POD -- \
  etcdctl --endpoints=localhost:2379 \
  snapshot save /tmp/etcd-backup.db

# 2. Copy backup out of pod
kubectl cp kube-system/$ETCD_POD:/tmp/etcd-backup.db ./etcd-backup.db

# 3. Upgrade control plane
# This is typically done via GKE release channel or managed k8s platform UI
# For self-managed, upgrade API server, scheduler, controller-manager

# Example for GKE:
gcloud container clusters upgrade $CLUSTER_NAME \
  --master \
  --cluster-version 1.29.0 \
  --quiet

# 4. Monitor control plane
kubectl get nodes --watch
# Wait until Ready condition is True
```

**Estimated Time**: 15-30 minutes

## Stage 2: Worker Node Upgrade (Rolling - 1 node at a time)

```bash
# Get list of nodes (excluding master-only nodes)
kubectl get nodes -o wide

# For each node:
for NODE in node-1 node-2 node-3; do
  echo "Upgrading $NODE..."
  
  # 1. Cordon node (prevent new pods)
  kubectl cordon $NODE
  
  # 2. Drain pods from node (graceful eviction)
  kubectl drain $NODE \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --grace-period=30 \
    --timeout=5m
  
  # 3. Wait for all pods to move to other nodes
  kubectl get pods -o wide | grep $NODE
  # Should return nothing after drain completes
  
  # 4. Upgrade node OS + kubelet
  # This varies by provider:
  
  # GKE:
  gcloud compute instances stop $NODE
  gcloud compute instances start $NODE
  # GKE auto-upgrades kubelet on node restart
  
  # OR Self-managed (SSH to node):
  ssh ubuntu@$NODE_IP "sudo apt update && sudo apt upgrade -y"
  
  # 5. Uncordon node (allow pod scheduling)
  kubectl uncordon $NODE
  
  # 6. Wait for node to be ready
  kubectl wait --for=condition=Ready node/$NODE --timeout=5m
  
  # 7. Verify pods are returning to node
  sleep 30
  kubectl get pods -o wide | grep $NODE
  # Should show pods returning
  
  echo "✅ $NODE upgraded successfully"
done
```

**Estimated Time**: 15 minutes per node (45 minutes total for 3-node cluster)

## Stage 3: Validation (Post-upgrade)

```bash
# 1. Verify all nodes are Ready
kubectl get nodes
# All should show "Ready" in STATUS column

# 2. Verify cluster version
kubectl version --short
# Server version should match target

# 3. Verify all pods are running
kubectl get pods -A
# No pods should be in Pending/CrashLoopBackOff/Error

# 4. Verify critical services
kubectl get deployment -A | grep -E "code-server|agent-api|prometheus"
# All should show desired == available

# 5. Run health checks
for svc in code-server agent-api embeddings; do
  curl -f https://${svc}.prod.example.com/health || echo "❌ $svc failed"
done

# 6. Run smoke tests
./scripts/smoke-tests.sh production

# 7. Monitor metrics (watch for 15 minutes)
watch -n 5 'kubectl top nodes; echo "---"; kubectl top pod -A | head -20'
```

## Rollback Procedure

If validation fails, rollback immediately:

### Option A: Rollback Control Plane (if cluster is broken)

```bash
# Restore etcd from backup
kubectl cp ./etcd-backup.db kube-system/$ETCD_POD:/tmp/etcd-restore.db

kubectl exec -n kube-system $ETCD_POD -- \
  etcdctl --endpoints=localhost:2379 \
  snapshot restore /tmp/etcd-restore.db --data-dir /var/lib/etcd-restored

# Restart kube-apiserver
kubectl delete pod -n kube-system -l component=kube-apiserver
```

### Option B: Drain new nodes, re-enable old nodes

```bash
# If new nodes are using new k8s version and old k8s still running:

# 1. Cordon new nodes
kubectl cordon node-new-1 node-new-2

# 2. Drain to old nodes
kubectl drain node-new-1 --ignore-daemonsets

# 3. Delete new nodes
kubectl delete node node-new-1

# 4. Uncordon old nodes
kubectl uncordon node-old-1 node-old-2
```

### Option C: Application rollback (if app incompatible)

```bash
# Revert recent deployments
kubectl set image deployment/code-server \
  code-server=code-server:v1.2.3 \
  -n code-server

kubectl rollout status deployment/code-server -n code-server
```

## Post-Upgrade Tasks

1. **Documentation Update**
   - Update cluster version in README
   - Document any breaking changes encountered

2. **Monitoring**
   - Review metrics for next 24 hours
   - Set up alerts for any degradation

3. **Post-Mortem** (if any issues)
   - Document what went wrong
   - Update procedures for next upgrade

4. **Release Notes Review**
   - Read k8s release notes
   - Plan for next version upgrade

## Common Issues & Solutions

### Issue: Pod not rescheduling after drain

```bash
# Check if node has capacity
kubectl describe node NODE_NAME

# Check pod events
kubectl describe pod POD_NAME -n NAMESPACE

# Force eviction if stuck
kubectl delete pod POD_NAME -n NAMESPACE --grace-period=0 --force
```

### Issue: Node stuck in "NotReady"

```bash
# Check node logs
kubectl describe node NODE_NAME

# Restart kubelet
ssh ubuntu@NODE_IP "sudo systemctl restart kubelet"

# Wait for node to become Ready
kubectl wait --for=condition=Ready node/NODE_NAME --timeout=10m
```

### Issue: Control plane API unstable

```bash
# Check API server logs
kubectl logs -n kube-system -l component=kube-apiserver --tail=50

# Check etcd health
kubectl exec -n kube-system etcd-pod -- \
  etcdctl -w table endpoint status

# If etcd is unhealthy, restore from backup
```

## Upgrade Schedule

Plan upgrades to align with k8s release schedule:

```
k8s Version | Release Date | Support Ends | Our Deadline
1.27        | Apr 2023     | Dec 2023     | Jun 2023
1.28        | Aug 2023     | Apr 2024     | Oct 2023
1.29        | Dec 2023     | Aug 2024     | Feb 2024
1.30        | Apr 2024     | Dec 2024     | Jun 2024
```

**Upgrade Frequency**: Every 2-3 minor versions (skip 1-2, never fall more than 2 behind)

## Pre-Production Testing

Before upgrading production, test in staging:

```bash
# 1. Mirror production cluster in staging
# 2. Perform full upgrade on staging cluster
# 3. Run all integration tests
# 4. Generate upgrade runbook refinements
# 5. Get approval before touching production
```

## Notification Template

Announce upgrade to customers:

```
Subject: Scheduled Maintenance - Kubernetes Cluster Upgrade

Dear Customers,

We'll be upgrading our Kubernetes infrastructure on [DATE] from [TIME] to [TIME] UTC.

During this window, you may experience:
- Brief latency increases (< 1 second)
- Possible brief connectivity drops (< 1 minute)
- Service interruptions are NOT expected

Our platform is designed to handle this seamlessly with zero downtime.

Questions? Contact support@example.com

Best regards,
Operations
```

## Success Criteria

✅ All nodes running k8s version X.Y.Z
✅ All pods scheduled and running
✅ Health checks passing
✅ Smoke tests passing
✅ Error rate < 0.1%
✅ P99 latency < 1 second
✅ No customer complaints (30-min wait period)
