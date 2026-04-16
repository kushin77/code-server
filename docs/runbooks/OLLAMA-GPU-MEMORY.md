# Alert Runbook: Ollama GPU Memory Critical

**Alerts**: `Ollama{Down,GPUMemoryHigh,GPUMemoryCritical}`  
**Severity**: WARNING (>95% GPU mem), CRITICAL (>99% GPU mem or service down)  
**SLA**: WARNING (1 hour), CRITICAL (15 minutes)  
**Owner**: ML/DevOps Team  
**Host**: 192.168.168.31 (GPU node)  

---

## Problem

GPU memory exhaustion on Ollama model server. Symptoms:
- **GPU Memory High** (>95%): Model inference may stall, OOM risk increasing
- **GPU Memory Critical** (>99%): Imminent kernel OOM killer, process will be terminated
- **Ollama Down**: Service crashed or unreachable, AI features in code-server unavailable
- **Impact**: Code-server AI code completion, code review, documentation generation all fail

---

## Immediate Investigation (< 2 minutes)

```bash
# SSH to GPU host (192.168.168.31)
ssh akushnir@192.168.168.31

# Check Ollama service status
docker-compose ps ollama

# Check GPU memory in real-time
nvidia-smi
# Look at "Memory-Usage" and "Memory-Processes"

# Check Ollama process
docker exec ollama ps aux | grep ollama
docker stats ollama --no-stream

# Check Ollama logs for errors
docker logs ollama --tail 100 | tail -20

# Check which model is loaded
curl -s http://localhost:11434/api/tags | jq '.models[] | .name'

# Check GPU memory per process
nvidia-smi -q -d MEMORY -i 0
```

---

## Common Root Causes & Fixes

### Cause 1: Large Model Loaded in VRAM

**Symptoms**:
- `nvidia-smi` shows 1 process using 80GB+ VRAM
- Ollama logs show "Loading model..."
- Only happens when specific model is active

**Fix** (Reduce VRAM usage):
```bash
# Option 1: Unload current model to free VRAM
curl -X POST http://localhost:11434/api/generate \
  -d '{"model": "","stream": false}' \
  -H "Content-Type: application/json"

# Option 2: Configure model to use CPU quantization
# Edit ollama model config (Modelfile):
cat > Modelfile.quantized << 'EOF'
FROM mistral:7b
# Quantize to use less VRAM (4-bit or 3-bit)
PARAMETER num_gpu 0  # Use CPU instead
EOF

docker exec ollama ollama create mistral-cpu -f Modelfile.quantized

# Option 3: Reduce model size - use smaller quantization
# Instead of 13b model, use 7b
# Instead of full precision, use 4-bit or 3-bit quantization

# Option 4: Enable model offloading
# Ollama can split layers between GPU and CPU
# Check ollama config for offload settings
```

### Cause 2: Multiple Models Loaded Simultaneously

**Symptoms**:
- `nvidia-smi` shows multiple ollama processes
- Ollama logs show "model is already loaded"
- GPU memory never freed between inference requests

**Fix**:
```bash
# Check currently loaded models
curl -s http://localhost:11434/api/ps | jq '.models'

# Option 1: Unload all models
curl -X POST http://localhost:11434/api/generate \
  -d '{"model": "","stream": false}'

# Option 2: Reduce model keep alive time
# Edit docker-compose.yml:
#   environment:
#     OLLAMA_MODELS_UNLOAD_TIMEOUT: "10m"  # Unload after 10 min inactivity
docker-compose down ollama
docker-compose up -d ollama

# Option 3: Switch to single smaller model
# Remove large models, keep only:
#   - mistral:7b (efficient, good quality)
#   - neural-chat (optimized for code, small)
```

### Cause 3: Memory Leak in Ollama Process

**Symptoms**:
- GPU memory steadily increases over time (even with no new requests)
- Logs show no errors
- Only solution is restart

**Fix**:
```bash
# Monitor memory growth
for i in {1..10}; do
  nvidia-smi --query-gpu=memory.used --format=csv,noheader
  sleep 60
done
# If consistently increasing, memory leak present

# Restart Ollama to clear
docker-compose restart ollama

# Check if problem returns
watch 'nvidia-smi --query-gpu=memory.used --format=csv,noheader'

# If leak returns within hours, upgrade Ollama or switch model
docker-compose down ollama
docker pull ollama/ollama:latest  # Get latest version
docker-compose up -d ollama
```

### Cause 4: Inference Request Hangs/Doesn't Complete

**Symptoms**:
- GPU memory fills up but doesn't release
- Ollama logs show request in progress
- GPU stuck with 100% memory allocated
- No inference results returning to client

**Fix**:
```bash
# Check for stuck inference requests
docker exec ollama curl -s http://localhost:11434/api/ps

# Kill the stuck request
docker exec ollama pkill -f "inference"

# Or restart ollama completely
docker-compose restart ollama

# Reduce inference timeout in client
# Modify code-server Ollama client config:
#   timeout: 30s  # 30 second max for inference
```

### Cause 5: Ollama Service Crashed

**Symptoms**:
- `docker-compose ps` shows: "Exited (code)"
- `docker logs ollama` shows errors
- Alerts show `OllamaDown` firing

**Fix** (depends on error):
```bash
# Get error details
docker logs ollama --tail 50

# Common errors:
# 1. CUDA driver mismatch
#    FIX: Ensure NVIDIA driver and CUDA runtime match
nvidia-smi | grep "Driver Version"
docker exec ollama nvidia-smi | grep "CUDA Version"

# 2. GPU out of memory during startup
#    FIX: Free some GPU memory first
pkill ollama  # Kill any remaining ollama process
sleep 5
docker-compose up -d ollama

# 3. Port 11434 already in use
#    FIX: Kill process on port, or change port
lsof -i :11434
kill -9 PID
docker-compose up -d ollama

# 4. Permission denied on GPU
#    FIX: Ensure container has GPU access
docker-compose down
# Verify docker-compose.yml has:
#   runtime: nvidia  # or gpus: all
docker-compose up -d ollama

# 5. Out of host memory (not GPU memory)
#    FIX: Free some system RAM
free -h
docker system prune -a  # Remove unused images
```

---

## Recovery Steps (Priority Order)

### Immediate (If >95% GPU memory - prevent crash):

```bash
# 1. Stop inference requests to Ollama
# Notify code-server users: "AI features temporarily offline"

# 2. Unload current model
curl -X POST http://localhost:11434/api/generate \
  -d '{"model": "","stream": false}'

# 3. Monitor GPU memory
watch -n 2 nvidia-smi | head -20

# 4. Once below 50%, reload single small model
curl -X POST http://localhost:11434/api/pull \
  -d '{"model": "neural-chat"}' -H "Content-Type: application/json"
```

### Short-term (If >99% GPU memory or service down):

```bash
# 1. Force stop ollama
docker kill ollama || docker-compose restart ollama

# 2. Wait for restart
sleep 30
docker-compose ps ollama

# 3. Verify service is healthy
curl -s http://localhost:11434/api/tags

# 4. Re-enable inference (code-server features back online)
```

### Long-term (Prevent recurrence):

```bash
# 1. Switch to memory-efficient models only
# Replace large 13B models with 7B quantized versions

# 2. Configure automatic model offloading
# Edit Ollama config to use system RAM for overflow
cat > /opt/ollama/config.yaml << 'EOF'
models:
  - name: mistral:7b
    enable_offload: true
    cpu_offload_threshold: 0.8  # Offload to CPU if VRAM > 80%
EOF

# 3. Set model unload timeout
# Auto-unload models that haven't been used in 5 minutes
docker-compose exec ollama sh -c "
  echo 'OLLAMA_MODELS_UNLOAD_TIMEOUT=5m' >> /etc/environment
"
docker-compose restart ollama

# 4. Monitor GPU memory regularly
# Add dashboard panel to Grafana
```

---

## Verification

After fixing, verify Ollama health:

```bash
# 1. Check service is running
docker-compose ps ollama
# Should show: "Up X seconds"

# 2. Check GPU memory is reasonable
nvidia-smi | grep "ollama"
# Should be < 60% for idle state

# 3. Verify model is loaded
curl -s http://localhost:11434/api/tags | jq '.models'

# 4. Test inference (quick request)
curl -X POST http://localhost:11434/api/generate \
  -d '{"model": "neural-chat", "prompt": "Hello", "stream": false}' \
  -H "Content-Type: application/json" | jq '.response'
# Should return inference result within 5 seconds

# 5. Check alerts clear
curl -s http://localhost:9093/api/v1/alerts | \
  jq '.data[] | select(.labels.alertname | test("Ollama"))'
```

---

## Escalation

If Ollama still crashing after 15 minutes:

1. **Check GPU driver health**:
   ```bash
   nvidia-smi  # Should work without errors
   dmesg | grep -i nvidia | tail -20
   ```

2. **Check for GPU hardware issues**:
   ```bash
   nvidia-smi --query-gpu=pstate,clocks_throttle_reasons.active --format=csv
   # If throttling, GPU may be overheating
   ```

3. **Disable GPU temporarily** (use CPU):
   ```bash
   docker-compose down ollama
   # Edit docker-compose.yml: Remove 'runtime: nvidia'
   docker-compose up -d ollama
   # Will be slower but will work
   ```

4. **Escalate to ML/DevOps team**:
   - Slack: @ml-team or @devops
   - Include: GPU metrics, Ollama logs, inference requests during crash
   - Consider: Upgrade GPU, switch to CPU-only inference

---

## Prevention

**Monitor GPU health**:
```bash
# Weekly GPU health check
nvidia-smi -q > /tmp/gpu-health-$(date +%Y%m%d).txt

# Watch for:
# - GPU temperature > 75°C
# - Power limit throttling
# - ECC memory errors
```

**Model management**:
```bash
# Monthly: audit loaded models
curl -s http://localhost:11434/api/ps | jq '.models | length'
# Should be 0-1 (not multiple large models)

# Monthly: test failover
docker-compose restart ollama
# Verify features back online within 2 minutes
```

---

**Document**: docs/runbooks/ollama-gpu-memory.md  
**Last Updated**: 2026-04-15  
**Approved By**: ML Lead  
