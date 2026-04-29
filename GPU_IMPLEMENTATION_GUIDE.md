# GPU Integration - Technical Implementation Guide

**Objective**: Enable GPU support for Ollama and dependent ML services  
**Effort**: 1.5-2 hours including verification and testing  
**Risk**: Low (CPU fallback available)  
**Expected Performance Gain**: 16-30x faster inference

---

## Phase 1: Verification (15 minutes)

### 1.1 Check Host GPU Availability

```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Verify NVIDIA driver
nvidia-smi
# Expected output:
# +---------------------------------------------------------------------------------------+
# | NVIDIA-SMI 550.xx.xx                Driver Version: 550.xx.xx                       |
# |-----------------------+----------------------+----------------------+
# | GPU  Name            Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
# | Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
# |   0  NVIDIA A100-PCIE-40GB  Off |   00:1F.0     Off |                    0 |
# |  0%   30C    P0   42W / 250W |       0MiB / 40960MiB |      0%      Default |
# +-----------------------+----------------------+----------------------+

# If command not found or error, GPU driver not installed
# See "Appendix A: NVIDIA Driver Installation"
```

### 1.2 Verify Docker GPU Support

```bash
# Test docker GPU access
docker run --rm --gpus all ubuntu nvidia-smi

# Expected output: GPU details (same as nvidia-smi above)
# If fails with "Could not load dynamic library":
#   - nvidia-docker plugin not installed
#   - Docker daemon not restarted after installation
#   - See "Appendix B: nvidia-docker Installation"

# Check docker runtime is installed
docker info | grep -i nvidia
# Expected: Should see nvidia in list of runtimes
```

### 1.3 Verify Current Ollama State (CPU-only)

```bash
# Current state: Ollama running on CPU
docker exec code-server-ollama nvidia-smi 2>&1 | head -3
# Expected: Either "command not found" or error (proving CPU-only)

# Check Ollama GPU setting
docker exec code-server-ollama env | grep OLLAMA_NUM_GPU
# Expected: OLLAMA_NUM_GPU=0 (disabled)

# Baseline inference speed (CPU)
time curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3",
    "prompt": "Generate a hello world program. ",
    "stream": false
  }' > /tmp/cpu_response.json

# Extract and record execution time
grep -o '"eval_duration":[0-9]*' /tmp/cpu_response.json
# Expected: Something like "eval_duration":15000000000 (~15 seconds for CPU)
```

---

## Phase 2: Environment Configuration (10 minutes)

### 2.1 Update .env.cluster

```bash
# Navigate to repository
cd /home/akushnir/code-server

# Backup original
cp .env.cluster .env.cluster.backup

# Edit .env.cluster
nano .env.cluster  # or vi, or your preferred editor

# CHANGE (line ~72):
# Before:
OLLAMA_NUM_GPU=0

# After:
OLLAMA_NUM_GPU=1

# ADD (after OLLAMA_NUM_GPU):
CUDA_VISIBLE_DEVICES=0
OLLAMA_NUM_PARALLEL=4
OLLAMA_NUM_THREAD=8
OLLAMA_KEEP_ALIVE=10m

# (Optional) Also update these for multimodal-ai:
CUDA_VISIBLE_DEVICES=0
WHISPER_DEVICE=cuda
```

### 2.2 Verify Configuration

```bash
# Verify changes
grep -A 3 "OLLAMA_NUM_GPU" .env.cluster
# Expected output:
# OLLAMA_NUM_GPU=1
# CUDA_VISIBLE_DEVICES=0
# OLLAMA_NUM_PARALLEL=4
# OLLAMA_NUM_THREAD=8
# OLLAMA_KEEP_ALIVE=10m

# Commit to version control
git add .env.cluster
git commit -m "Enable GPU support for Ollama inference"
```

---

## Phase 3: Terraform Updates (30 minutes)

### 3.1 Modify Ollama Container Configuration

**File**: `terraform/environments/private/modules/stack/containers-infrastructure.tf`

#### Option A: Simple Hard-Code (Recommended for immediate fix)

```hcl
# Find line ~194: resource "docker_container" "ollama" {

# BEFORE (lines 194-241):
resource "docker_container" "ollama" {
  name    = "code-server-ollama"
  image   = docker_image.ollama.image_id
  user    = "11434:11434"
  restart = "unless-stopped"

  depends_on = [docker_container.ollama_init]

  env = [
    "HOME=/home/ollama",
    "OLLAMA_HOST=0.0.0.0:11434",
    "OLLAMA_MODELS=/home/ollama/.ollama/models",
  ]

  # ... rest of config

# AFTER (add runtime, add env vars):
resource "docker_container" "ollama" {
  name    = "code-server-ollama"
  image   = docker_image.ollama.image_id
  user    = "11434:11434"
  restart = "unless-stopped"
  
  # ← ADD THIS LINE:
  runtime = "nvidia"

  depends_on = [docker_container.ollama_init]

  env = [
    "HOME=/home/ollama",
    "OLLAMA_HOST=0.0.0.0:11434",
    "OLLAMA_MODELS=/home/ollama/.ollama/models",
    # ← ADD THESE LINES:
    "OLLAMA_NUM_GPU=1",
    "CUDA_VISIBLE_DEVICES=0",
    "OLLAMA_NUM_PARALLEL=4",
    "OLLAMA_NUM_THREAD=8",
    "OLLAMA_KEEP_ALIVE=10m",
  ]

  # ... rest remains the same
```

#### Option B: Conditional on Variable (Future-proof)

```hcl
# In same file, containers-infrastructure.tf:

# Step 1: Add variable reference at module level (if not present)
# The variable gpu_available comes from var.gpu_available passed from parent module

# Step 2: Modify docker_container.ollama:
resource "docker_container" "ollama" {
  name    = "code-server-ollama"
  image   = docker_image.ollama.image_id
  user    = "11434:11434"
  restart = "unless-stopped"
  
  # Conditional runtime based on GPU availability
  runtime = var.gpu_available ? "nvidia" : "runc"

  depends_on = [docker_container.ollama_init]

  # Conditional environment variables
  env = concat([
    "HOME=/home/ollama",
    "OLLAMA_HOST=0.0.0.0:11434",
    "OLLAMA_MODELS=/home/ollama/.ollama/models",
  ], var.gpu_available ? [
    "OLLAMA_NUM_GPU=1",
    "CUDA_VISIBLE_DEVICES=0",
    "OLLAMA_NUM_PARALLEL=4",
    "OLLAMA_NUM_THREAD=8",
    "OLLAMA_KEEP_ALIVE=10m",
  ] : [])

  # ... rest remains the same
}
```

### 3.2 Option B Extended: Variable Propagation

If using Option B, also update:

**File**: `terraform/environments/private/modules/stack/variables.tf`

```hcl
# Add or verify this variable exists:
variable "gpu_available" {
  type        = bool
  default     = false
  description = "Whether GPU is available on host for ML inference"
}
```

**File**: `terraform/environments/private/main.tf`

```hcl
# Find module "primary" block and add:
module "primary" {
  # ... existing configuration ...
  
  # ADD:
  gpu_available = var.enable_gpu
  
  # ... rest of configuration ...
}

module "replica" {
  # ... existing configuration ...
  
  # ADD (if using active-active):
  gpu_available = var.enable_gpu
  
  # ... rest of configuration ...
}
```

**File**: `terraform/environments/private/variables.tf`

```hcl
# Add new variable:
variable "enable_gpu" {
  type        = bool
  default     = false
  description = "Enable GPU support for Ollama and ML services"
}
```

**File**: `terraform.tfvars` (or create if doesn't exist)

```hcl
# Add or update:
enable_gpu = true
```

### 3.3 Validate Terraform Changes

```bash
# Change to terraform directory
cd /home/akushnir/code-server/terraform/environments/private

# Initialize terraform (if needed)
terraform init

# Show what will change
terraform plan -target=module.primary.docker_container.ollama

# Expected output should show:
# - runtime = "nvidia" (was "runc")
# - OLLAMA_NUM_GPU=1 in env
# - CUDA_VISIBLE_DEVICES=0 in env
# - Other OLLAMA_* GPU variables

# If satisfied, proceed to Phase 4
```

---

## Phase 4: Deployment (15 minutes)

### 4.1 Apply Terraform to Primary

```bash
# From /home/akushnir/code-server/terraform/environments/private

# Apply changes
terraform apply -auto-approve -target=module.primary.docker_container.ollama

# This will:
# 1. Stop current ollama container
# 2. Create new container with nvidia runtime
# 3. Start new container with GPU env vars
# 4. Takes ~30-60 seconds

# Watch the deployment
watch -n 1 'docker ps | grep ollama'
# Exit with Ctrl+C when running
```

### 4.2 Apply to Replica (if active-active)

```bash
# If using active-active replication (192.168.168.42):
terraform apply -auto-approve -target=module.replica.docker_container.ollama

# Verify both Ollama instances are running
docker ps --format "table {{.Names}}\t{{.Status}}" | grep ollama
# Should show both instances running on both hosts (if applicable)
```

### 4.3 Monitor Container Startup

```bash
# Monitor logs during startup
docker logs -f code-server-ollama

# Look for:
# - CUDA initialization messages
# - "WARNING" or "ERROR" containing "gpu", "cuda", "nvidia"
# - Model loading messages (e.g., "llama3 loaded")

# Exit with Ctrl+C when ready
```

---

## Phase 5: Verification (20 minutes)

### 5.1 Confirm GPU Access

```bash
# Test GPU is accessible from container
docker exec code-server-ollama nvidia-smi

# Expected output: GPU information including:
# - GPU model (e.g., NVIDIA A100, L4)
# - Memory (e.g., 40GB)
# - Driver version

# If fails with "command not found":
#   - nvidia-docker not installed on host
#   - Docker daemon not restarted
#   - runtime = "nvidia" not applied correctly
#   See "Troubleshooting" section below
```

### 5.2 Verify Ollama GPU Status

```bash
# Show Ollama model details with GPU info
docker exec code-server-ollama ollama show llama3

# Look for:
# - "parameters gpu_layer" or "gpu_memory"
# - Should show GPU is being used for acceleration

# Alternative: Check process
docker exec code-server-ollama ps aux | grep ollama
# Should show ollama process (CPU thread count should be 8)
```

### 5.3 Performance Benchmark

```bash
# Test inference performance with GPU
time curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3",
    "prompt": "Generate a hello world program. ",
    "stream": false
  }' > /tmp/gpu_response.json

# Extract execution times
echo "=== Execution Duration (nanoseconds) ==="
grep -o '"eval_duration":[0-9]*' /tmp/gpu_response.json

# Compare with CPU baseline from Phase 1
# CPU was: ~15000000000 (15 seconds)
# GPU should be: ~500000000-1000000000 (0.5-1 second)
# Expected speedup: 15-30x

# Check token throughput
echo "=== Full Response ==="
cat /tmp/gpu_response.json | jq '.eval_duration, .eval_count'
```

### 5.4 Memory Usage

```bash
# Monitor GPU memory during inference
docker exec code-server-ollama nvidia-smi -l 1
# Should show GPU memory increasing during inference
# Press Ctrl+C to exit

# Expected GPU memory usage:
# llama3:8b  = ~8-10 GB VRAM
# mistral:7b = ~6-8 GB VRAM
# llava:13b  = ~15-18 GB VRAM
```

### 5.5 Multimodal-AI Functionality

```bash
# Test multimodal-ai (depends on Ollama)
curl http://localhost:8005/health
# Expected: {"status":"healthy"} or similar

# Test with an image analysis request (if endpoint supports it)
curl -X POST http://localhost:8005/image/analyze \
  -F "image=@/path/to/image.png" \
  -F "context=test"
# Should complete much faster with GPU Ollama backend
```

### 5.6 System Health

```bash
# Overall system check
docker-compose -f docker-compose.enterprise.yml ps

# Should show:
# - code-server-ollama: Up (and healthy)
# - code-server-multimodal-ai: Up
# - code-server-memory-engine: Up
# - All other services: Up

# Check logs for errors
docker logs code-server-ollama | tail -20 | grep -i "error\|warn"
# Should be minimal or only informational

# Check system resources
docker stats --no-stream | grep ollama
# Should show GPU memory in use
```

---

## Phase 6: Monitoring Setup (Optional, 20 minutes)

### 6.1 Enable DCGM Exporter

```bash
# Activate observability profile with DCGM
cd /home/akushnir/code-server

# Start DCGM exporter
docker-compose -f docker-compose.observability.yml \
  --profile observability up -d dcgm-exporter

# Verify it's running
docker ps --filter name=dcgm
# Should show code-server-dcgm-exporter running

# Wait 30 seconds for initialization
sleep 30
```

### 6.2 Verify Metrics Collection

```bash
# Check DCGM exporter metrics
curl http://localhost:9400/metrics | head -30

# Should show DCGM metrics like:
# DCGM_FI_DEV_GPU_UTIL
# DCGM_FI_DEV_FB_USED
# DCGM_FI_DEV_FB_TOTAL
# DCGM_FI_DEV_GPU_TEMP

# If no metrics, DCGM daemon not running on host
# Run on host: sudo nv-hostengine (may need to install nvidia-datacenter-gpu-manager)
```

### 6.3 Verify Prometheus Scraping

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "dcgm")'

# Should show dcgm-exporter endpoint with state "up"

# Query a GPU metric
curl 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL'
# Should return GPU utilization metric
```

### 6.4 Verify Alerting

```bash
# Check Prometheus alert rules loaded
curl 'http://localhost:9090/api/v1/rules' | jq '.data.groups[] | select(.name == "gpu_health")'

# Should show GPU alert rules (GPUUtilizationHigh, GPUMemoryPressure, GPUECCErrorsDetected)

# Note: Alerts won't fire until metrics breach thresholds
```

---

## Testing Scenarios

### Scenario 1: High GPU Utilization

```bash
# Generate continuous inference load
for i in {1..10}; do
  curl -X POST http://localhost:11434/api/generate \
    -d '{
      "model":"llama3",
      "prompt":"Explain quantum computing in detail. ",
      "stream":false
    }' &
done
wait

# Monitor GPU during load
watch -n 1 'docker exec code-server-ollama nvidia-smi'
# Should see GPU memory climbing and utilization rising
```

### Scenario 2: GPU Memory Exhaustion

```bash
# Load all available models to stress GPU
docker exec code-server-ollama ollama pull mistral:7b
docker exec code-server-ollama ollama pull neural-chat:latest
docker exec code-server-ollama ollama pull llava:13b

# Monitor GPU memory
docker exec code-server-ollama nvidia-smi
# If exhausted: may show "out of memory" errors on subsequent inference
# Ollama will fallback to CPU or evict models
```

### Scenario 3: Failover to CPU

```bash
# Simulate GPU failure by disabling it
# Edit .env.cluster: OLLAMA_NUM_GPU=1 → OLLAMA_NUM_GPU=0

# Restart container
docker restart code-server-ollama

# Verify it still works (should use CPU)
docker exec code-server-ollama nvidia-smi
# Should fail with "command not found" (CPU-only now)

# Performance should degrade to ~5 tokens/sec (vs ~50+ with GPU)
curl -X POST http://localhost:11434/api/generate ...
```

---

## Troubleshooting

### Problem 1: "nvidia-smi: command not found"

**Cause**: NVIDIA driver not installed on host

**Solution**:
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Check driver installed
apt-cache search nvidia-driver | grep "^nvidia-driver-5"

# Install latest driver
sudo apt update
sudo apt install -y nvidia-driver-550

# Reboot required
sudo reboot

# After reboot, verify
nvidia-smi
```

### Problem 2: "docker: Error response from daemon: could not select device driver"

**Cause**: nvidia-docker runtime not installed or docker not restarted

**Solution**:
```bash
# Install nvidia-docker
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update
sudo apt-get install -y nvidia-docker2

# Restart docker
sudo systemctl restart docker

# Verify
docker run --rm --gpus all ubuntu nvidia-smi
```

### Problem 3: "CUDA out of memory" during inference

**Cause**: GPU memory exhausted

**Solution**:
```bash
# Option 1: Restart Ollama to clear cache
docker restart code-server-ollama

# Option 2: Unload models
docker exec code-server-ollama ollama list
docker exec code-server-ollama ollama rm mistral:7b  # Remove model to free VRAM

# Option 3: Fallback to CPU
# Edit .env.cluster: OLLAMA_NUM_GPU=0
docker restart code-server-ollama
```

### Problem 4: Slow inference (still looks like CPU speed)

**Cause**: GPU not actually being used

**Solution**:
```bash
# Verify GPU env var is set
docker exec code-server-ollama env | grep OLLAMA_NUM_GPU
# Should show OLLAMA_NUM_GPU=1 (not 0)

# Verify runtime is nvidia
docker inspect code-server-ollama | grep -A 1 '"Runtime"'
# Should show: "Runtime": "nvidia"

# Check Ollama logs for GPU loading
docker logs code-server-ollama | grep -i "cuda\|gpu"

# If still slow, verify with direct nvidia-smi
docker exec code-server-ollama nvidia-smi

# If all looks correct but still slow:
# - Model may be too large for GPU
# - GPU may be oversubscribed (multiple models loading)
# - Check disk I/O (reading model files from disk)
```

### Problem 5: DCGM exporter not showing metrics

**Cause**: DCGM daemon not running on host

**Solution**:
```bash
# SSH to host
ssh akushnir@192.168.168.31

# Install NVIDIA DCGM
sudo apt install -y datacenter-gpu-manager

# Start DCGM daemon
sudo nv-hostengine

# In docker container, verify metrics:
docker exec code-server-dcgm-exporter dcgmi -g 0
```

---

## Rollback Procedure

If GPU enablement causes issues, rollback to CPU:

```bash
# Edit .env.cluster
sed -i 's/OLLAMA_NUM_GPU=1/OLLAMA_NUM_GPU=0/' .env.cluster

# Rollback terraform (or manually edit to remove runtime):
# Option: Revert containers-infrastructure.tf changes
git checkout HEAD -- terraform/environments/private/modules/stack/containers-infrastructure.tf

# Reapply
cd /home/akushnir/code-server/terraform/environments/private
terraform apply -auto-approve -target=module.primary.docker_container.ollama

# Verify rollback
docker inspect code-server-ollama | grep -i runtime
# Should show "runc" again
```

---

## Performance Metrics Recording

Document baseline and post-GPU metrics for future reference:

```bash
# Create metrics file
cat > /tmp/gpu_metrics.txt << 'EOF'
=== CPU-Only (Baseline) ===
Date: $(date)
Model: llama3:8b
Tokens/sec: ~5
100-token latency: ~20 seconds
1-min inference: ~2 minutes
GPU Memory: N/A
Host: 192.168.168.31

=== GPU-Enabled ===
Date: $(date)
Model: llama3:8b
Tokens/sec: ~50-150
100-token latency: ~0.7-2 seconds
1-min inference: ~0.4-1 minute
GPU Memory: ~8-10 GB
Host: 192.168.168.31
GPU Model: (fill in from nvidia-smi)

=== Performance Improvement ===
Speedup: 10-30x
EOF

# Run inference test
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3","prompt":"test","stream":false}' \
  | jq -r '.eval_duration' >> /tmp/gpu_metrics.txt
```

---

## Appendix A: NVIDIA Driver Installation

For Ubuntu 22.04:

```bash
# Add NVIDIA repository
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
wget https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/cuda-$distribution.pin
sudo mv cuda-$distribution.pin /etc/apt/preferences.d/cuda-repository-pin-500
sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/3bf863cc.pub
sudo add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/ /"

# Install
sudo apt-get update
sudo apt-get install -y cuda-drivers-550

# Reboot
sudo reboot

# Verify
nvidia-smi
```

---

## Appendix B: nvidia-docker Installation

```bash
# Install nvidia-docker2
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update
sudo apt-get install -y nvidia-docker2

# Restart docker daemon
sudo systemctl restart docker

# Verify
docker run --rm --gpus all ubuntu nvidia-smi
```

---

## Summary

**Expected Timeline**:
- Phase 1 (Verification): 15 min
- Phase 2 (Configuration): 10 min
- Phase 3 (Terraform): 30 min
- Phase 4 (Deployment): 15 min
- Phase 5 (Verification): 20 min
- Phase 6 (Monitoring): 20 min (optional)

**Total**: 1.5-2 hours

**Success Criteria**:
✓ GPU detected in container
✓ Inference 16-30x faster
✓ DCGM metrics available (optional)
✓ All services running healthy

---

**Document Version**: 1.0  
**Date**: April 29, 2026  
**Status**: Ready for implementation
