# Main Configuration for 192.168.168.31 Docker Host Setup

# ============================================================================
# PHASE 1: CONNECTIVITY VALIDATION
# ============================================================================

# Validate SSH connectivity to target host
resource "null_resource" "validate_ssh_connectivity" {
  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no -i ${pathexpand(var.deploy_ssh_key_path)} ${var.deploy_user}@${var.deploy_host} 'hostname && uptime' > /dev/null 2>&1 && echo '✓ SSH connectivity OK'"
  }

  triggers = {
    host = var.deploy_host
    user = var.deploy_user
  }
}

# Validate target host OS and basic requirements
resource "null_resource" "validate_host_ready" {
  depends_on = [null_resource.validate_ssh_connectivity]

  provisioner "local-exec" {
    command = "ssh -i ${pathexpand(var.deploy_ssh_key_path)} ${var.deploy_user}@${var.deploy_host} 'uname -s | grep -i linux && echo \"✓ Linux OS detected\" || exit 1'"
  }
}

# ============================================================================
# PHASE 2: SYSTEM DEPENDENCIES
# ============================================================================

# Install required system packages (if not present)
resource "null_resource" "install_system_dependencies" {
  depends_on = [null_resource.validate_host_ready]

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "set -e",
      "echo '=== Installing System Dependencies ==='",

      # Update package manager
      "if command -v apt-get &>/dev/null; then",
      "  sudo apt-get update -qq",
      "  sudo apt-get install -y curl wget git jq tmux htop iotop nethogs rsync openssh-server openssh-client build-essential apt-transport-https ca-certificates gnupg lsb-release 2>&1 | tail -5",
      "elif command -v yum &>/dev/null; then",
      "  sudo yum install -y curl wget git jq tmux htop iotop nethogs rsync openssh-server openssh-clients gcc g++ make automake patch git-core 2>&1 | tail -5",
      "fi",

      "echo '✓ System dependencies installed'",
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
# PHASE 3: DOCKER INSTALLATION & CONFIGURATION
# ============================================================================

# Install Docker engine (if not already present)
resource "null_resource" "install_docker" {
  depends_on = [null_resource.install_system_dependencies]

  count = var.skip_docker_setup ? 0 : 1

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "set -e",
      "echo '=== Installing Docker ==='",

      # Check if Docker already installed
      "if command -v docker &>/dev/null; then",
      "  echo '✓ Docker already installed: '$(docker --version)",
      "else",
      "  if command -v apt-get &>/dev/null; then",
      "    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true",
      "    echo 'deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable' | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "    sudo apt-get update -qq && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>&1 | tail -3",
      "  elif command -v yum &>/dev/null; then",
      "    sudo yum install -y docker 2>&1 | tail -3",
      "  fi",
      "  echo '✓ Docker installed'",
      "fi",

      # Start Docker daemon
      "sudo systemctl enable docker 2>&1 | grep -v 'Created symlink' || true",
      "sudo systemctl start docker || true",
      "sudo usermod -aG docker ${var.deploy_user} || true",
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

# Verify Docker installation
resource "null_resource" "verify_docker" {
  depends_on = [null_resource.install_docker]

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "echo '=== Verifying Docker Installation ==='",
      "docker --version || echo 'Warning: Docker verification pending (requires logout/login for group membership)'",
      "which docker-compose || echo 'Docker Compose may need separate installation'",
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
# PHASE 4: SYSTEMD CONFIGURATION
# ============================================================================

# Ensure systemd mount units directory exists
resource "null_resource" "prepare_mount_directories" {
  depends_on = [null_resource.validate_host_ready]

  provisioner "remote-exec" {
    type = "ssh"

    inline = [
      "echo '=== Preparing Mount Directories ==='",
      "sudo mkdir -p ${var.nas_primary_mount_point} ${var.nas_backup_mount_point}",
      "sudo chown ${var.deploy_user}:${var.deploy_user} ${var.nas_primary_mount_point} 2>/dev/null || sudo chmod 755 ${var.nas_primary_mount_point}",
      "sudo chown ${var.deploy_user}:${var.deploy_user} ${var.nas_backup_mount_point} 2>/dev/null || sudo chmod 755 ${var.nas_backup_mount_point}",
      "echo '✓ Mount directories prepared'",
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
# PHASE 5: SYSTEM INFORMATION COLLECTION
# ============================================================================

# Collect system information for assessment
resource "null_resource" "collect_system_info" {
  depends_on = [null_resource.verify_docker]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Collecting System Information from ${var.deploy_host} ==="
      
      ssh -i ${pathexpand(var.deploy_ssh_key_path)} ${var.deploy_user}@${var.deploy_host} << 'SSH_EOF'
      echo "Hostname: $(hostname)"
      echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME || echo 'Unknown')"
      echo "Kernel: $(uname -r)"
      echo "CPUs: $(nproc)"
      echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
      echo "Docker: $(docker --version 2>/dev/null || echo 'Not accessible yet')"
      SSH_EOF
    EOT
  }
}

# ============================================================================
# OUTPUTS / HOST VALIDATION
# ============================================================================

output "host_ready" {
  description = "Indicator that host is ready for deployment"
  value       = "Host preparation complete - ready for GPU and NAS configuration"
}

output "deploy_host_info" {
  description = "Target host information"
  value = {
    host     = var.deploy_host
    user     = var.deploy_user
    document = "See docs/192.168.168.31-host-spec.md for detailed specifications"
  }
}
