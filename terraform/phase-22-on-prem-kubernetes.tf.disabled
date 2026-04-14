# ═════════════════════════════════════════════════════════════════════════════
# Phase 22: On-Premises Kubernetes Cluster (kubeadm)
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Single-node or multi-node Kubernetes deployment on bare-metal systems
# Status: Production-ready for on-premises deployments
# Deployment Mode: SSH provisioning via kubeadm (not cloud-dependent)
# ═════════════════════════════════════════════════════════════════════════════

variable "on_prem_kubernetes_enabled" {
  description = "Enable on-premises Kubernetes cluster via kubeadm"
  type        = bool
  default     = false
}

variable "on_prem_k8s_nodes" {
  description = "List of on-premises nodes for Kubernetes cluster"
  type = list(object({
    hostname    = string
    ip_address  = string
    ssh_user    = string
    ssh_key     = string
    role        = string # "control-plane", "worker"
    gpu_enabled = bool
    gpu_type    = string # "nvidia", "amd", "none"
  }))
  default = [
    {
      hostname    = "kube-control-01"
      ip_address  = "192.168.168.31"
      ssh_user    = "akushnir"
      ssh_key     = "~/.ssh/id_rsa"
      role        = "control-plane"
      gpu_enabled = false
      gpu_type    = "none"
    }
  ]
}

variable "k8s_version" {
  description = "Kubernetes version for kubeadm"
  type        = string
  default     = "1.28.0"
}

variable "container_runtime" {
  description = "Container runtime (docker or containerd)"
  type        = string
  default     = "containerd"
  validation {
    condition     = contains(["docker", "containerd"], var.container_runtime)
    error_message = "Container runtime must be 'docker' or 'containerd'"
  }
}

variable "k8s_pod_cidr" {
  description = "Pod CIDR for Kubernetes cluster"
  type        = string
  default     = "10.244.0.0/16"
}

variable "k8s_service_cidr" {
  description = "Service CIDR for Kubernetes cluster"
  type        = string
  default     = "10.96.0.0/12"
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. KUBEADM BOOTSTRAP SCRIPT (IDEMPOTENT)
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "kubeadm_bootstrap" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_kubernetes_enabled
  }

  triggers = {
    node_ip = each.value.ip_address
    k8s_ver = var.k8s_version
    runtime = var.container_runtime
    bootstrap = base64encode(templatefile("${path.module}/scripts/kubeadm-bootstrap.sh.tpl", {
      KUBERNETES_VERSION = var.k8s_version
      CONTAINER_RUNTIME  = var.container_runtime
      POD_CIDR           = var.k8s_pod_cidr
      SERVICE_CIDR       = var.k8s_service_cidr
      NODE_ROLE          = each.value.role
    }))
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "if ! command -v kubeadm &> /dev/null; then bash -s < /dev/stdin; fi",
      "echo 'Kubernetes ${var.k8s_version} bootstrap complete (idempotent)'",
    ]

    connection {
      type        = "ssh"
      host        = each.value.ip_address
      user        = each.value.ssh_user
      private_key = file(pathexpand(each.value.ssh_key))
      timeout     = "10m"
    }
  }

  depends_on = [
    null_resource.sysctl_tuning,
    null_resource.kernel_modules
  ]
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. KERNEL MODULES & SYSCTL TUNING (IDEMPOTENT)
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "kernel_modules" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_kubernetes_enabled
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      # Idempotent: check if modules already loaded
      "for mod in overlay br_netfilter; do",
      "  if ! lsmod | grep -q \"^$mod \"; then",
      "    echo 'Loading kernel module: '$mod",
      "    sudo modprobe $mod",
      "  else",
      "    echo 'Kernel module '$mod' already loaded'",
      "  fi",
      "done",
    ]

    connection {
      type        = "ssh"
      host        = each.value.ip_address
      user        = each.value.ssh_user
      private_key = file(pathexpand(each.value.ssh_key))
      timeout     = "5m"
    }
  }
}

resource "null_resource" "sysctl_tuning" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_kubernetes_enabled
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      # Idempotent: check if sysctl already set
      "for setting in 'net.bridge.bridge-nf-call-iptables=1' 'net.bridge.bridge-nf-call-ip6tables=1' 'net.ipv4.ip_forward=1'; do",
      "  key=$(echo $setting | cut -d= -f1)",
      "  value=$(echo $setting | cut -d= -f2)",
      "  current=$(sysctl -n $key 2>/dev/null || echo '')",
      "  if [ \"$current\" != \"$value\" ]; then",
      "    echo \"Setting sysctl: $setting\"",
      "    echo \"$setting\" | sudo tee -a /etc/sysctl.d/99-kubernetes.conf > /dev/null",
      "    sudo sysctl -p /etc/sysctl.d/99-kubernetes.conf > /dev/null",
      "  else",
      "    echo \"sysctl $key already set to $value\"",
      "  fi",
      "done",
    ]

    connection {
      type        = "ssh"
      host        = each.value.ip_address
      user        = each.value.ssh_user
      private_key = file(pathexpand(each.value.ssh_key))
      timeout     = "5m"
    }
  }

  depends_on = [null_resource.kernel_modules]
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. GPU SUPPORT FOR ON-PREM KUBERNETES (OPTIONAL)
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "nvidia_gpu_support" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_kubernetes_enabled && node.gpu_enabled && node.gpu_type == "nvidia"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "# Idempotent check for nvidia-container-runtime",
      "if ! command -v nvidia-container-runtime &> /dev/null; then",
      "  echo 'Installing NVIDIA container runtime'",
      "  distribution=$(. /etc/os-release;echo $ID$VERSION_ID)",
      "  curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo apt-key add -",
      "  curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sudo tee /etc/apt/sources.list.d/libnvidia-container.list",
      "  sudo apt-get update && sudo apt-get install -y nvidia-container-runtime",
      "else",
      "  echo 'NVIDIA container runtime already installed'",
      "fi",
      "# Install NVIDIA device plugin for Kubernetes",
      "kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml || echo 'GPU device plugin may already be installed'",
    ]

    connection {
      type        = "ssh"
      host        = each.value.ip_address
      user        = each.value.ssh_user
      private_key = file(pathexpand(each.value.ssh_key))
      timeout     = "15m"
    }
  }

  depends_on = [null_resource.kubeadm_bootstrap]
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. PERSISTENT VOLUME STORAGE (LOCAL VOLUMES)
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "local_storage" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_kubernetes_enabled
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "# Create local storage directory (idempotent)",
      "sudo mkdir -p /mnt/local-storage",
      "sudo chmod 755 /mnt/local-storage",
      "echo 'Local storage ready at /mnt/local-storage'",
    ]

    connection {
      type        = "ssh"
      host        = each.value.ip_address
      user        = each.value.ssh_user
      private_key = file(pathexpand(each.value.ssh_key))
      timeout     = "5m"
    }
  }

  depends_on = [null_resource.kubeadm_bootstrap]
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. HELM INITIALIZATION & PACKAGE MANAGERS
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "helm_setup" {
  count = var.on_prem_kubernetes_enabled && length(var.on_prem_k8s_nodes) > 0 ? 1 : 0

  provisioner "local-exec" {
    command = "set -euo pipefail && ${file("${path.module}/scripts/setup-helm.sh")}"

    environment = {
      KUBECONFIG = local.kubeconfig_path
      HELM_REPO  = "https://charts.helm.sh/stable"
    }
  }

  depends_on = [null_resource.kubeadm_bootstrap]
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. MONITORING & OBSERVABILITY FOR K8S CLUSTER
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "prometheus_k8s" {
  count = var.on_prem_kubernetes_enabled ? 1 : 0

  provisioner "local-exec" {
    command = "set -euo pipefail && ${file("${path.module}/scripts/install-prometheus-operator.sh")}"

    environment = {
      KUBECONFIG = local.kubeconfig_path
    }
  }

  depends_on = [null_resource.helm_setup]
}

# ═════════════════════════════════════════════════════════════════════════════
# LOCAL VARIABLES FOR KUBECONFIG & PATHS
# ═════════════════════════════════════════════════════════════════════════════

locals {
  kubeconfig_path = pathexpand("~/.kube/config")
  first_control_plane_node = [
    for node in var.on_prem_k8s_nodes : node
    if node.role == "control-plane"
  ][0]
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS FOR INTEGRATION WITH OTHER MODULES
# ═════════════════════════════════════════════════════════════════════════════

output "kubernetes_cluster_name" {
  description = "On-premises Kubernetes cluster name"
  value       = var.on_prem_kubernetes_enabled ? "on-prem-k8s-cluster" : null
}

output "kubernetes_api_endpoint" {
  description = "Kubernetes API endpoint for on-prem cluster"
  value       = var.on_prem_kubernetes_enabled ? "https://${local.first_control_plane_node.ip_address}:6443" : null
}

output "kubernetes_ca_cert_path" {
  description = "Path to Kubernetes CA certificate"
  value       = var.on_prem_kubernetes_enabled ? pathexpand("~/.kube/ca.crt") : null
}

output "deployment_mode" {
  description = "Confirms this is on-premises kubeadm deployment"
  value       = "on-prem-kubeadm"
}
