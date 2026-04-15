# IMPLEMENTATION: Issue #354 - Container Hardening (IN PROGRESS)

**Status**: 🔄 IN PROGRESS  
**Date**: 2026-04-15  
**Objective**: Add security_opt, cap_drop/cap_add, read_only filesystems, network segmentation

## Changes to Apply

### 1. Security Hardening Anchor (`x-hardening`)

Add reusable anchor with:
```yaml
x-hardening: &hardening
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
```

### 2. Per-Service Updates

**PostgreSQL** (Data tier - writable filesystem required):
```yaml
postgres:
  <<: *hardening
  cap_add:
    - CHOWN
    - FOWNER
    - DAC_OVERRIDE
    - SETGID
    - SETUID
    - FSETID
  user: "70:70"  # postgres:postgres
```

**Redis** (Data tier):
```yaml
redis:
  <<: *hardening
  cap_add:
    - SETGID
    - SETUID
  user: "999:999"  # redis:redis
  # Expose only on data network (not host)
  # ports: [] or expose: [6379]
```

**Caddy** (Frontend - reverse proxy):
```yaml
caddy:
  <<: *hardening
  cap_add:
    - NET_BIND_SERVICE
  user: "1000:1000"
  read_only: true
  tmpfs:
    - /tmp
    - /data  # ACME challenge temp files
```

**oauth2-proxy** (Frontend):
```yaml
oauth2-proxy:
  <<: *hardening
  user: "65534:65534"  # nobody:nogroup
  read_only: true
  tmpfs:
    - /tmp
```

**Code-server** (App tier - writable for user code):
```yaml
code-server:
  <<: *hardening
  # No explicit cap_add needed (user code runs with dropped caps)
  # Do NOT set read_only (user needs to write)
```

**Prometheus** (Monitoring):
```yaml
prometheus:
  <<: *hardening
  user: "65534:65534"
  read_only: true
  tmpfs:
    - /tmp
  volumes:
    - prometheus-data:/prometheus
```

**Grafana** (Monitoring):
```yaml
grafana:
  <<: *hardening
  cap_add:
    - CHOWN
  user: "472:472"  # grafana:grafana
  # writable filesystem for /var/lib/grafana
```

**AlertManager** (Monitoring):
```yaml
alertmanager:
  <<: *hardening
  user: "65534:65534"
  read_only: true
  tmpfs:
    - /tmp
```

**Jaeger** (Monitoring):
```yaml
jaeger:
  <<: *hardening
  user: "65534:65534"
  read_only: true
  tmpfs:
    - /tmp
```

### 3. Network Segmentation

Create separate networks (from data-flow perspective):

```yaml
networks:
  frontend:
    driver: bridge
  app:
    driver: bridge
  data:
    driver: bridge
    internal: true  # No internet access
  monitoring:
    driver: bridge
    internal: true
```

Network assignments:
- **frontend**: caddy, oauth2-proxy
- **app**: code-server, ollama, oauth2-proxy (bridge to app)
- **data**: postgres, redis (isolated)
- **monitoring**: prometheus, grafana, alertmanager, jaeger

### 4. Verification Steps

```bash
# 1. Check security options
docker inspect postgres | jq '.[] .HostConfig.SecurityOpt'
# Output: ["no-new-privileges:true"]

# 2. Check capability drops
docker inspect caddy | jq '.[] .HostConfig.CapDrop'
# Output: ["ALL"]

# 3. Check read-only filesystem
docker inspect prometheus | jq '.[] .HostConfig.ReadonlyRootfs'
# Output: true

# 4. Verify network isolation (caddy cannot reach postgres)
docker exec caddy bash -c "nc -zv postgres 5432"
# Output: Connection refused (not on data network)

# 5. Verify internal network isolation
docker exec postgres bash -c "curl https://google.com"
# Output: Connection refused (data network is internal)
```

## Acceptance Criteria

- [ ] `x-hardening` anchor defined in docker-compose.yml
- [ ] All services have `security_opt: [no-new-privileges:true]`
- [ ] All services have `cap_drop: [ALL]`
- [ ] Services have minimal `cap_add` (only what they need)
- [ ] Stateless services have `read_only: true`
- [ ] Services have non-root `user:` directives
- [ ] Database/monitoring services on isolated internal networks
- [ ] Frontend services on edge network (external access)
- [ ] Verification tests pass (all checks above)
- [ ] docker-compose ps shows all services healthy
- [ ] Zero manual port bindings for internal services (postgres, redis, prometheus, grafana, alertmanager, jaeger)

## Testing Strategy

```bash
# Deploy to staging
ssh staging-host
cd code-server-enterprise
docker-compose up -d

# Verify all services healthy
docker-compose ps | grep healthy

# Run CIS Docker Benchmark
docker run --rm --net host --pid host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc:/etc:ro \
  docker/docker-bench-security 2>&1 | grep -E "WARN|FAIL"

# Should show no FAIL on services we've hardened
```

## References

- Issue #354: feat(docker) Container hardening
- CIS Docker Benchmark: https://www.cisecurity.org/benchmark/docker
- Docker security: https://docs.docker.com/engine/security/
- Linux capabilities: https://man7.org/linux/man-pages/man7/capabilities.7.html

---

**Implementation Status**: Ready to apply changes to docker-compose.yml
