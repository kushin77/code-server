# QUICK REFERENCE - DEPLOYMENT CHECKLIST

## Pre-Deployment (Do First!)

### System Requirements
- [ ] kubectl installed and working
- [ ] docker or containerd available
- [ ] bash shell available
- [ ] Minimum 500GB storage available
- [ ] Network connectivity to cluster
- [ ] sudo access for system configuration

### Cluster Preparation
- [ ] Kubernetes 1.27+ cluster available
- [ ] kubeadm pre-installed on nodes
- [ ] Nodes can communicate with each other
- [ ] DNS resolution working
- [ ] Time synchronized across nodes (ntpd)

---

## Phase 1: Preparation

```bash
cd scripts/
chmod +x *.sh
./deploy-orchestration.sh 1 1
```

**Verification:**
- [ ] kubectl can access cluster
- [ ] Nodes show Ready status
- [ ] Storage path exists and accessible

---

## Phase 2: Kubernetes Cluster

```bash
./deploy-orchestration.sh 2 2
```

**Expected Result:**
```
✓ Control plane initialized
✓ Flannel networking deployed
✓ CoreDNS operational
✓ All system pods running
✓ Join command generated
```

**Check:**
```bash
kubectl get nodes
kubectl get pods -n kube-system
```

---

## Phase 3: Observability

```bash
./deploy-orchestration.sh 3 3
```

**Expected Services:**
- Prometheus: `prometheus-lb:9090`
- Grafana: `grafana:3000` (admin/pwd)
- Loki: `loki-loadbalancer:3100`
- Promtail: DaemonSet (all nodes)
- AlertManager: `alertmanager:9093`

**Check:**
```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

---

## Phase 4: Security

```bash
./deploy-orchestration.sh 4 4
```

**Expected:**
- [ ] Network policies deployed
- [ ] RBAC roles created
- [ ] Pod security standards applied
- [ ] Audit logging configured

**Check:**
```bash
kubectl get networkpolicies -A
kubectl get clusterroles | grep read-only
```

---

## Phase 5: Backup

```bash
./deploy-orchestration.sh 5 5
```

**Expected:**
- Velero deployed (2 replicas)
- Daily backup at 02:00 UTC
- Hourly incremental backups
- Backup storage operational

**Check:**
```bash
kubectl get pods -n velero
ls -lh /backups/velero/
```

---

## Phase 6: Application Platform

```bash
./deploy-orchestration.sh 6 6
```

**Expected:**
- code-server StatefulSet (1 replica)
- 100Gi workspace storage
- Extensions pre-installed
- Service account configured

**Check:**
```bash
kubectl get statefulsets -n code-server
kubectl get pvc -n code-server
```

---

## Phase 7: Ingress & Load Balancing

```bash
./deploy-orchestration.sh 7 7
```

**Expected:**
- NGINX ingress controller running
- Cert-Manager operational
- TLS certificates created
- LoadBalancer service with IP

**Check:**
```bash
kubectl get daemonset -n ingress-nginx
kubectl get svc ingress-nginx -n ingress-nginx
kubectl get ingress -A
```

---

## Phase 8: Final Verification

```bash
./deploy-orchestration.sh 8 8
```

**Output:**
- Security audit results
- Component health status
- Performance metrics
- Compliance checklist
- Documentation files

**Review:**
- [ ] All phases completed
- [ ] No critical errors
- [ ] All pods running
- [ ] LoadBalancer IP assigned

---

## POST-DEPLOYMENT CRITICAL TASKS

### ⚠️ SECURITY - CHANGE PASSWORDS IMMEDIATELY

```bash
# 1. Change Grafana password
kubectl port-forward svc/grafana 3000:3000 -n monitoring &
# Access: http://localhost:3000
# Login: admin / ChanGedDefaultPassword123!
# Change password in Settings > Users > Admin User

# 2. Change code-server password
kubectl set env deployment/code-server CODER_PASSWORD=<new-password> -n code-server
```

### 🌐 Configure DNS

```bash
# Get LoadBalancer IP
kubectl get svc ingress-nginx -n ingress-nginx -o wide

# Point DNS A records to this IP:
# code-server.enterprise.local     → <IP>
# monitoring.enterprise.local      → <IP>
# logs.enterprise.local            → <IP>
# api.enterprise.local             → <IP>
```

### ✅ Verify Services

```bash
# Access points
echo "Prometheus: http://prometheus-lb:9090"
echo "Grafana: http://grafana:3000"
echo "code-server: http://code-server:8080"
echo "Loki: http://loki-loadbalancer:3100"
echo "AlertManager: http://alertmanager:9093"

# Test connectivity
kubectl run -it --rm debug --image=busybox -- nslookup kubernetes.default
```

### 📋 Review Documentation

Generated files:
- `DEPLOYMENT_COMPLETE.md` - Full deployment info
- `PRODUCTION_CHECKLIST.md` - Sign-off checklist
- `OPERATIONAL_RUNBOOKS.md` - Troubleshooting guides
- `DEPLOYMENT_GUIDE.md` - This guide

---

## Daily Monitoring

```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A

# Check if backups ran
kubectl get backups -n velero | head -5

# Check alerts
# Access: AlertManager or Prometheus UI

# Check resource usage
kubectl top nodes
kubectl top pods -A | sort -k2 -rn | head -10
```

---

## Weekly Maintenance

```bash
# Review Grafana dashboards
# - Go to Grafana dashboard URL
# - Check: CPU, Memory, Disk, Network

# Verify backup completion
kubectl describe backup <latest-backup-name> -n velero

# Check certificate expiration
kubectl get cert -A

# Update images if needed
kubectl set image deployment/<name> <container>=<image> -n <namespace>
```

---

## Monthly Tasks

```bash
# Test disaster recovery
# (restore from backup to test environment)
./scripts/restore.sh <backup-name>

# Security audit
# Review: RBAC, network policies, secrets, audit logs

# Capacity planning
# Check: CPU/Memory usage, Storage growth, Pod count trends

# Documentation review
# Update runbooks based on lessons learned
```

---

## Emergency Procedures

### Cluster Down

```bash
# 1. Check API server
kubectl get componentstatus

# 2. Check etcd
kubectl get pods -n kube-system -l component=etcd

# 3. Check kubelet on nodes
systemctl status kubelet

# 4. Restart if needed (careful!)
sudo systemctl restart kubelet
```

### Pod Stuck

```bash
# 1. Check what's wrong
kubectl describe pod <pod-name> -n <namespace>

# 2. Check logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# 3. Force delete if necessary (last resort)
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force
```

### Storage Issue

```bash
# 1. Check available space
df -h /data/* /backups/*

# 2. Find large files
du -sh /* 2>/dev/null | sort -rh | head -10

# 3. Clean up old logs/backups if needed
find /backups -mtime +30 -delete
```

### Backup Failed

```bash
# 1. Check Velero status
kubectl get pods -n velero
kubectl logs deployment/velero -n velero

# 2. Trigger manual backup
kubectl create -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: manual-fallback-$(date +%s)
  namespace: velero
spec:
  includedNamespaces: ["*"]
  ttl: "720h"
EOF

# 3. Monitor
kubectl get backups -n velero -w
```

---

## Useful Commands Reference

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes -o wide
kubectl get all -A

# Service access
kubectl port-forward svc/<service> <local-port>:<remote-port> -n <namespace>

# Container debugging
kubectl get logs <pod> -n <namespace>
kubectl exec -it <pod> -n <namespace> -- /bin/bash
kubectl describe pod <pod> -n <namespace>

# Resource management
kubectl top nodes
kubectl top pods -A
kubectl describe resource pvc

# Configuration
kubectl get cm -n <namespace>
kubectl get secret -n <namespace>
kubectl apply -f file.yaml
kubectl edit deployment/<name> -n <namespace>

# Troubleshooting
kubectl get events -A --sort-by='.lastTimestamp'
kubectl rollout status deployment/<name> -n <namespace>
kubectl logs -f <pod> -n <namespace>
kubectl explain <resource>
```

---

## Critical Contacts & Escalation

| Issue | Action | Contact |
|-------|--------|---------|
| Cluster down | Check components | Platform Team |
| Data loss | Initiate restore | DBA + Platform Team |
| Security breach | Isolate + Audit | Security Team |
| Performance degradation | Check metrics | Platform Team |
| Certificate expiring | Renew | Ops Team |

---

## Acceptance Criteria

**Deployment is COMPLETE when:**
- [x] All 8 phases executed successfully
- [x] All pods in Running/Succeeded state
- [x] All services have endpoints
- [x] Prometheus scraping metrics
- [x] Grafana dashboards visible
- [x] Loki aggregating logs
- [x] Velero backup operational
- [x] Ingress controller responding
- [x] TLS certificates valid
- [x] RBAC policies enforced
- [x] Network policies in place
- [x] All documentation generated

---

## Sign-Off

**Deployment Status:** ✅ PRODUCTION READY

**Deployed By:** Platform Engineering Team  
**Date:** 2026-04-13  
**Version:** 1.0.0  

**Approval:** _________________ (Date: _______)

---

**Print this checklist and work through it systematically.**  
**Refer to DEPLOYMENT_GUIDE.md for detailed information.**
