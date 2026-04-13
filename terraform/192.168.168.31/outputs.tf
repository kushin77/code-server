# Terraform Outputs: Deployment Results & Assessment Data

# ============================================================================
# DEPLOYMENT STATUS
# ============================================================================

output "deployment_complete" {
  description = "Deployment completion status"
  value       = "Infrastructure provisioning complete - ready for docker-compose deployment"
}

output "deployment_summary" {
  description = "High-level deployment summary"
  value = {
    target_host     = var.deploy_host
    docker_ready    = "Host prepared for docker-compose deployment"
    gpu_configured  = var.skip_gpu_setup ? "Skipped" : "NVIDIA drivers, CUDA ${var.cuda_version}, cuDNN ${var.cudnn_version} configured"
    nas_mounted     = var.skip_nas_mount ? "Skipped" : "Primary and backup NAS mounts configured"
    storage_budget_gb = var.storage_ollama + var.storage_codeserver + var.storage_workspace
    deployment_url  = "https://${var.domain_name}:443 (after docker-compose deployment)"
  }
}

# ============================================================================
# CONNECTIVITY & ACCESS INFORMATION
# ============================================================================

output "ssh_access" {
  description = "SSH connection command for administrative access"
  value       = "ssh -i ${var.deploy_ssh_key_path} ${var.deploy_user}@${var.deploy_host}"
}

output "host_details" {
  description = "Target host connectivity details"
  value = {
    hostname       = var.deploy_host
    user           = var.deploy_user
    ssh_key        = var.deploy_ssh_key_path
    bastion_relay  = var.bastion_host != null ? var.bastion_host : "Direct connection (no bastion)"
    port           = 22
  }
}

# ============================================================================
# VERIFICATION COMMANDS
# ============================================================================

output "verification_commands" {
  description = "Commands to verify deployment readiness"
  value = {
    ssh_connectivity = "ssh -i ${var.deploy_ssh_key_path} ${var.deploy_user}@${var.deploy_host} 'hostname && uptime'"
    
    gpu_status = "ssh -i ${var.deploy_ssh_key_path} ${var.deploy_user}@${var.deploy_host} 'nvidia-smi --query-gpu=index,name,memory.total --format=csv'"
    
    docker_status = "ssh -i ${var.deploy_ssh_key_path} ${var.deploy_user}@${var.deploy_host} 'docker ps && docker version'"
    
    nas_mount_status = "ssh -i ${var.deploy_ssh_key_path} ${var.deploy_user}@${var.deploy_host} 'mount | grep /mnt/nas && df -h /mnt/nas-*'"
    
    system_info = "ssh -i ${var.deploy_ssh_key_path} ${var.deploy_user}@${var.deploy_host} 'bash scripts/infrastructure-assessment-31.sh > /tmp/assessment.txt && cat /tmp/assessment.txt'"
  }
}

# ============================================================================
# NAS & STORAGE INFORMATION
# ============================================================================

output "nas_configuration" {
  description = "NAS mount points and storage configuration"
  value = {
    primary_endpoint = var.nas_primary_endpoint
    primary_mount    = var.nas_primary_mount_point
    backup_endpoint  = var.nas_backup_endpoint
    backup_mount     = var.nas_backup_mount_point
    protocol         = var.nas_protocol
    mount_options    = var.nas_mount_options
    backup_schedule  = "Hourly incremental via systemd timer"
    rpo_target_min   = "15 minutes"
    rto_target_min   = "5 minutes"
  }
}

output "docker_volumes" {
  description = "Docker volume mount paths for docker-compose.yml configuration"
  value = {
    ollama_models = {
      container_path = "/mnt/models"
      host_path      = "${var.nas_primary_mount_point}/models"
      size_gb        = var.storage_ollama
    }
    codeserver_data = {
      container_path = "/home/coder/.local/share/code-server"
      host_path      = "${var.nas_primary_mount_point}/codeserver"
      size_gb        = var.storage_codeserver
    }
    workspace = {
      container_path = "/home/coder/projects"
      host_path      = "${var.nas_primary_mount_point}/workspaces"
      size_gb        = var.storage_workspace
    }
  }
}

# ============================================================================
# GPU INFORMATION
# ============================================================================

output "gpu_configuration" {
  description = "GPU setup details"
  value = {
    gpu_count            = var.gpu_count
    gpu_model            = var.gpu_model
    cuda_version         = var.cuda_version
    cudnn_version        = var.cudnn_version
    nvidia_container_runtime = "Configured"
    docker_runtime_option = "--runtime=nvidia"
    verification_command = "docker run --rm --runtime=nvidia nvidia/cuda:${var.cuda_version}-base nvidia-smi"
  }
}

output "ollama_configuration" {
  description = "Ollama LLM inference setup"
  value = {
    models_to_pull       = var.ollama_models
    gpu_allocation       = "OLLAMA_NUM_GPU=${var.ollama_num_gpu}"
    model_retention      = "OLLAMA_KEEP_ALIVE=${var.ollama_keep_alive}"
    models_path          = "${var.nas_primary_mount_point}/models"
    first_run_commands = [
      "ollama pull llama2:70b-chat",
      "ollama pull codegemma:latest",
      "ollama pull mistral:latest"
    ]
  }
}

# ============================================================================
# DOCKER COMPOSE READINESS
# ============================================================================

output "docker_compose_config" {
  description = "docker-compose deployment configuration"
  value = {
    config_file = "docker-compose.yml (see deployment/ directory)"
    environment_file = ".env file with:"
    config_details = {
      DEPLOY_HOST              = var.deploy_host
      DEPLOY_USER              = var.deploy_user
      DOMAIN_NAME              = var.domain_name
      TLS_ENABLED              = var.tls_enabled
      OLLAMA_NUM_GPU           = var.ollama_num_gpu
      OLLAMA_KEEP_ALIVE        = var.ollama_keep_alive
      STORAGE_CAPACITY_MODELS  = "${var.storage_ollama}G"
      STORAGE_CAPACITY_CODE    = "${var.storage_codeserver}G"
      STORAGE_CAPACITY_WORK    = "${var.storage_workspace}G"
    }
  }
}

# ============================================================================
# MONITORING & OBSERVABILITY READINESS
# ============================================================================

output "monitoring_setup_info" {
  description = "Information for monitoring and observability (see #144)"
  value = {
    prometheus_targets = [
      "192.168.168.31:9100 (node-exporter metrics)",
      "192.168.168.31:8080/metrics (code-server if exposed)",
      "192.168.168.31:11434/api/tags (Ollama API)"
    ]
    gpu_monitoring_required = "NVIDIA DCGM exporter (see #144)"
    nas_monitoring_required = "NFS/iSCSI mount point metrics via node-exporter"
    dashboard_template      = "See docs/ for Grafana dashboard JSON"
  }
}

# ============================================================================
# NEXT STEPS
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after Terraform apply"
  value = {
    step_1 = "Verify all components: Review verification_commands output above"
    step_2 = "Update docker-compose.yml with volume paths from docker_volumes output"
    step_3 = "Deploy containers: docker-compose -f docker-compose.yml up -d"
    step_4 = "Post-deployment validation: See testing files (#145)"
    step_5 = "Configure monitoring: Set up Prometheus scrape jobs (#144)"
    step_6 = "Create Phase 12 PR with IaC changes"
    documentation_link = "See docs/192.168.168.31-host-spec.md and docs/nas-specification-31.md"
    parent_issue = "#140: IaC Development - Terraform Modules for 192.168.168.31"
  }
}

# ============================================================================
# TROUBLESHOOTING LINKS
# ============================================================================

output "troubleshooting" {
  description = "Troubleshooting guide links"
  value = {
    infrastructure_assessment = "docs/192.168.168.31-host-spec.md (#139)"
    network_topology = "docs/network-topology-31.md (#139)"
    nas_specification = "docs/nas-specification-31.md (#142)"
    gpu_issues = "docs/GPU_CONFIGURATION_TROUBLESHOOTING.md (#141)"
    deployment_logs = "Check SSH logs: /var/log/cloud-init-output.log or syslog"
    terraform_debug = "TF_LOG=DEBUG terraform apply for detailed diagnostics"
  }
}
