# CONTAINER OVERLAP RESOLUTION

## Root Cause
The "-31" suffix containers (`code-server-31`, `ssh-proxy-31`) are from a separate Docker Compose instance running on the remote host (192.168.168.31). This was likely deployed during Phase 13/14 testing.

## Current docker-compose.yml Status: ✅ CORRECT

### Services Defined (7 total)
| Service | Container Name | Default Profile | Restart Policy | Notes |
|---------|---|---|---|---|
| code-server | code-server | default | unless-stopped | IDE + editor |
| ollama | ollama | default | unless-stopped | LLM inference server |
| ollama-init | ollama-init | **init** | **no** | One-time model pull (excluded from default) |
| ssh-proxy | ssh-proxy | default | unless-stopped | SSH proxy with audit logging |
| oauth2-proxy | oauth2-proxy | default | unless-stopped | Google OAuth sidecar |
| caddy | caddy | default | unless-stopped | TLS reverse proxy + DNS |
| redis | redis | default | unless-stopped | Cache layer (Tier 2) |

### Key Configurations For Overlap Resolution

#### 1. ollama-init (lines 119-175)
```yaml
profiles:
  - init                    # ← Excluded from default composition
restart: "no"              # ← Does NOT auto-restart after exit
command: exit 0            # ← Exits cleanly after model pulls
```
**Result**: Must explicitly run with `docker compose --profile init up` for model initialization

#### 2. Container Naming
- Explicit `container_name` on ALL services prevents auto-numbering
- No "scale" directives (keeps 1:1 service-to-container mapping)
- No dynamic naming based on Docker Compose project

#### 3. Network Isolation
- All services use `enterprise` bridge network (10.0.8.0/24)
- No port expose between services (DNS by container_name)
- External traffic: HTTP/HTTPS only through caddy (80/443)

## Resolution Steps

### Option 1: Immediate Cleanup (If On Same Host)
```bash
# Run from this workspace
bash scripts/cleanup-container-overlap.sh

# Then rebuild with clean state
docker compose down -v              # Remove all volumes too if full reset
docker compose up -d                # Bring up clean stack
```

### Option 2: Remote Host Cleanup (192.168.168.31)
```bash
ssh akushnir@192.168.168.31
  docker stop code-server-31 ssh-proxy-31 ollama-init 2>/dev/null || true
  docker rm -v code-server-31 ssh-proxy-31 ollama-init 2>/dev/null || true
  # If compose still running there, stop it:
  cd /home/akushnir/code-server-phase13 && docker compose down
exit
```

### Option 3: Verify No Duplicate Services in Compose File
The docker-compose.yml **correctly defines each service exactly once**. No duplicates. No service appears twice.

## Verification Commands

### Show Running Services (Should be 6, not 9)
```bash
docker ps --filter "network=enterprise" --format "{{.Names}}"
```

Expected output (6 containers):
```
code-server
caddy
oauth2-proxy
ssh-proxy
redis
ollama
```

### Show ollama-init Status
```bash
docker ps -a | grep ollama-init
# Should show: Exited (0) X minutes ago
# Should NOT show: Up X hours/minutes (if running, it's a problem)
```

### Verify Compose Stack Definition
```bash
docker compose config --services
```

Expected (7 services, including init profile):
```
code-server
ollama
ollama-init
ssh-proxy
oauth2-proxy
caddy
redis
```

## Post-Resolution Verification

1. **Container Count**: 6 running (no "-31" duplicates)
2. **Network**: All 6 on "enterprise" bridge (10.0.8.0/24)
3. **Memory**: Total ~620MB usage (well within limits)
   - code-server: ~85MB (4GB limit)
   - ollama: ~550MB (32GB limit)
   - others: ~5MB each
4. **Health**: All healthchecks passing
5. **Logs**: No restart loops, clean operation

## Long-term Compliance

✅ docker-compose.yml is production-ready
✅ IaC-compliant (idempotent, immutable, versioned)
✅ Explicit container naming (prevents conflicts)
✅ Proper profile usage (one-time init excluded)
✅ Correct restart policies (safety guards)

No further docker-compose.yml changes needed.
