## P1: Parameterize sentinel.conf for Multi-Host Deployment

### Problem

**File**: `sentinel.conf`, line 19-20

The Redis Sentinel configuration hardcodes the master hostname as `redis`:

```conf
sentinel monitor mymaster redis 6379 2
sentinel down-after-milliseconds mymaster 30000
```

### Impact

When `sentinel.conf` is deployed to the replica host (.42):
1. Sentinel tries to connect to local `redis` container as master
2. Local `redis` on .42 is configured as replica, not master
3. Sentinel can't discover the actual master on .31
4. Automatic failover is **broken**

### Current Behavior

On primary host (.31):
- `redis` container is master ✓
- Sentinel monitors `redis` (local) ✓
- Works by accident ✓

On replica host (.42):
- `redis` container is replica, not master
- Sentinel monitors local `redis` → wrong
- Failover detection broken ✗

### Required Changes

#### Option A: Environment Variable Parameterization

```conf
# sentinel.conf:
sentinel monitor mymaster ${REDIS_MASTER_HOST:-redis} 6379 2
```

```yaml
# docker-compose.yml:
redis-sentinel:
  environment:
    REDIS_MASTER_HOST: ${PRIMARY_HOST:-192.168.168.31}
```

**Note**: Sentinel doesn't natively support env vars in config. Need wrapper script.

#### Option B: Generate Host-Specific Config

```bash
# scripts/ops/generate-sentinel-conf.sh
#!/usr/bin/env bash
REDIS_MASTER_HOST="${REDIS_MASTER_HOST:-192.168.168.31}"
cat > sentinel.conf << EOF
sentinel monitor mymaster ${REDIS_MASTER_HOST} 6379 2
sentinel down-after-milliseconds mymaster 30000
sentinel failover-timeout mymaster 180000
sentinel parallel-syncs mymaster 1
EOF
```

#### Option C: Use Docker Network IP (Recommended)

```yaml
# docker-compose.yml:
redis-sentinel:
  command: |
    sh -c "
      MASTER_IP=$$(getent hosts redis-master | awk '{print $$1}')
      sed -i 's/redis/$${MASTER_IP}/g' /etc/sentinel.conf
      redis-sentinel /etc/sentinel.conf
    "
```

### Validation

```bash
# On replica host (.42), verify Sentinel knows correct master:
docker-compose exec redis-sentinel redis-cli -p 26379 SENTINEL master mymaster

# Expected output should show .31 IP, not localhost
```

### Definition of Done

- [ ] `sentinel.conf` parameterized or generated per-host
- [ ] Sentinel on .31 monitors actual master
- [ ] Sentinel on .42 monitors primary (.31) master
- [ ] Failover test: stop redis on .31, verify .42 promoted
- [ ] Documentation updated with multi-host setup

### Cross-References

- Parent: #957 (Redis HA)
- Related: #954 (HA EPIC)
- Blocked by: #993 (PRIMARY_HOST fix)
