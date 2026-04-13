#!/bin/bash
###############################################################################
# POST-REBOOT VALIDATION SCRIPT FOR HOST 192.168.168.31
#
# Run this AFTER rebooting the host to verify all fixes are working
#
# Usage:
#   scp validate-host-31.sh akushnir@192.168.168.31:/tmp/
#   ssh akushnir@192.168.168.31 "bash /tmp/validate-host-31.sh"
#
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

box() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ $1"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

### MAIN VALIDATION ###

box "POST-REBOOT VALIDATION - HOST 192.168.168.31"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

### 1. SYSTEM STABILITY ###

box "1. SYSTEM STABILITY CHECKS"

# Uptime
if [ -f /proc/uptime ]; then
    UPTIME=$(awk '{print int($1/60)}' /proc/uptime)
    if [ $UPTIME -ge 1 ]; then
        success "System has been stable for $UPTIME minutes"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        warn "System reboot very recent (< 1 minute)"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
fi

# Systemd health
if systemctl is-system-running | grep -q "running\|degraded"; then
    success "Systemd status: $(systemctl is-system-running)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    fail "Systemd has issues"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Failed services
if systemctl list-units --type=service --state=failed --no-pager | grep -q "loaded"; then
    FAILED=$(systemctl list-units --type=service --state=failed --format="{{unit}}" --no-pager | wc -l)
    fail "$FAILED failed systemd services detected"
    systemctl list-units --type=service --state=failed --no-pager
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    success "No failed systemd services"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

### 2. DOCKER HEALTH ###

box "2. DOCKER DAEMON HEALTH"

# Daemon running
if systemctl is-active --quiet docker; then
    success "Docker daemon is running"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    fail "Docker daemon not running"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "Status:"
    systemctl status docker
    exit 1
fi

# Version check
DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
if docker info > /dev/null 2>&1; then
    success "Docker client/server responding (version: $DOCKER_VERSION)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    fail "Docker daemon not responding"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    docker info
    exit 1
fi

# Images available
IMAGE_COUNT=$(docker images --format "{{.Repository}}" | wc -l)
if [ $IMAGE_COUNT -gt 0 ]; then
    success "Docker images available: $IMAGE_COUNT cached"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    warn "No Docker images cached (OK for fresh deploy)"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

### 3. NVIDIA GPU CHECKS ###

box "3. NVIDIA GPU HARDWARE & DRIVERS"

# nvidia-smi available
if ! command -v nvidia-smi &> /dev/null; then
    fail "nvidia-smi command not found"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    success "nvidia-smi utility available"
    PASS_COUNT=$((PASS_COUNT + 1))
    
    # Driver version
    DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    if [[ $DRIVER == 555.* ]] || [[ $DRIVER == 56[0-9].* ]]; then
        success "NVIDIA driver: $DRIVER (modern, ✓)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        warn "NVIDIA driver: $DRIVER (older version, working but consider upgrading)"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
    
    # CUDA version (from driver)
    CUDA=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1)
    if [ ! -z "$CUDA" ]; then
        success "GPU compute capability: $CUDA"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
    
    # GPU count and health
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
    success "GPU count: $GPU_COUNT"
    PASS_COUNT=$((PASS_COUNT + 1))
    
    # GPU status table
    echo ""
    echo "GPU Status Details:"
    nvidia-smi --query-gpu=index,name,memory.total,memory.free,temperature.gpu,power.draw --format=csv
    echo ""
fi

### 4. CUDA TOOLKIT ###

box "4. CUDA TOOLKIT INSTALLATION"

if command -v nvcc &> /dev/null; then
    CUDA_VER=$(nvcc --version | grep release | awk '{print $5}' | tr -d ',')
    if [[ $CUDA_VER == 12.4* ]]; then
        success "CUDA 12.4 compiler available: $CUDA_VER"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        warn "CUDA installed but version is $CUDA_VER (expected 12.4)"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
    
    # CUDA paths
    if [ -d /usr/local/cuda-12.4 ]; then
        success "CUDA toolkit directory: /usr/local/cuda-12.4"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
else
    fail "CUDA nvcc compiler not found in PATH"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "Trying to source bashrc..."
    source ~/.bashrc
    if command -v nvcc &> /dev/null; then
        warn "nvcc found after sourcing bashrc - add to current shell: export PATH=/usr/local/cuda-12.4/bin:\$PATH"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
fi

### 5. NVIDIA CONTAINER RUNTIME ###

box "5. NVIDIA CONTAINER RUNTIME"

if command -v nvidia-container-runtime &> /dev/null; then
    NV_RUNTIME=$(nvidia-container-runtime --version 2>&1 | head -1)
    success "NVIDIA container runtime installed: $NV_RUNTIME"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    fail "nvidia-container-runtime not found"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check Docker runtime config
if grep -q "nvidia" /etc/docker/daemon.json 2>/dev/null; then
    if grep -q "default-runtime" /etc/docker/daemon.json; then
        success "nvidia configured as Docker default runtime"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        warn "nvidia runtime available but not set as default"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
else
    warn "nvidia runtime not in docker daemon.json (OK but --runtime=nvidia flag required)"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

### 6.GPU IN DOCKER TEST ###

box "6. GPU INSIDE DOCKER CONTAINER TEST"

# Pull test image if needed
log "Testing GPU access inside Docker container..."
log "(This will pull nvidia/cuda:12.4-base if not cached, may take 1-2 minutes)"

if docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi > /tmp/docker-gpu-test.txt 2>&1; then
    GPU_COUNT_DOCKER=$(grep "GPU  Name" /tmp/docker-gpu-test.txt | wc -l)
    success "GPU accessible in Docker container: $GPU_COUNT_DOCKER device(s)"
    PASS_COUNT=$((PASS_COUNT + 1))
    
    # Show GPU output
    echo ""
    echo "GPU output inside container:"
    cat /tmp/docker-gpu-test.txt | head -20
    echo ""
else
    # Try without explicit runtime (might be default now)
    if docker run --rm nvidia/cuda:12.4-base nvidia-smi > /tmp/docker-gpu-test.txt 2>&1; then
        success "GPU accessible in Docker container (using default runtime)"
        PASS_COUNT=$((PASS_COUNT + 1))
        cat /tmp/docker-gpu-test.txt | head -15
    else
        fail "GPU not accessible inside Docker containers"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "Error output:"
        cat /tmp/docker-gpu-test.txt
    fi
fi
echo ""

### 7. NAS STORAGE ###

box "7. NAS STORAGE HEALTH"

# Check mount
if mount | grep -q "/mnt/nas-export"; then
    success "NAS mount /mnt/nas-export is active"
    PASS_COUNT=$((PASS_COUNT + 1))
    
    # Check capacity
    NAS_AVAIL=$(df /mnt/nas-export | tail -1 | awk '{print $4}')
    NAS_USE=$(df /mnt/nas-export | tail -1 | awk '{print $5}' | tr -d '%')
    if [ $NAS_USE -lt 80 ]; then
        success "NAS usage: ${NAS_USE}% (healthy, ${NAS_AVAIL}KB available)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        warn "NAS approaching capacity: ${NAS_USE}% used"
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
    
    # Test write
    if touch /mnt/nas-export/.test-$$ 2>/dev/null && rm -f /mnt/nas-export/.test-$$ 2>/dev/null; then
        success "NAS write capability verified"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        fail "NAS write test failed (read-only or permission issue)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    fail "NAS not mounted at /mnt/nas-export"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

### 8. RESOURCE AVAILABILITY ###

box "8. SYSTEM RESOURCES"

# Memory
MEM_AVAIL=$(free -h | grep "^Mem:" | awk '{print $7}')
success "Memory available: $MEM_AVAIL"
PASS_COUNT=$((PASS_COUNT + 1))

# Disk
DISK_AVAIL=$(df / | tail -1 | awk '{print $4}')
DISK_USE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [ $DISK_USE -lt 80 ]; then
    success "Root disk space: ${DISK_USE}% used (${DISK_AVAIL}B available)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    warn "Root disk usage high: ${DISK_USE}%"
    WARN_COUNT=$((WARN_COUNT + 1))
fi

# Load average
LOAD=$(uptime | awk -F'load average:' '{print $2}')
success "Load average: $LOAD"
PASS_COUNT=$((PASS_COUNT + 1))

### FINAL SUMMARY ###

box "VALIDATION SUMMARY"

echo "Passed:  ${GREEN}$PASS_COUNT${NC}"
echo "Failed:  ${RED}$FAIL_COUNT${NC}"
echo "Warned:  ${YELLOW}$WARN_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ ALL CRITICAL CHECKS PASSED${NC}"
    echo ""
    echo "The host is ready for code-server deployment!"
    echo ""
    echo "Next steps from local machine:"
    echo "  1. Run Terraform to deploy infrastructure"
    echo "  2. Deploy docker-compose stack"
    echo "  3. Run smoke tests"
    echo ""
    exit 0
else
    echo -e "${RED}✗ CRITICAL ISSUES DETECTED${NC}"
    echo ""
    echo "Issues to resolve:"
    echo "  • See failures above"
    echo "  • Manual intervention may be required"
    echo ""
    exit 1
fi
