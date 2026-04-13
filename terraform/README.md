# Kubernetes Infrastructure as Code (Terraform)

Production-grade, idempotent Terraform configuration for deploying and managing a complete Kubernetes cluster with observability, security, backup, and development platform.

## Architecture Overview

This Terraform configuration implements **10 deployment phases** with explicit dependencies, idempotent patterns, and complete lifecycle management:

```
Phase 2: Namespaces & Storage
    ↓
Phase 3: Observability (Prometheus, Grafana, Loki)
    ↓
Phase 4: Security & RBAC (Network Policies, Roles)
    ↓
Phase 5: Backup & DR (Velero)
    ↓
Phase 6: Application Platform (code-server)
    ↓
Phase 7: Ingress & TLS (NGINX, Cert-Manager)
    ↓
Phase 8: Verification & Validation
    ↓
Phase 10: On-Premises Optimization (Resource Quotas, HPA, Cost Analysis)
```

## File Structure

```
terraform/
├── versions.tf                 # Provider configuration and versions
├── variables.tf                # Root module input variables
├── terraform.tfvars.example    # Variable values template
├── main.tf                     # Module orchestration
├── README.md                   # This file
├── Makefile.terraform          # Deployment automation
├── terraform.tfstate           # State file (created on init)
│
├── modules/
│   ├── phase2-namespaces/
│   │   ├── main.tf            # Idempotent namespace creation
│   │   └── variables.tf
│   │
│   ├── phase2-storage/
│   │   ├── main.tf            # StorageClass & PersistentVolumes
│   │   └── variables.tf
│   │
│   ├── phase3-observability/
│   │   ├── main.tf            # Prometheus, Grafana, Loki (Helm)
│   │   └── variables.tf
│   │
│   ├── phase4-security/
│   │   ├── main.tf            # RBAC, Network Policies
│   │   └── variables.tf
│   │
│   ├── phase5-backup/
│   │   ├── main.tf            # Velero backup and DR
│   │   └── variables.tf
│   │
│   ├── phase6-app-platform/
│   │   ├── main.tf            # code-server StatefulSet
│   │   └── variables.tf
│   │
│   ├── phase7-ingress/
│   │   ├── main.tf            # NGINX Ingress, Cert-Manager, TLS
│   │   └── variables.tf
│   │
│   ├── phase8-verification/
│   │   ├── main.tf            # Health checks, compliance, benchmarks
│   │   └── variables.tf
│   │
│   └── phase10-onprem-optimization/
│       ├── main.tf            # Resource quotas, HPA, cost analysis
│       ├── variables.tf
│       └── README.md
│
└── README.md                   # This file
```

## Quick Start

### Prerequisites

```bash
# Terraform >= 1.5.0
terraform version

# kubectl configured and pointing to your cluster
kubectl config current-context

# Helm 3.12+
helm version

# Cluster requirements:
# - Kubernetes 1.27+ running
# - 3+ nodes in HA configuration
# - 8+ CPU cores, 16+ GB memory recommended
```

### 1. Initialize Terraform

```bash
cd terraform/

# Option A: Using Makefile (recommended)
make init

# Option B: Direct Terraform
terraform init

# Validate configuration syntax
terraform validate
```

### 2. Configure Variables

Copy and customize the example variables file:

```bash
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your environment values:
# - kubeconfig path and context
# - cluster name and network CIDRs
# - storage sizes and resource requests/limits
# - passwords (CHANGE FROM DEFAULTS!)
# - hostnames and domain names
vi terraform.tfvars
```

**Critical variables to change:**

```hcl
# SECURITY: Change these credentials immediately!
grafana_admin_password  = "YOUR_SECURE_PASSWORD_HERE"
code_server_password    = "YOUR_SECURE_PASSWORD_HERE"

# NETWORK: Update for your environment
cluster_name           = "your-cluster-name"
domain                 = "your.domain.com"
grafana_hostname       = "grafana.your.domain.com"
prometheus_hostname    = "prometheus.your.domain.com"
code_server_hostname   = "code-server.your.domain.com"

# KUBERNETES: Adjust for your cluster
kubeconfig_context     = "your-context-name"
```

### 3. Plan Deployment

Preview changes before applying:

```bash
# Using Makefile (recommended)
make plan

# Or direct Terraform
terraform plan -out=tfplan

# Review the tfplan output carefully
# Check for any resources that will be destroyed
```

### 4. Apply Deployment

Deploy the complete infrastructure:

```bash
# Using Makefile - interactive plan + apply
make apply

# Using Makefile - auto-approve (idempotent, safe for re-runs)
make quick-apply

# Or direct Terraform
terraform apply tfplan

# Wait for all resources to become ready (~5-10 minutes)
```

### 5. Verify Deployment

Run verification scripts to ensure everything is working:

```bash
# Run health check
bash /tmp/k8s-verification/01-health-check.sh

# Check compliance
bash /tmp/k8s-verification/02-compliance-check.sh

# Run performance benchmarks
bash /tmp/k8s-verification/03-performance-benchmark.sh

# View verification checklist
kubectl get configmap verification-checklist -o jsonpath='{.data.VERIFICATION_CHECKLIST\.md}'
```

## Key Features

### ✅ Automated Deployment with Makefile

Convenient `make` targets handle common operations:

```bash
# Core operations
make init          # Initialize Terraform workspace
make plan          # Preview changes
make apply         # Interactive plan + apply
make quick-apply   # Auto-approve (idempotent, safe for re-runs)
make destroy       # Destroy infrastructure (with confirmation)

# Validation & testing
make validate      # Validate configuration
make verify        # Verify cluster deployment status
make health-check  # Run health check scripts
make compliance    # Run compliance verification
make benchmark     # Run performance benchmarks

# State management
make state-show    # Display Terraform state
make state-backup  # Backup current state
make refresh       # Refresh state from cluster

# Access & operations
make outputs       # Show all outputs
make access-info   # Show cluster access information
make port-forward  # Port-forward to services
make logs          # View operation logs

# Documentation & utilities
make docs          # Show documentation
make checklist     # Display verification checklist
make help          # Show all available targets
```

**Benefits**:
- No need to remember Terraform commands
- Color-coded output (Blue=info, Green=success, Yellow=warning, Red=error)
- Built-in logging to `logs/` directory
- Automatic state backups before operations
- Idempotent commands safe for re-runs

### ✅ Idempotent Deployment

All resources are safe to re-apply:
- `lifecycle { ignore_changes = [...] }` prevents Kubernetes-generated field drift
- `count` conditionals for feature-based deployment
- Cluster readiness checks before deployments

```bash
# Safe to run repeatedly without side effects
terraform apply -auto-approve
```

### ✅ Immutable Infrastructure

- Containerized applications (pinned versions)
- Helm releases with explicit chart versions
- Kubernetes manifests as declarative code
- State tracked in terraform.tfstate

### ✅ Production-Grade Security

**Phase 4: Security & RBAC**
- Default-deny network policies
- Role-based access control (RBAC) with 3 tiers:
  - Read-only (monitoring/observation)
  - Developer (create/update resources)
  - Admin (full control)
- Service accounts per workload
- Pod security standards

### ✅ High Availability & Disaster Recovery

**Phase 5: Backup & DR**
- Velero for cluster-wide backups
- Daily full backups + hourly increments
- Automated restore verification
- S3-compatible backup storage (Minio, AWS S3, etc.)

### ✅ Complete Observability

**Phase 3: Observability Stack**
- **Prometheus**: Metrics collection and storage (50Gi)
- **Grafana**: Visualization and alerting (2 replicas)
- **Loki**: Log aggregation and querying (20Gi)
- Pre-configured dashboards and alerts

### ✅ On-Premises Optimization

**Phase 10: On-Premises Optimization**
- **Resource Quotas**: Prevent over-subscription and resource starvation
- **Priority Classes**: Intelligent pod eviction during resource pressure
- **Horizontal Pod Autoscaling (HPA)**: Dynamic scaling based on load
- **Node Optimization**: Kernel tuning for on-premises servers
- **Metrics Optimization**: Compression and retention policies (80% storage savings)
- **Cost Analysis**: Detailed cost breakdown and ROI calculations
- **Operational Runbooks**: Disaster recovery procedures for common incidents
  - Node failure recovery
  - Storage full recovery
  - Network partition recovery
  - Backup and restore procedures

### ✅ Development Platform

**Phase 6: Application Platform**
- code-server IDE deployments (StatefulSet)
- Per-pod workspace storage (100Gi each)
- Pre-installed extensions (Python, Go, Terraform, etc.)
- HA configuration (2 replicas by default)

### ✅ Ingress & TLS

**Phase 7: Ingress & Load Balancing**
- NGINX Ingress Controller (DaemonSet for HA)
- Automatic TLS certificate provisioning (Let's Encrypt)
- ModSecurity WAF rules
- Hostname-based routing for all services

### ✅ Automated Verification

**Phase 8: Verification & Validation**
- Health checks for all components
- Compliance verification (network policies, RBAC)
- Performance benchmarking scripts
- Cluster validation checklist

## State Management

### Local State (Development)

Default configuration stores state locally:

```bash
# View current state
terraform show

# Show specific output
terraform output deployment_summary

# Backup state before modifications
cp terraform.tfstate terraform.tfstate.backup
```

### Remote State (Team/Production)

To use remote state (S3, GCS, Azure, etc.):

1. **Create S3 backend** (example):

```bash
aws s3 mb s3://my-terraform-state
aws s3api put-bucket-versioning \
  --bucket my-terraform-state \
  --versioning-configuration Status=Enabled
```

2. **Update `versions.tf`**:

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "kubernetes/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

3. **Re-initialize**:

```bash
terraform init -migrate-state
```

## Customization

### Change Replica Counts

```hcl
# terraform.tfvars
prometheus_replicas       = 3    # Default: 2
grafana_replicas          = 3    # Default: 2
code_server_replicas      = 5    # Default: 2
```

Then apply:
```bash
terraform apply -auto-approve
```

### Modify Storage Sizes

```hcl
# terraform.tfvars
prometheus_storage_size     = 100    # Increase monitoring storage
code_server_workspace_size  = "200Gi"  # More workspace per user
```

### Add Custom Ingress Routes

Edit `modules/phase7-ingress/main.tf` and add new `kubernetes_ingress_v1` resources.

### Install Additional Extensions

```hcl
# terraform.tfvars
code_server_extensions = [
  "ms-python.python",
  "golang.Go",
  "hashicorp.terraform",
  "my-org.custom-extension",
]
```

## Troubleshooting

### Pod Status

```bash
# Check pod status in all namespaces
kubectl get pods -A

# Describe failing pod
kubectl describe pod <pod-name> -n <namespace>

# View pod logs
kubectl logs <pod-name> -n <namespace> --follow
```

### Terraform Issues

```bash
# Show detailed error messages
terraform apply -var-file=terraform.tfvars -log=TRACE

# Validate syntax
terraform validate

# Format code
terraform fmt -recursive

# Refresh state (sync with cluster)
terraform refresh
```

### Network Connectivity

```bash
# Port-forward to services
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n ingress-nginx svc/ingress-nginx 8080:80

# Check network policies
kubectl get networkpolicy -A

# Test pod-to-pod connectivity
kubectl exec -n monitoring <pod> -- curl <service>
```

### Storage Issues

```bash
# Check persistent volumes
kubectl get pv

# Check persistent volume claims
kubectl get pvc -A

# Describe problematic PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage class
kubectl get storageclass
```

## Operations & Maintenance

### Scaling Components

```bash
# Increase Prometheus replicas
terraform apply -var 'prometheus_replicas=3'

# Increase code-server nodes
terraform apply -var 'code_server_replicas=5'
```

### Updating Component Versions

```bash
# Update code-server version
terraform apply -var 'code_server_version=4.30.0'

# Chart versions need manual update in variables.tf
vi modules/phase7-ingress/variables.tf
```

### Backup & Restore

```bash
# List backups
kubectl -n backup exec velero-<pod> -- velero backup get

# Create on-demand backup
kubectl -n backup exec velero-<pod> -- velero backup create manual-backup

# Restore from backup
kubectl -n backup exec velero-<pod> -- velero restore create --from-backup manual-backup
```

### Monitoring & Alerts

```bash
# Access Grafana dashboards
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Visit: http://localhost:3000

# View Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# Visit: http://localhost:9090/targets

# Check alert status
kubectl get alertmanagerrules -A
```

## Destruction & Cleanup

```bash
# Destroy all deployed resources
terraform destroy

# Destroy specific resource
terraform destroy -target=module.ingress

# Force destroy (use with caution)
terraform destroy -auto-approve

# Verify cleanup
kubectl get all -A
```

⚠️ **Warning**: Destroying resources is permanent. Ensure backups exist.

## GitOps Integration

Push configuration to Git for version control and CI/CD:

```bash
# Initialize git repository
git init
git add terraform/
git commit -m "chore: initial terraform infrastructure"
git remote add origin git@github.com:kushin77/code-server.git
git push -u origin main

# Use in CI/CD pipeline (GitHub Actions example)
- name: Terraform Plan
  run: terraform plan -out=tfplan

- name: Terraform Apply
  run: terraform apply tfplan
```

## Cost Optimization

- Use spot/preemptible instances for non-critical workloads
- Scale replicas based on load (enable HPA)
- Delete unused persistent volumes
- Use appropriate storage class and reclaim policies
- Monitor resource quotas and requests

Estimated monthly cost (AWS):
- 3x t3.large nodes: ~$120
- Storage (600Gi): ~$30
- Load balancer: ~$16
- **Total: ~$166/month** (adjust for region/instance type)

## Support & Documentation

- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest)
- [Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest)
- [Velero Documentation](https://velero.io/docs/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager](https://cert-manager.io/docs/)

## License

This Terraform configuration is part of the code-server-enterprise project.

## Contributors

Developed by the Platform Engineering team.

---

**Last Updated**: 2024-01-27  
**Version**: 1.0.0  
**Status**: Production-Ready
