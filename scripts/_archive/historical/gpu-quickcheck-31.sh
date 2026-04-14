#!/bin/bash
# GPU Quick Validation Script for 192.168.168.31
# Purpose: Fast GPU validation checks
# Usage: ./gpu-quickcheck-31.sh

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test functions
test_gpu_hardware() {
  echo -e "${BLUE}→ GPU Hardware Detection${NC}"
  if lspci | grep -q nvidia; then
    GPU_COUNT=$(lspci | grep -i nvidia | wc -l)
    echo -e "${GREEN}✓ Found $GPU_COUNT NVIDIA GPU(s)${NC}"
    return 0
  else
    echo -e "${RED}✗ No NVIDIA GPUs detected${NC}"
    return 1
  fi
}

test_nvidia_smi() {
  echo -e "${BLUE}→ NVIDIA Driver (nvidia-smi)${NC}"
  if command -v nvidia-smi &> /dev/null; then
    DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    echo -e "${GREEN}✓ Driver version: $DRIVER${NC}"
    echo ""
    nvidia-smi --query-gpu=index,name,memory.total,driver_version,pstate \
      --format=table,noheader
    return 0
  else
    echo -e "${RED}✗ nvidia-smi not found${NC}"
    return 1
  fi
}

test_cuda_toolkit() {
  echo -e "${BLUE}→ CUDA Toolkit${NC}"
  if command -v nvcc &> /dev/null; then
    CUDA_VER=$(nvcc --version | grep release | sed 's/.*release //' | sed 's/,.*//')
    echo -e "${GREEN}✓ CUDA version: $CUDA_VER${NC}"

    # Check libraries
    if find /usr/local/cuda/lib64 -name "libcudart.so*" &> /dev/null; then
      echo -e "${GREEN}✓ CUDA runtime libraries found${NC}"
    else
      echo -e "${YELLOW}⚠ CUDA libraries not found${NC}"
    fi
    return 0
  else
    echo -e "${RED}✗ nvcc not found${NC}"
    return 1
  fi
}

test_cudnn() {
  echo -e "${BLUE}→ cuDNN Library${NC}"
  if find /usr/local/cuda -name "libcudnn.so*" &> /dev/null; then
    CUDNN_COUNT=$(find /usr/local/cuda -name "libcudnn.so*" | wc -l)
    echo -e "${GREEN}✓ cuDNN found ($CUDNN_COUNT libraries)${NC}"
    return 0
  else
    echo -e "${YELLOW}⚠ cuDNN not found${NC}"
    return 1
  fi
}

test_docker_gpu() {
  echo -e "${BLUE}→ Docker GPU Access${NC}"
  if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠ Docker not installed${NC}"
    return 1
  fi

  if docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓ Docker GPU access working${NC}"

    # Quick GPU test in container
    GPU_COUNT=$(docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi --list-gpus 2>/dev/null | wc -l)
    echo -e "${GREEN}✓ GPUs visible in container: $GPU_COUNT${NC}"
    return 0
  else
    echo -e "${RED}✗ Docker GPU access failed${NC}"
    return 1
  fi
}

test_ollama_gpu() {
  echo -e "${BLUE}→ Ollama GPU Access${NC}"

  if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠ Docker not installed, skipping Ollama test${NC}"
    return 1
  fi

  if docker ps --filter "name=ollama" --quiet | grep -q .; then
    if docker exec ollama nvidia-smi &> /dev/null 2>&1; then
      echo -e "${GREEN}✓ Ollama has GPU access${NC}"

      # Check if model is available
      if docker exec ollama ollama list 2>/dev/null | grep -q "llama2"; then
        echo -e "${GREEN}✓ Ollama models available${NC}"
      else
        echo -e "${YELLOW}⚠ No models loaded in Ollama${NC}"
      fi
      return 0
    else
      echo -e "${RED}✗ Ollama does not have GPU access${NC}"
      return 1
    fi
  else
    echo -e "${YELLOW}⚠ Ollama container not running${NC}"
    return 1
  fi
}

test_gpu_memory() {
  echo -e "${BLUE}→ GPU Memory Status${NC}"
  nvidia-smi --query-gpu=index,memory.total,memory.free,memory.used \
    --format=table,noheader 2>/dev/null || echo "Could not query GPU memory"
}

test_gpu_temperature() {
  echo -e "${BLUE}→ GPU Temperature${NC}"
  nvidia-smi --query-gpu=index,temperature.gpu,power.draw,power.limit \
    --format=table,noheader 2>/dev/null || echo "Could not query GPU temperature"
}

test_gpu_clocks() {
  echo -e "${BLUE}→ GPU Clock Speeds${NC}"
  nvidia-smi --query-gpu=index,clocks.current.graphics,clocks.current.memory \
    --format=table,noheader 2>/dev/null || echo "Could not query GPU clocks"
}

# Summary
print_summary() {
  echo ""
  echo -e "${BLUE}=== Quick Check Summary ===${NC}"
  echo ""

  # Count passes
  PASSED=0
  [[ $(test_gpu_hardware; echo $?) -eq 0 ]] && PASSED=$((PASSED + 1))
  [[ $(test_nvidia_smi; echo $?) -eq 0 ]] && PASSED=$((PASSED + 1))
  [[ $(test_cuda_toolkit; echo $?) -eq 0 ]] && PASSED=$((PASSED + 1))
  [[ $(test_docker_gpu; echo $?) -eq 0 ]] && PASSED=$((PASSED + 1))

  TOTAL=4
  PCT=$((PASSED * 100 / TOTAL))

  if [[ $PASSED -eq $TOTAL ]]; then
    echo -e "${GREEN}✓ All checks passed ($PASSED/$TOTAL)${NC}"
  else
    echo -e "${YELLOW}⚠ $PASSED/$TOTAL checks passed (${PCT}%)${NC}"
    echo ""
    echo "Run './gpu-deploy-31.sh troubleshoot' for detailed diagnostics"
  fi

  echo ""
  echo "Next steps:"
  echo "  1. Run './gpu-deploy-31.sh validate' for full validation"
  echo "  2. Run './gpu-monitor-31.sh' for real-time monitoring"
  echo "  3. Check GPU_TROUBLESHOOTING_GUIDE.md for common issues"
}

# Main execution
main() {
  echo -e "${BLUE}=== GPU Quick Check for 192.168.168.31 ===${NC}"
  echo ""

  test_gpu_hardware
  echo ""

  test_nvidia_smi
  echo ""

  test_cuda_toolkit
  echo ""

  test_cudnn
  echo ""

  test_gpu_memory
  echo ""

  test_gpu_temperature
  echo ""

  test_gpu_clocks
  echo ""

  test_docker_gpu
  echo ""

  test_ollama_gpu

  print_summary
}

main "$@"
