# K3s Cluster Provisioning Guide — Phase 4 Kubernetes Migration

**Status**: Ready for deployment (Q3 2026)  
**Targets**: Primary (.31) + Agent (.42)  
**Provisioner**: `scripts/ops/provision-k3s-cluster.sh`  

---

## Pre-requisite: Configure Passwordless Sudo (One-Time)

The k3s provisioner requires passwordless sudo on both target hosts. This is a one-time setup that requires your user credentials.

### Setup Steps:

**1. Configure sudoers on PRIMARY host (.31):**
```bash
bash scripts/ops/setup-k3s-sudoers.sh 192.168.168.31 akushnir
```

**2. Configure sudoers on REPLICA host (.42):**
```bash
bash scripts/ops/setup-k3s-sudoers.sh 192.168.168.42 akushnir
```

You will be prompted for your password during setup. This is the ONLY time you need to authenticate interactively.

**3. Verify configuration:**
```bash
# Should complete without password prompts
ssh akushnir@192.168.168.31 "sudo -n echo 'Primary OK'"
ssh akushnir@192.168.168.42 "sudo -n echo 'Replica OK'"
```

---

## Deploy K3s Cluster

### Option 1: Dry-run validation (recommended first)
```bash
export PRIMARY_HOST=192.168.168.31 \
       REPLICA_HOST=192.168.168.42 \
       SSH_USER=akushnir

DRY_RUN=true bash scripts/ops/provision-k3s-cluster.sh
```

### Option 2: Full provisioning (after dry-run succeeds)
```bash
bash scripts/ops/provision-k3s-cluster.sh
```

**Expected duration**: 8-12 minutes (parallel install on both nodes)

---

## Post-Deployment Verification

### 1. Check cluster health
```bash
# Export kubeconfig
export KUBECONFIG=~/.kube/k3s-config

# Verify nodes are Ready
kubectl get nodes

# Verify system pods running
kubectl get pods -A
```

### 2. Deploy Helm charts (next step)
```bash
helm upgrade --install code-server-enterprise ./helm/code-server-enterprise \
  -f helm/code-server-enterprise/values.phase4-k8s.yaml \
  --set global.domain=${APEX_DOMAIN:-kushnir.cloud}
```

### 3. Monitor deployment
```bash
# Watch pod startup
kubectl get pods -A --watch

# Check cert-manager readiness (required for TLS)
kubectl get crd | grep cert-manager

# Verify metrics-server installed (required for HPA)
kubectl get deployment metrics-server -n kube-system
```

---

## Troubleshooting

### Provisioner reports "Passwordless sudo not configured"
**Solution**: Run the setup script again:
```bash
bash scripts/ops/setup-k3s-sudoers.sh 192.168.168.31 akushnir
bash scripts/ops/setup-k3s-sudoers.sh 192.168.168.42 akushnir
```

### Cluster already exists (want to reinstall)
```bash
FORCE_REINSTALL=true bash scripts/ops/provision-k3s-cluster.sh
```

### Skip agent node (server-only)
```bash
SKIP_AGENT=true bash scripts/ops/provision-k3s-cluster.sh
```

### Check detailed logs
```bash
tail -f artifacts/k3s-cluster-provision/provision-*.log
```

---

## Architecture

The provisioner creates a **2-node k3s cluster** with:

| Component | Node | Role |
|-----------|------|------|
| k3s-server | 192.168.168.31 | Primary control plane + etcd |
| k3s-agent | 192.168.168.42 | Worker node |

**Features**:
- Cluster networking: `10.0.0.0/16` pod CIDR, `10.32.0.0/12` service CIDR
- High availability: etcd cluster-init mode
- TLS: cert-manager v1.14 deployed automatically
- Monitoring: metrics-server deployed for HPA support
- Ingress: traefik disabled (we use Caddy in Docker Compose layer)

---

## Idempotency

The provisioner is **fully idempotent**:
- Re-running is safe; existing installations are detected and skipped
- Set `FORCE_REINSTALL=true` to replace existing k3s
- Failed partial runs can be re-executed without cleanup

---

## Next: Migrate Workloads

Once cluster is operational, migrate workloads from Docker Compose:
```bash
# Deploy microservices via Helm
helm list -a

# Monitor pod status
kubectl get pods -A --watch

# Access cluster-internal services
kubectl port-forward svc/api 3100:3100 -n default
```

---

**Last Updated**: 2026-04-25  
**Status**: Phase 4 Kubernetes Migration (IN PROGRESS)  
**Related Issues**: #1537 (Q3 Phase 4), #1539 (EKS Provisioning)
