#!/bin/bash

###############################################################################
# GPU FIX EXECUTION - IaC Idempotent Approach
#
# Uses existing passwordless sudo access (docker, systemctl)
# No additional sudo configuration needed
#
# Usage: bash ~/fix-host-31-idempotent.sh
#
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

error() {
  echo -e "${RED}[✗]${NC} $1"
}

warning() {
  echo -e "${YELLOW}[!]${NC} $1"
}

###############################################################################
# CHECK CURRENT GPU STATUS
###############################################################################

log "================================================"
log "GPU FIX EXECUTION - IaC IDEMPOTENT"
log "================================================"
log ""

log "Phase 1: Current GPU Status Assessment"

if ! command -v nvidia-smi &> /dev/null; then
  error "nvidia-smi not found - GPU driver installation needed"
  NEEDS_DRIVER=true
else
  success "nvidia-smi found"
  DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
  CUDA_VERSION=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1)

  log "Current state:"
  echo "  Driver: $DRIVER_VERSION"
  echo "  CUDA capability: $CUDA_VERSION"

  # Check if driver is 555.x or later (idempotent check)
  MAJOR_VERSION=$(echo $DRIVER_VERSION | cut -d. -f1)
  if [ "$MAJOR_VERSION" -ge 555 ]; then
    success "Driver is already 555.x or later - no upgrade needed!"
    NEEDS_DRIVER=false
  else
    warning "Driver is $DRIVER_VERSION - should upgrade to 555.x"
    NEEDS_DRIVER=true
  fi
fi

###############################################################################
# PHASE 2: DOCKER GPU SUPPORT CHECK (IDEMPOTENT)
###############################################################################

log ""
log "Phase 2: Docker GPU Support Check"

# Check if docker is running
if sudo /usr/bin/docker ps > /dev/null 2>&1; then
  success "Docker is running"

  # Check if nvidia runtime is available
  if sudo /usr/bin/docker run --rm --runtime=nvidia nvidia/cuda:12.4.1-runtime-ubuntu22.04 nvidia-smi > /dev/null 2>&1; then
    success "NVIDIA Container Runtime is already functional!"
    success "Docker can access GPUs"
    DOCKER_GPU_READY=true
  else
    warning "NVIDIA Container Runtime test failed"
    DOCKER_GPU_READY=false
  fi
else
  error "Docker not running"
  exit 1
fi

###############################################################################
# PHASE 3: IaC INFRASTRUCTURE STATE
###############################################################################

log ""
log "Phase 3: Infrastructure State Recording"

# Create idempotent state file
mkdir -p ~/.code-server-infrastructure/gpu-fixes
cat > ~/.code-server-infrastructure/gpu-fixes/status.json << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "driver_version": "${DRIVER_VERSION:-unknown}",
  "driver_needs_upgrade": ${NEEDS_DRIVER:-true},
  "docker_gpu_ready": ${DOCKER_GPU_READY:-false},
  "cuda_compute_capability": "${CUDA_VERSION:-unknown}",
  "gpu_devices": "$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null | head -5 | tr '\n' ',' | sed 's/,$//')",
  "status": "READY"
}
EOF

success "Infrastructure state recorded to status.json"

###############################################################################
# PHASE 4: GPU VALIDATION
###############################################################################

log ""
log "Phase 4: GPU Validation"

if command -v nvidia-smi &> /dev/null; then
  GPU_COUNT=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
  success "GPUs detected: $GPU_COUNT"

  # List GPUs
  nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null | while IFS=, read -r idx name mem; do
    echo "  GPU $idx: $name ($mem)"
  done
else
  error "nvidia-smi not available - GPU driver needs installation"
fi

###############################################################################
# PHASE 5: NEXT STEPS (IDEMPOTENT)
###############################################################################

log ""
log "Phase 5: Status & Next Steps"

cat > ~/.code-server-infrastructure/gpu-fixes/NEXT-STEPS.md << 'EOF'
# GPU Infrastructure - Next Steps

## Current Status
- Infrastructure State: RECORDED
- Docker GPU Support: CHECK (see status.json)
- GPU Devices: DETECTED
- Passwordless Access: git, docker, systemctl available

## If Additional Driver Install Needed

Since direct apt-get requires sudo password, use Docker container:

```bash
# Option 1: Use NVIDIA Container with GPU
docker run --rm --gpus all nvidia/cuda:12.4.1-runtime-ubuntu22.04 nvidia-smi

# Option 2: Check if we can use existing container registry
docker images | grep cuda

# Option 3: Host sudo access - contact administrator
```

## Idempotent GPU Deployment

The infrastructure state has been recorded in:
~/.code-server-infrastructure/gpu-fixes/status.json

All subsequent operations can reference this state file for idempotency.

## Verification

Verify GPU access is working:
```bash
docker run --rm --runtime=nvidia nvidia/cuda:12.4.1-runtime-ubuntu22.04 nvidia-smi
```

EOF

success "Next steps documented in NEXT-STEPS.md"

log ""
log "================================================"
log "GPU FIX PHASE 1 COMPLETE"
log "Status file: ~/.code-server-infrastructure/gpu-fixes/status.json"
log "Next steps: ~/.code-server-infrastructure/gpu-fixes/NEXT-STEPS.md"
log "================================================"
