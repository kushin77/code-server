# Terraform module: ArgoCD
# Provides production-grade ArgoCD installation with Helm

This module installs and configures ArgoCD in a Kubernetes cluster using Terraform and Helm.

## Features

- **High Availability**: Multi-replica deployment with auto-scaling
- **Security**: RBAC, NetworkPolicy, and TLS support
- **Observability**: Prometheus metrics and ServiceMonitor
- **Git Integration**: Pre-configured git repository support
- **ApplicationSet support**: Multi-cluster deployments

## Usage

```hcl
module "argocd" {
  source = "./modules/argocd"

  namespace     = "argocd"
  helm_chart_version = "5.46.0"
  image_tag     = "v2.10.0"
  replicas      = 2

  enable_ingress = true
  ingress_hostname = "argocd.example.com"

  enable_rbac              = true
  enable_network_policy    = true
  enable_metrics          = true

  git_repositories = [
    {
      name = "code-server"
      url  = "https://github.com/kushin77/code-server"
      type = "git"
    }
  ]

  resource_requests = {
    cpu    = "500m"
    memory = "512Mi"
  }

  resource_limits = {
    cpu    = "2000m"
    memory = "1Gi"
  }

  tags = {
    Environment = "production"
    Phase       = "9-gitops"
  }
}
```

## Requirements

- Kubernetes 1.20+
- Terraform 1.5.0+
- Helm provider ~> 2.10
- Kubernetes provider ~> 2.20

## Providers

| Name | Version |
|------|---------|
| kubernetes | ~> 2.20 |
| helm | ~> 2.10 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| namespace | Kubernetes namespace | string | "argocd" | no |
| create_namespace | Create namespace | bool | true | no |
| helm_chart_version | Helm chart version | string | "5.46.0" | no |
| image_tag | Container image tag | string | "v2.10.0" | no |
| replicas | Server replicas | number | 2 | no |
| enable_ingress | Enable Ingress | bool | false | no |
| ingress_hostname | Ingress hostname | string | "argocd.example.com" | no |
| enable_rbac | Enable RBAC | bool | true | no |
| enable_network_policy | Enable NetworkPolicy | bool | true | no |
| enable_metrics | Enable Prometheus metrics | bool | true | no |
| resource_requests | Resource requests | object | {...} | no |
| resource_limits | Resource limits | object | {...} | no |
| git_repositories | Git repositories | list | [] | no |

## Outputs

| Name | Description |
|------|-------------|
| argocd_namespace | Namespace where ArgoCD is installed |
| argocd_server_service | ArgoCD server service name |
| argocd_server_url | ArgoCD server URL |
| initial_admin_password_secret | Secret with admin password |
| helm_release_status | Helm release status |

## Post-Installation Steps

### 1. Get Initial Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### 2. Port-Forward (if no Ingress)

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80
# Access at http://localhost:8080
```

### 3. Register Git Repository

```bash
argocd repo add https://github.com/kushin77/code-server \
  --username <github-user> \
  --password <github-token>
```

### 4. Create Application

```bash
kubectl apply -f gitops/argocd-applications.yaml
```

## Security Best Practices

1. **Enable Ingress with TLS**
```hcl
enable_ingress   = true
ingress_tls_cert = "argocd-tls-secret"
```

2. **Restrict RBAC**
```hcl
# See rbac-policy.csv for fine-grained permissions
```

3. **Enable NetworkPolicy**
```hcl
enable_network_policy = true
```

4. **Secure Git credentials**
```bash
kubectl create secret generic git-credentials \
  --from-literal=username=<user> \
  --from-literal=password=<token> \
  -n argocd
```

## Monitoring

Monitor ArgoCD health with Prometheus:

```hcl
variable "enable_metrics" {
  default = true
}
```

Expose metrics:
```bash
kubectl port-forward svc/argocd-metrics -n argocd 8082:8082
```

Prometheus scrape config:
```yaml
scrape_configs:
- job_name: argocd
  kubernetes_sd_configs:
  - role: service
    namespaces:
      names:
      - argocd
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_label_app_kubernetes_io_name]
    regex: argocd.*
    action: keep
```

## Troubleshooting

### ArgoCD Server not starting

```bash
kubectl logs -n argocd deployment/argocd-server
kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-server
```

### Git sync issues

```bash
argocd repo list
argocd app get <app-name>
argocd app logs <app-name> --follow
```

### NetworkPolicy blocking traffic

```bash
kubectl get networkpolicy -n argocd
kubectl describe networkpolicy -n argocd argocd-network-policy
```

## Lifecycle

### Upgrade ArgoCD

```hcl
helm_chart_version = "5.47.0"  # Update version
terraform apply
```

### Scale Replicas

```hcl
replicas = 3  # Increase from 2
terraform apply
```

### Enable TLSIngress

```hcl
enable_ingress      = true
ingress_hostname    = "argocd.mycompany.com"
ingress_tls_cert    = "cert-secret-name"
terraform apply
```

## Phase 9 Integration

This module is part of Phase 9 (GitOps) implementation:

- **Phase 9 GitOps Managers**: Kubernetes controllers for app management
- **ArgoCD Terraform Module**: IaC for ArgoCD infrastructure
- **ApplicationSet**: Multi-cluster deployments
- **GitOps Workflow**: Git-driven state management

Combined with **Phase 15 (Deployment)**, provides:
- Declarative application definitions
- Automated canary and blue-green deployments
- SLO-driven deployment gates
- Automatic health monitoring and remediation

---

**Version**: 1.0.0  
**Last Updated**: 2024-01-27  
**Compatibility**: Kubernetes 1.20+, Terraform 1.5.0+, Helm 3.x
