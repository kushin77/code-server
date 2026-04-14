# ═════════════════════════════════════════════════════════════════════════════
# On-Premises Deployment Configuration
# ═════════════════════════════════════════════════════════════════════════════
# Usage: terraform apply -var-file=environments/on-prem.tfvars
# Status: Ready for immediate deployment
# ═════════════════════════════════════════════════════════════════════════════

# Overall deployment mode
deployment_mode = "on-prem"

# ═════════════════════════════════════════════════════════════════════════════
# Phase 24: Operations Excellence & Resilience
# ═════════════════════════════════════════════════════════════════════════════

operations_excellence_enabled  = true
backup_retention_days          = 30
disaster_recovery_replicas     = 2

# ═════════════════════════════════════════════════════════════════════════════
# Phase 25: GraphQL API & Developer Portal
# ═════════════════════════════════════════════════════════════════════════════

graphql_api_portal_enabled = true
graphql_replicas           = 3
portal_replicas            = 2

# ═════════════════════════════════════════════════════════════════════════════
# Phase 22-A: On-Premises Kubernetes (kubeadm)
# ═════════════════════════════════════════════════════════════════════════════

on_prem_kubernetes_enabled = true
k8s_version                = "1.28.0"
container_runtime          = "containerd"
k8s_pod_cidr               = "10.244.0.0/16"
k8s_service_cidr           = "10.96.0.0/12"

# On-premises node configuration
# IMPORTANT: Update with your actual node IPs and SSH keys
on_prem_k8s_nodes = [
  {
    hostname      = "kube-control-01"
    ip_address    = "192.168.168.31"
    ssh_user      = "akushnir"
    ssh_key       = "~/.ssh/id_rsa"
    role          = "control-plane"
    gpu_enabled   = true
    gpu_type      = "nvidia"
  },
  # Uncomment to add worker nodes
  # {
  #   hostname      = "kube-worker-01"
  #   ip_address    = "192.168.168.32"
  #   ssh_user      = "akushnir"
  #   ssh_key       = "~/.ssh/id_rsa"
  #   role          = "worker"
  #   gpu_enabled   = false
  #   gpu_type      = "none"
  # },
  # {
  #   hostname      = "kube-worker-02"
  #   ip_address    = "192.168.168.33"
  #   ssh_user      = "akushnir"
  #   ssh_key       = "~/.ssh/id_rsa"
  #   role          = "worker"
  #   gpu_enabled   = true
  #   gpu_type      = "nvidia"
  # }
]

# ═════════════════════════════════════════════════════════════════════════════
# Phase 22-D: On-Premises GPU Infrastructure
# ═════════════════════════════════════════════════════════════════════════════

on_prem_gpu_enabled     = true
gpu_drivers_version     = "550.90.07"
cuda_toolkit_version    = "12.4"
cudnn_version           = "8.9.7"
gpu_memory_limit        = 24  # GB per GPU

# ═════════════════════════════════════════════════════════════════════════════
# Tags and Metadata
# ═════════════════════════════════════════════════════════════════════════════

common_tags = {
  Environment = "production"
  Deployment  = "on-premises"
  IaC         = "terraform"
  ManagedBy   = "terraform"
  CreatedDate = "2026-04-14"
}
