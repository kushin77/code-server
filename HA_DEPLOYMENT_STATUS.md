# HA Deployment Status

**Date**: April 30, 2026  
**Status**: Primary operational, Replica blocked, Keepalived staged  
**Baseline**: kushnir.cloud platform running on single primary host

## Current Architecture

### Network Topology
```
Internet
  ↓ [Port 80/443]
Router [192.168.168.1]
  ↓ Port-forward currently to .31
  ├─ Primary (.31): 192.168.168.31
  ├─ Replica (.42): 192.168.168.42
  └─ VIP (staged): 192.168.168.30 (VRRP, not yet active)

DNS: kushnir.cloud → 173.77.179.148 (Cloudflare) → Router port-forward → Primary
```

### Host Status

| Component | Primary (.31) | Replica (.42) |
|-----------|:-------------:|:-------------:|
| **Caddy** | ✅ Running | ❌ Blocked |
| **Containers** | 53 running | 9 running (partial) |
| **Keepalived** | 📋 Staged | 📋 Staged |
| **VIP** | 📋 Ready | 📋 Ready |

## ✅ What is Operational

### Primary Host (.31)
- **Caddy**: Listening on 0.0.0.0:80→80, 0.0.0.0:443→443 (both TCP and UDP)
- **Health Endpoint**: `/health` returns HTTP 200 "OK"
- **Core Services**: All operational
  - PostgreSQL (code-server-postgres) - Healthy
  - Redis (code-server-redis) - Healthy
  - GitLab (code-server-gitlab) - Healthy (after reconfiguration)
  - Vault (code-server-vault) - Healthy
  - MinIO (code-server-minio) - Healthy
  - Code Server IDE (code-server-ide) - Healthy
  - Agent Runtime services - Healthy
- **Container Count**: 53 services running
- **Configuration**: 
  - Caddyfile at `/tmp/Caddyfile` with env var `${APEX_DOMAIN}=kushnir.cloud`
  - All routes properly configured (oauth2, IDE, Grafana, GitLab, Vault, MinIO, Prometheus, OPA)

### Keepalived HA (Staged, ready for deployment)

**Files staged on both hosts**:
- `/tmp/keepalived.conf` - VRRP configuration (734 bytes)
- `/tmp/check-caddy-health.sh` - Health check script (262 bytes)

**Configuration** (Primary):
```
vrrp_instance VI_1 {
  state MASTER
  priority 100
  virtual_ipaddress { 192.168.168.30/24 }
  track_script { check_caddy }
}
```

**Configuration** (Replica):
```
vrrp_instance VI_1 {
  state BACKUP
  priority 90
  virtual_ipaddress { 192.168.168.30/24 }
  track_script { check_caddy }
}
```

**Health Check**: Monitors Caddy on port 80 (curl http://127.0.0.1/health)
**Failover Time**: ~9 seconds (3 failed checks × 3 second interval)

## ⚠️ What is Blocked

### Replica Host (.42) - Port 80 Blocker

**Problem**: `nginx-ingress-controller` process (Kubernetes-managed) holds port 80/443

**Evidence**:
```
PID: 17349
Process: /nginx-ingress-controller --publish-service=ingress-nginx/ingress-nginx-controller
User: message+ (non-root)
Port occupancy: ~40+ listening sockets on port 80 (netstat shows orphaned connections)
```

**Impact**:
- Docker cannot bind Caddy to port 80/443
- Error: `failed to bind host port for 0.0.0.0:80`
- Replica cannot serve external traffic
- No automatic failover capability

**Root Cause**: Kubernetes-like environment on replica has ingress controller managing ports

### Docker-Compose Env Vars (Replica)
- `QDRANT_GRPC_PORT` missing (causes ports syntax error)
- `OAUTH2_COOKIE_SECRET` missing (required, no fallback)
- Other optional vars missing (OLLAMA_URL, REPUTATION_ENGINE_URL, AUTH_DOMAIN, etc.)

## 📋 Next Steps

### Immediate (Required for HA)

1. **Option A: Kill ingress controller** (Recommended if safe)
   ```bash
   # On replica, requires sudo password
   ssh akushnir@192.168.168.42
   sudo pkill -9 -f nginx-ingress-controller
   # Then start Caddy (same docker run command as primary)
   ```
   **Risk**: May break other services if ingress controller is serving traffic

2. **Option B: Run Caddy on alternate port** (Workaround)
   ```bash
   # On replica: bind to port 8000 instead of 80
   docker run -d --name code-server-caddy \
     --network services \
     -p 8000:80 -p 8443:443 -p 8443:443/udp \
     -v /tmp/Caddyfile:/etc/caddy/Caddyfile:ro \
     -e APEX_DOMAIN=kushnir.cloud \
     caddy:2.7.4
   # Then update health check in keepalived to use port 8000
   ```
   **Limitation**: External traffic still needs to go through primary

3. **Option C: Configure passwordless sudo**
   ```bash
   # On replica, add to sudoers:
   akushnir ALL=(ALL) NOPASSWD: /usr/bin/pkill
   # Then use Option A
   ```

### Secondary (HA Deployment)

1. **Deploy keepalived on primary** (after Caddy confirmed on replica)
   ```bash
   ssh akushnir@192.168.168.31
   sudo apt-get install keepalived
   sudo cp /tmp/keepalived.conf /etc/keepalived/keepalived.conf
   sudo systemctl enable keepalived
   sudo systemctl restart keepalived
   ```

2. **Verify VIP activation**
   ```bash
   ip addr show eth0 | grep 192.168.168.30
   # Should show: inet 192.168.168.30/24 scope global secondary eth0
   ```

3. **Update router DNS**
   - Change port-forward target from 192.168.168.31 to 192.168.168.30
   - Point DNS kushnir.cloud → 192.168.168.30
   - Test failover: `docker stop code-server-caddy` on primary, verify .42 takes over

4. **Test HA Failover**
   ```bash
   # Stop Caddy on primary
   ssh akushnir@192.168.168.31 docker stop code-server-caddy
   # Wait 9 seconds, verify VIP moves to replica
   # Verify kushnir.cloud still accessible
   # Restart Caddy on primary, verify failback
   ```

## 🔧 Operational Procedures

### Check Primary Status
```bash
ssh akushnir@192.168.168.31 'curl -s http://127.0.0.1/health && echo "✓ OK" || echo "✗ Down"'
```

### Check VIP Status
```bash
ssh akushnir@192.168.168.31 'ip addr show | grep 192.168.168.30'
```

### Check Keepalived Logs
```bash
ssh akushnir@192.168.168.31 'sudo tail -f /var/log/syslog | grep keepalived'
```

### Manual Failover (if automatic failover not working)
```bash
# On primary:
ssh akushnir@192.168.168.31 'sudo systemctl stop keepalived'
# On replica:
ssh akushnir@192.168.168.42 'sudo systemctl start keepalived'
# Wait 3 seconds, verify VIP on replica
```

## 📊 Current Blockers

| Blocker | Severity | Owner | Solution |
|---------|----------|-------|----------|
| Replica port 80 held by nginx-ingress-controller | **CRITICAL** | User | Kill process or configure sudo |
| Docker-compose env vars incomplete | **HIGH** | Agent | Already fixed in .env.production |
| Keepalived not installed | **HIGH** | User | Manual: `apt-get install keepalived` |
| Router DNS not pointing to VIP | **HIGH** | User | Update port-forward target |
| Replica Docker-compose digest validation | **MEDIUM** | Dev | Workaround: manually deploy services |

## 📝 Configuration Files

### Keepalived Config (Primary)
- Location: `/tmp/keepalived.conf` on both hosts
- Destination: `/etc/keepalived/keepalived.conf` after manual sudo deployment

### Caddy Config
- Location: `/tmp/Caddyfile` on both hosts
- Running on: Primary port 80/443 (active)
- Status: Deployed, verified working

### Health Check
- Location: `/tmp/check-caddy-health.sh` on both hosts
- Command: `curl -f http://127.0.0.1/health`
- Interval: 3 seconds
- Threshold: 3 failures = switch

## 🎯 Success Criteria

- [ ] Replica Caddy running (resolve port 80 blocker)
- [ ] Keepalived deployed on both hosts
- [ ] VIP (192.168.168.30) active on primary
- [ ] Router port-forward updated to VIP
- [ ] DNS resolution working through VIP
- [ ] Manual failover successful (stop Caddy on .31, verify .42 takes over)
- [ ] Automatic failback working (restart Caddy on .31, verify VIP returns)

## 📚 References

- [CADDY_REPLICA_DEPLOYMENT_ISSUE.md](CADDY_REPLICA_DEPLOYMENT_ISSUE.md) - Detailed blocker analysis
- [KEEPALIVED_HA_DEPLOYMENT.md](KEEPALIVED_HA_DEPLOYMENT.md) - Full deployment guide
- [Caddyfile](config/caddy/Caddyfile) - Reverse proxy configuration
- [GSM_SECRETS_RUNBOOK.md](docs/operations/GSM_SECRETS_RUNBOOK.md) - Secrets management guide
