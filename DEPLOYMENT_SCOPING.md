# Deployment Scoping Strategy

**Objective**: Ensure code-server deployment only manages its own infrastructure and does not interfere with other workloads on the shared cluster.

**Date**: April 28, 2026  
**Environment**: Shared production cluster (192.168.168.31, 192.168.168.42)  
**Namespace**: `code-server` (dedicated namespace for isolation)

---

## 1. Resource Isolation Strategy

### 1.1 Namespace Isolation
```
Primary Namespace: code-server
- All code-server resources deployed here
- Network policies enforce in-namespace communication
- RBAC limits service account to code-server namespace only
```

### 1.2 Label Strategy
```
All resources must have:
  app.kubernetes.io/name: code-server-enterprise
  app.kubernetes.io/instance: code-server
  app.kubernetes.io/component: <service-name>
  app.kubernetes.io/managed-by: terraform-helm
  project: code-server
```

### 1.3 Resource Naming Convention
```
Format: code-server-<service-name>-<resource-type>
Examples:
  - code-server-postgres-deployment
  - code-server-redis-statefulset
  - code-server-ingress
  - code-server-configmap
```

---

## 2. Docker & Container Isolation

### 2.1 Container Naming
```
Prefix: code-server-
Format: code-server-<service>

All containers running code-server deployment:
✓ code-server-postgres
✓ code-server-redis
✓ code-server-redpanda
✓ code-server-qdrant
✓ code-server-prometheus
✓ code-server-grafana
✓ code-server-loki
✓ code-server-alertmanager
✓ code-server-ollama
✓ code-server-opa
✓ code-server-caddy
✓ code-server-oauth2-proxy
✓ code-server-redpanda-console
(+ all other services)
```

### 2.2 Network Isolation
```
Docker Compose Networks:
  - services (bridge) - internal service communication
  - database (bridge) - database layer
  - ingress (bridge) - external gateway

All networks prefixed with: code-server-
```

### 2.3 Volume/Storage Isolation
```
Volume Prefix: code-server_
Naming: code-server_<service>_<type>
Examples:
  - code-server_postgres_data
  - code-server_redis_data
  - code-server_qdrant_data

Only code-server containers can mount these volumes.
```

---

## 3. Terraform Scoping

### 3.1 Resource Selection
```
Terraform manages ONLY code-server resources:
✓ Labeled with project: code-server
✓ Named with code-server- prefix
✓ In code-server namespace

Terraform IGNORES:
✗ Resources without code-server labels
✗ Other projects' deployments
✗ Cluster-level resources (unless code-server-specific)
```

### 3.2 Terraform State Isolation
```
State file: terraform/environments/private/terraform.tfstate
Scope: code-server deployment ONLY
Data sources: Use label selectors to query only code-server resources

Example selector:
  selector {
    match_labels = {
      "app.kubernetes.io/name"      = "code-server-enterprise"
      "app.kubernetes.io/managed-by" = "terraform-helm"
    }
  }
```

### 3.3 Terraform Drift Detection
```
Only monitors code-server resources:
  - Deployments with project: code-server
  - Services with app: code-server-enterprise
  - ConfigMaps/Secrets in code-server namespace
  - PersistentVolumeClaims in code-server namespace

Ignores drift in:
  - Other projects' resources
  - Cluster infrastructure
  - Other namespaces
```

---

## 4. Kubernetes/Helm Scoping

### 4.1 Helm Release
```
Release Name: code-server
Namespace: code-server
Chart: helm/code-server-enterprise

Helm only manages resources in code-server namespace.
```

### 4.2 Namespace Configuration
```yaml
# Create dedicated namespace
apiVersion: v1
kind: Namespace
metadata:
  name: code-server
  labels:
    app.kubernetes.io/name: code-server-enterprise
    project: code-server
  annotations:
    description: "Dedicated namespace for code-server-enterprise deployment"
```

### 4.3 RBAC Scoping
```
Service Account: code-server
Namespace: code-server

Permissions limited to code-server namespace:
  - Read/Write Deployments in code-server
  - Read/Write Services in code-server
  - Read/Write ConfigMaps in code-server
  - Read/Write PersistentVolumeClaims in code-server
  - NO permissions in other namespaces
  - NO cluster-wide permissions
```

### 4.4 Network Policy
```yaml
# Ingress: Allow traffic only from code-server services
# Egress: Allow traffic only within code-server namespace
# DNS: Allow only code-server internal queries

No traffic to other namespaces.
```

---

## 5. Query & Selection Filters

### 5.1 Terraform Data Sources
```hcl
# Only query code-server resources
data "kubernetes_deployment" "code_server_services" {
  field_selector = "metadata.namespace=code-server"
  
  # Only list code-server deployments
  label_selector = "app.kubernetes.io/name=code-server-enterprise,app.kubernetes.io/managed-by=terraform-helm"
}
```

### 5.2 Docker CLI
```bash
# Only code-server containers
docker ps --filter "label=project=code-server"

# Only code-server volumes
docker volume ls --filter "label=project=code-server"

# Only code-server networks
docker network ls --filter "label=project=code-server"
```

### 5.3 kubectl Commands
```bash
# Only code-server resources
kubectl get deployments -n code-server -l app=code-server-enterprise

# Only code-server services
kubectl get services -n code-server -l app=code-server-enterprise

# Only code-server pods
kubectl get pods -n code-server -l app=code-server-enterprise
```

---

## 6. Shared Resources (Read-Only)

These resources are shared but code-server interacts with them read-only:

```
Cluster-level resources (NOT managed by code-server):
  - Ingress Controller
  - Service Mesh (Istio) - code-server deployed within it
  - DNS
  - Load Balancer (192.168.168.250 VIP)
  - Storage Classes
  - Monitoring systems outside code-server namespace

Code-server respects these but doesn't modify them.
```

---

## 7. Deployment Scope Checklist

### 7.1 Before Deployment
- [ ] Namespace `code-server` created
- [ ] Service account `code-server` created with limited RBAC
- [ ] All labels applied: `project: code-server`
- [ ] Network policies configured for namespace isolation
- [ ] RBAC policies enforce code-server namespace only
- [ ] Terraform data sources use proper selectors
- [ ] Docker-compose containers prefixed with `code-server-`

### 7.2 During Deployment
- [ ] Monitor that only code-server resources are created
- [ ] Verify no modifications to other projects' resources
- [ ] Check that terraform plan only shows code-server changes
- [ ] Confirm networks and volumes are prefixed correctly

### 7.3 After Deployment
- [ ] Verify all pods in code-server namespace only
- [ ] Confirm no cross-namespace communication
- [ ] Test network policies block external traffic
- [ ] Verify RBAC prevents access to other namespaces
- [ ] Ensure Terraform drift detection only monitors code-server resources

---

## 8. Scope Violations - What NOT to Do

❌ Do NOT:
- Deploy resources without `project: code-server` label
- Create resources in default or other namespaces
- Modify resources outside code-server namespace
- Use cluster-wide roles (use namespace-scoped roles)
- Delete volumes/networks not prefixed with code-server
- Query or modify other projects' Kubernetes resources
- Change cluster-wide settings
- Access shared ingress/load balancer without explicit approval

✅ Do INSTEAD:
- Always add proper labels: `project: code-server`
- Deploy everything in `code-server` namespace
- Use namespaced RBAC roles
- Prefix all resources: `code-server-`
- Document any shared resources accessed
- Use label selectors in Terraform
- Respect other projects' boundaries

---

## 9. Documentation References

- **Docker Compose Config**: `docker-compose-cluster.yml` (all containers `code-server-*`)
- **Terraform Config**: `terraform/environments/private/` (scoped selectors)
- **Helm Config**: `helm/code-server-enterprise/` (namespace-scoped templates)
- **RBAC Policy**: `kubernetes/rbac/code-server-rbac.yaml`
- **Network Policy**: `kubernetes/network-policies/code-server-netpol.yaml`

---

## 10. Implementation Timeline

| Phase | Task | Status |
|-------|------|--------|
| 1 | Create dedicated namespace | ⏳ |
| 2 | Apply labels to all resources | ⏳ |
| 3 | Configure RBAC with namespace scope | ⏳ |
| 4 | Update Terraform selectors | ⏳ |
| 5 | Deploy network policies | ⏳ |
| 6 | Verify isolation | ⏳ |
| 7 | Document running state | ⏳ |
| 8 | Monitor for scope violations | ⏳ |

---

## Summary

✅ **Isolated Deployment**: code-server operates within `code-server` namespace  
✅ **No Interference**: Other projects' resources unaffected  
✅ **Resource Labels**: All resources labeled for identification  
✅ **RBAC Limited**: Service account has namespace-scoped permissions only  
✅ **Network Isolated**: Network policies restrict in-namespace communication  
✅ **Terraform Scoped**: Only queries and manages code-server resources  

This strategy ensures code-server is a good citizen on the shared cluster.

