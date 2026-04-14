# ═════════════════════════════════════════════════════════════════════════════
# Terraform Module Integration & Dependency Management
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Explicit dependency declarations between phases/modules
# Ensures: Proper execution order, state consistency, integration validation
# Status: Production-ready, immutable infrastructure declarations
# ═════════════════════════════════════════════════════════════════════════════

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 24: OPERATIONS EXCELLENCE & RESILIENCE (Foundation)
# ═════════════════════════════════════════════════════════════════════════════

output "phase_24_velero_namespace" {
  description = "Velero namespace for backup & disaster recovery"
  value       = try(kubernetes_namespace.velero[0].metadata[0].name, null)
}

output "phase_24_deployment_complete" {
  description = "Phase 24: Operations Excellence deployment status"
  value       = var.operations_excellence_enabled
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 25: GRAPHQL API & DEVELOPER PORTAL (Depends on Phase 24, 23)
# ═════════════════════════════════════════════════════════════════════════════

# Phase 25 requires:
# - Phase 24: Disaster recovery infrastructure
# - Phase 23: Observability (Prometheus, Grafana)
# - Phase 22: Kubernetes cluster

output "phase_25_api_gateway_namespace" {
  description = "GraphQL API Gateway namespace"
  value       = try(kubernetes_namespace.api[0].metadata[0].name, null)
  depends_on = [
    kubernetes_namespace.velero,  # Phase 24 dependency
  ]
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 22-A: KUBERNETES CLUSTER (DEPLOYMENT MODE SELECTOR)
# ═════════════════════════════════════════════════════════════════════════════

locals {
  # Selector: Use on-prem kubeadm OR cloud EKS
  use_on_prem_k8s = var.on_prem_kubernetes_enabled
  
  kubernetes_config = {
    cluster_name = var.on_prem_kubernetes_enabled ? "on-prem-k8s-cluster" : "eks-code-server-prod"
    api_endpoint = var.on_prem_kubernetes_enabled ? "https://${var.on_prem_k8s_nodes[0].ip_address}:6443" : ""
    ca_cert_file = var.on_prem_kubernetes_enabled ? pathexpand("~/.kube/ca.crt") : ""
    deployment_mode = var.on_prem_kubernetes_enabled ? "on-prem-kubeadm" : "cloud-eks"
  }
}

output "kubernetes_deployment_mode" {
  description = "Kubernetes deployment mode (on-prem or cloud)"
  value       = local.kubernetes_config.deployment_mode
}

output "kubernetes_cluster_endpoint" {
  description = "Kubernetes cluster API endpoint"
  value       = local.kubernetes_config.api_endpoint
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 22-D: GPU INFRASTRUCTURE (On-Prem or Cloud)
# ═════════════════════════════════════════════════════════════════════════════

# GPU infrastructure depends on:
# - Phase 22-A Kubernetes cluster (must exist first)
# - Proper kernel modules and drivers

locals {
  gpu_config = {
    enabled                = var.on_prem_gpu_enabled
    deployment_mode        = var.on_prem_gpu_enabled ? "on-prem-gpu" : "aws-gpu"
    cuda_version           = var.on_prem_gpu_enabled ? var.cuda_toolkit_version : ""
    driver_version         = var.on_prem_gpu_enabled ? var.gpu_drivers_version : ""
    kubernetes_device_plugin = "nvidia-device-plugin"
  }
}

output "gpu_infrastructure_config" {
  description = "GPU infrastructure configuration"
  value       = local.gpu_config
  depends_on = [
    null_resource.kubeadm_bootstrap,  # Phase 22-A dependency
  ]
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 17: MULTI-REGION DISASTER RECOVERY
# ═════════════════════════════════════════════════════════════════════════════

# Phase 17 depends on:
# - Phase 16-A: Database HA (must be stable for baseline)
# - For cloud: Route53, AWS regions
# - For on-prem: Manual DNS/VPN failover

locals {
  dr_config = {
    deployment_mode = var.on_prem_kubernetes_enabled ? "on-prem-manual-dr" : "aws-route53-dr"
    rto_minutes      = var.on_prem_kubernetes_enabled ? 30 : 2  # Manual vs automated
    baseline_hours   = 4  # Require 4h of stable database before DR
  }
}

output "disaster_recovery_config" {
  description = "Disaster recovery configuration"
  value       = local.dr_config
}

# ═════════════════════════════════════════════════════════════════════════════
# PHASE 18: SECURITY HARDENING (Depends on Vault + mTLS)
# ═════════════════════════════════════════════════════════════════════════════

# Phase 18 depends on:
# - HashiCorp Vault (PKI initialization)
# - Kubernetes cluster (for service mesh)

output "security_vault_status" {
  description = "Vault initialization status"
  value       = var.operations_excellence_enabled ? "configured" : "disabled"
}

# ═════════════════════════════════════════════════════════════════════════════
# VALIDATION: DEPLOYMENT MODE CONSISTENCY
# ═════════════════════════════════════════════════════════════════════════════

variable "deployment_mode" {
  description = "Overall deployment mode (cloud or on-premises)"
  type        = string
  default     = "on-prem"
  validation {
    condition     = contains(["cloud", "on-prem", "hybrid"], var.deployment_mode)
    error_message = "Deployment mode must be 'cloud', 'on-prem', or 'hybrid'"
  }
}

# Validation logic
locals {
  deployment_validation = {
    consistency_check = (
      var.deployment_mode == "on-prem" && var.on_prem_kubernetes_enabled ? "VALID" :
      var.deployment_mode == "cloud" && !var.on_prem_kubernetes_enabled ? "VALID" :
      var.deployment_mode == "hybrid" ? "VALID" :
      "INVALID"
    )
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# MASTER EXECUTION SEQUENCE
# ═════════════════════════════════════════════════════════════════════════════

# Correct execution order:
# 1. Phase 24: Operations Excellence (foundations)
# 2. Phase 22-A: Kubernetes (on-prem-kubeadm or cloud-eks)
# 3. Phase 22-D: GPU (if enabled)
# 4. Phase 17: Multi-Region DR (after 4h baseline)
# 5. Phase 18: Security (Vault + mTLS)
# 6. Phase 25: GraphQL API Portal (integration layer)

locals {
  execution_sequence = [
    { phase = "24", name = "Operations Excellence", enabled = var.operations_excellence_enabled },
    { phase = "22-A", name = "Kubernetes", enabled = var.on_prem_kubernetes_enabled },
    { phase = "22-D", name = "GPU Infrastructure", enabled = var.on_prem_gpu_enabled },
    { phase = "17", name = "Disaster Recovery", enabled = true },  # Always planning DR
    { phase = "18", name = "Security Hardening", enabled = true },  # Always required
    { phase = "25", name = "GraphQL API Portal", enabled = var.graphql_api_portal_enabled },
  ]
}

output "execution_sequence" {
  description = "Recommended Terraform apply sequence"
  value       = local.execution_sequence
}

# ═════════════════════════════════════════════════════════════════════════════
# DEPLOYMENT STATUS SUMMARY
# ═════════════════════════════════════════════════════════════════════════════

output "infrastructure_status" {
  description = "Complete infrastructure deployment status"
  value = {
    deployment_mode             = var.deployment_mode
    kubernetes_mode             = var.on_prem_kubernetes_enabled ? "on-prem-kubeadm" : "cloud-eks"
    gpu_enabled                 = var.on_prem_gpu_enabled
    operations_excellence       = var.operations_excellence_enabled
    graphql_api_portal          = var.graphql_api_portal_enabled
    disaster_recovery_baseline  = "4 hours (Phase 16-A stability)"
    timestamp                   = timestamp()
  }
}
