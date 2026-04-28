# Deployment Scoping - Implementation Guide

**Purpose**: Ensure code-server only manages its own resources on shared cluster  
**Date**: April 28, 2026  
**Status**: Ready for Implementation

---

## Quick Start - Enforce Scoping Now

### 1. Apply RBAC & Namespace Isolation

```bash
# Create dedicated namespace and RBAC
kubectl apply -f kubernetes/rbac/code-server-rbac.yaml

# Apply network policies for isolation
kubectl apply -f kubernetes/network-policies/code-server-netpol.yaml

# Verify namespace created
kubectl get namespace code-server -o wide
```

### 2. Verify Isolation

```bash
# Check service account permissions (should only see code-server namespace)
kubectl auth can-i list deployments --as=system:serviceaccount:code-server:code-server -n code-server
# Result: yes

kubectl auth can-i list deployments --as=system:serviceaccount:code-server:code-server -n default
# Result: no

# List code-server resources only
kubectl get all -n code-server -l project=code-server
```

### 3. Deploy Helm Chart to Scoped Namespace

```bash
# Deploy to code-server namespace only
helm install code-server ./helm/code-server-enterprise \
  --namespace code-server \
  --create-namespace \
  --set global.domain=kushnir.cloud \
  --set global.tlsEmail=admin@kushnir.cloud

# Verify deployment
kubectl get deployments -n code-server -l project=code-server
```

---

## Docker Compose Scoping (Current Deployment)

### 1. Verify Container Naming

All containers must follow pattern: `code-server-<service>`

```bash
# Verify all running containers are code-server
ssh akushnir@192.168.168.31 'docker ps --format "{{.Names}}" | grep -v "^code-server-" && echo "ERROR: Non-code-server containers found!" || echo "✓ All containers properly scoped"'

# List all code-server containers
ssh akushnir@192.168.168.31 'docker ps --format "{{.Names}}" | grep "^code-server-"'
```

### 2. Verify Networks

```bash
# Only code-server networks
ssh akushnir@192.168.168.31 'docker network ls --filter "label=project=code-server"'

# Expected output:
#   code-server-enterprise_services
#   code-server-enterprise_database
#   code-server-enterprise_ingress
```

### 3. Verify Volumes

```bash
# Only code-server volumes
ssh akushnir@192.168.168.31 'docker volume ls --filter "label=project=code-server"'

# Expected output:
#   code-server_postgres_data
#   code-server_redis_data
#   code-server_qdrant_data
#   (all starting with code-server_)
```

### 4. Add Labels to Docker Resources

```bash
# Add labels to identify ownership
docker run \
  --label project=code-server \
  --label app=code-server-enterprise \
  --label managed-by=docker-compose \
  ...

# Add to docker-compose.yml:
services:
  postgres:
    labels:
      project: code-server
      app: code-server-enterprise
      component: database
```

---

## Terraform Scoping

### 1. Query Only Code-Server Resources

**Update `terraform/environments/private/main.tf`**:

```hcl
# Data source: Only code-server deployments
data "kubernetes_deployment" "code_server_deployments" {
  field_selector = "metadata.namespace=code-server"
  label_selector = "project=code-server,app.kubernetes.io/name=code-server-enterprise"
}

# Data source: Only code-server services
data "kubernetes_service" "code_server_services" {
  field_selector = "metadata.namespace=code-server"
  label_selector = "project=code-server"
}

# Data source: Only code-server ConfigMaps
data "kubernetes_config_map" "code_server_configs" {
  field_selector = "metadata.namespace=code-server"
  label_selector = "project=code-server"
}
```

### 2. Use Label Selectors in Terraform

**Update `terraform/environments/private/deployment.tf`**:

```hcl
# Only destroy code-server resources
resource "null_resource" "cleanup_other_resources" {
  provisioner "local-exec" {
    command = <<-EOT
      kubectl delete all -n code-server \
        -l project=code-server \
        -l app.kubernetes.io/name=code-server-enterprise
    EOT
  }
}

# Protect resources that aren't ours
lifecycle {
  prevent_destroy = true
}
```

### 3. Terraform State Filtering

**Create `terraform/environments/private/scoped-state.tf`**:

```hcl
# Validate that state only contains code-server resources
check "terraform_state_isolation" {
  data "kubernetes_resources" "all_resources" {
    for_each = {
      "deployments"   = "apps/v1/Deployment"
      "services"      = "v1/Service"
      "configmaps"    = "v1/ConfigMap"
      "statefulsets"  = "apps/v1/StatefulSet"
    }
    
    api_version = each.value
    kind        = each.key
  }
  
  assert "all_have_code_server_label" {
    condition = alltrue([
      for resource in data.kubernetes_resources.all_resources : 
      lookup(resource.metadata.labels, "project", "") == "code-server"
    ])
    error_message = "Found resources without project=code-server label!"
  }
}
```

---

## Verification Checklist

### Daily Verification

```bash
#!/bin/bash

echo "🔍 Code-Server Deployment Scoping Verification"
echo "=============================================="

# 1. Kubernetes Namespace
echo ""
echo "✓ Kubernetes Namespace:"
kubectl get namespace code-server -o wide

# 2. Verify Label Isolation
echo ""
echo "✓ Resources with project=code-server label:"
kubectl get all -n code-server -l project=code-server --no-headers | wc -l

# 3. Verify No Cross-Namespace Access
echo ""
echo "✓ Checking RBAC restrictions:"
kubectl auth can-i list pods --as=system:serviceaccount:code-server:code-server -n kube-system || echo "✓ Correctly blocked"

# 4. Docker Scoping (local)
echo ""
echo "✓ Docker containers:"
docker ps --format "{{.Names}}" | grep "^code-server-" | wc -l

# 5. Network Policies
echo ""
echo "✓ Network policies:"
kubectl get networkpolicies -n code-server -l project=code-server

# 6. Resource Status
echo ""
echo "✓ Deployment status:"
kubectl rollout status deployment -n code-server -l project=code-server
```

---

## Scope Violations - Detection

### What to Watch For

```bash
# ⚠️ Non-code-server containers running
docker ps --format "{{.Names}}" | grep -v "^code-server-"

# ⚠️ Resources in code-server namespace without label
kubectl get all -n code-server -o custom-columns=NAME:.metadata.name,PROJECT:.metadata.labels.project | grep "<none>"

# ⚠️ Terraform modifying non-code-server resources
terraform plan | grep -v "code-server"

# ⚠️ Service account accessing other namespaces
kubectl logs -n code-server -l project=code-server | grep "permission denied"
```

### Remediation

```bash
# Clean up non-code-server resources in code-server namespace
kubectl delete all -n code-server \
  --field-selector=metadata.name!=code-server-* \
  -l '!project=code-server'

# Restart pod to apply new RBAC
kubectl rollout restart deployment -n code-server -l project=code-server

# Verify cleanup
kubectl get all -n code-server
```

---

## Shared Cluster Best Practices

### ✅ DO:
- Always label resources: `project: code-server`
- Deploy only to `code-server` namespace
- Use RBAC for service account access control
- Monitor Terraform plan for cross-namespace changes
- Prefix all Docker resources: `code-server-`
- Test permissions before deploying

### ❌ DON'T:
- Modify resources in other namespaces
- Deploy to `default` namespace
- Use cluster-admin role for code-server
- Share service accounts with other projects
- Modify shared cluster resources
- Run containers without `code-server-` prefix
- Ignore network policies

---

## Automation Scripts

### Script 1: Verify Scoping

**`scripts/verify-scoping.sh`**:

```bash
#!/bin/bash
set -e

echo "🔍 Verifying code-server deployment scoping..."

# Check namespace
kubectl get ns code-server &>/dev/null || { echo "❌ code-server namespace not found"; exit 1; }

# Check RBAC
kubectl get rolebinding -n code-server code-server-deployment &>/dev/null || { echo "❌ RBAC not configured"; exit 1; }

# Check labels on all resources
non_labeled=$(kubectl get all -n code-server -o json | jq '.items[] | select(.metadata.labels.project != "code-server") | .metadata.name' | wc -l)
if [ "$non_labeled" -gt 0 ]; then
  echo "⚠️  Warning: $non_labeled resources missing project label"
fi

# Check network policies
kubectl get networkpolicies -n code-server &>/dev/null || { echo "⚠️  Warning: No network policies found"; }

echo "✅ Scoping verification complete!"
```

### Script 2: Cleanup Non-Code-Server Resources

**`scripts/cleanup-other-resources.sh`**:

```bash
#!/bin/bash
set -e

echo "🧹 Cleaning up non-code-server resources in code-server namespace..."

# Delete resources without project=code-server label
kubectl delete all -n code-server -l '!project=code-server' --dry-run=client

echo "✓ Cleanup simulation complete. Add --for-real to execute."
```

---

## Monitoring & Alerting

### Prometheus Rules (if using Prometheus)

```yaml
groups:
- name: code-server-scoping
  rules:
  - alert: ResourcesOutsideScope
    expr: count(kube_pod_labels{namespace!="code-server"}) > 0
    for: 5m
    annotations:
      summary: "Code-server resources detected outside code-server namespace"
```

### Log Monitoring

```bash
# Monitor for RBAC errors
kubectl logs -n code-server -l project=code-server --since=10m | grep "permission denied"

# Monitor for network policy blocks
kubectl logs -n code-server -l project=code-server --since=10m | grep "denied by NetworkPolicy"
```

---

## Documentation

- **Scoping Strategy**: `DEPLOYMENT_SCOPING.md`
- **RBAC Configuration**: `kubernetes/rbac/code-server-rbac.yaml`
- **Network Policies**: `kubernetes/network-policies/code-server-netpol.yaml`
- **Docker Compose**: `docker-compose-cluster.yml` (all containers `code-server-*`)
- **Terraform Config**: `terraform/environments/private/` (uses label selectors)

---

## Status

| Item | Status | Action |
|------|--------|--------|
| RBAC configured | ⏳ | `kubectl apply -f kubernetes/rbac/code-server-rbac.yaml` |
| Network policies | ⏳ | `kubectl apply -f kubernetes/network-policies/code-server-netpol.yaml` |
| Helm scoped | ⏳ | Deploy to `code-server` namespace only |
| Terraform scoped | ⏳ | Update to use label selectors |
| Docker scoped | ✅ | All containers prefixed with `code-server-` |
| Verification tested | ⏳ | Run verification scripts |

