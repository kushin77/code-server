# Runbook: Ollama Latency Spike (OllamaLatencySpike)

**Alert**: `OllamaLatencySpike` (p95 > 5s) | `OllamaLatencyCritical` (p95 > 15s) | `OllamaServiceDown` (health check fails)  
**Severity**: WARNING / CRITICAL  
**Component**: LLM inference engine  
**Related Issue**: #569

## Overview

This alert fires when Ollama LLM inference performance degrades. High latency indicates resource contention, model loading issues, or GPU problems.

## Quick Response

```bash
# 1. Check Ollama service status
docker-compose ps | grep ollama

# 2. Check health endpoint
docker-compose exec ollama curl -f http://localhost:11434/api/health || echo "Unhealthy"

# 3. Check loaded models
docker-compose exec ollama curl http://localhost:11434/api/tags | jq '.models | length'

# 4. View recent logs
docker-compose logs --tail 50 ollama | tail -20

# 5. Check resource usage
docker stats --no-stream ollama
```

## Detailed Investigation

### Step 1: Verify Service is Responsive

```bash
# Health check
docker-compose exec ollama curl -s -w "HTTP Status: %{http_code}\n" http://localhost:11434/api/health

# Check API version
docker-compose exec ollama curl http://localhost:11434/api/version | jq .

# List running models
docker-compose exec ollama ollama list

# Check process status
docker-compose exec ollama ps aux | grep ollama
```

### Step 2: Measure Latency

```bash
# Test inference latency directly
time docker-compose exec ollama ollama run llama2 "Hello" | head -5

# Use prometheus metrics (p95 latency)
curl -s 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.95,ollama_inference_duration_seconds)' | jq '.data.result'

# Get p50, p95, p99 latencies
curl -s 'http://prometheus:9090/api/v1/query' \
  -d 'query=histogram_quantile(0.50,ollama_inference_duration_seconds)' | jq '.data.result[0].value[1]'
curl -s 'http://prometheus:9090/api/v1/query' \
  -d 'query=histogram_quantile(0.95,ollama_inference_duration_seconds)' | jq '.data.result[0].value[1]'
```

### Step 3: Common Causes

| Cause | Detection | Fix |
|-------|-----------|-----|
| **Model not loaded** | `ollama list` shows 0 models or recently stopped | `ollama pull llama2 && ollama run llama2 "test"` |
| **GPU unavailable** | `ollama logs` shows "CUDA error" or "no GPU" | Check `nvidia-smi`, restart ollama: `docker-compose restart ollama` |
| **GPU memory full** | `nvidia-smi` shows 100% memory used | Reduce model context size or unload other models |
| **CPU fallback** | Model running on CPU instead of GPU | Check GPU driver, CUDA availability, docker runtime config |
| **Disk swap active** | High disk I/O when memory pressure detected | Increase Docker memory limit, extend swap space |
| **Network latency** | Remote model loading slow | Use local model copy or reduce model size |
| **Model too large** | Loading 70B parameter model with limited RAM | Switch to smaller model (7B, 13B) or increase resources |

### Step 4: Resource Analysis

```bash
# Check container resource limits
docker inspect ollama | jq '.HostConfig | {Memory, CpuQuota, Devices}'

# Check actual resource usage
docker stats ollama --no-stream --format "{{.CPUPerc}} | {{.MemUsage}} | {{.NetIO}} | {{.BlockIO}}"

# Check GPU status
docker-compose exec ollama nvidia-smi

# Check system memory pressure
docker-compose exec ollama free -h
docker-compose exec ollama top -bn 1 | head -15

# Check disk I/O
docker-compose exec ollama iostat -x 1 2 | tail -8
```

### Step 5: Performance Recovery

**Option 1: Restart with fresh state**
```bash
docker-compose restart ollama
# Wait for initialization
sleep 15
# Pre-load model to cache
docker-compose exec ollama ollama pull llama2
docker-compose exec ollama ollama run llama2 "Warming up" >/dev/null
```

**Option 2: Reduce model context/batch size**
```bash
# Check Ollama environment
docker-compose exec ollama printenv | grep -i ollama

# Reduce context for faster inference
docker-compose exec ollama ollama run llama2 --stream false --num-ctx 512 "test"
```

**Option 3: Switch to smaller model**
```bash
# List available models
docker-compose exec ollama ollama list

# Pull smaller, faster model
docker-compose exec ollama ollama pull mistral

# Test latency
time docker-compose exec ollama ollama run mistral "test"
```

**Option 4: Increase resources**
```yaml
# docker-compose.yml
ollama:
  deploy:
    resources:
      limits:
        memory: 16g  # Increase from 8g
        cpus: "4.0"  # Increase from 2.0
      reservations:
        devices:
          - driver: nvidia
            count: 1
            capabilities: [gpu]
```

### Step 6: Verify Fix

```bash
# Monitor latency trend (5 measurements)
for i in {1..5}; do
  curl -s 'http://prometheus:9090/api/v1/query?query=histogram_quantile(0.95,rate(ollama_inference_duration_seconds_bucket[5m]))' | jq '.data.result[0].value[1] | tonumber | floor' 
  sleep 10
done

# Latency should drop below threshold (< 5s for warning, < 15s for critical)
```

## Prevention

- **Alert configured**: Warning at p95 > 5s, critical at p95 > 15s
- **Model preloading**: Pull models during startup to avoid cache misses
- **Resource limits**: Allocate 8GB+ memory and 1+ GPU for inference
- **Baseline metrics**: Monitor ollama_inference_duration_seconds continuously
- **Load testing**: Test peak inference load periodically
- **Version updates**: Keep Ollama and CUDA drivers current

## Configuration Tuning

```yaml
# Optimized Ollama config
environment:
  # GPU optimization
  NVIDIA_DRIVER_CAPABILITIES: "compute,utility"
  CUDA_VISIBLE_DEVICES: "0"  # Use GPU 0
  
  # Inference tuning
  OLLAMA_NUM_PARALLEL: "4"  # Parallel requests
  OLLAMA_NUM_THREAD: "8"    # CPU threads per request
  
  # Memory management
  OLLAMA_KEEP_ALIVE: "5m"   # Keep model in memory 5min
  OLLAMA_MAX_QUEUE: "512"   # Request queue limit
```

## Monitoring Dashboard

```promql
# Grafana: Ollama Performance Dashboard

# Panel 1: Inference Duration p50/p95/p99
histogram_quantile(0.50, rate(ollama_inference_duration_seconds_bucket[5m]))
histogram_quantile(0.95, rate(ollama_inference_duration_seconds_bucket[5m]))
histogram_quantile(0.99, rate(ollama_inference_duration_seconds_bucket[5m]))

# Panel 2: Inference Success Rate
rate(ollama_inference_requests_total{status="success"}[5m]) / 
  rate(ollama_inference_requests_total[5m])

# Panel 3: GPU Memory Usage
nvidia_smi_memory_used_mb / nvidia_smi_memory_total_mb

# Panel 4: Model Cache Hits
rate(ollama_cache_hits_total[5m]) / 
  (rate(ollama_cache_hits_total[5m]) + rate(ollama_cache_misses_total[5m]))
```

## Escalation

If latency remains high after optimization:
1. Profile the specific request: `ollama run --verbose llama2 "test"`
2. Check if model quantization helps (use Q4, Q5 instead of fp16)
3. Consider horizontal scaling: Load balance across multiple Ollama instances
4. Review model architecture suitability for use case (semantic search vs gen search)

## Related Runbooks

- [Container Restart Investigation](container-restart-investigation.md) — Ollama crashes
- [Disk Space Cleanup](disk-space-cleanup.md) — Disk full causing I/O contention
- [PostgreSQL Replication Lag](postgresql-replication-lag.md) — If using vector DB for embeddings
