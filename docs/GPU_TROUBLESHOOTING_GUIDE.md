# GPU Configuration Troubleshooting Guide for 192.168.168.31

**Purpose**: Comprehensive guide for NVIDIA GPU setup, validation, and troubleshooting  
**Status**: Reference document for #141 GPU Configuration  
**Target Systems**: NVIDIA A100, H100, RTX series GPUs on Ubuntu/RHEL

---

## Quick Diagnosis (Run These First)

```bash
# 1. Check if GPU hardware is visible to host OS
lspci | grep -i nvidia

# 2. Check if drivers are loaded
nvidia-smi

# 3. Check CUDA installation
nvcc --version

# 4. Check cuDNN installation
find /usr/local/cuda -name "libcudnn*" | head -3

# 5. Check Docker GPU access
docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi

# 6. Check Ollama GPU setup
docker exec ollama sh -c "ollama list && ollama show llama2:70b-chat" 2>/dev/null || echo "Ollama container not running"
```

---

## Issue 1: GPU Not Visible (nvidia-smi fails or has no output)

### Symptoms
```
Command 'nvidia-smi' not found
or
NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver
```

### Root Causes & Solutions

**A. NVIDIA Drivers Not Installed**
```bash
# Check driver installation
dpkg -l | grep nvidia

# Install drivers (Ubuntu 22.04)
sudo apt update
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall

# Or manually install specific version
sudo apt install -y nvidia-driver-550

# Reboot to load kernel modules
sudo reboot

# Verify
nvidia-smi
```

**B. Kernel Module Not Loaded**
```bash
# Check if nvidia kernel module is loaded
lsmod | grep nvidia

# Load manually if not present
sudo modprobe nvidia
sudo modprobe nvidia_uvm

# Make it permanent
echo "nvidia" | sudo tee /etc/modules-load.d/nvidia.conf
echo "nvidia_uvm" | sudo tee -a /etc/modules-load.d/nvidia.conf

# Verify
lsmod | grep nvidia
```

**C. NVIDIA Driver Version Conflict with GPU**
```bash
# Check GPU compute capability
lspci -v -s $(lspci | grep NVIDIA | cut -d: -f1) | grep "Prog-if"

# Check minimum driver version required
# RTX cards: 450+
# A100: 450+
# H100: 550+

# Update if needed
sudo apt remove -y nvidia-driver-*
sudo apt install -y nvidia-driver-550
sudo reboot
```

**D. NVIDIA Container Toolkit Not Configured**
```bash
# Check if nvidia-container-runtime is installed
which nvidia-container-runtime

# If not found, install
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt update && sudo apt install -y nvidia-container-toolkit

# Configure Docker daemon
sudo nvidia-ctk runtime configure --runtime=nvidia

# Restart Docker
sudo systemctl restart docker

# Verify Docker GPU access
docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi
```

---

## Issue 2: CUDA 12.4 Installation Failing

### Symptoms
```
CUDA libraries not found: libcublas.so, libcudart.so
nvcc --version: command not found
/usr/local/cuda/lib64: No such file or directory
```

### Root Causes & Solutions

**A. Downloaded Incorrect CUDA Version**
```bash
# Check what GPU compute capability you have
nvidia-smi --query-gpu=compute_cap --format=csv,noheader

# Compute capability to CUDA version mapping:
# 7.0-7.5 (V100, T4): CUDA 11.8+
# 8.0-8.6 (A100, RTX30): CUDA 11.0+
# 8.7-8.9 (H100, RTX40): CUDA 12.0+

# For A100: CUDA 12.4 is optimal
# Verify you're downloading the right version
```

**B. CUDA Installation via Package Manager Failed**
```bash
# Ubuntu/Debian method
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
wget -O /tmp/cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i /tmp/cuda-keyring.deb
sudo apt-get update
sudo apt-get install -y cuda-toolkit-12-4

# If package not found, manually install via runfile
wget https://developer.nvidia.com/compute/cuda/12.4.0/local_installers/cuda_12.4.0_550.54.14_linux.run
sudo bash cuda_12.4.0_550.54.14_linux.run

# Add to PATH
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc

# Verify
nvcc --version
```

**C. Previous CUDA Installation Conflicts**
```bash
# Check for multiple CUDA installations
sudo find / -name "nvcc" 2>/dev/null

# If multiple found, remove old ones
sudo rm -rf /usr/local/cuda-11.*

# Keep only latest
ls -la /usr/local/ | grep cuda

# Rebuild cache
sudo ldconfig

# Verify
nvcc --version
```

---

## Issue 3: cuDNN Library Not Found or Incompatible

### Symptoms
```
error while loading shared libraries: libcudnn.so.9
error: incompatible architecture for linking
libcudnn.so.8: version GLIBCXX not found
```

### Root Causes & Solutions

**A. cuDNN Not Installed**
```bash
# Check current installation
ls -la /usr/local/cuda/lib64/libcudnn*

# If not found, cuDNN requires manual download (NVIDIA account login required)
# 1. Go to: https://developer.nvidia.com/cudnn
# 2. Sign in with NVIDIA developer account
# 3. Download cuDNN for CUDA 12.x
# 4. Extract and install:

tar -xvf cudnn-linux-x86_64-9.0.0.tar.xz
sudo cp cudnn-linux-*/include/cudnn*.h /usr/local/cuda/include/
sudo cp cudnn-linux-*/lib64/libcudnn* /usr/local/cuda/lib64/
sudo chmod a+r /usr/local/cuda/include/cudnn*.h
sudo chmod a+r /usr/local/cuda/lib64/libcudnn*

# Rebuild library cache
sudo ldconfig

# Verify
ldconfig -p | grep libcudnn
```

**B. cuDNN Version Mismatch**
```bash
# Check cuDNN version
cat /usr/local/cuda/include/cudnn_version.h | grep CUDNN_MAJOR

# CUDA 12.4 requires cuDNN 9.0 or later
# If you have cuDNN 8.x, upgrade:
# Download and extract latest cuDNN 9.x as above

# Verify compatibility
ls -la /usr/local/cuda/lib64/libcudnn.so* | head -3
```

**C. Architecture Mismatch (32-bit vs 64-bit)**
```bash
# Check your system architecture
getconf LONG_BIT

# cuDNN libraries should match your architecture
file /usr/local/cuda/lib64/libcudnn.so.9

# Should output: ELF 64-bit LSB shared object (for 64-bit systems)
# If mismatch, download correct version for your architecture
```

**D. GCC/glibc Compatibility Issues**
```bash
# Check GCC and glibc versions
gcc --version
ldd --version

# cuDNN 9.x requires:
# GCC 5.3+
# glibc 2.17+

# Update if needed
sudo apt update && sudo apt install -y build-essential

# Verify
gcc --version
```

---

## Issue 4: Docker GPU Access Not Working

### Symptoms
```
docker run --runtime=nvidia fails
Error response from daemon: OCI runtime create failed
could not find nvidia-container-runtime executable
runtime: nvidia: runtime executable not found
```

### Root Causes & Solutions

**A. nvidia-container-runtime Not Installed**
```bash
# Install nvidia-container-toolkit
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Verify installation
nvidia-container-runtime --version
```

**B. Docker Daemon Not Configured for nvidia Runtime**
```bash
# Check /etc/docker/daemon.json
cat /etc/docker/daemon.json

# If nvidia runtime missing, add it
sudo nvidia-ctk runtime configure --runtime=nvidia

# Or manually edit:
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
EOF

# Restart Docker
sudo systemctl restart docker

# Verify
docker info | grep nvidia
```

**C. User Not in Docker Group**
```bash
# Add current user to docker group
sudo usermod -aG docker $USER

# Apply group changes (requires logout/login or)
newgrp docker

# Verify
docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi

# If still fails, check permissions
ls -la /var/run/docker.sock
```

**D. nvidia-container-runtime Path Incorrect**
```bash
# Find nvidia-container-runtime path
which nvidia-container-runtime

# Update daemon.json with correct path
# Usually: /usr/bin/nvidia-container-runtime (post-toolkit install)
# Or: /usr/local/nvidia/bin/nvidia-container-runtime (if manual install)

# Verify with find
sudo find / -name "nvidia-container-runtime" -type f 2>/dev/null
```

---

## Issue 5: Ollama Container GPU Access Failing

### Symptoms
```
OLLAMA_NUM_GPU=2 but GPU not used
Ollama running on CPU only (slow inference)
ollama: error: dial unix /var/run/ollama.sock: connect: permission denied
```

### Root Causes & Solutions

**A. Environment Variable Not Set Correctly**
```bash
# Check how container is running
docker inspect ollama | grep -A 10 "Env"

# If OLLAMA_NUM_GPU not in environment, add to docker-compose.yml:
environment:
  - OLLAMA_NUM_GPU=2
  - OLLAMA_KEEP_ALIVE=24h

# Restart container
docker-compose down && docker-compose up -d

# Verify GPU allocation
docker exec ollama env | grep OLLAMA_NUM_GPU
```

**B. Docker Compose Not Using nvidia Runtime**
```bash
# Check docker-compose.yml
cat docker-compose.yml | grep -A 5 "ollama:"

# Add to ollama service:
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 2
          capabilities: [gpu]

# Or use old syntax (docker-compose v1):
runtime: nvidia

# Restart
docker-compose down && docker-compose up -d

# Verify GPU is visible inside container
docker exec ollama nvidia-smi
```

**C. GPU Memory Insufficient for Model**
```bash
# Check GPU memory
nvidia-smi --query-gpu=memory.total --format=csv,noheader

# Common model memory requirements:
# llama2:7b = 4GB
# llama2:13b = 8GB
# llama2:70b = 40GB
# codegemma:7b = 4GB

# If insufficient GPU memory:
# Option 1: Use smaller model
ollama pull llama2:7b-chat

# Option 2: Use CPU offload (slower)
OLLAMA_NUM_GPU=0
OLLAMA_MODEL=llama2:70b-chat ollama serve

# Option 3: Enable memory optimizations
OLLAMA_MEMORY_FRACTION=0.8
```

**D. Ollama Socket Permission Denied**
```bash
# Check socket permissions
ls -la /tmp/ollama.sock

# If permission denied, fix ownership
docker exec ollama chown 1000:1000 /var/run/ollama.sock

# Or restart ollama container with proper user
docker-compose down
docker-compose up -d

# Verify
docker exec ollama ollama list
```

---

## Issue 6: GPU Overheating or Power Issues

### Symptoms
```
GPU temperature > 80°C
Power management warnings
GPU clock throttling (reduced performance)
"GPU 0 is overheating"
```

### Root Causes & Solutions

**A. Inadequate Cooling/Ventilation**
```bash
# Check GPU temperature
nvidia-smi --query-gpu=temperature.gpu,power.draw,power.limit --format=csv

# Temperature targets:
# <70°C: Safe (optimal)
# 70-80°C: Acceptable (monitor)
# >80°C: Critical (reduce load or improve cooling)

# Improve cooling:
# 1. Ensure proper airflow in server/case
# 2. Clean dust filters
# 3. Check thermal paste (if accessible)
# 4. Use high-performance cooling solution
```

**B. Power Supply Insufficient**
```bash
# Check power draw vs limit
nvidia-smi --query-gpu=power.draw,power.limit --format=csv

# If power.draw approaches power.limit:
# 1. Upgrade PSU (if system-level issue)
# 2. Reduce model batch size in Ollama
# 3. Disable boost clocks
# 4. Spread load across time (queue inference jobs)

# Check host PSU capacity
cat /proc/cpuinfo | grep "power"  # May not show PSU
# Manual: Check PSU label or power meter
```

**C. Throttling Due to Power/Thermal Limits**
```bash
# Check for throttling
nvidia-smi -q -d CLOCK,MAX_POWER,THROTTLE

# If "Thermal Slowdown" or "Power Limit" is active:
# 1. Improve cooling (above)
# 2. Upgrade kernel driver (thermal management improvements)
# 3. If possible, disable power limit (not recommended for extended periods)

# Disable power limit temporarily (research first!)
nvidia-smi -pm 0  # Disables persistence mode
nvidia-smi -plr 450  # Resets power limit
```

---

## Issue 7: Performance Degradation or Slowness

### Symptoms
```
First-token latency >500ms (target <500ms)
Token generation <50 tokens/sec (target >50)
High CPU usage despite GPU
Inconsistent performance
```

### Root Causes & Solutions

**A. GPU Memory Not Actually Being Used**
```bash
# Check GPU utilization percentage
nvidia-smi dmon

# Columns:
# sm: GPU core utilization (should be >90%)
# mem: GPU memory utilization
# enc/dec: Video encoding/decoding

# If sm/mem low but performance bad:
# 1. Model may be running on CPU fallback
# 2. I/O bottleneck (slow disk/network)
# 3. Suboptimal batch size

# Check if using GPU:
docker exec ollama nvidia-smi | grep ollama
```

**B. Incorrect Batch Size**
```bash
# Ollama doesn't expose batch size config directly
# Performance tuning via model-specific settings:

# Option 1: Use model quantization (faster, less memory)
ollama pull llama2:7b-q4  # Quantized 4-bit

# Option 2: Adjust context window
# In ollama API: /api/generate with num_predict parameter

# Option 3: Check memory bandwidth saturation
nvidia-smi -q -d PCIE,MEMORY

# If PCIE bandwidth maxed, consider:
# - Reducing model size
# - Optimizing inference loop
# - Using inference batching
```

**C. Model Loading Time Excessive**
```bash
# Measure model load time
time ollama pull llama2:70b-chat

# Targets:
# First pull: 10-30 minutes (depends on download speed, 40GB model)
# Load into GPU: <10 seconds
# Subsequent loads: <5 seconds (if OLLAMA_KEEP_ALIVE prevents unload)

# If model load slow after first pull:
# 1. Check disk speed (dd test)
# 2. Verify GPU is idle before loading
# 3. Check if model cached in system RAM

dd if=/dev/zero of=/tmp/test.dat bs=1M count=1000 oflag=direct
# Should see >100MB/s for SSDs
```

**D. Host CPU or I/O Bottleneck**
```bash
# Monitor during model inference
iostat -x 1
dstat

# If disk I/O maxed (~100% util):
# 1. Model weights spilling to disk (insufficient GPU memory)
# 2. Disk too slow for model loading
# 3. Competing I/O workload

# Solution:
# 1. Upgrade storage to NVMe if on SATA
# 2. Reduce other workloads
# 3. Enable disk caching: echo 3 > /proc/sys/vm/drop_caches
```

---

## Issue 8: Container Runtime Errors During Startup

### Symptoms
```
Failed to initialize NVIDIA capabilities: could not load GPU driver libraries
could not find libnvidia-container.so.1
OCI runtime error [nvidia]: nvml: driver library not found
```

### Root Causes & Solutions

**A. GPU Driver Mismatch with nvidia-container-toolkit**
```bash
# Check both versions
nvidia-smi --query-gpu=driver_version --format=csv,noheader
nvidia-container-runtime --version

# If mismatch, they should be compatible
# Driver 550.x works with nvidia-container-toolkit v1.13+

# Update both to compatible versions
sudo apt update
sudo apt install -y --only-upgrade nvidia-driver-550 nvidia-container-toolkit
sudo systemctl restart docker
```

**B. libnvidia-container Missing**
```bash
# Find libnvidia-container
ldconfig -p | grep libnvidia-container

# If not found, install
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt update
sudo apt install -y libnvidia-container1

# Rebuild cache
sudo ldconfig
```

**C. SELinux or AppArmor Blocking GPU Access**
```bash
# Check if SELinux is enforcing
getenforce

# If enforcing, may need to disable or add GPU exception
# For development: sudo setenforce 0 (temporary)
# For production: https://nvidia.github.io/nvidia-docker/advanced-topics/cgroups/

# Check AppArmor (Ubuntu)
sudo aa-status | grep docker

# If in enforce mode, update profile or disable for troubleshooting
sudo aa-enforce /etc/apparmor.d/docker
sudo systemctl restart apparmor
```

---

## Validation Checklist

After implementing GPU configuration, verify all items:

- [ ] `lspci | grep NVIDIA` shows both GPUs
- [ ] `nvidia-smi` displays both GPUs with driver/CUDA versions
- [ ] `nvcc --version` shows CUDA 12.4
- [ ] `ls /usr/local/cuda/lib64/libcudnn*` shows cuDNN libraries
- [ ] `docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi` shows GPU
- [ ] `docker exec ollama nvidia-smi` shows GPU inside container
- [ ] `ollama list` runs without errors inside container
- [ ] `ollama pull llama2:70b-chat` completes and loads to GPU
- [ ] First-token latency <500ms measured
- [ ] Token generation >50 tokens/sec for 70B model
- [ ] GPU temperature <80°C under load
- [ ] `nvidia-smi dmon` shows sm >80%, mem >50% during inference

---

## Quick Reference: Common Commands

```bash
# GPU Health Check
nvidia-smi -q -d CLOCK,MAX_POWER,THROTTLE

# Monitor Real-Time
nvidia-smi dmon

# GPU Memory Detailed
nvidia-smi --query-gpu=memory.free,memory.used,memory.total --format=csv

# Process-Level GPU Usage
nvidia-smi pmon

# Check for Throttling
nvidia-smi -q | grep Throttle

# Docker GPU Test
docker run --rm --runtime=nvidia nvidia/cuda:12.4-base nvidia-smi

# Inside Container
docker exec <container-id> nvidia-smi

# Ollama GPU Test
docker exec ollama sh -c "ollama pull llama2:7b-chat && ollama run llama2:7b-chat 'Hello'"

# Performance Profiling
nvidia-smi --query-gpu=timestamp,name,utilization.gpu,utilization.memory,memory.used --format=csv -lms 1000
```

---

## Support & Next Steps

If issues persist after troubleshooting:

1. **Capture diagnostic output**:
   ```bash
   nvidia-smi -q > gpu-diagnostics.txt
   docker exec ollama nvidia-smi >> gpu-diagnostics.txt
   docker logs ollama >> gpu-diagnostics.txt
   ```

2. **Check system logs**:
   ```bash
   dmesg | grep -i nvidia | tail -20
   sudo journalctl -u docker -n 50
   ```

3. **Reference documentation**:
   - NVIDIA CUDA Toolkit: https://docs.nvidia.com/cuda/
   - nvidia-docker: https://github.com/NVIDIA/nvidia-docker
   - Ollama GPU support: https://github.com/ollama/ollama/blob/main/README.md#gpu-acceleration

---

**Document Status**: Reference guide complete  
**Related Issues**: #140 (IaC), #141 (GPU config), #144 (Monitoring)  
**Last Updated**: April 13, 2026
