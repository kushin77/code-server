#!/bin/bash
# @file        scripts/gpu-deploy-31.sh
# @module      operations
# @description gpu deploy 31 — on-prem code-server
# @owner       platform
# @status      active
# File:    gpu-deploy-31.sh
# Owner:   Platform Engineering
# Purpose: GPU deployment and validation for ${DEPLOY_HOST}
# Status:  ACTIVE
# Usage:   ./gpu-deploy-31.sh [validate|deploy|troubleshoot|all] [--dry-run]

set -e

# Bootstrap _common library (logging, utils, error-handler, config)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

LOG_DIR="${SCRIPT_DIR}/../logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${LOG_DIR}/gpu-deploy-${TIMESTAMP}.log"
DRY_RUN=false
ACTION="${1:-all}"

mkdir -p "$LOG_DIR"

# Execute with optional dry-run
execute() {
  local cmd="$@"
  log_info "Executing: $cmd"
  
  if [[ $DRY_RUN == true ]]; then
    log_warning "[DRY-RUN] Would execute: $cmd"
  else
    eval "$cmd" 2>&1 | tee -a "$LOG_FILE" || {
      log_error "Command failed: $cmd"
      return 1
    }
  fi
}

# Phase 1: Validation
validate_gpu_setup() {
  log_info "=== GPU Setup Validation ==="
  
  local failed=0
  
  # Check GPU hardware
  log_info "Checking GPU hardware..."
  if lspci | grep -q nvidia; then
    GPU_COUNT=$(lspci | grep -i nvidia | wc -l)
    log_success "Found $GPU_COUNT NVIDIA GPU(s)"
  else
    log_error "No NVIDIA GPUs detected"
    failed=$((failed + 1))
  fi
  
  # Check driver
  log_info "Checking NVIDIA driver..."
  if command -v nvidia-smi &> /dev/null; then
    DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    if [[ ${DRIVER_VERSION%.*} -ge 550 ]]; then
      log_success "Driver version: $DRIVER_VERSION (≥550)"
    else
      log_error "Driver version $DRIVER_VERSION is below minimum (550)"
      failed=$((failed + 1))
    fi
  else
    log_error "nvidia-smi not found"
    failed=$((failed + 1))
  fi
  
  # Check CUDA
  log_info "Checking CUDA toolkit..."
  if command -v nvcc &> /dev/null; then
    CUDA_VERSION=$(nvcc --version | grep -oP "release \K[0-9.]+")
    if [[ $CUDA_VERSION == 12.4* ]]; then
      log_success "CUDA version: $CUDA_VERSION"
    else
      log_warning "CUDA version $CUDA_VERSION detected (expected 12.4.x)"
    fi
  else
    log_error "nvcc not found"
    failed=$((failed + 1))
  fi
  
  # Check cuDNN
  log_info "Checking cuDNN..."
  if find /usr/local/cuda -name "libcudnn.so.9" &> /dev/null; then
    log_success "cuDNN 9.x installed"
  else
    log_warning "cuDNN 9.x not found"
    failed=$((failed + 1))
  fi
  
  # Check Docker GPU support
  log_info "Checking Docker GPU support..."
  if docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi &> /dev/null; then
    log_success "Docker GPU access working"
  else
    log_error "Docker GPU access not working"
    failed=$((failed + 1))
  fi
  
  if [[ $failed -eq 0 ]]; then
    log_success "All GPU validations passed"
    return 0
  else
    log_error "GPU validation failed with $failed issues"
    return 1
  fi
}

# Phase 2: Deployment (using Terraform)
deploy_gpu_infrastructure() {
  log_info "=== GPU Infrastructure Deployment ==="
  
  # Check Terraform configuration
  TF_DIR="${SCRIPT_DIR}/../terraform/${DEPLOY_HOST}"
  if [[ ! -d $TF_DIR ]]; then
    log_error "Terraform directory not found: $TF_DIR"
    return 1
  fi
  
  log_info "Using Terraform directory: $TF_DIR"
  
  # Initialize Terraform
  log_info "Initializing Terraform..."
  execute "cd $TF_DIR && terraform init"
  
  # Plan deployment
  log_info "Planning GPU infrastructure changes..."
  execute "cd $TF_DIR && terraform plan -out=tfplan"
  
  if [[ $DRY_RUN == false ]]; then
    read -p "Apply Terraform plan? (yes/no): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      log_info "Applying Terraform configuration..."
      execute "cd $TF_DIR && terraform apply tfplan"
      log_success "GPU infrastructure deployed successfully"
    else
      log_warning "Terraform apply cancelled"
    fi
  fi
}

# Phase 3: Performance Testing
test_gpu_performance() {
  log_info "=== GPU Performance Testing ==="
  
  # Test small model loading
  log_info "Testing model loading with $SMALL_MODEL..."
  SMALL_MODEL="llama2:7b-chat"
  
  docker exec ollama ollama pull "$SMALL_MODEL" 2>&1 | tee -a "$LOG_FILE" || {
    log_warning "Model pull failed, continuing with tests..."
  }
  
  # Measure first-token latency
  log_info "Measuring first-token latency..."
  START=$(date +%s%N)
  docker exec ollama ollama run "$SMALL_MODEL" "Say 'hello'" < /dev/null 2>&1 | tail -5 | tee -a "$LOG_FILE"
  END=$(date +%s%N)
  LATENCY=$(( (END - START) / 1000000 ))
  
  if [[ $LATENCY -lt 500 ]]; then
    log_success "First-token latency: ${LATENCY}ms (target: <500ms)"
  else
    log_warning "First-token latency: ${LATENCY}ms (target: <500ms)"
  fi
  
  # Monitor GPU utilization
  log_info "GPU Performance Summary:"
  nvidia-smi --query-gpu=name,utilization.gpu,utilization.memory,memory.used,temperature.gpu,power.draw \
    --format=csv,noheader
}

# Phase 4: Troubleshooting
troubleshoot_gpu_issues() {
  log_info "=== GPU Troubleshooting ==="
  
  log_info "Collecting diagnostic information..."
  
  # GPU diagnostics
  log_info "GPU Hardware Status:"
  lspci -v -s $(lspci | grep -i nvidia | cut -d: -f1 | head -1) 2>/dev/null | head -10 | tee -a "$LOG_FILE"
  
  # Driver diagnostics
  log_info "Driver and Kernel Module Status:"
  lsmod | grep nvidia | tee -a "$LOG_FILE"
  
  # CUDA diagnostics
  log_info "CUDA Installation Status:"
  ls -la /usr/local/cuda/lib64/libcuda* 2>/dev/null | tee -a "$LOG_FILE" || echo "CUDA libraries not found" | tee -a "$LOG_FILE"
  
  # Docker diagnostics
  log_info "Docker GPU Runtime Status:"
  docker info | grep -i nvidia | tee -a "$LOG_FILE" || echo "nvidia runtime not in docker info" | tee -a "$LOG_FILE"
  
  # System logs
  log_info "Recent System Logs (NVIDIA):"
  dmesg | grep -i nvidia | tail -10 | tee -a "$LOG_FILE"
  
  # Detailed GPU info
  log_info "Detailed GPU Information:"
  nvidia-smi -q 2>/dev/null | head -50 | tee -a "$LOG_FILE"
}

# Phase 5: Advanced monitoring setup
setup_monitoring() {
  log_info "=== Setting up GPU Monitoring ==="
  
  log_info "Creating monitoring script..."
  
  MONITOR_SCRIPT="${SCRIPT_DIR}/gpu-monitor-31.sh"
  cat > "$MONITOR_SCRIPT" << 'MONITOR_EOF'
#!/bin/bash
# Real-time GPU monitoring for ${DEPLOY_HOST}

INTERVAL=${1:-1}  # Default 1 second

echo "GPU Monitoring (interval: ${INTERVAL}s) - Press Ctrl+C to exit"
echo ""

while true; do
  clear
  echo "=== GPU Status $(date) ==="
  
  # GPU list
  nvidia-smi --query-gpu=index,name,driver_version,pstate \
    --format=table,noheader
  
  echo ""
  echo "=== GPU Utilization ==="
  nvidia-smi --query-gpu=index,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,clocks.current.graphics \
    --format=table,noheader
  
  echo ""
  echo "=== Processes Using GPU ==="
  nvidia-smi pmon -c 1 2>/dev/null || echo "(No processes using GPU)"
  
  sleep "$INTERVAL"
done
MONITOR_EOF
  
  chmod +x "$MONITOR_SCRIPT"
  log_success "Monitoring script created: $MONITOR_SCRIPT"
}

# Main execution
main() {
  log_info "GPU Deployment Script Started"
  log_info "Action: $ACTION, Dry-run: $DRY_RUN"
  
  case "$ACTION" in
    validate)
      validate_gpu_setup
      ;;
    deploy)
      deploy_gpu_infrastructure
      ;;
    test)
      test_gpu_performance
      ;;
    troubleshoot)
      troubleshoot_gpu_issues
      ;;
    monitor)
      setup_monitoring
      ;;
    all)
      validate_gpu_setup && log_success "Validation passed"
      log_info ""
      deploy_gpu_infrastructure && log_success "Deployment complete"
      log_info ""
      test_gpu_performance && log_success "Performance tests passed"
      log_info ""
      setup_monitoring && log_success "Monitoring enabled"
      ;;
    *)
      log_error "Unknown action: $ACTION"
      echo "Usage: $0 [validate|deploy|test|troubleshoot|monitor|all] [--dry-run]"
      return 1
      ;;
  esac
  
  log_success "GPU deployment script completed"
  log_info "Log file: $LOG_FILE"
}

# Parse dry-run flag
if [[ $2 == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Run main
main "$@"
