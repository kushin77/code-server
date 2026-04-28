# CODE-SERVER SCOPING - QUICK REFERENCE CARD

## Core Concept
Code-server must operate as an isolated deployment on the shared cluster, managing only its own resources and not interfering with other workloads.

---

## Essential Resources

| Resource | Location | Purpose |
|----------|----------|---------|
| **Strategy** | `DEPLOYMENT_SCOPING.md` | Why and how scoping works |
| **Implementation** | `SCOPING_IMPLEMENTATION.md` | Step-by-step guide |
| **Boundaries** | `SCOPE_BOUNDARIES.txt` | What's allowed/forbidden |
| **RBAC** | `kubernetes/rbac/code-server-rbac.yaml` | Namespace-scoped permissions |
| **Network** | `kubernetes/network-policies/code-server-netpol.yaml` | Traffic isolation |
| **Validator** | `scripts/validate-scoping.sh` | Pre-deployment checks |

---

## Critical Constraints

```
✅ DO:
  • Use namespace: code-server
  • Prefix containers: code-server-<service>
  • Label all resources: project: code-server
  • Query with: label_selector = "project=code-server"
  • Use service account: code-server (namespace-scoped)

❌ DON'T:
  • Deploy to namespace: default
  • Create cluster-admin roles
  • Access resources outside code-server namespace
  • Modify shared infrastructure
  • Use root/privileged containers
```

---

## Scope Definition

| Category | Scope |
|----------|-------|
| **Namespace** | `code-server` only |
| **Label** | `project: code-server` (all resources) |
| **Container Names** | `code-server-<service>` |
| **Volume Names** | `code-server_<service>_data` |
| **Network Names** | `code-server-enterprise_<network>` |
| **RBAC** | Namespace-scoped, no cluster-wide |
| **DNS** | Internal only (kube-system) |
| **Traffic** | In-namespace only |

---

## Pre-Deployment Checklist (5 minutes)

```bash
# 1. Validate configuration
./scripts/validate-scoping.sh

# 2. Create namespace and apply RBAC
kubectl apply -f kubernetes/rbac/code-server-rbac.yaml

# 3. Apply network policies
kubectl apply -f kubernetes/network-policies/code-server-netpol.yaml

# 4. Verify namespace exists
kubectl get namespace code-server

# 5. Deploy to scoped namespace
helm install code-server ./helm/code-server-enterprise \
  -n code-server --create-namespace
```

---

## Red Flags (Stop & Review)

🚩 `namespace: default`  
🚩 `clusterAdmin: true`  
🚩 Container without `code-server-` prefix  
🚩 Missing label: `project: code-server`  
🚩 Accessing resources outside `code-server` namespace  
🚩 Cluster-wide role usage  
🚩 Privileged container/capabilities  

**Action**: Roll back, fix, re-validate before deploying.

---

## Quick Commands

```bash
# Validate scoping
./scripts/validate-scoping.sh

# Check namespace isolation
kubectl auth can-i list pods -n code-server \
  --as=system:serviceaccount:code-server:code-server

# List only code-server resources
kubectl get all -n code-server -l project=code-server

# Check RBAC
kubectl describe role code-server-deployment -n code-server

# Check network policies
kubectl describe networkpolicies -n code-server

# Find unlabeled resources (should be empty)
kubectl get all -n code-server -o json | \
  jq '.items[] | select(.metadata.labels.project != "code-server")'

# Find containers without prefix
docker ps --format "{{.Names}}" | grep -v ^code-server-
```

---

## Scope Enforcement Matrix

| Violation | Detection | Action | Owner |
|-----------|-----------|--------|-------|
| Wrong namespace | Validation script | Reject PR | Code review |
| Missing label | Validation script | Reject PR | Code review |
| Wrong container name | Validation script | Reject PR | Code review |
| Cluster-admin usage | Validation script | Reject PR | Code review |
| Cross-namespace access | RBAC error | Alert + Investigate | Ops |
| Cross-namespace traffic | Network policy drop | Alert + Investigate | Ops |
| Unauthorized container | Pod security policy | Reject pod | K8s admission |

---

## Example Configurations

### ✅ CORRECT Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: code-server-postgres
  namespace: code-server
  labels:
    project: code-server
    app.kubernetes.io/name: code-server-enterprise
spec:
  selector:
    matchLabels:
      project: code-server
  template:
    metadata:
      labels:
        project: code-server
    spec:
      serviceAccountName: code-server
      containers:
      - name: code-server-postgres
        image: postgres:15
        # ... rest of config
```

### ❌ INCORRECT Deployment

```yaml
# DON'T DO THIS:
namespace: default  # ← WRONG
serviceAccountName: admin  # ← WRONG
labels:
  project: other  # ← WRONG
containers:
- name: postgres  # ← WRONG (should be code-server-postgres)
  privileged: true  # ← WRONG
```

---

## Terraform Query Examples

```hcl
# ✅ CORRECT: Query only code-server resources
data "kubernetes_deployment" "code_server" {
  metadata {
    namespace = "code-server"
    label_selector = "project=code-server"
  }
}

# ❌ WRONG: No filtering
data "kubernetes_deployment" "all" {
  # This will find ALL deployments in the cluster!
}

# ❌ WRONG: Wrong namespace
data "kubernetes_deployment" "wrong" {
  metadata {
    namespace = "default"  # Should be "code-server"
  }
}
```

---

## Helm Values Template

```yaml
# Set when deploying:
helm install code-server ./helm/code-server-enterprise \
  --namespace code-server \
  --create-namespace \
  --set namespace=code-server \
  --set labels.project=code-server \
  --set labels.app.kubernetes.io/name=code-server-enterprise \
  --set serviceAccount.name=code-server
```

---

## Troubleshooting

| Problem | Check | Fix |
|---------|-------|-----|
| "Permission denied" | RBAC scope | Service account must be in code-server namespace |
| "Connection refused" | Network policy | Network policy may be blocking (check egress) |
| Pod not starting | Labels | Missing project: code-server label |
| Docker container fails | Naming | Container name must start with code-server- |
| Validation fails | Script output | Read error messages carefully |

---

## Support Channels

| Issue | Resource |
|-------|----------|
| **Strategy questions** | `DEPLOYMENT_SCOPING.md` |
| **Implementation help** | `SCOPING_IMPLEMENTATION.md` |
| **Boundary questions** | `SCOPE_BOUNDARIES.txt` |
| **RBAC issues** | Check `kubernetes/rbac/code-server-rbac.yaml` |
| **Network issues** | Check `kubernetes/network-policies/code-server-netpol.yaml` |
| **Validation errors** | Run `./scripts/validate-scoping.sh --strict` |

---

## Key Takeaways

1. **Namespace**: All resources go in `code-server` namespace
2. **Labels**: All resources have label `project: code-server`
3. **Names**: All containers prefixed `code-server-`
4. **RBAC**: Service account `code-server` is namespace-scoped
5. **Network**: In-namespace communication only
6. **Validation**: Run `./scripts/validate-scoping.sh` before deploying

---

**Status**: 🟢 Ready for deployment  
**Last Updated**: 2026-04-28  
**Scope**: Shared cluster deployment isolation
