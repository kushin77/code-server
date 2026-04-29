# GPU Integration Quick Reference

## 🎯 Current Status: CPU-ONLY (GPU Disabled)

**Readiness Level**: 🟡 YELLOW — Ready to enable with 1.5-2 hour configuration effort

---

## 📊 Quick Facts

| Item | Status | Location |
|------|--------|----------|
| GPU Support Architectured | ✅ Yes | Throughout codebase |
| GPU Device Access Configured | ❌ No | Ollama container missing `runtime="nvidia"` |
| OLLAMA_NUM_GPU Setting | ❌ 0 (disabled) | `.env.cluster:72` |
| DCGM Monitoring Available | ✅ Yes | `docker-compose.observability.yml:54-99` |
| DCGM Actively Monitoring | ❌ No | Profile not active in deployment |
| Alert Rules Defined | ✅ Yes | `monitoring/alerts/alert-rules.yml:66-98` |
| ML Services GPU-Aware | ✅ Yes | Ollama, Multimodal-AI, Memory-Engine |
| GPU Metrics Real Implementation | ❌ Mocked | `apps/execution-scheduler/monitors.py:64-71` |

---

## 🔴 Critical Missing Pieces

1. **Ollama Container**: Missing `runtime = "nvidia"` in terraform
2. **Environment Variable**: `OLLAMA_NUM_GPU=0` needs to be `OLLAMA_NUM_GPU=1`
3. **CUDA Variables**: Not set in .env file
4. **Host Prerequisites**: GPU driver not verified

---

## 🟢 What's Ready to Use

1. ✅ DCGM Exporter image configured
2. ✅ Prometheus alert rules for GPU metrics
3. ✅ Ollama supports GPU out of the box
4. ✅ Multimodal-AI can use GPU via Ollama
5. ✅ Docker-compose profile for observability

---

## 📋 5-Minute Verification

```bash
# SSH to primary host
ssh akushnir@192.168.168.31

# Check GPU availability
nvidia-smi
# Should show: NVIDIA-SMI xxx.xx Driver Version xxx.xx

# Check docker GPU support
docker run --rm --gpus all ubuntu nvidia-smi
# Should show: GPU details (not "command not found")

# Current Ollama state (should be CPU)
docker exec code-server-ollama nvidia-smi 2>&1 | head -3
# Expected: Either "command not found" or error (currently CPU-only)
```

---

## 🚀 3-Step Quick Enable

### Step 1: Update Environment (1 minute)
```bash
# Edit .env.cluster
sed -i 's/OLLAMA_NUM_GPU=0/OLLAMA_NUM_GPU=1/' .env.cluster

# Add CUDA variable
echo 'CUDA_VISIBLE_DEVICES=0' >> .env.cluster
```

### Step 2: Update Terraform (2 minutes)
```bash
# File: terraform/environments/private/modules/stack/containers-infrastructure.tf
# Find line: resource "docker_container" "ollama" {
# After: image = docker_image.ollama.image_id
# Add: runtime = "nvidia"

# Find: env = [
# After the environment block, add to env array:
# "OLLAMA_NUM_GPU=1",
# "CUDA_VISIBLE_DEVICES=0",
```

### Step 3: Deploy (10 minutes)
```bash
# Apply terraform
cd /home/akushnir/code-server/terraform/environments/private
terraform apply -auto-approve -target=module.primary.docker_container.ollama

# Verify GPU access
docker exec code-server-ollama nvidia-smi

# Test inference (should be 10-20x faster)
curl -X POST http://localhost:11434/api/generate \
  -d '{"model":"llama3","prompt":"test","stream":false}' \
  | jq '.eval_duration'
```

---

## 📈 Expected Performance Improvement

| Operation | CPU | GPU (A100) | Speedup |
|-----------|:---:|:----------:|:-------:|
| 100 tokens | ~20s | ~0.7s | **28x** |
| 1 min audio | ~2 sec | ~0.5 sec | **4x** |
| 1 image | ~60s | ~2s | **30x** |

---

## 🛠️ Implementation Checklist

### Pre-Flight (15 min)
- [ ] SSH to 192.168.168.31
- [ ] Run `nvidia-smi` (verify driver exists)
- [ ] Run `docker run --gpus all ubuntu nvidia-smi` (verify docker GPU)
- [ ] Check `docker -v` (should be 24.0+)

### Configuration (10 min)
- [ ] Edit `.env.cluster`: Change `OLLAMA_NUM_GPU=0` → `OLLAMA_NUM_GPU=1`
- [ ] Add `CUDA_VISIBLE_DEVICES=0` to .env.cluster
- [ ] Commit changes to git

### Terraform (30 min)
- [ ] Edit `containers-infrastructure.tf`: Add `runtime = "nvidia"` to Ollama container
- [ ] Edit Ollama env block: Add `"OLLAMA_NUM_GPU=1"` and `"CUDA_VISIBLE_DEVICES=0"`
- [ ] Run `terraform plan -target=module.primary.docker_container.ollama`
- [ ] Verify plan shows runtime change
- [ ] Run `terraform apply -auto-approve -target=module.primary.docker_container.ollama`

### Verification (20 min)
- [ ] Wait for container restart (monitor: `docker logs -f code-server-ollama`)
- [ ] Run: `docker exec code-server-ollama nvidia-smi` (should work)
- [ ] Run: `docker exec code-server-ollama ollama show llama3` (should show GPU memory)
- [ ] Benchmark: `curl -X POST http://localhost:11434/api/generate...`
- [ ] Compare: CPU ~20s vs GPU ~1s for 100 tokens

### Post-Deploy (Optional)
- [ ] Enable DCGM monitoring: `docker-compose --profile observability up -d dcgm-exporter`
- [ ] Verify metrics: `curl http://localhost:9400/metrics | grep DCGM`
- [ ] Check Prometheus: `curl http://localhost:9090/api/v1/targets`

---

## ⚠️ Important Notes

### If No GPU Hardware
- Continue with CPU (works fine for non-interactive inference)
- Current performance: ~5 tokens/sec (acceptable)
- Can upgrade to GPU later with same config

### If GPU Is Missing
- Check error: `docker logs code-server-ollama | grep -i error`
- Verify driver: `nvidia-smi` on host
- Verify docker runtime: `docker info | grep nvidia`

### Fallback Strategy
- If GPU fails: Environment variable `OLLAMA_NUM_GPU=0` reverts to CPU
- Inference continues but slower
- No application downtime

---

## 🔧 Key Files to Modify

1. **`.env.cluster`** — Set GPU environment variables
2. **`terraform/environments/private/modules/stack/containers-infrastructure.tf`** — Add runtime binding
3. **`.env.production`** (optional) — Same env vars for production

---

## 📚 Reference Locations

| Item | Location |
|------|----------|
| Ollama Container | `terraform/environments/private/modules/stack/containers-infrastructure.tf:194` |
| GPU Variable | `terraform/modules/ai/variables.tf:20` |
| DCGM Exporter | `docker-compose.observability.yml:54` |
| Alert Rules | `monitoring/alerts/alert-rules.yml:66` |
| Multimodal-AI | `terraform/environments/private/modules/stack/containers-ai.tf:70` |
| Execution Scheduler | `apps/execution-scheduler/monitors.py:64` |
| Env Config | `.env.cluster:72` (OLLAMA_NUM_GPU) |

---

## 🎓 GPU Requirements By Model

| Model | Min VRAM | Recommended | CPU Time | GPU Time |
|-------|:--------:|:----------:|:--------:|:--------:|
| **llama3:8b** | 6GB | 8GB | 20s/100tok | 0.7s/100tok |
| **mistral:7b** | 5GB | 8GB | 15s/100tok | 0.6s/100tok |
| **llava:13b** | 8GB | 16GB | 60s/image | 2s/image |
| **neural-chat** | 4GB | 6GB | 10s/100tok | 0.4s/100tok |

---

## 🚨 Troubleshooting

### GPU not detected in container
```bash
# Check docker GPU support:
docker run --rm --gpus all ubuntu nvidia-smi
# If fails: nvidia-docker not installed or docker daemon not restarted

# Solution:
sudo systemctl restart docker
docker run --rm --gpus all ubuntu nvidia-smi
```

### CUDA out of memory
```bash
# Check GPU memory:
docker exec code-server-ollama nvidia-smi

# If full, restart container:
docker restart code-server-ollama

# Or fallback to CPU:
# Set OLLAMA_NUM_GPU=0 and restart
```

### Slow inference (still CPU)
```bash
# Verify GPU is active:
docker exec code-server-ollama nvidia-smi

# Check Ollama process:
docker exec code-server-ollama ps aux | grep ollama

# Verify env var:
docker exec code-server-ollama env | grep OLLAMA_NUM_GPU
# Should show: OLLAMA_NUM_GPU=1 (not 0)
```

---

## ✅ Success Criteria

You'll know GPU is enabled when:
- [ ] `docker exec code-server-ollama nvidia-smi` shows GPU details
- [ ] Inference time drops from ~20s to ~1s for 100 tokens
- [ ] `docker logs code-server-ollama` shows CUDA initialization
- [ ] Multimodal-AI responses become instant (< 2 seconds)
- [ ] `docker stats` shows GPU memory usage (if available)

---

## 📞 Next Steps

1. **Verify host** (5 min) — Run `nvidia-smi` on 192.168.168.31
2. **Enable GPU** (30 min) — Follow 3-step quick enable above
3. **Test performance** (10 min) — Benchmark inference speed
4. **Enable monitoring** (20 min) — Optional DCGM setup
5. **Document** (5 min) — Add GPU enablement notes to runbooks

**Total Time: 1.5-2 hours**

---

Generated: April 29, 2026 | Assessment: GPU integration ready to enable
