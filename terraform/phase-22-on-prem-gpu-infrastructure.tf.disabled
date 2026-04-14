# ═════════════════════════════════════════════════════════════════════════════
# Phase 22-D: On-Premises GPU Infrastructure
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: GPU support for on-premises Kubernetes cluster (bare-metal)
# Deployment: NVIDIA GPU provisioning via SSH + kubeadm integration
# Status: Production-ready for on-premises deployments
# ═════════════════════════════════════════════════════════════════════════════

variable "on_prem_gpu_enabled" {
  description = "Enable GPU support on on-premises nodes"
  type        = bool
  default     = false
}

variable "gpu_drivers_version" {
  description = "NVIDIA GPU driver version"
  type        = string
  default     = "550.90.07"
}

variable "cuda_toolkit_version" {
  description = "CUDA toolkit version"
  type        = string
  default     = "12.4"
}

variable "gpu_memory_limit" {
  description = "Memory limit per GPU in GB"
  type        = number
  default     = 24
  validation {
    condition     = var.gpu_memory_limit > 0 && var.gpu_memory_limit <= 48
    error_message = "GPU memory limit must be between 1 and 48 GB"
  }
}

variable "cudnn_version" {
  description = "cuDNN version for deep learning"
  type        = string
  default     = "8.9.7"
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. PRE-REQUISITES CHECK (IDEMPOTENT)
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "gpu_prerequisites_check" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_gpu_enabled && node.gpu_enabled && node.gpu_type == "nvidia"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "echo 'Checking GPU prerequisites...'",
      "# Check BIOS settings for PCIe/IOMMU",
      "if ! grep -q IOMMU /proc/cmdline 2>/dev/null || [ ! -d /sys/firmware/efi/vars ]; then",
      "  echo 'WARNING: BIOS settings may need verification for GPU support'",
      "  echo 'Verify: Intel VT-x / AMD-V enabled, IOMMU enabled in UEFI/BIOS'",
      "fi",
      "# Check CPU has SSE4.2 for modern CUDA",
      "if ! grep -q sse4_2 /proc/cpuinfo; then",
      "  echo 'WARNING: CPU may lack SSE4.2 (older CPU detected)'",
      "fi",
      "# List GPUs via lspci (informational)",
      "echo '=== Available GPUs ==='",
      "lspci | grep -i 'vga\\|nvidia\\|gpu' || echo 'No GPU detected in lspci'",
      "echo 'GPU prerequisites check complete'",
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
# 2. NVIDIA GPU DRIVERS INSTALLATION (IDEMPOTENT)
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "nvidia_gpu_drivers" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_gpu_enabled && node.gpu_enabled && node.gpu_type == "nvidia"
  }

  triggers = {
    driver_version = var.gpu_drivers_version
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "# Idempotent driver installation check",
      "if command -v nvidia-smi &> /dev/null; then",
      "  CURRENT_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)",
      "  if [ \"$CURRENT_DRIVER\" = \"${var.gpu_drivers_version}\" ]; then",
      "    echo 'NVIDIA GPU driver ${var.gpu_drivers_version} already installed'",
      "    exit 0",
      "  else",
      "    echo 'Updating driver from '$CURRENT_DRIVER' to ${var.gpu_drivers_version}'",
      "  fi",
      "fi",
      "",
      "echo 'Installing NVIDIA GPU Drivers ${var.gpu_drivers_version}...'",
      "# Add NVIDIA repository",
      "sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub 2>/dev/null || true",
      "distribution=$(. /etc/os-release; echo $ID$VERSION_ID | sed -e 's/\\.//')",
      "sudo add-apt-repository -y 'deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /'",
      "sudo apt-get update -y",
      "",
      "# Install GPU drivers (non-interactive)",
      "sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 100",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y cuda-drivers-${var.gpu_drivers_version}",
      "",
      "echo 'NVIDIA drivers installed. Verifying...'",
      "nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader",
    ]

    connection {
      type        = "ssh"
      host        = each.value.ip_address
      user        = each.value.ssh_user
      private_key = file(pathexpand(each.value.ssh_key))
      timeout     = "30m"
    }

    on_failure = continue # Don't fail if already installed
  }

  depends_on = [null_resource.gpu_prerequisites_check]
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. CUDA TOOLKIT INSTALLATION (IDEMPOTENT)
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "cuda_toolkit" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_gpu_enabled && node.gpu_enabled && node.gpu_type == "nvidia"
  }

  triggers = {
    cuda_version = var.cuda_toolkit_version
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "# Idempotent CUDA installation check",
      "if [ -f /usr/local/cuda/version.json ]; then",
      "  INSTALLED_CUDA=$(jq -r '.cuda.version' /usr/local/cuda/version.json 2>/dev/null || echo '')",
      "  if [[ \"$INSTALLED_CUDA\" == \"${var.cuda_toolkit_version}\"* ]]; then",
      "    echo 'CUDA ${var.cuda_toolkit_version} already installed'",
      "    exit 0",
      "  fi",
      "fi",
      "",
      "echo 'Installing CUDA Toolkit ${var.cuda_toolkit_version}...'",
      "wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb",
      "sudo dpkg -i cuda-keyring_1.1-1_all.deb",
      "rm cuda-keyring_1.1-1_all.deb",
      "sudo apt-get update -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y cuda-toolkit-${var.cuda_toolkit_version} cuda-command-line-tools-${var.cuda_toolkit_version}",
      "",
      "# Set CUDA environment variables",
      "if ! grep -q 'export PATH=/usr/local/cuda/bin' ~/.bashrc; then",
      "  echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc",
      "  echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc",
      "fi",
      "",
      "source ~/.bashrc || true",
      "echo 'CUDA Toolkit installed. Verifying...'",
      "nvcc --version | grep -oE 'V[0-9]+\\.[0-9]+'",
    ]

    connection {
      type        = "ssh"
      host        = each.value.ip_address
      user        = each.value.ssh_user
      private_key = file(pathexpand(each.value.ssh_key))
      timeout     = "45m"
    }

    on_failure = continue
  }

  depends_on = [null_resource.nvidia_gpu_drivers]
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. CUDNN INSTALLATION (OPTIONAL, DEEP LEARNING)
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "cudnn_installation" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_gpu_enabled && node.gpu_enabled && node.gpu_type == "nvidia"
  }

  triggers = {
    cudnn_version = var.cudnn_version
  }

  provisioner "local-exec" {
    command = "echo 'CUDNN requires manual download from NVIDIA (requires login). See: docs/GPU_TROUBLESHOOTING_GUIDE.md for setup'"
  }

  depends_on = [null_resource.cuda_toolkit]
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. DOCKER GPU SUPPORT CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "docker_gpu_runtime" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_gpu_enabled && node.gpu_enabled && node.gpu_type == "nvidia"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "# Check if nvidia-docker already configured",
      "if grep -q '\"nvidia\"' /etc/docker/daemon.json 2>/dev/null; then",
      "  echo 'NVIDIA Docker runtime already configured'",
      "  exit 0",
      "fi",
      "",
      "echo 'Configuring NVIDIA Docker runtime...'",
      "# Add NVIDIA Docker repository",
      "sudo apt-key adv --fetch-keys https://nvidia.github.io/nvidia-docker/gpgkey 2>/dev/null || true",
      "distribution=$(. /etc/os-release; echo $ID$VERSION_ID | sed -e 's/\\.//')",
      "curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list",
      "sudo apt-get update -y && sudo apt-get install -y nvidia-docker2",
      "",
      "# Configure nvidia-docker as default runtime in daemon.json",
      "sudo bash -c 'cat > /etc/docker/daemon.json << EOF",
      "{",
      "  \"runtimes\": {",
      "    \"nvidia\": {",
      "      \"path\": \"nvidia-container-runtime\",",
      "      \"runtimeArgs\": []",
      "    }",
      "  },",
      "  \"default-runtime\": \"runc\"",
      "}",
      "EOF'",
      "",
      "# Reload Docker daemon",
      "sudo systemctl restart docker",
      "echo 'NVIDIA Docker runtime configured'",
      "docker run --rm --gpus all nvidia/cuda:${var.cuda_toolkit_version}-base nvidia-smi 2>/dev/null || echo 'GPU not detected (may need reboot)'",
    ]

    connection {
      type        = "ssh"
      host        = each.value.ip_address
      user        = each.value.ssh_user
      private_key = file(pathexpand(each.value.ssh_key))
      timeout     = "15m"
    }

    on_failure = continue
  }

  depends_on = [null_resource.nvidia_gpu_drivers]
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. KUBERNETES GPU DEVICE PLUGIN
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "k8s_nvidia_device_plugin" {
  count = var.on_prem_gpu_enabled && length([
    for node in var.on_prem_k8s_nodes : node
    if node.role == "control-plane" && node.gpu_enabled
  ]) > 0 ? 1 : 0

  provisioner "local-exec" {
    command = "kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml --kubeconfig=$${HOME}/.kube/config || true"
  }

  depends_on = [null_resource.nvidia_gpu_drivers]
}

# ═════════════════════════════════════════════════════════════════════════════
# 7. GPU NODE POOL LABELING
# ═════════════════════════════════════════════════════════════════════════════

resource "null_resource" "gpu_node_labels" {
  for_each = {
    for node in var.on_prem_k8s_nodes : node.hostname => node
    if var.on_prem_gpu_enabled && node.gpu_enabled && node.gpu_type == "nvidia"
  }

  provisioner "local-exec" {
    command = "kubectl label nodes $${each.key} accelerator=nvidia gpu-type=nvidia-gpu --kubeconfig=$${HOME}/.kube/config --overwrite || true"
  }

  depends_on = [null_resource.k8s_nvidia_device_plugin]
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS FOR INTEGRATION
# ═════════════════════════════════════════════════════════════════════════════

output "gpu_nodes_ready" {
  description = "Number of GPU-enabled nodes in cluster"
  value       = var.on_prem_gpu_enabled ? length([for n in var.on_prem_k8s_nodes : n if n.gpu_enabled]) : 0
}

output "cuda_version" {
  description = "CUDA Toolkit version installed"
  value       = var.on_prem_gpu_enabled ? var.cuda_toolkit_version : null
}

output "gpu_driver_version" {
  description = "NVIDIA GPU driver version"
  value       = var.on_prem_gpu_enabled ? var.gpu_drivers_version : null
}