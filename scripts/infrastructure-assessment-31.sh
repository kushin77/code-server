#!/bin/bash
# Infrastructure Assessment Script for 192.168.168.31
# Purpose: Gather comprehensive host specifications, GPU config, NAS connectivity
# Usage: ssh akushnir@192.168.168.31 'bash -s' < scripts/infrastructure-assessment-31.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Infrastructure Assessment: 192.168.168.31                     ║${NC}"
echo -e "${BLUE}║   Assessment Date: $(date '+%Y-%m-%d %H:%M:%S')                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# 1. SYSTEM INFORMATION
# ============================================================================
echo -e "${YELLOW}[1. SYSTEM INFORMATION]${NC}"
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo "Current Date: $(date)"
echo "Kernel: $(uname -r)"
echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -s)"
echo ""

# ============================================================================
# 2. CPU INFORMATION
# ============================================================================
echo -e "${YELLOW}[2. CPU INFORMATION]${NC}"
if command -v lscpu &> /dev/null; then
    lscpu | grep -E "Architecture|CPU op-mode|Byte Order|CPU\(s\)|On-line|Vendor|Model name|CPU max MHz|CPU min MHz"
else
    echo "CPU: $(cat /proc/cpuinfo | grep "model name" | uniq)"
    echo "Cores: $(grep -c ^processor /proc/cpuinfo)"
fi
echo ""

# ============================================================================
# 3. MEMORY INFORMATION
# ============================================================================
echo -e "${YELLOW}[3. MEMORY INFORMATION]${NC}"
free -h
echo "Memory Details:"
grep MemTotal /proc/meminfo
grep MemAvailable /proc/meminfo
echo ""

# ============================================================================
# 4. STORAGE INFORMATION
# ============================================================================
echo -e "${YELLOW}[4. STORAGE INFORMATION]${NC}"
echo "Disk Usage (All Filesystems):"
df -h
echo ""
echo "Root Disk I/O Capabilities:"
if command -v lsblk &> /dev/null; then
    lsblk -d -o NAME,SIZE,TYPE,ROTA,SCHED 2>/dev/null | head -10
fi
echo ""

# ============================================================================
# 5. GPU INFORMATION
# ============================================================================
echo -e "${YELLOW}[5. GPU INFORMATION]${NC}"
if command -v nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓ NVIDIA GPU Detected${NC}"
    echo "Driver and CUDA Version:"
    nvidia-smi --query-gpu=driver_version,compute_cap --format=csv,noheader | head -1
    echo ""
    
    echo "GPU Details:"
    nvidia-smi --query-gpu=index,name,memory.total,memory.free,temperature.gpu,power.draw,power.limit --format=csv
    echo ""
    
    echo "GPU Compute Capabilities:"
    nvidia-smi --query-gpu=compute_cap --format=csv,noheader | sort -u
    echo ""
    
    echo "CUDA Version (from nvcc):"
    if command -v nvcc &> /dev/null; then
        nvcc --version | grep release
    else
        echo "Warning: nvcc not found in PATH"
    fi
    echo ""
else
    echo -e "${RED}✗ No NVIDIA GPU detected${NC}"
    echo "Run: 'nvidia-smi' for more details"
    echo ""
fi

# ============================================================================
# 6. CUDA & cuDNN
# ============================================================================
echo -e "${YELLOW}[6. CUDA & cuDNN LIBRARIES]${NC}"
if [ -d "/usr/local/cuda" ]; then
    echo "CUDA Installation: /usr/local/cuda"
    ls -la /usr/local/cuda/lib64/libcuda* 2>/dev/null | head -3
else
    echo "Warning: /usr/local/cuda not found"
fi
echo ""

echo "cuDNN Libraries:"
if find /usr/local/cuda -name "libcudnn*" 2>/dev/null; then
    echo "Status: Found"
else
    find /usr -name "libcudnn*" 2>/dev/null || echo "Warning: cuDNN not found"
fi
echo ""

# ============================================================================
# 7. DOCKER & NVIDIA CONTAINER RUNTIME
# ============================================================================
echo -e "${YELLOW}[7. DOCKER & CONTAINER RUNTIME]${NC}"
if command -v docker &> /dev/null; then
    echo -e "${GREEN}✓ Docker Installed${NC}"
    docker --version
    echo ""
    
    echo "Docker Daemon Status:"
    systemctl is-active docker 2>/dev/null || docker info > /dev/null 2>&1 && echo "✓ Docker daemon running" || echo "✗ Docker daemon not running"
    echo ""
    
    # Check if NVIDIA Container Runtime is available
    echo "NVIDIA Container Runtime:"
    if docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi &>/dev/null 2>&1; then
        echo "✓ NVIDIA Container Runtime: Available and working"
        docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi 2>/dev/null | head -10
    else
        echo "Warning: NVIDIA Container Runtime may not be configured"
        echo "Testing with standard runtime..."
        docker run --rm nvidia/cuda:12.4-base nvidia-smi 2>&1 | head -3 || echo "GPU access via Docker may require nvidia-container-runtime"
    fi
else
    echo -e "${RED}✗ Docker not installed${NC}"
fi
echo ""

# ============================================================================
# 8. DOCKER COMPOSE
# ============================================================================
echo -e "${YELLOW}[8. DOCKER COMPOSE]${NC}"
if command -v docker-compose &> /dev/null; then
    docker-compose --version
elif command -v docker &> /dev/null && docker compose version &>/dev/null 2>&1; then
    echo "Docker Compose (standalone):"
    docker compose version
else
    echo -e "${RED}✗ Docker Compose not found${NC}"
fi
echo ""

# ============================================================================
# 9. NETWORK CONFIGURATION
# ============================================================================
echo -e "${YELLOW}[9. NETWORK CONFIGURATION]${NC}"
echo "Network Interfaces:"
if command -v ip &> /dev/null; then
    ip addr show | grep -E "^\d|inet"
else
    ifconfig 2>/dev/null || echo "Unable to display network configuration"
fi
echo ""

echo "DNS Configuration:"
cat /etc/resolv.conf 2>/dev/null | grep -E "^nameserver|^search" || echo "DNS configuration not accessible"
echo ""

echo "Routing Table (default routes):"
if command -v ip &> /dev/null; then
    ip route show | grep default
else
    route -n | grep 0.0.0.0 2>/dev/null || echo "Unable to display routing"
fi
echo ""

# ============================================================================
# 10. NAS MOUNT POINTS
# ============================================================================
echo -e "${YELLOW}[10. NAS MOUNT POINTS]${NC}"
echo "Current Mounts:"
mount | grep -E "/mnt/nas|nfs|iscsi" || echo "No NAS mounts found"
echo ""

echo "Mount Points Status:"
for mount_point in /mnt/nas /mnt/nas-primary /mnt/nas-backup /mnt/nas-models; do
    if [ -d "$mount_point" ]; then
        read -r -d '' capacity_info <<EOF || true
$(df -h "$mount_point" 2>/dev/null | tail -1)
EOF
        echo "$mount_point: $capacity_info"
    fi
done
echo ""

# ============================================================================
# 11. NAS CONNECTIVITY & PERFORMANCE
# ============================================================================
echo -e "${YELLOW}[11. NAS CONNECTIVITY TESTS]${NC}"
if [ -d "/mnt/nas-primary" ] && [ -w "/mnt/nas-primary" ]; then
    echo "NAS Write Test (100MB):"
    test_file="/mnt/nas-primary/.connectivity-test-$(date +%s)"
    if dd if=/dev/zero of="$test_file" bs=1M count=100 2>&1 | tail -2; then
        rm -f "$test_file"
        echo "✓ NAS write test passed"
    else
        echo "✗ NAS write test failed"
    fi
    echo ""
    
    echo "NAS Latency Baseline (1GB sequential read):"
    test_read="/mnt/nas-primary/.latency-test-$(date +%s)"
    if dd if=/dev/zero of="$test_read" bs=1M count=1000 2>&1 | head -1; then
        time dd if="$test_read" of=/dev/null bs=1M 2>&1 | tail -3
        rm -f "$test_read"
    fi
else
    echo "NAS mounts not accessible or writable"
    echo "Mount status: $(mount | grep /mnt/nas || echo 'Not mounted')"
fi
echo ""

# ============================================================================
# 12. INTERNET CONNECTIVITY
# ============================================================================
echo -e "${YELLOW}[12. INTERNET CONNECTIVITY]${NC}"
echo "DNS Resolution Test (google.com):"
nslookup google.com 2>/dev/null | grep -A1 "Name:" | head -2 || echo "DNS resolution failed"
echo ""

echo "GitHub API Access:"
if command -v curl &> /dev/null; then
    if curl -s -I https://api.github.com --connect-timeout 5 | head -1; then
        echo "✓ HTTPS connectivity working"
    else
        echo "✗ HTTPS connectivity issue"
    fi
else
    echo "Skip: curl not available"
fi
echo ""

# ============================================================================
# 13. SYSTEMD & SERVICE MANAGEMENT
# ============================================================================
echo -e "${YELLOW}[13. SYSTEMD & SERVICE MANAGEMENT]${NC}"
if command -v systemctl &> /dev/null; then
    echo "Systemd Version: $(systemctl --version | head -1)"
    echo "Enabled Systemd Services:"
    systemctl list-unit-files --state=enabled 2>/dev/null | grep -E "docker|nvidia|nfs|iscsi" | head -5 || echo "No relevant services found"
else
    echo "Warning: systemctl not available (systemd may not be the init system)"
fi
echo ""

# ============================================================================
# 14. SSH CONFIGURATION
# ============================================================================
echo -e "${YELLOW}[14. SSH CONFIGURATION]${NC}"
echo "SSH Service Status:"
if systemctl is-active ssh &>/dev/null 2>&1; then
    echo "✓ SSH service is active"
elif systemctl is-active sshd &>/dev/null 2>&1; then
    echo "✓ SSHD service is active"
else
    echo "⚠ SSH service status unknown"
fi
echo ""

echo "SSH Configuration (Key Settings):"
sudo grep -E "^PermitRootLogin|^PasswordAuthentication|^PubkeyAuthentication|^Port" /etc/ssh/sshd_config 2>/dev/null || echo "SSH sshd_config not accessible"
echo ""

# ============================================================================
# 15. FILESYSTEM & PERMISSIONS
# ============================================================================
echo -e "${YELLOW}[15. FILESYSTEM & PERMISSIONS]${NC}"
echo "Current User: $(whoami)"
echo "Home Directory: $HOME"
echo "Current User ID: $(id -u)"
echo ""

echo "SSH Key Permissions:"
if [ -d "$HOME/.ssh" ]; then
    ls -la "$HOME/.ssh/" | head -5
else
    echo "SSH directory not configured"
fi
echo ""

echo "Docker Group Membership:"
if id -nG | grep -qw docker; then
    echo "✓ Current user is in docker group"
else
    echo "⚠ Current user NOT in docker group (sudo required for docker commands)"
fi
echo ""

# ============================================================================
# 16. RESOURCE LIMITS & ULIMIT
# ============================================================================
echo -e "${YELLOW}[16. RESOURCE LIMITS]${NC}"
echo "File Descriptor Limits:"
ulimit -n
echo ""

echo "Max Processes:"
ulimit -u
echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    ASSESSMENT COMPLETE                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next Steps:"
echo "1. Export assessment output to file:"
echo "   ssh akushnir@192.168.168.31 'bash -s' < scripts/infrastructure-assessment-31.sh > docs/assessment-31-results.txt"
echo ""
echo "2. Review results and update docs/192.168.168.31-host-spec.md"
echo ""
echo "3. Proceed to #140: IaC Development (Terraform modules)"
echo ""
