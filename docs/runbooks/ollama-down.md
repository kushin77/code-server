# Runbook: Ollama GPU Model Server Down/Degraded

**Alerts**:
- `OllamaDown` (service unreachable, MEDIUM)
- `OllamaGPUMemoryHigh` (GPU memory > 95%, HIGH)

**Impact**: AI/ML features in code-server degraded (syntax completion, refactoring suggestions)  
**Time to Resolution**: < 10 minutes  
**Recovery Time Target**: < 5 minutes  

---

## Symptoms

- Alert: "Ollama model server is DOWN"
- Alert: "GPU memory {{ value }}% used — Ollama may OOM soon"
- code-server AI features timeout/fail
- `curl http://localhost:11434/api/tags` returns error
- GPU showing high VRAM usage (nvidia-smi)

---

## Root Causes

### OllamaDown

1. **Container crashed** - Ollama process exited unexpectedly
2. **Port mismatch** - Config change to port != 11434
3. **GPU driver issue** - NVIDIA driver crashed or needs reset
4. **Model loading failed** - Model file corrupted, GPU incompatible
5. **Out of memory** - OOMKilled by Docker

### OllamaGPUMemoryHigh

1. **Large model loaded** - 70B model uses 40GB+ VRAM
2. **Multiple models in memory** - Not unloaded after use
3. **Memory leak** - Ollama process holding memory after inference
4. **Query batch too large** - Processing too many tokens at once

---

## Immediate Diagnosis

### Step 1: Check Service Status

```bash
ssh akushnir@primary.prod.internal

# Check if container is running
docker ps | grep ollama

# Check container status
docker ps -a | grep ollama
# "Up X minutes" = running, "Exited (code)" = crashed

# Check if listening on port 11434
curl -s http://localhost:11434/api/tags | head -10
# Should return JSON with loaded models
```

### Step 2: Check Logs

```bash
# View recent container logs
docker logs ollama --tail 50

# Look for errors:
# "CUDA out of memory" → GPU memory issue
# "no such file" → Model file missing
# "connection refused" → Port issue
# "Segmentation fault" → Driver/hardware issue
```

### Step 3: Check GPU Status

```bash
# View GPU memory and processes
nvidia-smi

# Expected output:
# +------+..+-------+-------+
# | GPU | Name | Mem-Usage | Mem-Total |
# |  0  | RTX 3090 |  8000MiB | 24576MiB |
# +------+..+-------+-------+
# | Ollama | 8000MiB |

# If GPU not listed: Driver issue
# If memory 100% used: GPU memory full
# If no Ollama process: Container crashed
```

### Step 4: Check Loaded Models

```bash
# List currently loaded models
curl -s http://localhost:11434/api/tags | jq '.models[] | {name, size}'

# Example output:
# {
#   "name": "neural-chat:7b-v3.1-q4_0",
#   "size": 3826049024
# }
```

---

## Troubleshooting

### If Container is Stopped (OllamaDown)

```bash
# 1. Check why it stopped
docker logs ollama --tail 20
# Look for crash reason

# 2. Restart container
docker-compose restart ollama

# 3. Monitor startup
docker logs ollama --follow
# Should see "Loaded model <name> in Xs"

# 4. Verify it's responding
curl -s http://localhost:11434/api/tags
```

### If GPU Memory Is High (OllamaGPUMemoryHigh)

#### Check Model Size vs Available VRAM

```bash
# Get loaded model size
curl -s http://localhost:11434/api/tags | jq '.models[] | {name, size}'

# Get available GPU memory
nvidia-smi --query-gpu=memory.total,memory.used --format=csv,noheader

# Rule of thumb:
# 7B model needs 5-7GB VRAM
# 13B model needs 10-12GB VRAM
# 70B model needs 40GB+ VRAM

# If loaded model > available VRAM:
# Solution: Unload large model, load smaller one
```

#### Unload Unused Models (Free GPU Memory)

```bash
# Unload specific model
curl -X POST http://localhost:11434/api/generate \
  -d '{"model": "neural-chat:7b", "keep_alive": 0}'

# Unload ALL models
curl -X POST http://localhost:11434/api/generate \
  -d '{"model": "", "keep_alive": 0}'

# Wait 5 seconds, check GPU memory
sleep 5
nvidia-smi

# Should show significant memory freed
```

#### Load Smaller Model

```bash
# If 70B model consumes too much memory, switch to smaller variant

# Available models (ordered by size):
# - orca-mini:3b (3B, ~2GB VRAM)
# - neural-chat:7b (7B, ~5GB VRAM)
# - mistral:7b (7B, ~5GB VRAM)
# - llama2:13b (13B, ~10GB VRAM)
# - neural-chat:13b (13B, ~10GB VRAM)
# - mistral:medium (27B, ~18GB VRAM)
# - llama2:70b (70B, 40GB+ VRAM)

# Pull and test smaller model
docker exec ollama ollama pull orca-mini:3b
docker exec ollama ollama run orca-mini:3b "Why is the sky blue?"

# Update config to use smaller model by default
# Edit docker-compose.yml or environment
```

### If GPU Driver Is Broken (nvidia-smi fails)

```bash
# Check driver status
lspci | grep -i nvidia
# Should show GPU

# Restart GPU drivers
sudo modprobe -r nvidia_uvm nvidia
sudo modprobe nvidia_uvm
# or
sudo rmmod nvidia_uvm
sudo rmmod nvidia
sudo modprobe nvidia
sudo modprobe nvidia_uvm

# Restart Ollama
docker-compose restart ollama

# Verify GPU detected again
nvidia-smi
docker exec ollama nvidia-smi
```

### If Model File Is Corrupted

```bash
# Ollama models are cached in ~/.ollama/models/

# List cached models
ls -la ~/.ollama/models/blobs/

# Find and delete corrupted model
docker exec ollama rm -rf ~/.ollama/models/<model_name>

# Re-pull model
docker exec ollama ollama pull neural-chat:7b

# Restart Ollama
docker-compose restart ollama
```

---

## Recovery Actions

### For OllamaDown (Medium Severity)

1. ✅ Check logs to diagnose crash reason
2. ✅ Restart container: `docker-compose restart ollama`
3. ✅ Verify responsiveness: `curl http://localhost:11434/api/tags`
4. ✅ Monitor logs for 2 minutes: `docker logs ollama --follow`
5. ✅ If restarts repeatedly → see troubleshooting for crash causes

### For OllamaGPUMemoryHigh (High Severity)

1. ✅ Check loaded models: `curl http://localhost:11434/api/tags | jq`
2. ✅ Unload unnecessary models (see "Unload Unused Models" above)
3. ✅ If needed, switch to smaller model variant
4. ✅ Monitor GPU memory: `nvidia-smi --query-gpu=memory.used --format=csv --loop 1`
5. ✅ Alert clears when GPU memory < 85%

---

## Prevention

### 1. Set GPU Memory Limits

```yaml
# docker-compose.yml
services:
  ollama:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1  # Number of GPUs
              capabilities: [gpu]
```

### 2. Automate Model Management

```bash
# Unload models not used for 1 hour
0 * * * * curl -X POST http://localhost:11434/api/generate -d '{"model": "", "keep_alive": 0}'

# Or keep only specified models in memory
# In Ollama config: model_manager.keep_models = ["neural-chat:7b"]
```

### 3. Monitor GPU Actively

```bash
# Add to Prometheus scrape config:
# - job_name: 'gpu'
#   static_configs:
#     - targets: ['localhost:9400']  # nvidia_gpu_prometheus_exporter

# Query GPU memory metric:
# nvidia_smi_memory_used_bytes / nvidia_smi_memory_total_bytes
```

### 4. Set Up Graceful Degradation

```bash
# If Ollama is down > 5 minutes, code-server should degrade gracefully
# (disable AI features, show warning, but continue functioning)
```

---

## Related Alerts

- `HostCPUUsageHigh` - GPU workload impacts CPU
- `HostMemoryUsageHigh` - GPU memory pressure can affect system memory
- `ContainerRestartLoop` - If Ollama crashes repeatedly

---

*Last Updated: April 18, 2026*  
*On-Call Contact: @devops-team*
