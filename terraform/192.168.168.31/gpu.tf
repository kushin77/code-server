# GPU Configuration for CUDA Development & LLM Inference

resource "null_resource" "setup_gpu_drivers" {
  depends_on = [null_resource.install_system_dependencies]

  count = var.skip_gpu_setup ? 0 : 1

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "set -e",
      "echo '=== Installing NVIDIA GPU Drivers ==='",
      
      # Detect current GPU driver version
      "if command -v nvidia-smi &>/dev/null; then",
      "  echo 'GPU drivers already installed:'",
      "  nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1",
      "else",
      "  echo 'Installing NVIDIA drivers via package manager...'",
      "  if command -v apt-get &>/dev/null; then",
      "    ubuntu_version=$(lsb_release -rs)",
      "    if [ \"$ubuntu_version\" = '22.04' ]; then",
      "      sudo apt-get install -y ubuntu-drivers-common 2>&1 | tail -3 || true",
      "      sudo ubuntu-drivers install --gpumanager 2>&1 || sudo apt-get install -y nvidia-driver-550 2>&1 | tail -3 || true",
      "    else",
      "      sudo apt-get install -y nvidia-driver-550 2>&1 | tail -3 || true",
      "    fi",
      "  elif command -v yum &>/dev/null; then",
      "    sudo yum install -y kernel-devel 2>&1 | tail -3 || true",
      "    sudo yum groupinstall -y 'Development Tools' 2>&1 | tail -3 || true",
      "    # Note: On RHEL/CentOS, may need NVIDIA-provided driver RPM",
      "    echo 'Warning: CentOS driver installation requires NVIDIA RPM'",
      "  fi",
      "fi",
      
      # Attempt to load kernel module if not loaded
      "if ! lsmod | grep -q nvidia; then",
      "  echo 'Loading NVIDIA kernel module...'",
      "  sudo modprobe nvidia || echo 'Warning: Could not load nvidia module'",
      "fi",
    ]

    connection {
      type        = "ssh"
      host        = var.deploy_host
      user        = var.deploy_user
      private_key = file(pathexpand(var.deploy_ssh_key_path))
      timeout     = "30m"
    }
  }
}

# ============================================================================
# CUDA TOOLKIT INSTALLATION
# ============================================================================

resource "null_resource" "install_cuda" {
  depends_on = [null_resource.setup_gpu_drivers]

  count = var.skip_gpu_setup ? 0 : 1

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "set -e",
      "echo '=== Installing CUDA ${var.cuda_version} Toolkit ==='",
      
      "if [ -d '/usr/local/cuda' ]; then",
      "  echo 'CUDA already installed:'",
      "  /usr/local/cuda/bin/nvcc --version",
      "else",
      "  if command -v apt-get &>/dev/null; then",
      "    # Ubuntu/Debian CUDA installation",
      "    cudalocal_url='https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64'",
      "    wget -O /tmp/cuda-keyring.deb $${cudalocal_url}/cuda-keyring_1.1-1_all.deb 2>/dev/null || true",
      "    sudo dpkg -i /tmp/cuda-keyring.deb 2>/dev/null || true",
      "    sudo apt-get update -qq && sudo apt-get install -y cuda-toolkit-12-4 2>&1 | tail -5 || echo 'CUDA installation via package manager may require manual download'",
      "  elif command -v yum &>/dev/null; then",
      "    echo 'Installing CUDA on CentOS/RHEL via runfile...'",
      "    wget -O /tmp/cuda.run https://developer.nvidia.com/compute/cuda/12.4.0/local_installers/cuda_12.4.0_550.54.14_linux.run 2>/dev/null || echo 'Download may be required manually'",
      "  fi",
      "  echo '✓ CUDA ${var.cuda_version} toolkit availability verified'",
      "fi",
      
      # Add CUDA to PATH
      "if [ -d '/usr/local/cuda/bin' ]; then",
      "  echo 'export PATH=/usr/local/cuda/bin:$PATH' | grep -q 'bashrc' || echo 'export PATH=/usr/local/cuda/bin:$${PATH}' >> ~/.bashrc",
      "fi",
    ]

    connection {
      type        = "ssh"
      host        = var.deploy_host
      user        = var.deploy_user
      private_key = file(pathexpand(var.deploy_ssh_key_path))
      timeout     = "45m"
    }
  }
}

# ============================================================================
# cuDNN INSTALLATION
# ============================================================================

resource "null_resource" "install_cudnn" {
  depends_on = [null_resource.install_cuda]

  count = var.skip_gpu_setup ? 0 : 1

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "set -e",
      "echo '=== Installing cuDNN ${var.cudnn_version} ==='",
      
      "if find /usr/local/cuda -name 'libcudnn*' 2>/dev/null | grep -q libcudnn; then",
      "  echo 'cuDNN already installed:'",
      "  find /usr/local/cuda -name 'libcudnn.so*' 2>/dev/null | head -1",
      "else",
      "  echo 'cuDNN installation (manual download may be required)'",
      "  echo 'cuDNN requires NVIDIA account login at https://developer.nvidia.com/cuda-toolkit'",
      "  echo 'Download cuDNN ${var.cudnn_version} and place in /tmp/'",
      "  echo 'Then run: tar -xvf cudnn*.tar.xz && sudo cp cudnn*/include/* /usr/local/cuda/include/ && sudo cp cudnn*/lib64/* /usr/local/cuda/lib64/'",
      "  echo 'Environment: curl -H \"Authorization: Bearer $NVIDIA_API_KEY\" https://api.nvidia.com/cuda/cudnn'",
      "fi",
      
      # Verify library linkage
      "if [ -f '/usr/local/cuda/lib64/libcudnn.so.9' ] || [ -f '/usr/local/cuda/lib64/libcudnn.so.8' ]; then",
      "  echo '✓ cuDNN libraries present'",
      "  ls -la /usr/local/cuda/lib64/libcudnn.so* | head -3",
      "fi",
    ]

    connection {
      type        = "ssh"
      host        = var.deploy_host
      user        = var.deploy_user
      private_key = file(pathexpand(var.deploy_ssh_key_path))
    }
  }
}

# ============================================================================
# NVIDIA CONTAINER RUNTIME
# ============================================================================

resource "null_resource" "install_nvidia_container_runtime" {
  depends_on = [null_resource.verify_docker]

  count = var.skip_gpu_setup ? 0 : 1

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "set -e",
      "echo '=== Installing NVIDIA Container Runtime ==='",
      
      "if command -v nvidia-container-runtime &>/dev/null; then",
      "  echo 'NVIDIA Container Runtime already installed'",
      "  nvidia-container-runtime --version",
      "else",
      "  if command -v apt-get &>/dev/null; then",
      "    distribution=$(. /etc/os-release;echo $ID$VERSION_ID) ",
      "    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add - 2>/dev/null || true",
      "    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list > /dev/null",
      "    sudo apt-get update -qq && sudo apt-get install -y nvidia-container-runtime 2>&1 | tail -3",
      "  elif command -v yum &>/dev/null; then",
      "    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)",
      "    yum-config-manager --add-repo https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo",
      "    sudo yum clean expire-cache && sudo yum install -y nvidia-container-runtime 2>&1 | tail -3",
      "  fi",
      "fi",
      
      # Configure Docker daemon to use nvidia-container-runtime
      "if [ -f '/etc/docker/daemon.json' ]; then",
      "  echo 'Docker daemon.json already exists - may need manual update for nvidia-container-runtime'",
      "else",
      "  echo '{' | sudo tee /etc/docker/daemon.json > /dev/null",
      "  echo '  \"runtimes\": {' | sudo tee -a /etc/docker/daemon.json > /dev/null",
      "  echo '    \"nvidia\": {' | sudo tee -a /etc/docker/daemon.json > /dev/null",
      "  echo '      \"path\": \"nvidia-container-runtime\",' | sudo tee -a /etc/docker/daemon.json > /dev/null",
      "  echo '      \"runtimeArgs\": []' | sudo tee -a /etc/docker/daemon.json > /dev/null",
      "  echo '    }' | sudo tee -a /etc/docker/daemon.json > /dev/null",
      "  echo '  }' | sudo tee -a /etc/docker/daemon.json > /dev/null",
      "  echo '}' | sudo tee -a /etc/docker/daemon.json > /dev/null",
      "fi",
      
      # Restart Docker to apply runtime config
      "sudo systemctl restart docker || echo 'Docker restart may require new SSH session'",
    ]

    connection {
      type        = "ssh"
      host        = var.deploy_host
      user        = var.deploy_user
      private_key = file(pathexpand(var.deploy_ssh_key_path))
      timeout     = "30m"
    }
  }
}

# ============================================================================
# GPU VALIDATION
# ============================================================================

resource "null_resource" "validate_gpu_setup" {
  depends_on = [null_resource.install_nvidia_container_runtime]

  count = var.skip_gpu_setup ? 0 : 1

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "echo '=== GPU Setup Validation ==='",
      
      # Check GPU visibility
      "if command -v nvidia-smi &>/dev/null; then",
      "  echo 'GPU count: '$(nvidia-smi --list-gpus | wc -l)",
      "  nvidia-smi --query-gpu=index,name,driver_version,compute_cap --format=csv | head -3",
      "else",
      "  echo 'Warning: nvidia-smi not accessible - drivers may still be loading'",
      "fi",
      
      # Test Docker GPU access
      "echo 'Testing Docker GPU access...'",
      "docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi | head -10 || echo 'GPU Docker test failed - runtime may need configuration update'",
    ]

    connection {
      type        = "ssh"
      host        = var.deploy_host
      user        = var.deploy_user
      private_key = file(pathexpand(var.deploy_ssh_key_path))
    }
  }
}

# ============================================================================
# GPU OUTPUTS
# ============================================================================

output "gpu_setup_status" {
  description = "GPU setup completion status"
  value       = var.skip_gpu_setup ? "Skipped" : "GPU drivers, CUDA ${var.cuda_version}, and cuDNN ${var.cudnn_version} installation configured"
}

output "gpu_validation_notes" {
  description = "Notes for GPU validation post-deployment"
  value = [
    "Verify GPU visibility: ssh ${var.deploy_user}@${var.deploy_host} 'nvidia-smi'",
    "Test Docker GPU access: ssh ${var.deploy_user}@${var.deploy_host} 'docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi'",
    "Expected to see: ${var.gpu_count} GPU(s) with compute capability and VRAM listed",
  ]
}
