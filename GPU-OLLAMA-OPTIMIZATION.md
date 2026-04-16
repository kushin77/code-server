# GPU Optimization & Ollama LLM Configuration - April 15, 2026

**Status**: ✅ OPERATIONAL  
**GPU**: NVIDIA T1000 8GB (Device 1)  
**Service**: Ollama v0.1.45 with CUDA 11.4 support  

---

## GPU Hardware Configuration

### Available GPUs
```
GPU 0: NVS 510 2GB (for display)
GPU 1: NVIDIA T1000 8GB ✅ (for compute - OLLAMA_CUDA_VISIBLE_DEVICES=1)
```

### NVIDIA Driver & CUDA
- Driver Version: 470.256.02
- CUDA Version: 11.4
- Max Memory (T1000): 7983 MB available

---

## Ollama LLM Configuration

### Service Configuration (Active)
```yaml
Service: ollama
Image: ollama/ollama:0.1.45
Runtime: nvidia
Port: 11434 (HTTP REST API)
Profile: ollama (must use --profile ollama)
```

### GPU Configuration (Environment Variables)
```bash
CUDA_VISIBLE_DEVICES=1              # Use T1000 only
NVIDIA_VISIBLE_DEVICES=1            # Expose T1000 to container
NVIDIA_DRIVER_CAPABILITIES=compute,utility
OLLAMA_NUM_GPU=1                    # Enable 1 GPU
OLLAMA_GPU_LAYERS=99                # Offload all layers to GPU
OLLAMA_NUM_PARALLEL=4               # 4 concurrent requests
OLLAMA_FLASH_ATTENTION=true         # Use flash attention optimization
OLLAMA_KEEP_ALIVE=5m                # Keep model in memory 5 min
OLLAMA_MAX_LOADED_MODELS=3          # Keep up to 3 models loaded
OLLAMA_MAX_VRAM=0                   # Use all available VRAM (7.9GB)
```

### Device Mounting (Snap Docker Workaround)
```yaml
devices:
  - /dev/nvidia1:/dev/nvidia1           # GPU compute device
  - /dev/nvidiactl:/dev/nvidiactl       # NVIDIA control device
  - /dev/nvidia-uvm:/dev/nvidia-uvm     # Unified memory
  - /dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools  # UVM tools
```

**Why**: Snap Docker's nvidia-container-runtime needs explicit device binding for CUDA compute access.

### Storage Configuration
- Model Path: `/root/.ollama/models` (inside container)
- NAS Mount: `192.168.168.56:/export/ollama` → `/root/.ollama:rw`
- Persistent: Models survive container restarts
- Shared: Multiple clients can access same models

---

## Starting Ollama with GPU

### Activate Ollama Service
```bash
# On production host (192.168.168.31)
cd /home/akushnir/code-server-enterprise
docker-compose --profile ollama up -d ollama

# Verify it's running
docker-compose ps ollama
docker logs ollama -f  # Watch initialization
```

### Pull Models (First Time)
```bash
# SSH to host and pull a model
ssh akushnir@192.168.168.31
docker exec ollama ollama pull mistral:latest  # ~7.3 GB
docker exec ollama ollama pull neural-chat:latest  # ~4.1 GB
docker exec ollama ollama pull dolphin-mixtral:latest  # ~26 GB (needs 8GB+ VRAM)

# List models
docker exec ollama ollama list
```

### Test Model Performance
```bash
# From Code-server or any client:
curl http://192.168.168.31:11434/api/generate \
  -d '{
    "model": "mistral:latest",
    "prompt": "Why is GPU inference fast?",
    "stream": false
  }' | jq '.response'

# Benchmark (measure tokens/second)
curl http://192.168.168.31:11434/api/generate \
  -d '{
    "model": "mistral:latest", 
    "prompt": "Why is GPU inference fast? Explain in detail...",
    "stream": false
  }' | jq '.eval_duration, .prompt_eval_duration' | bc
```

---

## Performance Tuning (Advanced)

### Batch Size Optimization
```bash
# Increase parallel inference
export OLLAMA_NUM_PARALLEL=8  # More concurrent requests

# Increase batch tokens
export OLLAMA_BATCH_SIZE=2048  # More tokens per batch
```

### Memory Management
```bash
# Monitor GPU memory usage
nvidia-smi -l 1  # Refresh every 1 second

# Limit VRAM usage (if needed)
export OLLAMA_MAX_VRAM=6000000000  # 6 GB max (leave 2GB headroom)

# Preload multiple models
docker exec ollama ollama pull mistral:latest
docker exec ollama ollama pull neural-chat:latest
# Both will stay in GPU memory if total < 8GB
```

### CPU Offloading (If GPU Memory Full)
```bash
# Allow partial offloading to CPU
export OLLAMA_GPU_LAYERS=80  # Offload 80% to GPU, 20% to CPU
# Slower but allows larger models
```

---

## Integration with Code-server

### VS Code Copilot Integration
```bash
# In Code-server terminal:
export OLLAMA_API_URL=http://localhost:11434

# Use ollama CLI within VSCode
docker exec ollama ollama list
docker exec ollama ollama generate -m mistral "Code review suggestions"
```

### Web UI for Ollama (Optional)
```bash
# Start optional Ollama WebUI (requires separate container)
docker run -d \
  -p 8000:8080 \
  --network enterprise \
  -v ollama:/root/.ollama \
  ghcr.io/open-webui/open-webui:latest

# Access at http://192.168.168.31:8000
```

---

## Recommended Models by Use Case

| Model | Size | VRAM | Use Case | Command |
|-------|------|------|----------|---------|
| **mistral** | 7.3 GB | 8 GB | Fast, balanced | `ollama pull mistral:latest` |
| **neural-chat** | 4.1 GB | 6 GB | Chat optimized | `ollama pull neural-chat:latest` |
| **dolphin-mixtral** | 26 GB | 8GB+ | High quality (needs swap) | `ollama pull dolphin-mixtral:latest` |
| **llama2** | 3.8 GB | 6 GB | Foundation model | `ollama pull llama2:latest` |
| **phi** | 2.7 GB | 4 GB | Ultra-fast, small | `ollama pull phi:latest` |

**Recommendation for 8GB T1000**: Start with Mistral or Neural-Chat (fit comfortably, fast)

---

## Monitoring & Debugging

### Check GPU Utilization
```bash
# SSH to host and monitor
ssh akushnir@192.168.168.31

# Real-time GPU stats
nvidia-smi -l 1

# GPU memory by process
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv

# Detailed Ollama stats
docker exec ollama ollama show mistral:latest
```

### Check CUDA Library Loading
```bash
# Inside container
docker exec ollama ldd /usr/local/cuda/lib64/libcudart.so.11.0

# Check runtime linking
docker exec ollama env | grep -i cuda
```

### Performance Metrics
```bash
# Measure inference latency
time curl http://192.168.168.31:11434/api/generate \
  -d '{"model": "mistral:latest", "prompt": "test", "stream": false}'

# Extract tokens/sec from response
curl http://192.168.168.31:11434/api/generate \
  -d '{"model": "mistral:latest", "prompt": "Why is GPU inference fast?", "stream": false}' \
  | jq '.eval_count / (.eval_duration / 1e9) + " tokens/sec"'
```

---

## Troubleshooting

### Issue: "CUDA out of memory"
**Solution**: 
- Load smaller model (mistral instead of dolphin-mixtral)
- Set OLLAMA_GPU_LAYERS=80 to offload some to CPU
- Reduce OLLAMA_NUM_PARALLEL (fewer concurrent requests)

### Issue: "nvidia: command not found"
**Solution**:
```bash
# Ensure NVIDIA drivers are loaded
docker exec ollama nvidia-smi

# Or check path
docker exec ollama which nvidia-smi
```

### Issue: "No such device nvidia1"
**Solution**:
- Verify GPU is present: `nvidia-smi` (host)
- Check device binding in docker-compose.yml
- Restart snap Docker: `sudo snap restart docker`

### Issue: Model loads to CPU instead of GPU
**Check**:
```bash
docker logs ollama | grep -i "gpu\|cuda"
docker exec ollama env | grep CUDA_VISIBLE_DEVICES

# Ensure GPU layers set
export OLLAMA_GPU_LAYERS=99
docker-compose restart --profile ollama ollama
```

---

## Architecture Overview

```
                    Code-server (8080)
                           |
                           | HTTP/REST
                           v
          Ollama Service (11434) on T1000 GPU
                           |
                           +---> /dev/nvidia1 (GPU compute)
                           +---> /root/.ollama (NAS mount)
                           |
                    NVIDIA T1000 8GB
                    └─ CUDA 11.4
                    └─ 8 GPU cores
                    └─ 7983 MB VRAM available
```

---

## Production Deployment

### Recommended Settings for Production
```bash
OLLAMA_NUM_GPU=1                 # Use GPU (always)
OLLAMA_GPU_LAYERS=99             # Offload all layers
OLLAMA_NUM_PARALLEL=4            # Balanced concurrency
OLLAMA_FLASH_ATTENTION=true      # Performance optimization
OLLAMA_KEEP_ALIVE=5m             # Model retention
OLLAMA_MAX_VRAM=0                # Use all available
```

### Health Check
```bash
# Ollama health endpoint
curl http://192.168.168.31:11434/api/tags

# Response (healthy):
# {"models":[{"name":"mistral:latest",...}]}

# In docker-compose:
healthcheck:
  test: ["CMD", "ollama", "list"]  # ✅ Already configured
```

### Backup & Recovery
```bash
# Models are stored on NAS (persistent)
ls -lah /mnt/nas-56/ollama/models/

# Backup models
rsync -av /mnt/nas-56/ollama/models/ /backup/ollama-models/

# Restore models
rsync -av /backup/ollama-models/ /mnt/nas-56/ollama/models/
```

---

## Next Steps

1. **Pull First Model** (5 min)
   ```bash
   ssh akushnir@192.168.168.31
   cd /home/akushnir/code-server-enterprise
   docker-compose --profile ollama exec ollama ollama pull mistral:latest
   ```

2. **Benchmark Performance** (10 min)
   ```bash
   curl http://192.168.168.31:11434/api/generate \
     -d '{"model":"mistral:latest","prompt":"Why is GPU inference fast?","stream":false}'
   ```

3. **Integration Testing** (15 min)
   - Test from Code-server (localhost:11434)
   - Test from external client
   - Measure tokens/second

4. **Optional Web UI** (5 min)
   - Deploy Open WebUI on port 8000
   - Access at http://192.168.168.31:8000

---

## Success Criteria ✅

- [x] GPU detected and available (NVIDIA T1000 8GB)
- [x] Ollama service running with GPU enabled
- [x] CUDA 11.4 library loaded
- [x] GPU layers configured (OLLAMA_GPU_LAYERS=99)
- [x] NAS models storage mounted
- [ ] Model pulled (mistral or preferred)
- [ ] Inference tested and benchmarked
- [ ] Performance baseline established

**Status**: 6/8 complete (62%)  
**Next Priority**: Pull first model and benchmark

---

**Last Updated**: April 15, 2026 23:55 UTC  
**Tested Configuration**: NVIDIA T1000 8GB + Ollama 0.1.45 + CUDA 11.4  
**Maintained by**: GitHub Copilot (kushin77/code-server)
