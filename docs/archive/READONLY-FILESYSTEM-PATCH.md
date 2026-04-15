# Read-Only Filesystem Configuration Patch for docker-compose.yml

## Strategy
Add `read_only: true` + `tmpfs: [...]` to each service before the `deploy:` or `healthcheck:` block.
Tmpfs mounts are allocated for runtime-required writable paths.

## Services to Update

### 1. coredns (line 28)
```yaml
coredns:
  # ... existing config ...
  command: -conf /etc/coredns/Corefile
  read_only: true
  tmpfs:
    - /run
    - /tmp
  healthcheck:
    # ... existing healthcheck ...
```

### 2. postgres (line 49)
```yaml
postgres:
  # ... existing config up to deploy: ...
  read_only: true
  tmpfs:
    - /var/run/postgresql
    - /var/lib/postgresql/tmp
  deploy:
    # ... existing deploy ...
```

### 3. redis (line 83)
```yaml
redis:
  # ... existing config ...
  volumes:
    - redis-data:/data
  read_only: true
  tmpfs:
    - /var/run
    - /tmp
  healthcheck:
    # ... or wherever next block is ...
```

### 4. minio (line 117)
```yaml
minio:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /tmp
  healthcheck:
    # ...
```

### 5. code-server (line 148)
```yaml
code-server:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /tmp
    - /home/coder/.local
  deploy:
    # ... existing deploy ...
```

### 6. oauth2-proxy (line 269)
```yaml
oauth2-proxy:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /tmp
  healthcheck:
    # ...
```

### 7. caddy (line 319)
```yaml
caddy:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /var/lib/caddy
    - /var/cache/caddy
  deploy:
    # ... existing deploy ...
```

### 8. prometheus (line 345)
```yaml
prometheus:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /tmp
  deploy:
    # ... existing deploy ...
```

### 9. grafana (line 378)
```yaml
grafana:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /var/lib/grafana/plugins
    - /var/lib/grafana/png-cache
  deploy:
    # ... existing deploy ...
```

### 10. alertmanager (line 413)
```yaml
alertmanager:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /tmp
  deploy:
    # ... existing deploy ...
```

### 11. jaeger (line 441)
```yaml
jaeger:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /tmp
  deploy:
    # ... existing deploy ...
```

### 12. pgbouncer (line 476)
```yaml
pgbouncer:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /var/run
    - /tmp
  deploy:
    # ... existing deploy ...
```

### 13. vault (line 510)
```yaml
vault:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /tmp
  deploy:
    # ... existing deploy ...
```

### 14. falco (line 578)
```yaml
falco:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /tmp
  deploy:
    # ... existing deploy ...
```

### 15. falcosidekick (line 621)
```yaml
falcosidekick:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /tmp
  deploy:
    # ... existing deploy ...
```

### 16. loki (line 652)
```yaml
loki:
  # ... existing config ...
  read_only: true
  tmpfs:
    - /run
    - /tmp
    - /var/log/loki
  deploy:
    # ... existing deploy ...
```

## Deployment Steps

1. **Backup current docker-compose.yml**:
   ```bash
   cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d-%H%M%S)
   ```

2. **Review and apply changes** (manually or via script)

3. **Test with dry-run**:
   ```bash
   docker-compose --dry-run -f docker-compose.yml config | head -100
   ```

4. **Redeploy services**:
   ```bash
   docker-compose down
   docker-compose up -d
   ```

5. **Verify read-only enforcement**:
   ```bash
   for svc in coredns postgres redis code-server caddy prometheus grafana alertmanager jaeger loki vault pgbouncer; do
     echo "=== $svc ==="
     docker inspect $svc | grep -E "ReadOnly|Tmpfs" | head -5
   done
   ```

6. **Test write permissions**:
   ```bash
   docker exec code-server touch /test-write  # Should fail
   docker exec postgres touch /var/lib/postgresql/data/test  # May fail
   ```

## Rollback Plan

If issues arise:
```bash
# Restore original
cp docker-compose.yml.bak.$(ls -t docker-compose.yml.bak.* | head -1) docker-compose.yml
docker-compose down
docker-compose up -d
```

## Security Benefits

- **Immutability**: Prevents runtime code/config modifications
- **Attack surface**: Reduces exploitation opportunities (e.g., container breakout, privilege escalation)
- **Compliance**: Meets CIS, NIST, and SLSA supply chain integrity requirements
- **Debuggability**: Forces explicit tmpfs mount requirements (clearer intent)

## Performance Impact

- **Positive**: tmpfs is in-memory, faster than disk I/O
- **Neutral**: read-only enforcement has minimal CPU overhead
- **No bandwidth impact**: All I/O remains local

## Known Considerations

- **postgres**: May need additional tmpfs for vacuum operations
- **grafana**: Plugin installations require `/var/lib/grafana/plugins` tmpfs
- **falco**: eBPF programs may require additional `/sys` / `/proc` volumes (already granted)
- **vault**: May need `/var/lib/vault` if persistence is required

## Verification Checklist

- [ ] All 16+ services have `read_only: true`
- [ ] Appropriate tmpfs mounts for each service
- [ ] No services fail to start
- [ ] No "Read-only file system" errors in logs
- [ ] Services maintain health checks passing
- [ ] Persistent data volumes still work (postgres-data, redis-data, etc.)
- [ ] Monitoring shows normal operation (Prometheus scrapes, Grafana loads)
- [ ] No performance degradation observed
